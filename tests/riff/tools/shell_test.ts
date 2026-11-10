import { describe, expect, test } from 'bun:test';
import type { FxToolResult } from 'libfx/node';
import { execFileSync } from 'node:child_process';
import type { ToolCallUpdate } from '@agentclientprotocol/sdk/unstable';
import {
  mkdtemp,
  mkdir,
  readFile,
  realpath,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { openFinder } from '../../../src/platform/fff.ts';
import { LIMITS } from '../../../src/riff/tools/limits.ts';
import { ALLOW_SESSION, DENY } from '../../../src/riff/tools/permission.ts';
import { shell } from '../../../src/riff/tools/shell.ts';
import { riffTools } from '../../../src/riff/tools/tools.ts';
import { until } from '../../session/conversation_fake.ts';

const live = () => new AbortController().signal;
const meta = (update: ToolCallUpdate, key: string) =>
  update._meta?.[key] as
    | {
        data?: string;
        terminal_id?: string;
        exit_code?: number | null;
        signal?: string | null;
      }
    | undefined;

async function directory() {
  return realpath(await mkdtemp(join(tmpdir(), 'chord-riff-shell-')));
}

describe('riff shell execution', () => {
  test('streams both outputs before exit and returns the real exit code', async () => {
    const root = await directory();
    const updates: ToolCallUpdate[] = [];
    let sawFirst = false;

    try {
      const result = await shell(
        root,
        {
          command:
            'printf first; printf error >&2; while test ! -e gate; do sleep 0.01; done; printf second; exit 7',
        },
        live(),
        'shell-1',
        async (update) => {
          updates.push(update);

          if (meta(update, 'terminal_output_delta')?.data?.includes('first')) {
            sawFirst = true;

            await writeFile(join(root, 'gate'), '');
          }
        },
      );

      expect(sawFirst).toBe(true);
      expect(result.text).toContain('first');
      expect(result.text).toContain('second');
      expect(result.text).toContain('error');
      expect(result.text).toContain('Exit code 7');
      expect(result.isError).toBe(true);
      expect(updates[0]).toMatchObject({
        content: [{ type: 'terminal', terminalId: 'shell-1' }],
        _meta: { terminal_info: { terminal_id: 'shell-1', cwd: root } },
      });
      expect(meta(updates.at(-1)!, 'terminal_exit')).toEqual({
        terminal_id: 'shell-1',
        exit_code: 7,
        signal: null,
      });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test('abort kills the shell group including its child sleep and preserves received output', async () => {
    const root = await directory();
    const controller = new AbortController();
    const updates: ToolCallUpdate[] = [];
    let child = 0;

    try {
      await expect(
        shell(
          root,
          { command: "sleep 30 & child=$!; printf 'child:%s\\n' $child; wait" },
          controller.signal,
          'abort',
          (update) => {
            updates.push(update);

            const data = meta(update, 'terminal_output_delta')?.data ?? '';
            const match = /child:(\d+)/.exec(data);

            if (match !== null) {
              child = Number(match[1]);

              controller.abort(new Error('stopped by person'));
            }
          },
        ),
      ).rejects.toThrow('stopped by person');
      expect(child).toBeGreaterThan(0);
      expect(() => process.kill(child, 0)).toThrow();
      expect(
        updates.some((update) =>
          meta(update, 'terminal_output_delta')?.data?.includes('child:'),
        ),
      ).toBe(true);
      expect(meta(updates.at(-1)!, 'terminal_exit')?.exit_code).toBeNull();
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test('model byte and line caps leave the terminal stream complete', async () => {
    const root = await directory();

    try {
      for (const command of [
        "printf '%270000s' x",
        'i=0; while test $i -lt 2100; do printf "line\\n"; i=$((i+1)); done',
      ]) {
        let streamed = 0;
        const result = await shell(
          root,
          { command },
          live(),
          'capped',
          (update) => {
            streamed +=
              meta(update, 'terminal_output_delta')?.data?.length ?? 0;
          },
        );

        expect(result.text).toContain('output truncated');
        expect(result.text).toContain('Exit code 0');
        expect(result.isError).toBe(false);
        expect(result.text.length).toBeLessThanOrEqual(LIMITS.shellBytes + 100);
        expect(streamed).toBeGreaterThan(result.text.length);
      }
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test('exact grants persist across modes while auto independently admits direct commands', async () => {
    const root = await directory();
    const finder = openFinder(root);
    let asks = 0;
    let mode: 'ask' | 'auto' = 'ask';
    const tools = riffTools({
      directory: root,
      finder,
      grants: new Set(),
      mode: () => mode,
      ask: () => Promise.resolve(++asks === 1 ? ALLOW_SESSION : DENY),
    });
    const tool = tools.find((tool) => tool.name === 'shell')!;
    const run = (command: string) =>
      tool.execute(
        { command },
        { signal: live(), executionId: 'shell', sessionId: 's' },
      ) as Promise<unknown>;

    try {
      await run('ls');
      await run('ls');
      await expect(run('ls -la')).rejects.toThrow('denied');

      mode = 'auto';

      await run('ls');
      await run('ls -la');
      await expect(run('ls --color=always')).rejects.toThrow('denied');
      expect(asks).toBe(3);
    } finally {
      await finder.destroy();
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe('CHD-605 tester: shell cancellation boundaries', () => {
  test('an already cancelled call publishes no terminal and starts no command', async () => {
    const root = await directory();
    const controller = new AbortController();
    const updates: ToolCallUpdate[] = [];
    const reason = new Error('cancel before launch');

    controller.abort(reason);

    try {
      await expect(
        shell(
          root,
          { command: 'printf never' },
          controller.signal,
          'early',
          (update) => {
            updates.push(update);
          },
        ),
      ).rejects.toBe(reason);
      expect(updates).toEqual([]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test('cancelling one session reaps its child without stopping another session', async () => {
    const first = await directory();
    const second = await directory();
    const controllers = [new AbortController(), new AbortController()];
    const outputs = ['', ''];
    const updates: ToolCallUpdate[][] = [[], []];
    const jobs = [first, second].map((root, index) =>
      shell(
        root,
        {
          command:
            index === 0
              ? "sleep 30 & child=$!; printf 'child:%s\\n' $child; wait"
              : 'printf READY; while test ! -e release; do sleep 0.01; done; printf FINISHED',
        },
        controllers[index]!.signal,
        'same-id-in-different-session',
        (update) => {
          updates[index]!.push(update);

          outputs[index] += meta(update, 'terminal_output_delta')?.data ?? '';
        },
      ),
    );
    const settled = Promise.allSettled(jobs);

    try {
      await until(
        () => /child:\d+/.test(outputs[0]!) && outputs[1]!.includes('READY'),
      );

      const child = Number(/child:(\d+)/.exec(outputs[0]!)![1]);

      controllers[0]!.abort(new Error('cancel first session only'));
      await expect(jobs[0]!).rejects.toThrow('cancel first session only');
      expect(() => process.kill(child, 0)).toThrow();
      expect(controllers[1]!.signal.aborted).toBe(false);
      await writeFile(join(second, 'release'), '');

      const result = await jobs[1]!;

      expect(result.isError).toBe(false);
      expect(result.text).toContain('READYFINISHED');
      expect(outputs[0]).not.toContain('FINISHED');
      expect(meta(updates[0]!.at(-1)!, 'terminal_exit')?.exit_code).toBeNull();
      expect(meta(updates[1]!.at(-1)!, 'terminal_exit')?.exit_code).toBe(0);
    } finally {
      for (const controller of controllers) {
        controller.abort();
      }

      await settled;
      await rm(first, { recursive: true, force: true });
      await rm(second, { recursive: true, force: true });
    }
  });

  test('a late session approval after cancellation cannot start or grant a shell', async () => {
    const root = await directory();
    const finder = openFinder(root);
    const grants = new Set<string>();
    const answer = Promise.withResolvers<string>();
    const controller = new AbortController();
    let asked = 0;
    let began = 0;
    const tools = riffTools({
      directory: root,
      finder,
      grants,
      mode: () => 'ask',
      begin: () => {
        began++;
      },
      ask: () => (++asked === 1 ? answer.promise : Promise.resolve(DENY)),
    });
    const tool = tools.find((tool) => tool.name === 'shell')!;
    const run = (signal: AbortSignal) =>
      tool.execute(
        { command: 'printf never' },
        { signal, executionId: 'cancelled-shell', sessionId: 's' },
      ) as Promise<unknown>;
    const job = run(controller.signal);
    const settled = Promise.allSettled([job]);

    try {
      await until(() => asked === 1);
      controller.abort(new Error('cancel permission wait'));
      answer.resolve(ALLOW_SESSION);
      await expect(job).rejects.toThrow('cancel permission wait');
      expect(grants.size).toBe(0);
      expect(began).toBe(0);
      await expect(run(live())).rejects.toThrow('denied');
      expect(asked).toBe(2);
    } finally {
      controller.abort();
      answer.resolve(DENY);
      await settled;
      await finder.destroy();
      await rm(root, { recursive: true, force: true });
    }
  });
});

async function commandSession(
  mode: 'auto' | 'ask' = 'auto',
  grants = new Set<string>(),
) {
  const root = await directory();
  const home = join(root, 'fixture-home');

  await mkdir(home);

  const startup = join(home, 'bashenv');
  const bin = join(home, 'bin');

  await mkdir(bin);
  await writeFile(
    join(bin, 'node'),
    '#!/bin/sh\nprintf "fixture-node-version\\n"\n',
    { mode: 0o755 },
  );

  await writeFile(startup, '');

  const environment = {
    HOME: home,
    XDG_CONFIG_HOME: home,
    GIT_CONFIG_NOSYSTEM: '1',
    SHELL: '/bin/bash',
    BASH_ENV: startup,
    PATH: `${bin}:/usr/bin:/bin`,
    CHORD_RESOURCE_FIXTURE: 'true',
  };
  const finder = openFinder(root);
  const updates: ToolCallUpdate[] = [];
  const counts = { ask: 0, review: 0, begin: 0 };
  const tools = riffTools({
    directory: root,
    finder,
    grants,
    commandEnvironment: environment,
    mode: () => mode,
    begin: () => {
      counts.begin++;
    },
    stream: () => (update) => {
      updates.push(update);
    },
    review: () => {
      counts.review++;

      return Promise.resolve({ outcome: 'clear' });
    },
    ask: () => {
      counts.ask++;

      return Promise.resolve(DENY);
    },
  });
  const tool = tools.find((tool) => tool.name === 'shell')!;

  return {
    root,
    environment,
    updates,
    counts,
    git: (...args: string[]) =>
      execFileSync('/usr/bin/git', args, {
        cwd: root,
        env: environment,
        stdio: 'pipe',
      }),
    run: (command: string) =>
      tool.execute(
        { command },
        { signal: live(), executionId: 'admission', sessionId: 'fixture' },
      ) as Promise<FxToolResult>,
    close: async () => {
      await finder.destroy();
      await rm(root, { recursive: true, force: true });
    },
  };
}

describe('CHD-609 command admission and terminal streaming', () => {
  test('auto direct pipeline streams terminal output without review or permission', async () => {
    const s = await commandSession();

    try {
      const result = await s.run("printf '%s' 'direct output' | wc -c");

      expect(result.isError).toBe(false);
      expect(result.text).toContain('13');
      expect(s.counts).toEqual({ ask: 0, review: 0, begin: 1 });
      expect(
        s.updates.some((u) =>
          meta(u, 'terminal_output_delta')?.data?.includes('13'),
        ),
      ).toBe(true);
      expect(meta(s.updates.at(-1)!, 'terminal_exit')?.exit_code).toBe(0);
    } finally {
      await s.close();
    }
  });

  test('ask mode still asks for an ungranted direct command', async () => {
    const s = await commandSession('ask');

    try {
      await expect(s.run('printf x')).rejects.toThrow('denied');
      expect(s.counts).toEqual({ ask: 1, review: 0, begin: 0 });
      expect(s.updates).toEqual([]);
    } finally {
      await s.close();
    }
  });

  test('exact grants precede both direct planning and review', async () => {
    const command = 'printf granted > granted.txt';
    const s = await commandSession('auto', new Set([`shell:${command}`]));

    try {
      expect((await s.run(command)).isError).toBe(false);
      expect(await readFile(join(s.root, 'granted.txt'), 'utf8')).toBe(
        'granted',
      );
      expect(s.counts).toEqual({ ask: 0, review: 0, begin: 1 });
    } finally {
      await s.close();
    }
  });

  test('reversible commands run after a fresh captured-name check', async () => {
    const s = await commandSession();

    try {
      expect((await s.run('node --version')).isError).toBe(false);
      expect(s.counts).toEqual({ ask: 0, review: 0, begin: 1 });
    } finally {
      await s.close();
    }
  });

  test('commands outside both lists still use the existing review', async () => {
    const s = await commandSession();

    try {
      const result = await s.run('printf reviewed; pwd');

      expect(result.text).toContain('reviewed');
      expect(s.counts).toEqual({ ask: 0, review: 1, begin: 1 });
    } finally {
      await s.close();
    }
  });

  test('admitted git stage uses the safe invocation without review', async () => {
    const s = await commandSession();

    try {
      s.git('init', '-q');

      const result = await s.run('git status --short | wc -l');

      expect(result.isError).toBe(false);
      expect(s.counts).toEqual({ ask: 0, review: 0, begin: 1 });
      expect(meta(s.updates.at(-1)!, 'terminal_exit')?.exit_code).toBe(0);
    } finally {
      await s.close();
    }
  });

  test.each(['git status', 'git status --ignored'])(
    'safe_git refusal holds before any fallback: %s',
    async (command) => {
      const s = await commandSession();

      try {
        s.git('init', '-q');
        s.git('config', 'filter.a=b.clean', 'malicious');
        await expect(s.run(command)).rejects.toThrow(
          'chord did not run this git command',
        );
        expect(s.counts).toEqual({ ask: 0, review: 0, begin: 0 });
        expect(s.updates).toEqual([]);
      } finally {
        await s.close();
      }
    },
  );
});

describe('CHD-609 reversible alias gate integration', () => {
  test('captured alias in any word falls back to review; the next call captures again', async () => {
    const s = await commandSession();

    try {
      await writeFile(s.environment.BASH_ENV, "alias node='false'\n");
      expect((await s.run('node --version')).isError).toBe(false);
      expect(s.counts.review).toBe(1);
      await writeFile(s.environment.BASH_ENV, '');
      expect((await s.run('node --version')).isError).toBe(false);
      expect(s.counts.review).toBe(1);
      expect(s.counts.begin).toBe(2);
    } finally {
      await s.close();
    }
  });

  test('unknown shell falls back to review', async () => {
    const s = await commandSession();

    try {
      s.environment.SHELL = '/bin/sh';

      expect((await s.run('node --version')).isError).toBe(false);
      expect(s.counts.review).toBe(1);
    } finally {
      await s.close();
    }
  });
});

test('CHD-609 actual reviewed shell execution uses only fixture startup and environment', async () => {
  const s = await commandSession();

  try {
    await writeFile(
      s.environment.BASH_ENV,
      'export CHORD_FIXTURE_VALUE=fixture-shell\n',
    );

    const result = await s.run('printf %s "$CHORD_FIXTURE_VALUE"');

    expect(result.text).toContain('fixture-shell');
    expect(result.isError).toBe(false);
    expect(s.counts).toEqual({ ask: 0, review: 1, begin: 1 });
  } finally {
    await s.close();
  }
});

describe('CHD-609 tester: direct admission lifecycle', () => {
  test('a direct command failure returns its real exit without review fallback', async () => {
    const s = await commandSession();

    try {
      const result = await s.run('ls -- no-such-fixture-entry');

      expect(result.isError).toBe(true);
      expect(result.text).toContain('no-such-fixture-entry');
      expect(s.counts).toEqual({ ask: 0, review: 0, begin: 1 });
      expect(
        meta(s.updates.at(-1)!, 'terminal_exit')?.exit_code,
      ).toBeGreaterThan(0);
    } finally {
      await s.close();
    }
  });

  test('unsafe git in a later stage holds the entire pipeline before streaming', async () => {
    const s = await commandSession();

    try {
      s.git('init', '-q');
      s.git('config', 'filter.a=b.clean', 'unused');
      await expect(
        s.run("printf '%s' 'must-not-stream' | git status"),
      ).rejects.toThrow('chord did not run this git command');
      expect(s.counts).toEqual({ ask: 0, review: 0, begin: 0 });
      expect(s.updates).toEqual([]);
    } finally {
      await s.close();
    }
  });

  test('an exact shell grant remains authoritative when safe git would refuse', async () => {
    const command = 'git status --ignored';
    const s = await commandSession('auto', new Set([`shell:${command}`]));

    try {
      s.git('init', '-q');
      s.git('config', 'filter.a=b.clean', 'unused');

      const result = await s.run(command);

      expect(result.isError).toBe(false);
      expect(s.counts).toEqual({ ask: 0, review: 0, begin: 1 });
      expect(meta(s.updates.at(-1)!, 'terminal_exit')?.exit_code).toBe(0);
    } finally {
      await s.close();
    }
  });

  test('cancellation at begin cannot start an admitted direct command', async () => {
    const root = await directory();
    const home = join(root, 'home');

    await mkdir(home);

    const finder = openFinder(root);
    const controller = new AbortController();
    const reason = new Error('cancel before direct launch');
    const updates: ToolCallUpdate[] = [];
    const counts = { begin: 0, review: 0, ask: 0 };
    const grants = new Set<string>();
    const tools = riffTools({
      directory: root,
      finder,
      grants,
      commandEnvironment: {
        HOME: home,
        XDG_CONFIG_HOME: home,
        GIT_CONFIG_NOSYSTEM: '1',
        SHELL: '/bin/sh',
        CHORD_RESOURCE_FIXTURE: 'true',
      },
      mode: () => 'auto',
      begin: () => {
        counts.begin++;
        controller.abort(reason);
      },
      stream: () => (update) => {
        updates.push(update);
      },
      review: () => {
        counts.review++;

        return Promise.resolve({ outcome: 'clear' });
      },
      ask: () => {
        counts.ask++;

        return Promise.resolve(DENY);
      },
    });
    const tool = tools.find((tool) => tool.name === 'shell')!;

    try {
      await expect(
        tool.execute(
          { command: "printf '%s' 'never-launched'" },
          {
            signal: controller.signal,
            executionId: 'cancel-direct',
            sessionId: 'fixture',
          },
        ),
      ).rejects.toBe(reason);
      expect(counts).toEqual({ begin: 1, review: 0, ask: 0 });
      expect(updates).toEqual([]);
      expect(grants.size).toBe(0);
    } finally {
      controller.abort();
      await finder.destroy();
      await rm(root, { recursive: true, force: true });
    }
  });
});

describe('CHD-609 tester: reversible shell startup', () => {
  test('a zsh startup alias named by a reversible command requires review before execution', async () => {
    const s = await commandSession();
    const startup = join(s.environment.HOME, '.zshenv');

    Object.assign(s.environment, {
      SHELL: '/bin/zsh',
      ZDOTDIR: s.environment.HOME,
    });

    try {
      await writeFile(startup, "alias node='printf alias-node'\n");

      const held = await s.run('node --version');

      expect(held.isError).toBe(false);
      expect(held.text).toContain('alias-node');
      expect(s.counts).toEqual({ ask: 0, review: 1, begin: 1 });
      await writeFile(startup, '');

      const fresh = await s.run('node --version');

      expect(fresh.text).toContain('fixture-node-version');
      expect(s.counts).toEqual({ ask: 0, review: 1, begin: 2 });
    } finally {
      await s.close();
    }
  });
});

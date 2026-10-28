import { describe, expect, test } from 'bun:test';
import { spawn, spawnSync, type ChildProcess } from 'node:child_process';
import assert from 'node:assert/strict';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { quote } from 'shell-quote';
import { until } from './ui/app/render.tsx';
import { fakeAgentCommand } from './fixtures/fake.ts';

const alive = (pid: number) => {
  try {
    process.kill(pid, 0);

    return true;
  } catch {
    return false;
  }
};

const stop = (pid: number | undefined, signal: NodeJS.Signals) => {
  if (pid === undefined || pid <= 0) {
    return;
  }

  try {
    process.kill(pid, signal);
  } catch (failure) {
    if ((failure as NodeJS.ErrnoException).code !== 'ESRCH') {
      throw failure;
    }
  }
};

interface OwnedStartup {
  readonly targetPid?: number;
  readonly controllerPid: number;
}

async function stopTarget(child: OwnedStartup, grace = 3_000) {
  if (child.targetPid && !alive(child.targetPid)) {
    return;
  }

  stop(child.controllerPid, 'SIGTERM');

  try {
    await until(
      `owned CLI ${child.targetPid} reaped`,
      () => !child.targetPid || !alive(child.targetPid),
      grace,
    );
  } catch {
    stop(child.targetPid, 'SIGKILL');
    // Only the still-live controller can reap its direct child.
    await until(
      `owned CLI ${child.targetPid} reaped`,
      () => !child.targetPid || !alive(child.targetPid),
    );
  }
}

async function directExit<T>(
  controller: ChildProcess,
  finished: Promise<T>,
): Promise<T> {
  const ended = () =>
    controller.exitCode !== null || controller.signalCode !== null;

  try {
    await until('direct controller exit', ended, 3_000);
  } catch {
    stop(controller.pid, 'SIGKILL');
    await until('direct controller killed', ended);
  }

  return await finished;
}

for (const choose of [false, true]) {
  test(`CHD-532 actual handler keeps all startup factories behind choice, choose=${choose}`, () => {
    const place = mkdtempSync(join(tmpdir(), 'chord-start-boundary-'));
    const project = join(place, 'project');
    const settings = join(project, '.chord', 'settings.json');
    const content = JSON.stringify({
      agent: 'unknown-unselected-default',
      agents: { fixture: { command: fakeAgentCommand() } },
    });

    mkdirSync(join(project, '.chord'), { recursive: true });
    writeFileSync(settings, content);

    try {
      const ran = spawnSync(
        process.execPath,
        [
          fileURLToPath(
            new URL('./fixtures/startup_boundary.tsx', import.meta.url),
          ),
          ...(choose ? ['--choose'] : []),
        ],
        {
          env: {
            ...process.env,
            XDG_CONFIG_HOME: join(place, 'config'),
            XDG_STATE_HOME: join(place, 'state'),
            CHORD_RESOURCE_FIXTURE: 'true',
            CHORD_START_PROJECT: project,
          },
          encoding: 'utf8',
          timeout: 15_000,
        },
      );

      expect(ran.status, ran.stderr).toBe(0);
      expect(JSON.parse(ran.stdout.trim())).toEqual({
        session: 0,
        server: 0,
        resources: 0,
        copier: choose ? 1 : 0,
      });
      expect(readFileSync(settings, 'utf8')).toBe(content);
    } finally {
      rmSync(place, { recursive: true, force: true });
    }
  });
}

for (const mode of [
  'select',
  'cancel',
  'explicit',
  'model',
  'catalog',
  'refused',
  'missing',
] as const) {
  test(`CHD-532 actual fake CLI ${mode} uses the intended startup route`, async () => {
    const place = `/tmp/chord-qa.chd532-cli-${process.pid}-${mode}`;
    const socket = `chd532-${process.pid}-${mode}`;
    const project = join(place, 'project');
    const log = join(place, 'starts');
    const receipt = join(place, 'exit.json');
    const ownership = join(place, 'owned.json');
    const settings = join(project, '.chord', 'settings.json');
    const command = [
      process.execPath,
      fileURLToPath(new URL('./fixtures/startup_agent.ts', import.meta.url)),
    ];
    const preferred =
      mode === 'refused' || mode === 'catalog'
        ? 'claude'
        : mode === 'missing'
          ? 'fx'
          : 'fixture';
    const stopped = mode === 'refused' || mode === 'missing';
    const content = JSON.stringify({
      agent: mode === 'cancel' ? 'unknown-unselected-default' : preferred,
      mouse: false,
      agents: {
        fixture: { command, model: 'fake-small' },
        ...(mode === 'refused'
          ? { claude: { command: 7 } }
          : mode === 'catalog'
            ? { claude: { command, model: 'fake-small' } }
            : {}),
      },
    });

    rmSync(place, { recursive: true, force: true });
    mkdirSync(join(project, '.chord'), { recursive: true });
    writeFileSync(settings, content);

    const env = {
      ...process.env,
      XDG_CONFIG_HOME: join(place, 'config'),
      XDG_STATE_HOME: join(place, 'state'),
      CHORD_RESOURCE_FIXTURE: 'true',
      CHORD_START_LOG: log,
    };
    const tmux = (...args: string[]) =>
      spawnSync('tmux', ['-L', socket, ...args], { env, encoding: 'utf8' });
    const frame = () => tmux('capture-pane', '-t', 'picker', '-p').stdout;
    let serverPid = 0;
    const observations: unknown[] = [];
    const errors: unknown[] = [];
    const owned = () =>
      existsSync(ownership)
        ? (JSON.parse(readFileSync(ownership, 'utf8')) as {
            targetPid?: number;
            controllerPid: number;
          })
        : undefined;
    const observed = (phase: string) => {
      const child = owned();
      const pids = [child?.targetPid, child?.controllerPid, serverPid]
        .filter((pid) => pid !== undefined && pid > 0)
        .join(',');

      return {
        phase,
        socket,
        serverPid,
        ownership: child,
        receipt: existsSync(receipt)
          ? readFileSync(receipt, 'utf8')
          : undefined,
        processes:
          pids === ''
            ? undefined
            : spawnSync('ps', ['-o', 'pid=,ppid=,stat=,args=', '-p', pids], {
                encoding: 'utf8',
                timeout: 1_000,
              }),
        pane: tmux(
          'display-message',
          '-p',
          '-t',
          'picker',
          '#{pid}|#{pane_pid}|#{pane_current_command}|#{pane_dead}|#{pane_dead_status}|#{pane_dead_signal}',
        ),
      };
    };

    const diagnostic = () =>
      JSON.stringify({
        version: tmux('-V'),
        current: observed('diagnostic'),
        observations,
        controllerError: existsSync(`${receipt}.error`)
          ? readFileSync(`${receipt}.error`, 'utf8')
          : undefined,
        frame: frame(),
      });
    const exited = async (expected: number) => {
      await until(`fake CLI ${mode} target exit receipt`, () => {
        if (existsSync(`${receipt}.error`)) {
          throw new Error(diagnostic());
        }

        return existsSync(receipt);
      }).catch((failure: Error) => {
        throw new Error(`${failure.message}; ${diagnostic()}`);
      });

      const result = JSON.parse(readFileSync(receipt, 'utf8')) as {
        targetPid: number;
        controllerPid: number;
        code: number | null;
        signal: string | null;
        error: string | null;
      };

      observations.push(observed('target-exit-receipt'));

      const detail = diagnostic();
      const owner = owned();

      assert(owner?.targetPid !== undefined, detail);
      expect(result.targetPid, detail).toBe(owner.targetPid);
      expect(result.targetPid, detail).toBeGreaterThan(0);
      expect(result.controllerPid, detail).toBe(owner.controllerPid);
      expect(result.targetPid, detail).not.toBe(result.controllerPid);
      expect(result.code, detail).toBe(expected);
      expect(result.signal, detail).toBeNull();
      expect(result.error, detail).toBeNull();
    };

    const starts = () =>
      existsSync(log)
        ? readFileSync(log, 'utf8')
            .trim()
            .split('\n')
            .filter(Boolean)
            .map(Number)
        : [];

    try {
      const opened = tmux(
        'new-session',
        '-d',
        '-s',
        'picker',
        '-x',
        '80',
        '-y',
        '24',
        `exec ${quote([
          ...(mode === 'missing'
            ? ['/usr/bin/env', `PATH=${join(place, 'empty')}`]
            : []),
          process.execPath,
          fileURLToPath(
            new URL('./fixtures/startup_controller.ts', import.meta.url),
          ),
          receipt,
          ownership,
          ...(process.env['CHORD_START_BINARY']
            ? [process.env['CHORD_START_BINARY']!]
            : [
                process.execPath,
                fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
              ]),
          ...(mode === 'explicit' ? ['fixture'] : []),
          ...(mode === 'model' ? ['--model', 'fake-large'] : []),
          '-C',
          project,
        ])}`,
      );

      expect(opened.status, opened.stderr).toBe(0);

      serverPid = Number(
        tmux('display-message', '-p', '-t', 'picker', '#{pid}').stdout.trim(),
      );

      expect(serverPid).toBeGreaterThan(0);
      expect(
        tmux('set-option', '-t', 'picker', 'remain-on-exit', 'on').status,
      ).toBe(0);

      if (mode !== 'explicit') {
        await until('actual unnamed startup picker', () =>
          frame().includes('Select agent'),
        );
        expect(starts()).toEqual([]);
        expect(frame()).not.toContain('Fake Small');

        if (mode === 'cancel') {
          tmux('send-keys', '-t', 'picker', 'Escape');
          await exited(0);
          expect(starts()).toEqual([]);
        } else {
          expect(
            frame()
              .split('\n')
              .find((line) => line.includes('❯')),
          ).toContain(preferred);
          tmux('send-keys', '-t', 'picker', 'Enter');
        }
      }

      if (stopped) {
        await exited(1);
        expect(frame()).toContain(
          mode === 'missing' ? 'which is not on PATH' : 'expected a string',
        );
        expect(starts()).toEqual([]);
      }

      if (mode !== 'cancel' && !stopped) {
        await until('selected fake agent is ready', () =>
          frame().includes(mode === 'model' ? 'Fake Large' : 'Fake Small'),
        );
        expect(starts()).toHaveLength(1);
        expect(frame()).not.toContain('Select agent');
        tmux('send-keys', '-t', 'picker', '-l', 'text');
        tmux('send-keys', '-t', 'picker', 'Enter');
        await until('selected fake agent answers', () =>
          frame().includes('Hello, world.'),
        );
        tmux('send-keys', '-t', 'picker', 'C-c', 'C-c');
        await exited(0);
      }

      expect(readFileSync(settings, 'utf8')).toBe(content);
    } catch (failure) {
      errors.push(failure);
    } finally {
      try {
        const child = owned();
        const controller =
          child?.controllerPid ??
          Number(
            tmux(
              'display-message',
              '-p',
              '-t',
              'picker',
              '#{pane_pid}',
            ).stdout.trim(),
          );

        observations.push(observed('before-cleanup-signals'));

        try {
          await stopTarget({ ...child, controllerPid: controller });
        } catch (failure) {
          errors.push(new Error(`${String(failure)}; ${diagnostic()}`));
        }

        observations.push(observed('target-reap-before-tmux-release'));
        // tmux owns this controller: release its parent before requiring PID absence.
        tmux('kill-server');
        observations.push(observed('after-tmux-release'));

        try {
          await until('tmux-owned target, controller and server reaped', () =>
            [child?.targetPid, controller, serverPid].every(
              (pid) => !pid || !alive(pid),
            ),
          );
          observations.push(observed('all-owned-PIDs-absent'));
        } catch (failure) {
          errors.push(new Error(`${String(failure)}; ${diagnostic()}`));
        }

        for (const pid of starts()) {
          stop(pid, 'SIGTERM');

          try {
            await until(`fake process ${pid} exited`, () => !alive(pid), 3_000);
          } catch {
            stop(pid, 'SIGKILL');

            try {
              await until(`fake process ${pid} killed`, () => !alive(pid));
            } catch (failure) {
              errors.push(new Error(`${String(failure)}; ${diagnostic()}`));
            }
          }
        }
      } catch (failure) {
        errors.push(failure);
      } finally {
        tmux('kill-server');

        try {
          rmSync(place, { recursive: true, force: true });
        } catch (failure) {
          errors.push(failure);
        }
      }
    }

    if (errors.length > 1) {
      throw new AggregateError(
        errors,
        'Startup assertion and/or owned cleanup failed',
      );
    }

    if (errors.length === 1) {
      throw errors[0];
    }
  });
}

test('CHD-532 cleanup fallback reaps its target before stopping the controller', async () => {
  const place = mkdtempSync(join(tmpdir(), 'chord-start-cleanup-'));
  const receipt = join(place, 'exit.json');
  const ownership = join(place, 'owned.json');
  const ready = join(place, 'ready');
  const controller = spawn(
    process.execPath,
    [
      fileURLToPath(
        new URL('./fixtures/startup_controller.ts', import.meta.url),
      ),
      receipt,
      ownership,
      process.execPath,
      '-e',
      "const fs = require('node:fs'); process.on('SIGTERM', () => {}); fs.writeFileSync(process.argv[1], 'ready'); setInterval(() => {}, 1000);",
      ready,
    ],
    { stdio: 'ignore' },
  );
  const finished = new Promise<{
    code: number | null;
    signal: NodeJS.Signals | null;
  }>((resolve, reject) => {
    controller.once('error', reject);
    controller.once('exit', (code, signal) => resolve({ code, signal }));
  });

  let child: OwnedStartup | undefined;
  const failures: unknown[] = [];

  try {
    await until(
      'fixture target ignores TERM',
      () => existsSync(ready) && existsSync(ownership),
    );

    child = JSON.parse(readFileSync(ownership, 'utf8')) as OwnedStartup;

    expect(child.controllerPid).toBe(controller.pid!);
    // No grace forces the parent's TERM handler and the fallback to race.
    await stopTarget(child, 0);
    await directExit(controller, finished);

    const result = JSON.parse(readFileSync(receipt, 'utf8')) as {
      targetPid: number;
      signal: string;
      code: null;
      error: null;
    };

    expect(result.targetPid).toBe(child.targetPid!);
    expect(result.signal).toBe('SIGKILL');
    expect(result.code).toBeNull();
    expect(result.error).toBeNull();
    expect(await finished).toEqual({ code: 1, signal: null });
    expect(alive(child.targetPid!)).toBe(false);
  } catch (failure) {
    failures.push(failure);
  } finally {
    try {
      child ??= existsSync(ownership)
        ? (JSON.parse(readFileSync(ownership, 'utf8')) as OwnedStartup)
        : { controllerPid: controller.pid ?? 0 };

      await stopTarget(child);
      await directExit(controller, finished);
    } catch (failure) {
      failures.push(failure);
    } finally {
      try {
        rmSync(place, { recursive: true, force: true });
      } catch (failure) {
        failures.push(failure);
      }
    }
  }

  if (failures.length > 1) {
    throw new AggregateError(
      failures,
      'Direct child assertion and/or cleanup failed',
    );
  }

  if (failures.length === 1) {
    throw failures[0];
  }
});

describe('CHD-532 tester: actual handler bypass routes', () => {
  for (const mode of [
    'explicit',
    'command',
    'stdin-only',
    'stdout-only',
    'continue',
    'resume-id',
    'resume-picker',
    'headless',
  ] as const) {
    test(`${mode} never enters the new agent picker`, () => {
      const place = mkdtempSync(join(tmpdir(), 'chord-start-skip-'));
      const project = join(place, 'project');
      const settings = join(project, '.chord', 'settings.json');
      const script = join(place, 'route.ts');
      const command = fakeAgentCommand();
      const content = JSON.stringify({
        agent: 'fixture',
        agents: { fixture: { command } },
      });
      const args: string[] = ['-C', project];

      if (mode === 'explicit') {
        args.push('fixture');
      }

      if (mode === 'command') {
        args.push('--agent-command', quote(command));
      }

      if (mode === 'continue') {
        args.push('--continue');
      }

      if (mode === 'resume-id') {
        args.push('--resume=unrecorded-fixture');
      }

      if (mode === 'resume-picker') {
        args.push('--resume');
      }

      if (mode === 'headless') {
        args.push('-p', 'text');
      }

      mkdirSync(join(project, '.chord'), { recursive: true });
      writeFileSync(settings, content);
      writeFileSync(
        script,
        `import { spyOn } from 'bun:test';
import { writeFileSync } from 'node:fs';
const mark = () => writeFileSync(${JSON.stringify(join(place, 'called'))}, 'called');
Object.defineProperty(process.stdin, 'isTTY', { value: ${mode !== 'stdout-only'}, configurable: true });
Object.defineProperty(process.stdout, 'isTTY', { value: ${mode !== 'stdin-only'}, configurable: true });
const { cli, startServices } = await import(${JSON.stringify(new URL('../src/main.tsx', import.meta.url).pathname)});
const calls = { terminal: 0, render: 0, copier: 0 };
const stop = new Error('fixture boundary');
spyOn(startServices, 'openTerminal').mockImplementation(async () => { calls.terminal++; mark(); return { renderer: {}, dark: true }; });
spyOn(startServices, 'render').mockImplementation(() => { calls.render++; mark(); throw stop; });
spyOn(startServices, 'copier').mockImplementation(() => { calls.copier++; mark(); throw stop; });
try {
  await cli.noExit().throwErrors().parse(${JSON.stringify(args)});
} catch (error) {
  console.log(JSON.stringify({ calls, error: error.message }));
}
`,
      );

      try {
        const ran = spawnSync(process.execPath, [script], {
          env: {
            ...process.env,
            XDG_CONFIG_HOME: join(place, 'config'),
            XDG_STATE_HOME: join(place, 'state'),
            CHORD_RESOURCE_FIXTURE: 'true',
          },
          encoding: 'utf8',
          timeout: 15_000,
        });

        if (mode === 'continue' || mode === 'resume-picker') {
          expect(ran.status).toBe(2);
          expect(ran.stderr).toContain('No earlier fixture session');
          expect(existsSync(join(place, 'called'))).toBe(false);
        } else if (mode === 'headless') {
          expect(ran.status, ran.stderr).toBe(0);
          expect(ran.stdout).toContain('Hello, world.');
          expect(existsSync(join(place, 'called'))).toBe(false);
        } else {
          const result = JSON.parse(ran.stdout.trim());

          expect(ran.status, ran.stderr).toBe(0);
          expect(result.calls.terminal).toBe(1);
          expect(result.calls.render).toBe(0);

          expect(result.calls.copier).toBe(1);
          expect(result.error).toBe('fixture boundary');
        }

        expect(readFileSync(settings, 'utf8')).toBe(content);
      } finally {
        rmSync(place, { recursive: true, force: true });
      }
    });
  }
});

import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ValidationError } from '@cliffy/command';
import { quote } from 'shell-quote';
import { chordCommand } from '../src/cli.ts';
import { fakeAgentCommand } from './fixtures/fake.ts';
import { recordSession } from './fixtures/records.ts';
import {
  resumeCommand,
  sessionById,
  type SessionRecord,
} from '../src/session/sessions.ts';

/** What chord's own flags make of `argv`, with nothing run on them. */
async function parsed(argv: string[]) {
  let seen:
    | {
        agent?: string;
        cwd: string;
        model?: string;
        resume?: string | true;
      }
    | undefined;

  await chordCommand()
    .noExit()
    .throwErrors()
    .action((options, agent) => {
      seen = {
        cwd: options.cwd,
        ...(agent === undefined ? {} : { agent }),
        ...(options.model === undefined ? {} : { model: options.model }),
        ...(options.resume === undefined ? {} : { resume: options.resume }),
      };
    })
    .parse(argv);

  return seen;
}

/** The session main.tsx opens for one id from `argv`: id, agent, directory. */
async function resumed(argv: string[], records: SessionRecord[]) {
  const seen = await parsed(argv);
  const agent = seen?.agent ?? 'claude';
  const resume = sessionById(records, String(seen?.resume), {
    agent,
    cwd: seen?.cwd ?? '/',
  });

  return [resume.sessionId, agent, resume.cwd];
}

function record(id: string, agent: string, cwd: string): SessionRecord {
  return {
    path: `/state/records/${id}.jsonl`,
    sessionId: id,
    agent,
    cwd,
    lastUsedAt: 1,
    prompt: id,
  };
}

test('--resume with no id asks for the picker, the agent before or after it', async () => {
  expect((await parsed(['--resume']))?.resume).toStrictEqual(true);
  expect(await parsed(['claude', '-r'])).toStrictEqual({
    agent: 'claude',
    cwd: process.cwd(),
    resume: true,
  });
  expect(await parsed(['-r', '-C', '/tmp'])).toStrictEqual({
    cwd: '/tmp',
    resume: true,
  });
});

test('an id is read as one, a UUID or a window id alike, and a second -r is refused by Cliffy (Q181)', async () => {
  for (const id of ['aaa', 'w-1a2b3c4d', '-x', '0199a1b2-3c4d-7e8f']) {
    expect((await parsed([`--resume=${id}`]))?.resume).toStrictEqual(id);
  }

  for (const argv of [
    ['-r', 'aaa', '-r', 'ccc'],
    ['--resume', 'aaa', '--resume=ccc'],
    ['-r', 'aaa', '-r'],
  ]) {
    await expect(parsed(argv)).rejects.toThrow('can only occur once');
  }
});

test("a word equal to one of chord's option names is not an id: the owner's accepted limit", async () => {
  // The optional id is Cliffy's own [id:string], which never takes an option
  // name as the value; the owner kept it over rewriting argv.
  expect(await parsed(['--resume', 'model'])).toStrictEqual({
    agent: 'model',
    cwd: process.cwd(),
    resume: true,
  });
  expect(await parsed(['--resume=c'])).toStrictEqual({
    cwd: process.cwd(),
    resume: true,
  });
});

test('one id from argv is as it was, the agent before or after it', async () => {
  const records = [record('aaa', 'codex', '/project')];
  const find = { agent: 'codex', cwd: '/project' };

  expect((await parsed(['--resume', 'aaa']))?.resume).toStrictEqual('aaa');
  expect(sessionById(records, 'aaa', find).record).toStrictEqual(
    '/state/records/aaa.jsonl',
  );

  for (const argv of [
    ['--resume', 'aaa', 'codex'],
    ['codex', '--resume', 'aaa'],
    ['-r', 'aaa', 'codex', '-C', '/tmp'],
  ]) {
    expect(await resumed(argv, records)).toStrictEqual([
      'aaa',
      'codex',
      '/project',
    ]);
  }

  // An id chord never saw goes to the agent named, as before.
  expect(
    await resumed(['--resume', 'zzz', 'codex', '-C', '/w'], records),
  ).toStrictEqual(['zzz', 'codex', '/w']);
});

test('[agent] and the other flags sit on either side of the id', async () => {
  expect(
    await parsed(['fake', '-C', '/tmp', '-r', 'aaa', '-m', 'opus']),
  ).toStrictEqual({
    agent: 'fake',
    cwd: '/tmp',
    model: 'opus',
    resume: 'aaa',
  });
  // A flag's value is never taken for an id, however it reads.
  expect(await parsed(['-C', '--resume', '-r', 'aaa', 'fake'])).toStrictEqual({
    agent: 'fake',
    cwd: '--resume',
    resume: 'aaa',
  });
  await expect(parsed(['--continue', '--resume', 'aaa'])).rejects.toThrow(
    ValidationError,
  );
});

test('--resume with no id asks for the picker, not an id, and is refused only where nobody can pick', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-cli-'));

  try {
    const { status, stderr: said } = spawnSync(
      process.execPath,
      [
        fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
        'fake',
        '--agent-command',
        'true',
        '--resume',
        '-C',
        dir,
      ],
      {
        env: {
          ...process.env,
          XDG_STATE_HOME: join(dir, 'state'),
          XDG_CONFIG_HOME: join(dir, 'config'),
          NO_COLOR: '1',
        },
        stdio: ['ignore', 'pipe', 'pipe'],
        encoding: 'utf8',
      },
    );

    expect(status).toStrictEqual(2);
    expect(said).toContain('--resume needs an id when not in a terminal');
    expect(!said.includes('Missing value'), said).toBeTruthy();
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("a refused command for the agent starts nothing, chord's own command neither, and says why (CHD-466)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-cli-'));

  try {
    await mkdir(join(dir, 'config', 'chord'), { recursive: true });
    await writeFile(
      join(dir, 'config', 'chord', 'settings.json'),
      JSON.stringify({ agents: { codex: { command: 7 } } }),
    );

    const { status, stderr: said } = spawnSync(
      process.execPath,
      [
        fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
        'codex',
        '-p',
        'hi',
        '-C',
        dir,
      ],
      {
        env: {
          ...process.env,
          HOME: dir,
          XDG_STATE_HOME: join(dir, 'state'),
          XDG_CONFIG_HOME: join(dir, 'config'),
          // No npx to run: were the registry's command tried, it would fail
          // on PATH, not start the agent.
          PATH: join(dir, 'bin'),
          NO_COLOR: '1',
        },
        stdio: ['ignore', 'pipe', 'pipe'],
        encoding: 'utf8',
      },
    );

    expect(status).toStrictEqual(1);
    // The warning says what happens, then the refusal says it again.
    expect(said).toContain(
      '"agents.codex.command": expected a string, got a number · codex will not start',
    );
    expect(said).not.toContain('ignored');
    expect(said).toContain(
      'chord: codex not started: agents.codex.command in config/chord/settings.json: expected a string, got a number',
    );
    expect(said).not.toContain('npx');
  } finally {
    await rm(dir, { recursive: true });
  }
});

describe('CHD-466 U2 tester: initial agent on resume', () => {
  test('session resume refuses the initial runtime in the record directory', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-refused-resume-'));
    const here = join(dir, 'here');
    const there = join(dir, 'there');
    const config = join(dir, 'config');
    const stateHome = join(dir, 'state');
    const stateDir = join(stateHome, 'chord');
    const marker = join(dir, 'started');
    const wrapper = join(dir, 'fake-start.ts');

    try {
      await mkdir(here);
      await mkdir(join(there, '.chord'), { recursive: true });
      await mkdir(join(config, 'chord'), { recursive: true });
      await writeFile(
        wrapper,
        'import { writeFileSync } from "node:fs"; writeFileSync(' +
          JSON.stringify(marker) +
          ', "started"); await import(' +
          JSON.stringify(fakeAgentCommand()[1]) +
          ');',
      );
      await writeFile(
        join(config, 'chord', 'settings.json'),
        JSON.stringify({
          agent: 'fake',
          agents: { fake: { command: [process.execPath, wrapper] } },
        }),
      );

      const sessionId = await recordSession({
        stateDir,
        cwd: there,
        command: fakeAgentCommand(),
        prompts: ['text'],
      });

      await writeFile(
        join(there, '.chord', 'settings.json'),
        JSON.stringify({ agents: { fake: { command: null } } }),
      );

      const result = spawnSync(
        process.execPath,
        [
          fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
          '-C',
          here,
          '--resume',
          sessionId,
        ],
        {
          env: {
            ...process.env,
            HOME: dir,
            XDG_CONFIG_HOME: config,
            XDG_STATE_HOME: stateHome,
            PATH: join(dir, 'no-programs'),
            NO_COLOR: '1',
          },
          stdio: ['ignore', 'pipe', 'pipe'],
          encoding: 'utf8',
          timeout: 10000,
        },
      );

      expect(await readFile(marker, 'utf8').catch(() => '')).toBe('');
      expect(result.status).toBe(1);
      expect(result.stderr).toContain(
        'fake not started: agents.fake.command in .chord/settings.json: expected a string, got null',
      );

      expect(result.stderr).not.toContain('npx');
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

describe('CHD-493 U1 tester: migration commands cross shell and CLI boundaries', () => {
  for (const sessionId of [
    'ordinary',
    '-opaque',
    "two words'$(touch injected)",
  ]) {
    test(`a suggested command roundtrips opaque id ${JSON.stringify(sessionId)}`, async () => {
      const cwd = await mkdtemp(join(tmpdir(), 'chord-command-'));

      try {
        const command = resumeCommand('fake', sessionId);
        const shell = spawnSync(
          'sh',
          ['-c', `chord() { printf '%s\\0' "$@"; }\n${command}`],
          { cwd, encoding: 'utf8' },
        );

        expect(shell.status).toBe(0);

        const argv = shell.stdout.split('\0').slice(0, -1);
        const options = await parsed(argv);

        expect(options?.resume).toBe(sessionId);
        expect(options?.agent).toBe('fake');
        expect(
          await readFile(join(cwd, 'injected')).catch(() => undefined),
        ).toBeUndefined();
      } finally {
        await rm(cwd, { recursive: true });
      }
    });
  }

  test('an old mixed window id keeps the invocation agent and leaves its record untouched', async () => {
    const cwd = await mkdtemp(join(tmpdir(), 'chord-old-window-'));
    const stateHome = join(cwd, 'state');
    const directory = join(cwd, "another ' directory");
    const path = join(stateHome, 'chord', 'windows', 'w-migration.json');
    const text = `${JSON.stringify(
      {
        id: 'w-migration',
        at: 1,
        front: 1,
        tabs: [
          { agent: 'fake', sessionId: 'not-recorded', cwd: directory },
          { agent: 'codex', sessionId: 'also-missing', cwd },
        ],
      },
      null,
      2,
    )}\n`;

    try {
      await mkdir(join(stateHome, 'chord', 'windows'), { recursive: true });
      await writeFile(path, text);

      expect(
        await resumed(['cursor', '--cwd', cwd, '--resume', 'w-migration'], []),
      ).toEqual(['w-migration', 'cursor', cwd]);

      const result = spawnSync(
        process.execPath,
        [
          fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
          'cursor',
          '--cwd',
          cwd,
          '--resume',
          'w-migration',
        ],
        {
          env: {
            ...process.env,
            HOME: cwd,
            XDG_CONFIG_HOME: join(cwd, 'config'),
            XDG_STATE_HOME: stateHome,
            PATH: join(cwd, 'no-programs'),
            NO_COLOR: '1',
          },
          encoding: 'utf8',
          timeout: 10000,
        },
      );

      expect(result.status).toBe(1);
      expect(result.stderr).toContain(
        'chord: cursor runs "agent", which is not on PATH;',
      );
      expect(await readFile(path, 'utf8')).toBe(text);
    } finally {
      await rm(cwd, { recursive: true });
    }
  });
});

describe('CHD-493 U9 tester: native duplicate-option boundaries', () => {
  for (const args of [
    ['-r', 'one', '-r', 'two'],
    ['--resume', 'one', '--resume', 'two'],
    ['-r', 'one', '--resume=two'],
    ['--resume=one', '-r', 'two'],
    ['--resume=one', '--resume=two'],
    ['-r', '-r'],
    ['--resume', '--resume'],
    ['-r', '--resume=two'],
    ['--resume=one', '-r'],
  ]) {
    test(`duplicate ${args.join(' ')} stops before the startup action`, async () => {
      let started = 0;
      const command = chordCommand()
        .noExit()
        .throwErrors()
        .action(() => {
          started++;
        });

      await expect(command.parse(args)).rejects.toThrow('can only occur once');
      expect(started).toBe(0);

      const dir = await mkdtemp(join(tmpdir(), 'chord-duplicate-resume-'));
      const state = join(dir, 'state');
      const settings = join(dir, '.chord', 'settings.json');
      const malformed = '{this settings file must never be parsed';

      try {
        await mkdir(join(dir, '.chord'));
        await mkdir(state);
        await writeFile(settings, malformed);

        const result = spawnSync(
          process.execPath,
          [
            fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
            '--agent-command',
            quote(fakeAgentCommand()),
            ...args,
            '-C',
            dir,
          ],
          {
            env: {
              ...process.env,
              HOME: dir,
              XDG_STATE_HOME: state,
              XDG_CONFIG_HOME: join(dir, 'config'),
              PATH: join(dir, 'no-programs'),
              NO_COLOR: '1',
            },
            stdio: ['ignore', 'pipe', 'pipe'],
            encoding: 'utf8',
            timeout: 10000,
          },
        );

        expect(result.status).toBe(2);
        expect(result.stderr).toContain(
          'can only occur once, but was found several times.',
        );
        expect(result.stderr).not.toContain('settings.json');
        expect(result.stderr).not.toContain('not on PATH');
        expect(result.stdout).not.toContain('\x1b[?1049h');
        expect(await readdir(state)).toEqual([]);
        expect(await readFile(settings, 'utf8')).toBe(malformed);
      } finally {
        await rm(dir, { recursive: true });
      }
    });
  }
});

test('CHD-532 CLI help explains invocation-only unnamed interactive choice', () => {
  const help = chordCommand().getHelp().replace(/\s+/g, ' ');

  expect(help).toContain(
    'A new unnamed interactive start asks which agent to use for this invocation',
  );
  expect(help).toContain(
    'explicit commands, headless and resume routes keep their existing behavior',
  );
});

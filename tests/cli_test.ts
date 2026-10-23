import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ValidationError } from '@cliffy/command';
import { chordCommand } from '../src/cli.ts';
import { fakeAgentCommand } from './fixtures/fake.ts';
import { recordSession } from './fixtures/records.ts';
import {
  ResumeError,
  resumeCommand,
  sessionById,
  type SessionRecord,
  severalRefusal,
} from '../src/session/sessions.ts';

/** What chord's own flags make of `argv`, with nothing run on them. */
async function parsed(argv: string[]) {
  let seen:
    | {
        agent?: string;
        cwd: string;
        model?: string;
        resume?: (string | true)[];
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
  const resume = sessionById(records, String(seen?.resume?.[0]), {
    agent,
    cwd: seen?.cwd ?? '/',
  });

  return [resume.sessionId, agent, resume.cwd];
}

/** What main.tsx says to several ids from `argv`: its refusal's lines. */
async function refused(argv: string[], records: SessionRecord[]) {
  const seen = await parsed(argv);
  const refusal = severalRefusal(records, (seen?.resume ?? []).map(String), {
    agent: seen?.agent ?? 'claude',
    cwd: seen?.cwd ?? '/',
  });

  expect(refusal).toBeInstanceOf(ResumeError);

  return refusal.message.split('\n');
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

const three = [
  record('aaa', 'fake', '/proj'),
  record('bbb', 'fake', '/other'),
  record('ccc', 'fake2', '/other'),
];

test("-r <id> -r <id> … from argv is refused with a command each, in the order given, each on its record's agent where it works", async () => {
  const lines = [
    '--resume opens one session; it was given 3. Open each in a chord of its own:',
    'chord fake2 --cwd /other --resume ccc',
    'chord fake --cwd /proj --resume aaa',
    'chord fake --cwd /other --resume bbb',
  ];

  expect(
    await refused(['-r', 'ccc', '-r', 'aaa', '-r', 'bbb'], three),
  ).toStrictEqual(lines);
  expect(
    await refused(['--resume', 'ccc', '--resume=aaa', '-r', 'bbb'], three),
  ).toStrictEqual(lines);
});

test('--resume with no id asks for the picker, the agent before or after it', async () => {
  expect((await parsed(['--resume']))?.resume).toStrictEqual([true]);
  expect(await parsed(['claude', '-r'])).toStrictEqual({
    agent: 'claude',
    cwd: process.cwd(),
    resume: [true],
  });
  expect(await parsed(['-r', '-C', '/tmp'])).toStrictEqual({
    cwd: '/tmp',
    resume: [true],
  });
});

test('an id is read as one, a UUID or a window id alike', async () => {
  for (const id of ['aaa', 'w-1a2b3c4d', '-x', '0199a1b2-3c4d-7e8f']) {
    expect((await parsed([`--resume=${id}`]))?.resume).toStrictEqual([id]);
  }

  expect(
    (await parsed(['-r', 'aaa', '-r', 'ccc', '--resume', 'w-1a2b3c4d']))
      ?.resume,
  ).toStrictEqual(['aaa', 'ccc', 'w-1a2b3c4d']);
});

test("a word equal to one of chord's option names is not an id: the owner's accepted limit", async () => {
  // The optional id is Cliffy's own [id:string], which never takes an option
  // name as the value; the owner kept it over rewriting argv.
  expect(await parsed(['--resume', 'model'])).toStrictEqual({
    agent: 'model',
    cwd: process.cwd(),
    resume: [true],
  });
  expect(await parsed(['--resume=c'])).toStrictEqual({
    cwd: process.cwd(),
    resume: [true],
  });
  expect(await parsed(['-r', 'aaa', '-r', 'c'])).toStrictEqual({
    agent: 'c',
    cwd: process.cwd(),
    resume: ['aaa', true],
  });
});

test('one id from argv is as it was, the agent before or after it', async () => {
  const records = [record('aaa', 'codex', '/project')];
  const find = { agent: 'codex', cwd: '/project' };

  expect((await parsed(['--resume', 'aaa']))?.resume).toStrictEqual(['aaa']);
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

test('[agent] and the other flags sit on either side of the ids', async () => {
  expect(
    await parsed([
      'fake',
      '-C',
      '/tmp',
      '-r',
      'aaa',
      '-m',
      'opus',
      '-r',
      'ccc',
    ]),
  ).toStrictEqual({
    agent: 'fake',
    cwd: '/tmp',
    model: 'opus',
    resume: ['aaa', 'ccc'],
  });
  // A flag's value is never taken for an id, however it reads.
  expect(
    await parsed(['-C', '--resume', '-r', 'aaa', 'fake', '--resume=bbb']),
  ).toStrictEqual({ agent: 'fake', cwd: '--resume', resume: ['aaa', 'bbb'] });
  await expect(
    parsed(['--continue', '--resume', 'aaa', '--resume', 'bbb']),
  ).rejects.toThrow(ValidationError);
});

test('ten ids, an unknown id among several, the same id twice and an agent named on the command line are all refused alike from argv', async () => {
  const ten = Array.from({ length: 10 }, (_, index) => `s${index}`);
  const records = ten.map((id) => record(id, 'fake', '/proj'));

  expect(
    await refused(
      ten.flatMap((id) => ['-r', id]),
      records,
    ),
  ).toStrictEqual([
    '--resume opens one session; it was given 10. Open each in a chord of its own:',
    ...ten.map((id) => `chord fake --cwd /proj --resume ${id}`),
  ]);
  // An id chord has no record of takes this command's agent and directory,
  // and says so; one said twice is said twice.
  expect(
    await refused(
      ['-C', '/here', '-r', 'aaa', '-r', 'zzz', '-r', 'aaa'],
      three,
    ),
  ).toStrictEqual([
    '--resume opens one session; it was given 3. Open each in a chord of its own:',
    'chord fake --cwd /proj --resume aaa',
    "chord claude --cwd /here --resume zzz  # no record; the agent and directory are this command's",
    'chord fake --cwd /proj --resume aaa',
  ]);
  // An agent named on the command line is not resolved here: each line
  // carries its record's agent.
  expect(
    await refused(['fake', '-r', 'aaa', '-r', 'ccc'], three),
  ).toStrictEqual([
    '--resume opens one session; it was given 2. Open each in a chord of its own:',
    'chord fake --cwd /proj --resume aaa',
    'chord fake2 --cwd /other --resume ccc',
  ]);
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
  for (const window of [false, true]) {
    test(`${window ? 'saved window refuses before startup' : 'session resume refuses the initial runtime in the record directory'}`, async () => {
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

        const windowId = 'w-refused';

        if (window) {
          await mkdir(join(stateDir, 'windows'), { recursive: true });
          await writeFile(
            join(stateDir, 'windows', `${windowId}.json`),
            `${JSON.stringify(
              {
                id: windowId,
                at: 1,
                tabs: [{ sessionId, agent: 'fake', cwd: there }],
                front: 0,
              },
              null,
              2,
            )}\n`,
          );
        }

        const result = spawnSync(
          process.execPath,
          [
            fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
            '-C',
            here,
            '--resume',
            window ? windowId : sessionId,
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
        expect(result.status).toBe(window ? 2 : 1);

        if (window) {
          expect(result.stderr).toContain(
            `${windowId} was a window of 1 session; chord opens one session per run now. Resume it with:\nchord fake --cwd ${there} --resume ${sessionId}`,
          );
          expect(result.stderr).not.toContain('fake not started:');
        } else {
          expect(result.stderr).toContain(
            'fake not started: agents.fake.command in .chord/settings.json: expected a string, got null',
          );
        }

        expect(result.stderr).not.toContain('npx');
      } finally {
        await rm(dir, { recursive: true });
      }
    });
  }
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
        const command = resumeCommand('fake', sessionId, undefined, cwd);
        const shell = spawnSync(
          'sh',
          ['-c', `chord() { printf '%s\\0' "$@"; }\n${command}`],
          { cwd, encoding: 'utf8' },
        );

        expect(shell.status).toBe(0);

        const argv = shell.stdout.split('\0').slice(0, -1);
        const options = await parsed(argv);

        expect(options?.resume).toEqual([sessionId]);
        expect(options?.cwd).toBe(cwd);
        expect(
          await readFile(join(cwd, 'injected')).catch(() => undefined),
        ).toBeUndefined();
      } finally {
        await rm(cwd, { recursive: true });
      }
    });
  }

  test('an old mixed window is refused without starting a runtime or changing its record', async () => {
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

      const result = spawnSync(
        process.execPath,
        [
          fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
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

      expect(result.status).toBe(2);
      expect(result.stderr).toContain(
        'w-migration was a window of 2 sessions;',
      );
      expect(result.stderr).toContain(
        resumeCommand('fake', 'not-recorded', undefined, directory),
      );
      expect(result.stderr).toContain(
        resumeCommand('codex', 'also-missing', undefined, cwd),
      );
      expect(result.stderr).not.toContain('not found on PATH');
      expect(await readFile(path, 'utf8')).toBe(text);
    } finally {
      await rm(cwd, { recursive: true });
    }
  });
});

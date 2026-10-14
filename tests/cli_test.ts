import { expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ValidationError } from '@cliffy/command';
import { chordCommand } from '../src/cli.ts';
import {
  ResumeError,
  sessionById,
  type SessionRecord,
  sessionsByIds,
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

/** The tabs main.tsx opens from `argv`: each id, its agent and directory. */
async function opened(argv: string[], records: SessionRecord[]) {
  const seen = await parsed(argv);

  return sessionsByIds(records, (seen?.resume ?? []).map(String), {
    agent: seen?.agent ?? 'claude',
    cwd: seen?.cwd ?? '/',
    named: seen?.agent !== undefined,
  }).map(({ agent, resume }) => [resume.sessionId, agent, resume.cwd]);
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

test('-r <id> -r <id> … from argv opens a tab each, in the order given, each where its record works', async () => {
  const tabs = [
    ['ccc', 'fake2', '/other'],
    ['aaa', 'fake', '/proj'],
    ['bbb', 'fake', '/other'],
  ];

  expect(
    await opened(['-r', 'ccc', '-r', 'aaa', '-r', 'bbb'], three),
  ).toStrictEqual(tabs);
  expect(
    await opened(['--resume', 'ccc', '--resume=aaa', '-r', 'bbb'], three),
  ).toStrictEqual(tabs);
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
  expect(
    sessionsByIds(records, ['aaa'], { ...find, named: false }),
  ).toStrictEqual([
    { agent: 'codex', resume: sessionById(records, 'aaa', find) },
  ]);

  for (const argv of [
    ['--resume', 'aaa', 'codex'],
    ['codex', '--resume', 'aaa'],
    ['-r', 'aaa', 'codex', '-C', '/tmp'],
  ]) {
    expect(await opened(argv, records)).toStrictEqual([
      ['aaa', 'codex', '/project'],
    ]);
  }

  // An id chord never saw goes to the agent named, as before.
  expect(
    await opened(['--resume', 'zzz', 'codex', '-C', '/w'], records),
  ).toStrictEqual([['zzz', 'codex', '/w']]);
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

test('ten ids, an unknown id among several and the same id twice refuse from argv', async () => {
  const ten = Array.from({ length: 10 }, (_, index) => `s${index}`);
  const nine = ten.slice(0, 9);
  const records = ten.map((id) => record(id, 'fake', '/proj'));

  expect(
    (
      await opened(
        nine.flatMap((id) => ['-r', id]),
        records,
      )
    ).length,
  ).toStrictEqual(9);

  const tooMany = opened(
    ten.flatMap((id) => ['-r', id]),
    records,
  );

  await expect(tooMany).rejects.toThrow(ResumeError);
  await expect(tooMany).rejects.toThrow(
    'A window opens at most 9 sessions; --resume named 10.',
  );

  const unknown = opened(['-r', 'aaa', '-r', 'zzz', '-r', 'bbb'], three);

  await expect(unknown).rejects.toThrow(ResumeError);
  await expect(unknown).rejects.toThrow('No session zzz among');

  const twice = opened(['-r', 'aaa', '-r', 'bbb', '-r', 'aaa'], three);

  await expect(twice).rejects.toThrow(ResumeError);
  await expect(twice).rejects.toThrow('Session aaa is named twice.');

  const foreign = opened(['fake', '-r', 'aaa', '-r', 'ccc'], three);

  await expect(foreign).rejects.toThrow(ResumeError);
  await expect(foreign).rejects.toThrow(
    'Session ccc belongs to another agent (fake2).',
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

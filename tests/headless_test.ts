import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import {
  failureOf,
  type HeadlessOptions,
  joinPiped,
  Reply,
  resultJson,
  runHeadless,
} from '../src/headless.ts';
import type { OneshotOutcome } from '../src/session/oneshot.ts';
import { turnCost } from '../src/session/prices.ts';
import stripAnsi from 'strip-ansi';
import { fakeAgentCommand } from './fixtures/fake.ts';
import { TRACEBACK_ERROR } from './fixtures/fake_agent/options.ts';

/** The tokens each of the fake agent's turns reports. */
const TURN_TOKENS = {
  inputTokens: 1000,
  outputTokens: 200,
  cachedReadTokens: 800,
  totalTokens: 2000,
};

const say = (text: string): SessionUpdate => ({
  sessionUpdate: 'agent_message_chunk',
  content: { type: 'text', text },
});

const think = (text: string): SessionUpdate => ({
  sessionUpdate: 'agent_thought_chunk',
  content: { type: 'text', text },
});

const call: SessionUpdate = {
  sessionUpdate: 'tool_call',
  title: 'Read',
  status: 'pending',
  toolCallId: 'read-1',
};

const done = (stopReason = 'end_turn'): OneshotOutcome => ({
  sessionId: 'session-1',
  result: { status: 'completed', stopReason },
});

test('piped input follows the prompt on a line of its own', () => {
  expect(joinPiped('Explain', 'some code\n')).toStrictEqual(
    'Explain\nsome code\n',
  );
  expect(joinPiped('Explain', undefined)).toStrictEqual('Explain');
  expect(joinPiped('Explain', '')).toStrictEqual('Explain');
  expect(joinPiped('', 'only piped')).toStrictEqual('only piped');
});

test('the reply keeps the agent text and leaves its thinking out', () => {
  const reply = new Reply();
  const written = [think('hmm'), say('Hel'), say('lo')].map((event) =>
    reply.take(event),
  );

  expect(written).toStrictEqual(['', 'Hel', 'lo']);
  expect(reply.text).toStrictEqual('Hello');
  expect(reply.end()).toStrictEqual('\n');
});

test('text after a tool call starts a paragraph of its own', () => {
  const reply = new Reply();

  for (const event of [call, say('Reading.'), call, say('Done.')]) {
    reply.take(event);
  }

  expect(reply.text).toStrictEqual('Reading.\n\nDone.');

  const ended = new Reply();

  for (const event of [say('Line.\n'), call, say('Next.\n')]) {
    ended.take(event);
  }

  expect(ended.text).toStrictEqual('Line.\n\nNext.\n');
  expect(ended.end()).toStrictEqual('');
});

test('a markdown plan reaches stdout once, as it grows', () => {
  const plan = (planId: string, content: string): SessionUpdate => ({
    sessionUpdate: 'plan_update',
    plan: { type: 'markdown', planId, content },
  });
  const reply = new Reply();
  const written = [
    say('Here it is.\n'),
    plan('a', '1. Read'),
    plan('a', '1. Read'),
    plan('a', '1. Read\n2. Write\n'),
    plan('a', 'rewritten'),
  ].map((event) => reply.take(event));

  expect(written).toStrictEqual([
    'Here it is.\n',
    '1. Read',
    '',
    '\n2. Write\n',
    '',
  ]);
  expect(reply.text).toStrictEqual('Here it is.\nrewritten');
});

test('the JSON result has a markdown plan as last sent', () => {
  const plan = (planId: string, content: string): SessionUpdate => ({
    sessionUpdate: 'plan_update',
    plan: { type: 'markdown', planId, content },
  });
  const reply = new Reply();
  const written = [
    plan('a', '1. Read'),
    plan('a', '1. Inspect'),
    plan('a', '1. Inspect\n2. Write'),
    say(' Done.'),
    call,
    plan('b', 'Gone'),
    { sessionUpdate: 'plan_removed', planId: 'b' } as SessionUpdate,
    say('Bye.'),
  ].map((event) => reply.take(event));

  // stdout cannot take back what it printed.
  expect(written).toStrictEqual([
    '1. Read',
    '',
    '',
    ' Done.',
    '',
    '\n\nGone',
    '',
    'Bye.',
  ]);
  expect(reply.text).toStrictEqual('1. Inspect\n2. Write Done.\n\nBye.');
  expect(resultJson(done(), reply.text).result).toStrictEqual(
    '1. Inspect\n2. Write Done.\n\nBye.',
  );
});

test('only an ended turn counts as a finished answer', () => {
  expect(failureOf(done())).toStrictEqual(undefined);
  expect(failureOf(done('max_tokens'))).toStrictEqual(
    'The agent stopped: max_tokens.',
  );
  expect(
    failureOf({
      sessionId: 's',
      result: { status: 'failed', error: { message: 'It broke.' } },
    }),
  ).toStrictEqual('It broke.');
});

test('the JSON result names what Claude Code names', () => {
  expect(
    resultJson(
      {
        ...done(),
        usage: { inputTokens: 10, outputTokens: 2, cachedReadTokens: 5 },
        cost: { amount: 0.5, currency: 'USD' },
      },
      'Hi.',
    ),
  ).toStrictEqual({
    type: 'result',
    is_error: false,
    result: 'Hi.',
    session_id: 'session-1',
    stop_reason: 'end_turn',
    usage: { input_tokens: 10, output_tokens: 2, cache_read_input_tokens: 5 },
    total_cost_usd: 0.5,
  });
  expect(
    resultJson(
      {
        sessionId: 's',
        result: { status: 'failed', error: { message: 'It broke.' } },
        cost: { amount: 3, currency: 'EUR' },
      },
      '',
    ),
  ).toStrictEqual({
    type: 'result',
    is_error: true,
    result: '',
    session_id: 's',
    cost: { amount: 3, currency: 'EUR' },
    error: 'It broke.',
  });
});

/** Runs `chord -p` in-process against the fake agent and keeps its output. */
async function headless(
  prompt: string,
  format: 'text' | 'json' = 'text',
  more: Pick<HeadlessOptions, 'mode' | 'allowAll'> & {
    agentFlags?: string[];
  } = {},
) {
  const { agentFlags = [], ...options } = more;
  const dir = await mkdtemp(join(tmpdir(), 'chord-headless-'));
  let stdout = '';
  let stderr = '';

  try {
    const code = await runHeadless({
      agent: 'fake',
      cwd: dir,
      prompt,
      format,
      agentCommand: fakeAgentCommand(undefined, ...agentFlags),
      ...options,
      stdout: (text) => {
        stdout += text;

        return Promise.resolve();
      },
      stderr: (text) => {
        stderr += text;

        return Promise.resolve();
      },
    });

    return { code, stdout, stderr };
  } finally {
    await rm(dir, { recursive: true });
  }
}

test('-p prints the reply and exits 0', async () => {
  expect(await headless('text')).toStrictEqual({
    code: 0,
    stdout: 'Hello, world. This reply came in chunks.\n',
    stderr: '',
  });
});

test('-p --output-format json prints one object with the usage', async () => {
  const { code, stdout, stderr } = await headless('status', 'json');
  const lines = stdout.trimEnd().split('\n');
  const result = JSON.parse(lines[0] ?? '');

  expect(code).toStrictEqual(0);
  expect(stderr).toStrictEqual('');
  expect(lines.length).toStrictEqual(1);
  expect(result.session_id).toMatch(/^[0-9a-f-]{36}$/);
  expect({ ...result, session_id: 'id' }).toStrictEqual({
    type: 'result',
    is_error: false,
    result: 'Status sent.',
    session_id: 'id',
    stop_reason: 'end_turn',
    usage: { input_tokens: 1000, output_tokens: 200, total_tokens: 1200 },
    total_cost_usd: 0.01,
  });
});

test('-p --output-format json marks a cost chord worked out from the tokens', async () => {
  const { code, stdout } = await headless('text', 'json', {
    agentFlags: ['--tokens-only'],
  });
  const result = JSON.parse(stdout);

  expect(code).toStrictEqual(0);
  expect(result.usage).toStrictEqual({
    input_tokens: 1000,
    output_tokens: 200,
    cache_read_input_tokens: 800,
    total_tokens: 2000,
  });
  expect(result.total_cost_usd).toStrictEqual(
    turnCost('gpt-5.3-codex', TURN_TOKENS),
  );
  expect(result.cost_estimated).toStrictEqual(true);
});

test('a failing agent exits 1 with its error on stderr', async () => {
  expect(await headless('error')).toStrictEqual({
    code: 1,
    stdout: 'About to fail.\n',
    stderr: 'chord: The fake agent failed on purpose.\n',
  });

  const json = await headless('error', 'json');

  expect(json.code).toStrictEqual(1);
  expect(JSON.parse(json.stdout).is_error).toStrictEqual(true);
  expect(json.stderr).toStrictEqual(
    'chord: The fake agent failed on purpose.\n',
  );
});

test('a permission is refused, and stderr says so', async () => {
  expect(await headless('permission')).toStrictEqual({
    code: 0,
    stdout: 'Permission: deny.\n',
    stderr: 'chord: refused Write notes.txt: -p cannot ask for permission.\n',
  });
});

test('--permission-mode runs the turn in that mode, as the agent sees it inside the turn', async () => {
  expect(
    await headless('mode', 'text', {
      mode: { id: 'plan', from: 'set by --permission-mode' },
    }),
  ).toStrictEqual({ code: 0, stdout: 'Mode: plan.\n', stderr: '' });
});

test('a mode the agent does not offer is said on stderr, and the turn runs read-only', async () => {
  expect(
    await headless('permission', 'text', {
      mode: { id: 'nosuch', from: 'set by --permission-mode' },
    }),
  ).toStrictEqual({
    code: 0,
    stdout: 'Permission: deny.\n',
    stderr:
      'chord: could not start in nosuch mode, set by --permission-mode: the agent offers default, acceptEdits, plan\n' +
      'chord: refused Write notes.txt: -p cannot ask for permission.\n',
  });
});

test('an agent with no modes is said to offer none, and the turn runs read-only', async () => {
  expect(
    await headless('permission', 'text', {
      mode: { id: 'plan', from: 'set by --permission-mode' },
      agentFlags: ['--no-modes'],
    }),
  ).toStrictEqual({
    code: 0,
    stdout: 'Permission: deny.\n',
    stderr:
      'chord: could not start in plan mode, set by --permission-mode: the agent offers no modes\n' +
      'chord: refused Write notes.txt: -p cannot ask for permission.\n',
  });
});

test('allowing every permission answers allow once, and stderr names it', async () => {
  expect(
    await headless('permission', 'text', { allowAll: true }),
  ).toStrictEqual({
    code: 0,
    stdout: 'Permission: allow.\n',
    stderr: 'chord: allowed Write notes.txt.\n',
  });

  const json = await headless('permission', 'json', { allowAll: true });

  expect(json.code).toStrictEqual(0);
  expect(json.stderr).toStrictEqual('chord: allowed Write notes.txt.\n');
  expect(json.stdout.trimEnd().split('\n').length).toStrictEqual(1);
  expect(JSON.parse(json.stdout).result).toStrictEqual('Permission: allow.');
});

test('with both, the mode is asked for and what the agent still asks is allowed', async () => {
  expect(
    await headless('mode', 'text', {
      mode: { id: 'acceptEdits', from: 'set by --permission-mode' },
      allowAll: true,
    }),
  ).toStrictEqual({ code: 0, stdout: 'Mode: acceptEdits.\n', stderr: '' });
  expect(
    await headless('permission', 'text', {
      mode: { id: 'acceptEdits', from: 'set by --permission-mode' },
      allowAll: true,
    }),
  ).toStrictEqual({
    code: 0,
    stdout: 'Permission: allow.\n',
    stderr: 'chord: allowed Write notes.txt.\n',
  });
});

test('an agent that does not start exits 1 and says why', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-headless-'));
  let stderr = '';

  try {
    const code = await runHeadless({
      agent: 'fake',
      cwd: dir,
      prompt: 'text',
      format: 'text',
      agentCommand: [join(dir, 'no-such-agent')],
      stdout: () => Promise.resolve(),
      stderr: (text) => {
        stderr += text;

        return Promise.resolve();
      },
    });

    expect(code).toStrictEqual(1);
    expect(
      stderr.startsWith('chord: fake did not start: '),
      stderr,
    ).toBeTruthy();
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("an agent that needs a login says so, its ways in and chord's way on, a line each (CHD-435)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-headless-'));
  let stderr = '';

  try {
    const code = await runHeadless({
      agent: 'fake',
      cwd: dir,
      prompt: 'text',
      format: 'text',
      agentCommand: fakeAgentCommand(undefined, '--auth-required', 'methods'),
      stdout: () => Promise.resolve(),
      stderr: (text) => {
        stderr += text;

        return Promise.resolve();
      },
    });

    expect(code).toStrictEqual(1);
    expect(stderr.split('\n')).toStrictEqual([
      'chord: fake did not start: Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY',
      'chord: fake offers: Log in with the fake (Run `fake login` in the terminal), Log in with SSO',
      "chord: chord does not sign agents in. Sign in with fake's own CLI in a terminal, or set its API key where it offers one.",
      '',
    ]);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('an agent that exits before initialize says so with its code, then the end of its stderr, a line each (CHD-454)', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-headless-'));
  let stderr = '';

  try {
    const code = await runHeadless({
      agent: 'fake',
      cwd: dir,
      prompt: 'text',
      format: 'text',
      agentCommand: fakeAgentCommand(undefined, '--start-fails', 'traceback'),
      stdout: () => Promise.resolve(),
      stderr: (text) => {
        stderr += text;

        return Promise.resolve();
      },
    });
    const lines = stderr.split('\n');

    expect(code).toStrictEqual(1);
    expect(lines.slice(0, 4)).toStrictEqual([
      'chord: fake did not start: it exited with code 1 before answering initialize.',
      'chord: The end of its stderr:',
      'chord:   … +116 lines',
      'chord:       from .module_58 import run',
    ]);
    expect(lines.at(-2)).toStrictEqual(`chord:   ${TRACEBACK_ERROR}`);
    expect(lines.length).toStrictEqual(10);
  } finally {
    await rm(dir, { recursive: true });
  }
});

/**
 * Runs chord's command line from source, as a script would, in a fresh
 * directory with `project` as its `.chord/settings.json` and no user file.
 */
async function chord(
  args: string[],
  stdin: string,
  project?: unknown,
  env?: Record<string, string>,
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-headless-'));
  const agent = fakeAgentCommand()
    .map((word) => `'${word}'`)
    .join(' ');

  try {
    if (project !== undefined) {
      await mkdir(join(dir, '.chord'));
      await writeFile(
        join(dir, '.chord', 'settings.json'),
        JSON.stringify(project),
      );
    }

    const { status, stdout, stderr } = spawnSync(
      process.execPath,
      [
        fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
        ...args,
        'fake',
        '--agent-command',
        agent,
        '-C',
        dir,
      ],
      {
        env: {
          ...process.env,
          XDG_STATE_HOME: join(dir, 'state'),
          XDG_CONFIG_HOME: join(dir, 'config'),
          NO_COLOR: '1',
          ...env,
        },
        input: stdin,
        encoding: 'utf8',
      },
    );

    return { code: status, stdout, stderr };
  } finally {
    await rm(dir, { recursive: true });
  }
}

test('piped stdin joins the prompt on the command line', async () => {
  expect(await chord(['-p', '/echo one'], 'two\n')).toStrictEqual({
    code: 0,
    stdout: 'one\ntwo\n',
    stderr: '',
  });

  const { code, stdout } = await chord(
    ['-p', '/echo one', '--output-format', 'json'],
    'two',
  );

  expect(code).toStrictEqual(0);
  expect(JSON.parse(stdout).result).toStrictEqual('one\ntwo');
});

test('the command line exits 1 when the agent fails', async () => {
  expect(await chord(['-p', 'error'], '')).toStrictEqual({
    code: 1,
    stdout: 'About to fail.\n',
    stderr: 'chord: The fake agent failed on purpose.\n',
  });
});

test('--output-format needs -p', async () => {
  const { code, stderr } = await chord(['--output-format', 'json'], '');

  expect(code).toStrictEqual(2);
  expect(stderr).toMatch(/depends on option "--print"/);
});

test('the command line takes the mode from the project file, and the flag over it', async () => {
  const project = { agents: { fake: { permissionMode: 'plan' } } };

  expect(await chord(['-p', 'mode'], '', project)).toStrictEqual({
    code: 0,
    stdout: 'Mode: plan.\n',
    stderr: '',
  });
  expect(
    await chord(
      ['-p', 'mode', '--permission-mode', 'acceptEdits'],
      '',
      project,
    ),
  ).toStrictEqual({ code: 0, stdout: 'Mode: acceptEdits.\n', stderr: '' });
  expect(
    await chord(['-p', 'mode'], '', {
      agents: { fake: { permissionMode: 'nosuch' } },
    }),
  ).toStrictEqual({
    code: 0,
    stdout: 'Mode: default.\n',
    stderr:
      'chord: could not start in nosuch mode, set in .chord/settings.json: the agent offers default, acceptEdits, plan\n',
  });
});

test('the command line takes the effort from the project file, and the flag over it', async () => {
  const project = { agents: { fake: { effort: 'high' } } };

  expect(await chord(['-p', 'effort'], '', project)).toStrictEqual({
    code: 0,
    stdout: 'Effort: high.\n',
    stderr: '',
  });
  expect(
    await chord(['-p', 'effort', '--effort', 'low'], '', project),
  ).toStrictEqual({ code: 0, stdout: 'Effort: low.\n', stderr: '' });
  // The turn still runs, on the agent's own effort.
  expect(await chord(['-p', 'effort', '--effort', 'max'], '')).toStrictEqual({
    code: 0,
    stdout: 'Effort: medium.\n',
    stderr:
      'chord: could not start on max effort, set by --effort: the agent offers low, medium, high\n',
  });
});

test('the command line says an effort asked of an agent with none, and runs the turn', async () => {
  expect(
    await chord(['-p', 'effort', '--effort', 'high'], '', undefined, {
      CHORD_FAKE_NO_CONFIG: '1',
    }),
  ).toStrictEqual({
    code: 0,
    stdout: 'Effort: none.\n',
    stderr:
      'chord: could not start on high effort, set by --effort: the agent offers no efforts\n',
  });
});

test('the command line allows every permission with --dangerously-skip-permissions', async () => {
  expect(
    await chord(['-p', 'permission', '--dangerously-skip-permissions'], ''),
  ).toStrictEqual({
    code: 0,
    stdout: 'Permission: allow.\n',
    stderr: 'chord: allowed Write notes.txt.\n',
  });
});

test('--dangerously-skip-permissions needs -p', async () => {
  const { code, stdout, stderr } = await chord(
    ['--dangerously-skip-permissions'],
    '',
  );

  expect(code).toStrictEqual(2);
  // Cliffy's help goes to stdout with the error, but no window opens.
  expect(!stdout.includes('\x1b[?1049h'), stdout).toBeTruthy();
  expect(stderr).toMatch(/--dangerously-skip-permissions works only with -p/);
});

/**
 * Runs chord's command line from source with `path` alone as PATH, holding
 * `stubs`: each a command that execs the fake agent, as a CLI the person
 * installed would answer ACP; `overridden` names an agent the project's
 * settings file starts as the fake agent; `recorded` names the agent the
 * sessions `RECORDED` gives are of, in chord's records, one for all or one
 * each.
 */
async function onPath(
  args: string[],
  stubs: string[],
  overridden?: string,
  recorded?: string | readonly string[],
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-path-'));
  const bin = join(dir, 'bin');
  const agent = fakeAgentCommand()
    .map((word) => `'${word}'`)
    .join(' ');

  try {
    await mkdir(bin);

    for (const stub of stubs) {
      await writeFile(join(bin, stub), `#!/bin/sh\nexec ${agent} "$@"\n`, {
        mode: 0o755,
      });
    }

    if (recorded !== undefined) {
      await seedRecords(join(dir, 'state', 'chord'), recorded, dir);
    }

    if (overridden !== undefined) {
      await mkdir(join(dir, '.chord'));
      await writeFile(
        join(dir, '.chord', 'settings.json'),
        JSON.stringify({ agents: { [overridden]: { command: agent } } }),
      );
    }

    const { status, stdout, stderr } = spawnSync(
      process.execPath,
      [
        fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
        ...args,
        '-C',
        dir,
      ],
      {
        env: {
          ...process.env,
          PATH: bin,
          XDG_STATE_HOME: join(dir, 'state'),
          XDG_CONFIG_HOME: join(dir, 'config'),
          NO_COLOR: '1',
        },
        stdio: ['ignore', 'pipe', 'pipe'],
        encoding: 'utf8',
      },
    );

    return { code: status, stdout, stderr };
  } finally {
    await rm(dir, { recursive: true });
  }
}

/**
 * Two sessions in chord's records, and a window record holding both, as
 * chord wrote one before 0.58.0.
 */
const RECORDED = [
  '0b5c5f9e-0000-4000-8000-000000000001',
  '0b5c5f9e-0000-4000-8000-000000000002',
];
const RECORDED_WINDOW = 'w-0b5c5f9e';

async function seedRecords(
  stateDir: string,
  agents: string | readonly string[],
  cwd: string,
) {
  const agentOf = (index: number) =>
    typeof agents === 'string' ? agents : agents[index]!;

  await mkdir(join(stateDir, 'records'), { recursive: true });

  for (const [index, sessionId] of RECORDED.entries()) {
    const agent = agentOf(index);

    await writeFile(
      join(stateDir, 'records', `${sessionId}.jsonl`),
      [
        { type: 'session', version: 1, sessionId, agent, cwd, at: 1 },
        { type: 'prompt', turnId: 't1', at: 2, prompt: 'hi', images: 0 },
      ]
        .map((entry) => JSON.stringify(entry))
        .join('\n') + '\n',
    );
  }

  // As 0.57.0's windowText wrote it: chord writes none since.
  await mkdir(join(stateDir, 'windows'), { recursive: true });
  await writeFile(
    join(stateDir, 'windows', `${RECORDED_WINDOW}.json`),
    `${JSON.stringify(
      {
        id: RECORDED_WINDOW,
        at: 3,
        tabs: RECORDED.map((sessionId, index) => ({
          sessionId,
          agent: agentOf(index),
          cwd,
        })),
        front: 0,
      },
      null,
      2,
    )}\n`,
  );
}

test('an agent whose command is not on PATH is refused in one line', async () => {
  expect(await onPath(['cursor', '-p', '/echo hi'], [])).toStrictEqual({
    code: 1,
    stdout: '',
    stderr:
      'chord: cursor runs "agent", which is not on PATH; ' +
      'install it from https://cursor.com/docs/cli/installation\n',
  });
});

test('a table agent starts by the command PATH finds', async () => {
  expect(await onPath(['cursor', '-p', '/echo hi'], ['agent'])).toStrictEqual({
    code: 0,
    stdout: 'hi\n',
    stderr: '',
  });
});

test('a settings command overrides a table agent, PATH or not', async () => {
  expect(
    await onPath(['cursor', '-p', '/echo hi'], [], 'cursor'),
  ).toStrictEqual({
    code: 0,
    stdout: 'hi\n',
    stderr: '',
  });
});

test("one -r, its agent named or not, asks PATH for its record's agent, not the default one (Q180)", async () => {
  // Were the default asked for, the line would name claude and npx.
  for (const named of [['cursor'], []]) {
    expect(
      await onPath([...named, '-r', RECORDED[0]!], [], undefined, 'cursor'),
    ).toStrictEqual({
      code: 1,
      stdout: '',
      stderr:
        'chord: cursor runs "agent", which is not on PATH; ' +
        'install it from https://cursor.com/docs/cli/installation\n',
    });
  }
});

test('one -r is refused on another agent named, or on an --agent-command, which goes with the default agent alone (Q180, Q56)', async () => {
  for (const args of [
    ['claude', '-r', RECORDED[0]!],
    ['--agent-command', 'my-acp', '-r', RECORDED[0]!],
  ]) {
    const { code, stderr } = await onPath(args, [], undefined, 'cursor');

    expect(code).toBe(2);
    expect(refusal(stderr)).toEqual([
      `Session ${RECORDED[0]} belongs to another agent (cursor).`,
    ]);
  }
});

/**
 * The lines chord printed after Cliffy's "error: ", its help and the colours
 * Cliffy paints whatever NO_COLOR says left out.
 */
function refusal(stderr: string): string[] {
  const plain = stripAnsi(stderr);

  return plain
    .slice(plain.indexOf('error: ') + 'error: '.length)
    .trimEnd()
    .split('\n');
}

test('a second -r is refused by Cliffy, before anything asks PATH (Q181)', async () => {
  const several = await onPath(
    RECORDED.flatMap((id) => ['-r', id]),
    [],
    undefined,
    'cursor',
  );

  // A ValidationError, as every --resume refusal is.
  expect(several.code).toBe(2);
  expect(several.stderr).not.toContain('not on PATH');
  expect(refusal(several.stderr)).toEqual([
    'Option "-r" can only occur once, but was found several times.',
  ]);
});

test("an old window's w-… id goes on to start the agent named, as an id chord has no record of (Q179)", async () => {
  // The window record seedRecords leaves holds both sessions; were it read,
  // they would be said back. Here the id goes on to start the agent named,
  // as one chord has no record of does, and PATH has no cursor.
  expect(
    await onPath(['cursor', '-r', RECORDED_WINDOW], [], undefined, 'cursor'),
  ).toStrictEqual({
    code: 1,
    stdout: '',
    stderr:
      'chord: cursor runs "agent", which is not on PATH; ' +
      'install it from https://cursor.com/docs/cli/installation\n',
  });
});

test('a name only the settings define starts', async () => {
  expect(await onPath(['mine', '-p', '/echo hi'], [], 'mine')).toStrictEqual({
    code: 0,
    stdout: 'hi\n',
    stderr: '',
  });
});

test('chord agents marks each own CLI by PATH and lists a settings name', async () => {
  const { code, stdout, stderr } = await onPath(['agents'], ['goose'], 'mine');
  const line = (name: string) =>
    stdout.split('\n').find((row) => row.startsWith(`${name} `));

  expect({ code, stderr }).toStrictEqual({ code: 0, stderr: '' });
  expect(line('goose') ?? '').toMatch(/own CLI · found +goose acp$/);
  expect(line('cursor') ?? '').toMatch(/own CLI · not on PATH +agent acp$/);
  expect(line('mine') ?? '').toMatch(/settings +'.*fake_agent\/main\.ts'$/);
  expect(line('claude') ?? '').toMatch(/npx +npx -y /);
});

test('a form is declined, and stderr names each question it asked', async () => {
  expect(await headless('askcodex')).toStrictEqual({
    code: 0,
    stdout: 'Elicitation answer: decline\n',
    stderr:
      'chord: fake asked: What would you like to focus on next? — skipped (no one to answer under -p)\n' +
      'chord: fake asked: Paste the API token for the staging deploy. — skipped (no one to answer under -p)\n',
  });
  // A form chord reads no questions in is named by its message.
  expect(await headless('form')).toStrictEqual({
    code: 0,
    stdout: 'Elicitation answer: decline\n',
    stderr:
      'chord: fake asked: Set up the deploy target — skipped (no one to answer under -p)\n',
  });
  // A link nobody can open is cancelled, as before.
  expect((await headless('link')).stdout).toStrictEqual(
    'Elicitation answer: cancel\n',
  );
});

describe('CHD-1 tester: headless question diagnostics', () => {
  const cases: [string, string[]][] = [
    [
      'askclaude',
      [
        'Which language should helper scripts use?',
        'Which checks should run before a commit?',
      ],
    ],
    ['askclaudeone', ['Which language should helper scripts use?']],
    [
      'askcodex',
      [
        'What would you like to focus on next?',
        'Paste the API token for the staging deploy.',
      ],
    ],
    [
      'askcodexwait',
      [
        'What would you like to focus on next?',
        'Paste the API token for the staging deploy.',
      ],
    ],
    [
      'askdroid',
      [
        'Where should uploads be kept?',
        'Which formats should be accepted?',
        'What should the bucket be called?',
      ],
    ],
    ['askopencode', ['Where should the new tests go?']],
    ['askdimcode', ['Where should it deploy?']],
    ['form', ['Set up the deploy target']],
  ];

  for (const [scenario, questions] of cases) {
    test(`${scenario}: decline continues in text and JSON while stderr names every skipped question`, async () => {
      const expected = questions
        .map(
          (question) =>
            `chord: fake asked: ${question} — skipped (no one to answer under -p)\n`,
        )
        .join('');

      for (const format of ['text', 'json'] as const) {
        const result = await headless(scenario, format);

        expect(result.code).toBe(0);
        expect(result.stderr).toBe(expected);

        if (format === 'text') {
          expect(result.stdout).toBe('Elicitation answer: decline\n');
        } else {
          const lines = result.stdout.trimEnd().split('\n');
          const parsed = JSON.parse(lines[0] ?? 'null');

          expect(lines.length).toBe(1);
          expect(parsed).toMatchObject({
            type: 'result',
            is_error: false,
            result: 'Elicitation answer: decline',
            stop_reason: 'end_turn',
          });
          expect(parsed.session_id).toMatch(/^[0-9a-f-]{36}$/);
          expect(parsed).not.toHaveProperty('questions');
        }
      }
    });
  }

  test('allow-all still skips questions, while links stay cancelled without skipped-question diagnostics', async () => {
    const plain = await headless('askclaude');
    const allowed = await headless('askclaude', 'text', { allowAll: true });

    expect(allowed).toStrictEqual(plain);

    const link = await headless('link', 'json');

    expect(link.code).toBe(0);
    expect(JSON.parse(link.stdout)).toMatchObject({
      result: 'Elicitation answer: cancel',
      is_error: false,
    });
    expect(link.stderr).toBe('');
  });
});

describe('CHD-441 tester: the CLI forwards the MCP setting through headless and oneshot', () => {
  test('false sends no servers and true restores configured stdio and HTTP servers', async () => {
    const servers = {
      files: { command: 'unused-mcp-server', args: ['--example'] },
      docs: { type: 'http', url: 'https://docs.example/mcp' },
    };

    for (const mcpServers of [false, true]) {
      const result = await chord(['-p', 'mcp'], '', {
        agents: { fake: { mcpServers } },
        mcpServers: servers,
      });

      expect(result.code).toBe(0);
      expect(result.stderr).toBe('');

      const given: unknown = JSON.parse(
        result.stdout.trim().replace(/^```json\n|\n```$/g, ''),
      );

      expect(given).toStrictEqual(
        mcpServers
          ? [
              {
                name: 'files',
                command: 'unused-mcp-server',
                args: ['--example'],
                env: [],
              },
              {
                type: 'http',
                name: 'docs',
                url: 'https://docs.example/mcp',
                headers: [],
              },
            ]
          : [],
      );
    }
  });
});

describe('CHD-435 tester: headless sign-in boundaries', () => {
  for (const kind of ['bare', 'link', 'linkother']) {
    test(`${kind} prints only the appropriate plain stderr guidance`, async () => {
      const cwd = await mkdtemp(join(tmpdir(), 'chord-headless-signin-'));
      let stdout = '';
      let stderr = '';

      try {
        const code = await runHeadless({
          agent: 'fake',
          cwd,
          prompt: 'text',
          format: 'text',
          agentCommand: fakeAgentCommand(undefined, '--auth-required', kind),
          stdout: (text) => {
            stdout += text;

            return Promise.resolve();
          },
          stderr: (text) => {
            stderr += text;

            return Promise.resolve();
          },
        });

        expect(code).toBe(1);
        expect(stdout).toBe('');
        expect(stderr).not.toContain('fake offers:');
        expect(stderr).not.toContain('\x1b[');

        if (kind === 'linkother') {
          expect(stderr).toBe(
            'chord: fake did not start: it refused session/new: The fake could not open its session.\n',
          );
        } else {
          const message =
            kind === 'bare'
              ? 'Authentication required'
              : 'Authentication required: Sign-in was cancelled. Retry to sign in.';

          expect(stderr.split('\n')).toEqual([
            `chord: fake did not start: ${message}`,
            "chord: chord does not sign agents in. Sign in with fake's own CLI in a terminal, or set its API key where it offers one.",
            '',
          ]);
        }
      } finally {
        await rm(cwd, { recursive: true });
      }
    });
  }
});

describe('CHD-454 tester: headless structured failure boundaries', () => {
  for (const shape of [
    'closed',
    'signal',
    'stdout',
    'zeroalias',
    'zeronotacp',
    'otheralias',
  ]) {
    test(`${shape} keeps its structured headline and only applicable detail`, async () => {
      const cwd = await mkdtemp(join(tmpdir(), 'chord-headless-start-'));
      let stdout = '';
      let stderr = '';
      const command =
        shape === 'closed'
          ? [
              'sh',
              '-c',
              'printf "  raw diagnostic\\n" >&2; exec 1>&-; exec sleep 30',
            ]
          : shape === 'signal'
            ? ['sh', '-c', 'kill -TERM $$']
            : fakeAgentCommand(
                undefined,
                '--start-fails',
                shape === 'stdout'
                  ? 'stdout'
                  : shape === 'zeronotacp'
                    ? 'notacp'
                    : 'alias',
              );
      const agent = shape.startsWith('zero') ? 'zeroclaw' : 'fake';

      try {
        const code = await runHeadless({
          agent,
          cwd,
          prompt: 'text',
          format: 'text',
          agentCommand: command,
          stdout: (text) => {
            stdout += text;

            return Promise.resolve();
          },
          stderr: (text) => {
            stderr += text;

            return Promise.resolve();
          },
        });

        expect(code).toBe(1);
        expect(stdout).toBe('');
        expect(stderr).not.toContain('chord ran');
        expect(stderr.includes('Set a default agent:')).toBe(
          shape === 'zeroalias',
        );

        if (shape === 'closed') {
          expect(stderr.split('\n')).toEqual([
            'chord: fake did not start: it closed its connection before answering initialize.',
            'chord: The end of its stderr:',
            'chord:     raw diagnostic',
            '',
          ]);
        } else if (shape === 'signal') {
          expect(stderr).toBe(
            'chord: fake did not start: it was stopped by SIGTERM before answering initialize.\n',
          );
        } else if (shape === 'stdout') {
          expect(stderr).toBe(
            'chord: fake did not start: it exited with code 0 before answering initialize.\n',
          );
          expect(stderr).not.toContain('no longer maintained');
        }
      } finally {
        await rm(cwd, { recursive: true });
      }
    });
  }
});

describe('CHD-493 U8 tester: recorded runtime precedes startup validation', () => {
  async function startup(args: string[], recordCommand?: string) {
    const dir = await mkdtemp(join(tmpdir(), 'chord-u8-startup-'));
    const here = join(dir, 'here');
    const there = join(dir, 'there');
    const state = join(dir, 'state');
    const config = join(dir, 'config');

    try {
      await mkdir(join(here, '.chord'), { recursive: true });
      await mkdir(join(there, '.chord'), { recursive: true });
      await mkdir(join(config, 'chord'), { recursive: true });
      await writeFile(
        join(config, 'chord', 'settings.json'),
        JSON.stringify({
          agent: 'gemini',
        }),
      );
      await seedRecords(join(state, 'chord'), 'cursor', there);

      if (recordCommand !== undefined) {
        await writeFile(
          join(there, '.chord', 'settings.json'),
          JSON.stringify({
            agents: { cursor: { command: recordCommand } },
          }),
        );
      }

      return spawnSync(
        process.execPath,
        [
          fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
          ...args,
          '-C',
          here,
        ],
        {
          env: {
            ...process.env,
            HOME: dir,
            XDG_STATE_HOME: state,
            XDG_CONFIG_HOME: config,
            PATH: join(dir, 'no-programs'),
            NO_COLOR: '1',
          },
          stdio: ['ignore', 'pipe', 'pipe'],
          encoding: 'utf8',
          timeout: 10000,
        },
      );
    } finally {
      await rm(dir, { recursive: true });
    }
  }

  test('a recorded agent overrides settings.agent before PATH validation', async () => {
    const result = await startup(['-r', RECORDED[0]!]);

    expect(result.status).toBe(1);
    expect(result.stderr).toContain(
      'chord: cursor runs "agent", which is not on PATH;',
    );
    expect(result.stderr).not.toContain('gemini runs');
  });

  for (const id of ['unknown-u8', 'w-unknown-u8']) {
    test(`an unrecorded ${id} keeps settings.agent`, async () => {
      const result = await startup(['-r', id]);

      expect(result.status).toBe(1);
      expect(result.stderr).toContain('chord: gemini runs ');
      expect(result.stderr).toContain('not on PATH');
      expect(result.stderr).not.toContain('cursor runs');
    });
  }

  for (const args of [
    ['gemini', '-r', RECORDED[0]!],
    ['--agent-command', 'missing-override-u8', '-r', RECORDED[0]!],
  ]) {
    test(`an explicit agent or command cannot adopt another runtime's record: ${args[0]}`, async () => {
      const result = await startup(args);

      expect(result.status).toBe(2);
      expect(result.stderr).toContain(
        `Session ${RECORDED[0]} belongs to another agent (cursor).`,
      );
      expect(result.stderr).not.toContain('not on PATH');
    });
  }

  test('a command in the record directory never replaces the invocation command', async () => {
    const result = await startup(['-r', RECORDED[0]!], 'missing-record-u8');

    expect(result.status).toBe(1);
    expect(result.stderr).toContain(
      'cursor runs "agent", which is not on PATH;',
    );
    expect(result.stderr).not.toContain('missing-record-u8');
  });
});

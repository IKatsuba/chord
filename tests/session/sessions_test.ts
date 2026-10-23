import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { shellContext, withContext } from '../../src/session/context.ts';
import {
  entryOf,
  FileRecording,
  historyEntries,
  promptLine,
  readPast,
  recordActions,
  type RecordEntry,
  runPasts,
  withTaskWork,
} from '../../src/session/record.ts';
import { taskUpdate } from '../../src/session/tasks.ts';
import {
  earlierSessions,
  elsewhereRefusal,
  latestSession,
  resumeCommand,
  ResumeError,
  sessionById,
  type SessionRecord,
  severalRefusal,
  summaryOf,
} from '../../src/session/sessions.ts';
import { pastActions } from '../../src/session/replay.ts';
import type { PastAction, Session } from '../../src/session/session.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import {
  type ChordTool,
  emptyTranscript,
  type Transcript,
  type TranscriptAction,
} from '../../src/session/transcript/types.ts';

/** A past as the transcript draws it; its tokens are counted elsewhere. */
function transcriptOf(past: readonly PastAction[]): Transcript {
  return past
    .filter((action): action is TranscriptAction => action.type !== 'usage')
    .reduce(reduceTranscript, emptyTranscript);
}

function record(
  name: string,
  overrides: Partial<SessionRecord> = {},
): SessionRecord {
  return {
    path: `/state/records/${name}.jsonl`,
    sessionId: `id-${name}`,
    agent: 'claude',
    cwd: '/work',
    lastUsedAt: Date.parse('2026-10-01T00:00:00.000Z'),
    prompt: name,
    ...overrides,
  };
}

const CLAUDE = { agent: 'claude', cwd: '/work' };
const DAY = 24 * 60 * 60 * 1000;

function lines(...entries: RecordEntry[]): string {
  return entries.map((entry) => `${JSON.stringify(entry)}\n`).join('');
}

const HEADER: RecordEntry = {
  type: 'session',
  version: 1,
  sessionId: 'abc',
  agent: 'claude',
  cwd: '/work',
  at: 1,
};

test("a record's summary is its header, its first prompt on one line and its last prompt's time", () => {
  const run = {
    command: 'git status',
    stdout: 'clean',
    stderr: '',
    running: false,
    code: 0,
  };

  expect(
    summaryOf(
      '/r.jsonl',
      lines(
        HEADER,
        {
          type: 'prompt',
          turnId: 't1',
          at: 10,
          prompt: withContext(shellContext([run]), 'fix  the\nbuild\n'),
          images: 0,
        },
        {
          type: 'update',
          turnId: 't1',
          update: {
            sessionUpdate: 'agent_message_chunk',
            content: { type: 'text', text: '{"type":"prompt"' },
          },
        },
        { type: 'prompt', turnId: 't2', at: 20, prompt: 'later', images: 0 },
      ),
    ),
  ).toStrictEqual({
    path: '/r.jsonl',
    sessionId: 'abc',
    agent: 'claude',
    cwd: '/work',
    lastUsedAt: 20,
    prompt: 'fix the build',
  });
  // Nothing sent, or no header: not a session to offer.
  expect(summaryOf('/r.jsonl', lines(HEADER))).toStrictEqual(undefined);
  expect(summaryOf('/r.jsonl', 'garbage\n')).toStrictEqual(undefined);
});

test("a session's first prompt reads as its first command when it was only shell output", () => {
  const run = {
    command: 'git status',
    stdout: 'clean',
    stderr: '',
    running: false,
    code: 0,
  };

  expect(promptLine(withContext(shellContext([run]), ''))).toStrictEqual(
    '!git status',
  );
  expect(
    promptLine(withContext(shellContext([run]), 'and now?')),
  ).toStrictEqual('and now?');
});

test('--continue takes the session used last', () => {
  const records = [
    record('old'),
    record('new', { lastUsedAt: record('old').lastUsedAt + DAY }),
  ];

  expect(latestSession(records, CLAUDE)).toStrictEqual({
    sessionId: 'id-new',
    cwd: '/work',
    record: '/state/records/new.jsonl',
    lastUsedAt: record('old').lastUsedAt + DAY,
    prompt: record('new').prompt,
  });
});

test("--continue does not take a task agent's session, which is its parent's work", () => {
  expect(
    latestSession(
      [
        record('old'),
        record('new', {
          lastUsedAt: record('old').lastUsedAt + DAY,
          parent: 'id-old',
        }),
      ],
      CLAUDE,
    ).sessionId,
  ).toStrictEqual('id-old');
});

test("/resume's row for an agent another started leads with its name, which its header is called by", () => {
  const child = summaryOf(
    '/r.jsonl',
    lines(
      { ...HEADER, parent: 'id-main', name: 'parser' },
      {
        type: 'prompt',
        turnId: 't1',
        at: 10,
        prompt: 'agentchild',
        images: 0,
        from: { name: 'main', reachable: true },
      },
    ),
  )!;

  expect(child.name).toStrictEqual('parser');

  const [row] = earlierSessions([child], CLAUDE);

  expect(row?.prompt).toStrictEqual('parser · agentchild');
  expect(row?.resume.name).toStrictEqual('parser');
  expect(row?.resume.prompt).toStrictEqual('agentchild');
});

test("--continue does not take another agent's session", () => {
  const continued = () =>
    latestSession([record('codex', { agent: 'codex' })], CLAUDE);

  expect(continued).toThrow(ResumeError);
  expect(continued).toThrow('No earlier claude session in /work to continue.');
});

test("--resume names the agent a session belongs to when it is another's", () => {
  const foreign = () =>
    sessionById(
      [record('codex', { agent: 'codex', sessionId: 'abc' })],
      'abc',
      CLAUDE,
    );

  expect(foreign).toThrow(ResumeError);
  expect(foreign).toThrow('Session abc belongs to another agent (codex).');
  // One chord never saw goes to the agent as it is.
  expect(sessionById([], 'xyz', CLAUDE)).toStrictEqual({
    sessionId: 'xyz',
    cwd: '/work',
  });
});

test('--resume with several ids is refused, each said back as a command on its own agent in its own directory, in the order given', () => {
  const records = [
    record('a'),
    record('b', { agent: 'codex', cwd: '/other' }),
    record('c', { cwd: '/my work' }),
    // An older record of the same session: its latest speaks for it.
    record('old-b', {
      sessionId: 'id-b',
      agent: 'codex',
      cwd: '/gone',
      lastUsedAt: Date.parse('2026-09-01T00:00:00.000Z'),
    }),
  ];
  const refusal = severalRefusal(records, ['id-c', 'id-b', 'id-x', 'id-c'], {
    ...CLAUDE,
    agentCommand: 'claude-acp --fast',
  });

  expect(refusal).toBeInstanceOf(ResumeError);
  expect(refusal.message.split('\n')).toStrictEqual([
    '--resume opens one session; it was given 4. Open each in a chord of its own:',
    // The typed --agent-command goes with the agent it starts alone.
    "chord claude --cwd '/my work' --agent-command 'claude-acp --fast' --resume id-c",
    'chord codex --cwd /other --resume id-b',
    "chord claude --cwd /work --agent-command 'claude-acp --fast' --resume id-x  # no record; the agent and directory are this command's",
    "chord claude --cwd '/my work' --agent-command 'claude-acp --fast' --resume id-c",
  ]);
  expect(
    severalRefusal(records, ['id-a', 'id-b'], CLAUDE).message.split('\n'),
  ).toStrictEqual([
    '--resume opens one session; it was given 2. Open each in a chord of its own:',
    'chord claude --cwd /work --resume id-a',
    'chord codex --cwd /other --resume id-b',
  ]);
});

test('--resume with one id is as it was: another agent refused, an unknown one to the agent', () => {
  const records = [record('a'), record('b', { agent: 'codex' })];

  expect(sessionById(records, 'id-a', CLAUDE).record).toStrictEqual(
    '/state/records/a.jsonl',
  );
  expect(sessionById(records, 'xyz', CLAUDE)).toStrictEqual({
    sessionId: 'xyz',
    cwd: '/work',
  });
  expect(() => sessionById(records, 'id-b', CLAUDE)).toThrow(ResumeError);
  expect(() => sessionById(records, 'id-b', CLAUDE)).toThrow(
    'Session id-b belongs to another agent (codex).',
  );
});

test('the resume command carries an --agent-command, and every word of it is quoted for a shell', () => {
  expect(resumeCommand('claude', 'abc')).toStrictEqual(
    'chord claude --resume abc',
  );
  expect(resumeCommand('fake', 'abc', "deno run 'x y.ts'")).toStrictEqual(
    `chord fake --agent-command 'deno run '\\''x y.ts'\\''' --resume abc`,
  );
  // A directory goes right after the agent, quoted the same way.
  expect(
    resumeCommand('codex', 'abc', undefined, '/work/my app'),
  ).toStrictEqual("chord codex --cwd '/work/my app' --resume abc");
  // An id or agent is opaque: it pastes as one word, and nothing in it runs.
  expect(resumeCommand('my agent', 'a b')).toStrictEqual(
    "chord 'my agent' --resume 'a b'",
  );
  expect(resumeCommand('claude', "$(touch x)'; ls")).toStrictEqual(
    `chord claude --resume '$(touch x)'\\''; ls'`,
  );
  // One that starts with a dash is joined to its flag, or it reads as one.
  expect(resumeCommand('fake', '-opaque')).toStrictEqual(
    'chord fake --resume=-opaque',
  );
});

test("/resume offers this directory's sessions newest first, once each, but the open one", () => {
  const at = (day: number) => record('a').lastUsedAt + day * DAY;
  const records = [
    record('a', { lastUsedAt: at(0), prompt: 'first' }),
    record('c', { lastUsedAt: at(2), prompt: 'third' }),
    record('b', { lastUsedAt: at(1), prompt: 'second' }),
    // The session on screen.
    record('open', { lastUsedAt: at(3) }),
    // `a` again, in an older record two windows left.
    record('a-twice', {
      sessionId: 'id-a',
      lastUsedAt: at(-30),
      prompt: 'stale',
    }),
    record('elsewhere', { cwd: '/other' }),
    record('codex', { agent: 'codex' }),
  ];
  const offered = earlierSessions(records, CLAUDE, 'id-open');

  expect(
    offered.map(({ resume, prompt }) => [resume.sessionId, prompt]),
  ).toStrictEqual([
    ['id-c', 'third'],
    ['id-b', 'second'],
    ['id-a', 'first'],
  ]);
  expect(offered[0]?.lastUsedAt).toStrictEqual('2026-10-03T00:00:00.000Z');
  expect(offered[0]?.resume.record).toStrictEqual('/state/records/c.jsonl');
  expect(earlierSessions([record('open')], CLAUDE, 'id-open')).toStrictEqual(
    [],
  );
  expect(
    earlierSessions(records, { agent: 'claude' }, 'id-open').map(
      ({ resume }) => resume.cwd,
    ),
  ).toStrictEqual(['/work', '/work', '/work', '/other']);
});

test('a recorded past draws its prompts, updates and results in order, under turns of their own, with their tokens', () => {
  const past = recordActions([
    HEADER,
    { type: 'state', options: {} },
    { type: 'prompt', turnId: 't1', at: 5, prompt: 'look', images: 0 },
    {
      type: 'update',
      turnId: 't1',
      update: {
        sessionUpdate: 'agent_thought_chunk',
        content: { type: 'text', text: 'Reading it.' },
      },
    },
    {
      type: 'update',
      turnId: 't1',
      update: {
        sessionUpdate: 'tool_call',
        toolCallId: 'c1',
        title: 'Read a.ts',
        kind: 'read',
        status: 'failed',
        content: [
          {
            type: 'content',
            content: { type: 'text', text: 'ENOENT' },
          },
        ],
      },
    },
    {
      type: 'result',
      turnId: 't1',
      result: { status: 'completed', stopReason: 'end_turn' },
    },
    // After its answer, as some agents send it.
    {
      type: 'update',
      turnId: 't1',
      update: {
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text: 'It is gone.' },
      },
    },
    { type: 'usage', turnId: 't1', usage: { totalTokens: 9 } },
  ]);
  const transcript = transcriptOf(past);

  expect(past.filter((action) => action.type === 'usage')).toStrictEqual([
    { type: 'usage', turnId: 'history-t1', usage: { totalTokens: 9 } },
  ]);
  expect(transcript.turn).toStrictEqual({ status: 'idle' });
  expect(
    transcript.entries.map((entry) => [entry.kind, entry.turnId]),
  ).toStrictEqual([
    ['user', 'history-t1'],
    ['thought', 'history-t1'],
    ['tool', 'history-t1'],
    ['assistant', 'history-t1'],
  ]);

  const tool = transcript.entries[2];

  expect(tool?.kind === 'tool' && tool.call.status).toStrictEqual('failed');
  expect(tool?.kind === 'tool' && tool.call.kind).toStrictEqual('read');
});

test('a recorded turn with no end, as when chord was stopped mid-turn, is not left working', () => {
  const actions = recordActions([
    { type: 'prompt', turnId: 't1', at: 5, prompt: 'go', images: 0 },
    { type: 'prompt', turnId: 't2', at: 6, prompt: 'again', images: 0 },
  ]);

  expect(
    actions
      .filter((action) => action.type === 'result')
      .map(
        (action) =>
          action.type === 'result' && [action.turnId, action.result.status],
      ),
  ).toStrictEqual([
    ['history-t1', 'completed'],
    ['history-t2', 'completed'],
  ]);
  expect(transcriptOf(actions).turn).toStrictEqual({ status: 'idle' });
});

test('shell output sent with a recorded prompt replays as the runs it came from', () => {
  const sent = withContext(
    shellContext([
      {
        command: 'false',
        stdout: '',
        stderr: 'bad',
        running: false,
        code: 1,
      },
    ]),
    'why?',
  );
  const { entries } = transcriptOf(
    recordActions([
      { type: 'prompt', turnId: 't', at: 5, prompt: sent, images: 0 },
    ]),
  );

  expect(entries).toStrictEqual([
    {
      kind: 'shell',
      turnId: 'history-t-shell-1',
      run: {
        command: 'false',
        stdout: '',
        stderr: 'bad',
        running: false,
        code: 1,
      },
    },
    { kind: 'user', turnId: 'history-t', text: 'why?' },
  ]);
});

test('a recorded prompt shows its images as placeholders', () => {
  const shown = (prompt: string, images: number) =>
    transcriptOf(
      recordActions([{ type: 'prompt', turnId: 't', at: 5, prompt, images }]),
    ).entries.flatMap((entry) => (entry.kind === 'user' ? [entry.text] : []));

  // chord's own prompt names its image already.
  expect(shown('[Image #1] what', 1)).toStrictEqual(['[Image #1] what']);
  expect(shown('look', 2)).toStrictEqual(['look [Image #1] [Image #2]']);
  expect(shown('', 1)).toStrictEqual(['[Image #1]']);
});

test("a replayed prompt's resource links draw nothing beside the @path it names", () => {
  const typed = 'look at @src/a.ts';
  const past = pastActions(
    [
      {
        update: {
          sessionUpdate: 'user_message_chunk',
          content: { type: 'text', text: typed },
        },
      },
      {
        update: {
          sessionUpdate: 'user_message_chunk',
          content: {
            type: 'resource_link',
            name: 'src/a.ts',
            uri: 'file:///repo/src/a.ts',
          },
        },
      },
      {
        update: {
          sessionUpdate: 'agent_message_chunk',
          content: { type: 'text', text: 'ok' },
        },
      },
    ],
    5,
  );

  expect(
    transcriptOf(past).entries.flatMap((entry) =>
      entry.kind === 'user' ? [entry.text] : [],
    ),
  ).toStrictEqual([typed]);
});

test("an agent's replayed past becomes a record's lines, shell output put back ahead of its prompt", () => {
  const run = {
    command: 'ls',
    stdout: 'a',
    stderr: '',
    running: false,
    code: 0,
  };
  const past = recordActions([
    {
      type: 'prompt',
      turnId: 't',
      at: 5,
      prompt: withContext(shellContext([run]), 'and?'),
      images: 0,
    },
    {
      type: 'update',
      turnId: 't',
      update: {
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text: 'ok' },
      },
    },
  ]);

  expect(recordActions(historyEntries(past)).length).toStrictEqual(past.length);
  expect(historyEntries(past)[0]).toStrictEqual({
    type: 'prompt',
    turnId: 'history-t',
    at: 5,
    prompt: withContext(shellContext([run]), 'and?'),
    images: 0,
  });
});

/** `open_agent`'s line in a parent's record, as chord served it. */
function opened(id: string, name: string, agent: string): RecordEntry {
  return {
    type: 'served',
    turnId: 't1',
    call: {
      tool: 'open_agent',
      input: { agent, prompt: 'go', name },
      answer: { id, name, agent },
    },
  };
}

test('a resumed past closes by naming the long-lived agents open when it was left, but none closed before', () => {
  const entries: RecordEntry[] = [
    { type: 'prompt', turnId: 't1', at: 5, prompt: 'agents', images: 0 },
    opened('a1', 'parser', 'codex'),
    opened('a2', 'docs', 'claude'),
    opened('a3', 'printer', 'gemini'),
    {
      type: 'result',
      turnId: 't1',
      result: { status: 'completed', stopReason: 'end_turn' },
    },
    { type: 'closed', agent: 'a3' },
  ];
  const actions = recordActions(entries);

  expect(actions.at(-1)).toStrictEqual({
    type: 'left_open',
    turnId: 'history-left',
    agents: [
      { name: 'parser', runtime: 'codex' },
      { name: 'docs', runtime: 'claude' },
    ],
  });
  expect(transcriptOf(actions).entries.at(-1)?.kind).toStrictEqual('left_open');

  // Every one closed in its own time: no note.
  expect(
    !recordActions([
      ...entries,
      { type: 'closed', agent: 'a1' },
      { type: 'closed', agent: 'a2' },
    ]).some((action) => action.type === 'left_open'),
  ).toBeTruthy();
});

test('a long-lived agent closed while its parent goes on is recorded by its id', () => {
  expect(
    entryOf({ type: 'agent_closed', id: 'a1' }, { type: 'state', options: {} }),
  ).toStrictEqual({ type: 'closed', agent: 'a1' });
});

test("a message's prompt reads on one line as what was said, without its wrapper", () => {
  expect(
    promptLine('<message from="main">\nRun the parser\ntests.\n</message>'),
  ).toStrictEqual('Run the parser tests.');
});

test('the model, mode and config values are recorded once they move', () => {
  const state = { type: 'state' as const, model: 'm', options: {} };

  expect(
    entryOf(
      {
        type: 'modes',
        modes: { current: 'plan', available: [] },
      },
      state,
    ),
  ).toStrictEqual({ type: 'state', model: 'm', mode: 'plan', options: {} });
  expect(
    entryOf(
      {
        type: 'model',
        models: { current: 'm', available: [] },
      },
      state,
    ),
  ).toStrictEqual(undefined);
  expect(entryOf({ type: 'closing' }, state)).toStrictEqual(undefined);
});

test('a session in another directory is refused with the command that opens it there', () => {
  const chosen = { sessionId: 'id-there', cwd: '/h/other' };

  expect(
    elsewhereRefusal(chosen, { agent: 'claude', shownCwd: '~/other' }),
  ).toStrictEqual(
    'That session is in ~/other. Quit and open it there with:\n' +
      'chord claude --resume id-there',
  );
  expect(
    elsewhereRefusal(chosen, {
      agent: 'mine',
      agentCommand: 'my-agent --acp',
      shownCwd: '~/other',
    }),
  ).toStrictEqual(
    "That session is in ~/other. Quit and open it there with:\nchord mine --agent-command 'my-agent --acp' --resume id-there",
  );
});

test("a record draws a message as the row it was, and chord's calls as what chord served", () => {
  const { entries } = transcriptOf(
    recordActions([
      {
        type: 'prompt',
        turnId: 'p1',
        at: 1,
        prompt: '<message from="parser · codex">\nTwo tests fail.\n</message>',
        images: 0,
      },
      {
        type: 'update',
        turnId: 'p1',
        update: {
          sessionUpdate: 'tool_call',
          toolCallId: 'c1',
          title: 'mcp__chord__list_sessions',
          rawInput: {},
        },
      },
      {
        type: 'served',
        turnId: 'p1',
        call: { tool: 'list_sessions', input: {}, answer: { sessions: [] } },
      },
    ]),
  );

  expect(entries[0]).toStrictEqual({
    kind: 'message',
    turnId: 'history-p1',
    from: { name: 'parser', runtime: 'codex' },
    text: 'Two tests fail.',
  });
  expect(
    entries[1]?.kind === 'tool' ? entries[1].call.chord?.tool : undefined,
  ).toStrictEqual('list_sessions');
});

test('a record keeps whether a message came from an agent send_message reaches, which its wrapper does not say', () => {
  const from = { name: 'parser', runtime: 'codex', reachable: true } as const;
  const { entries } = transcriptOf(
    recordActions([
      {
        type: 'prompt',
        turnId: 'p1',
        at: 1,
        prompt: '<message from="parser · codex">\nTwo tests fail.\n</message>',
        images: 0,
        from,
      },
    ]),
  );

  expect(
    entries[0]?.kind === 'message' ? entries[0].from : undefined,
  ).toStrictEqual(from);
});

/** A record kept before senders were: the wrappers, and what was served. */
function legacyFroms(
  served: readonly [ChordTool, string][],
  senders: readonly string[],
) {
  const { entries } = transcriptOf(
    recordActions([
      ...served.map(([tool, name], index): RecordEntry => ({
        type: 'served',
        turnId: `s${index}`,
        call: { tool, input: {}, answer: { id: `id${index}`, name } },
      })),
      ...senders.map((sender, index): RecordEntry => ({
        type: 'prompt',
        turnId: `p${index}`,
        at: index,
        prompt: `<message from="${sender}">\nHi\n</message>`,
        images: 0,
      })),
    ]),
  );

  return entries.flatMap((entry) =>
    entry.kind === 'message' ? [entry.from] : [],
  );
}

test('a record kept before senders were reads a child open_agent opened and main as reachable', () => {
  expect(
    legacyFroms(
      [['open_agent', 'engineer']],
      ['engineer · fx', 'main', 'chord'],
    ),
  ).toStrictEqual([
    { name: 'engineer', runtime: 'fx', reachable: true },
    { name: 'main', reachable: true },
    { name: 'chord' },
  ]);
});

test('a record kept before senders were leaves a task bare, even one named as a child is', () => {
  expect(
    legacyFroms(
      [
        ['open_agent', 'parser'],
        ['spawn_task', 'parser'],
        ['spawn_task', 'main'],
      ],
      [
        'parser · codex',
        'main',
        'engineer · fx',
        'Fix the tokenizer · codex · report',
      ],
    ),
  ).toStrictEqual([
    { name: 'parser', runtime: 'codex' },
    { name: 'main' },
    { name: 'engineer', runtime: 'fx' },
    { name: 'Fix the tokenizer', runtime: 'codex', note: 'report' },
  ]);
});

test("a resumed parent's task block takes its work from the task's own record, and stays bare without it", () => {
  const start: RecordEntry = {
    type: 'update',
    turnId: 't1',
    update: taskUpdate('task-1', 'running', {
      name: 'Fix the tokenizer',
      runtime: 'codex',
      prompt: 'Fix it',
    }),
    at: 1,
  };
  const end: RecordEntry = {
    type: 'update',
    turnId: 't2',
    update: taskUpdate('task-1', 'completed'),
    at: 9,
  };
  const parent: RecordEntry[] = [start, end];
  const read: RecordEntry = {
    type: 'update',
    turnId: 'c1',
    update: {
      sessionUpdate: 'tool_call',
      toolCallId: 'r1',
      title: 'Read tokenize.ts',
      status: 'completed',
    },
    at: 3,
  };
  const nested: RecordEntry = { ...read, subagentId: 'its-own' };
  const served: RecordEntry = {
    type: 'served',
    turnId: 'c1',
    call: { tool: 'send_message', input: { to: 'main' }, answer: {} },
  };
  const child: RecordEntry[] = [
    {
      type: 'session',
      version: 1,
      sessionId: 'child',
      agent: 'codex',
      cwd: '/w',
      at: 0,
      parent: 'main-id',
      task: 'task-1',
    },
    { type: 'prompt', turnId: 'c1', at: 2, prompt: 'Fix it', images: 0 },
    read,
    nested,
    served,
    {
      type: 'result',
      turnId: 'c1',
      result: { status: 'completed', stopReason: 'end_turn' },
    },
  ];

  expect(withTaskWork(parent, new Map([['task-1', child]]))).toStrictEqual([
    start,
    { ...read, turnId: 't1', subagentId: 'task-1' },
    { ...nested, turnId: 't1' },
    { ...served, turnId: 't1', subagentId: 'task-1' },
    end,
  ]);
  // With no record of its own, the block is as the parent kept it, marked
  // so its ending counts no work.
  expect(withTaskWork(parent, new Map([['task-2', child]]))).toStrictEqual(
    withTaskWork(parent, new Map()),
  );
  expect(
    withTaskWork(parent, new Map()).map((entry) =>
      entry.type === 'update'
        ? (entry.update._meta?.['chord/task'] as { workLost?: boolean })
            ?.workLost
        : undefined,
    ),
  ).toStrictEqual([true, undefined]);
});

/** `run_team`'s line in a parent's record, as chord served it. */
function ran(id: string, name: string, team: string): RecordEntry {
  return {
    type: 'served',
    turnId: 't1',
    call: {
      tool: 'run_team',
      input: { team, job: 'Fix issue 214' },
      answer: { id, name, team, agent: 'claude', model: 'opus' },
    },
  };
}

/** A lead's record: its header, and the members it opened. */
function leadRecord(
  id: string,
  team: string,
  ...entries: RecordEntry[]
): RecordEntry[] {
  return [
    {
      type: 'session',
      version: 1,
      sessionId: `session-${id}`,
      agent: 'claude',
      cwd: '/w',
      at: 0,
      parent: 'main-id',
      name: team,
      id,
      team,
    },
    ...entries,
  ];
}

test("a resumed past names each team run open when it was left as one item, counting the members its lead's record had open", () => {
  const entries: RecordEntry[] = [
    { type: 'prompt', turnId: 't1', at: 5, prompt: 'hand it on', images: 0 },
    opened('a1', 'parser', 'codex'),
    ran('l1', 'bugfix', 'bugfix'),
    ran('l2', 'bugfix 2', 'bugfix'),
    ran('l3', 'docs', 'docs'),
    { type: 'closed', agent: 'l3' },
  ];
  const runs = new Map([
    [
      'l1',
      leadRecord(
        'l1',
        'bugfix',
        opened('m1', 'tester', 'claude'),
        opened('m2', 'coder', 'codex'),
        opened('m3', 'reviewer', 'claude'),
      ),
    ],
    [
      'l2',
      leadRecord(
        'l2',
        'bugfix',
        opened('m4', 'tester', 'claude'),
        opened('m5', 'coder', 'codex'),
        { type: 'closed', agent: 'm5' },
      ),
    ],
  ]);

  expect(recordActions(entries, runs).at(-1)).toStrictEqual({
    type: 'left_open',
    turnId: 'history-left',
    agents: [
      { name: 'parser', runtime: 'codex' },
      { name: 'bugfix', runtime: 'claude', team: 'bugfix', agents: 4 },
      { name: 'bugfix 2', runtime: 'claude', team: 'bugfix', agents: 2 },
    ],
  });

  // A lead whose record has gone counts itself alone.
  expect(recordActions(entries).at(-1)).toStrictEqual({
    type: 'left_open',
    turnId: 'history-left',
    agents: [
      { name: 'parser', runtime: 'codex' },
      { name: 'bugfix', runtime: 'claude', team: 'bugfix', agents: 1 },
      { name: 'bugfix 2', runtime: 'claude', team: 'bugfix', agents: 1 },
    ],
  });
});

test("a person's /team run is recorded as the run_team call it was, so a resume knows the run", () => {
  const call = ran('l1', 'bugfix', 'bugfix');

  assert(call.type === 'served');
  expect(
    entryOf(
      { type: 'run_typed', turnId: 't1', call: call.call },
      { type: 'state', options: {} },
    ),
  ).toStrictEqual({ type: 'ran', turnId: 't1', call: call.call });
});

/** A resumed past with a typed run, then the agent's own `run_team` call. */
function typedThenCalled(answerFirst: boolean): Transcript {
  const typed = ran('old', 'bugfix', 'bugfix');
  const again = ran('new', 'bugfix 2', 'bugfix');

  assert(typed.type === 'served' && again.type === 'served');

  const call: TranscriptAction = {
    type: 'update',
    turnId: 'now',
    update: {
      sessionUpdate: 'tool_call',
      toolCallId: 'c1',
      title: 'mcp__chord__run_team',
      rawInput: again.call.input,
    },
  };
  const answer: TranscriptAction = {
    type: 'served',
    turnId: 'now',
    call: again.call,
  };
  const past = recordActions([{ type: 'ran', turnId: 't0', call: typed.call }]);

  return [...(answerFirst ? [answer, call] : [call, answer])].reduce(
    reduceTranscript,
    transcriptOf(past),
  );
}

test("a typed run resumed is no answer to the agent's own run_team call with the same arguments", () => {
  for (const answerFirst of [false, true]) {
    const { entries, served } = typedThenCalled(answerFirst);
    const tool = entries.find((entry) => entry.kind === 'tool');

    expect(
      tool?.kind === 'tool' ? tool.call.chord?.answer : undefined,
    ).toStrictEqual({
      id: 'new',
      name: 'bugfix 2',
      team: 'bugfix',
      agent: 'claude',
      model: 'opus',
    });
    expect(served).toStrictEqual(undefined);
  }
});

test("a typed run resumed is counted in the closing note like the agent's", () => {
  const typed = ran('l1', 'bugfix', 'bugfix');

  assert(typed.type === 'served');
  expect(
    recordActions(
      [{ type: 'ran', turnId: 't1', call: typed.call }],
      new Map([
        ['l1', leadRecord('l1', 'bugfix', opened('m1', 'tester', 'claude'))],
      ]),
    ),
  ).toStrictEqual([
    {
      type: 'left_open',
      turnId: 'history-left',
      agents: [
        {
          name: 'bugfix',
          runtime: 'claude',
          team: 'bugfix',
          agents: 2,
        },
      ],
    },
  ]);
});

test("a parent's team runs are read from their leads' records beside its own, by chord's id for each lead", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-runs-'));

  try {
    const lead = leadRecord('l1', 'bugfix', opened('m1', 'tester', 'claude'));
    const member: RecordEntry[] = [
      {
        type: 'session',
        version: 1,
        sessionId: 'session-m1',
        agent: 'claude',
        cwd: '/w',
        at: 0,
        parent: 'session-l1',
        name: 'tester',
        id: 'm1',
      },
    ];
    const other: RecordEntry[] = [
      { ...lead[0]!, parent: 'other-id' } as RecordEntry,
    ];
    const write = (name: string, entries: readonly RecordEntry[]) =>
      writeFile(
        `${dir}/${name}.jsonl`,
        entries.map((entry) => JSON.stringify(entry)).join('\n') + '\n',
      );

    await write('lead', lead);
    await write('member', member);
    await write('other', other);

    expect(await runPasts(dir, 'main-id')).toStrictEqual(
      new Map([['l1', lead]]),
    );
    // The member's record names its lead, not main.
    expect([...(await runPasts(dir, 'session-l1')).keys()]).toStrictEqual([]);
  } finally {
    await rm(dir, { recursive: true });
  }
});

/** A session as `FileRecording` reads it as it opens. */
function stubSession(id: string): Session {
  return {
    id,
    agent: 'claude',
    cwd: '/w',
    record: undefined,
    models: () => undefined,
    modes: () => undefined,
    options: () => [],
    history: () => [],
  } as unknown as Session;
}

test("a team lead's record names main as its parent and its team, and a member's names its lead and its member name", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'chord-team-records-'));

  try {
    const record = async (
      child: ConstructorParameters<typeof FileRecording>[3],
      id: string,
    ) => {
      const recording = new FileRecording(
        stateDir,
        () => {},
        () => 7,
        child,
      );

      recording.opened(stubSession(id));
      recording.sent('t1', 'go', 0, [], 8);
      await recording.flushed();

      return (await readPast(recording.path!))[0];
    };

    expect(
      await record(
        { parent: () => 'main-id', name: 'bugfix', id: 'l1', team: 'bugfix' },
        'lead-id',
      ),
    ).toStrictEqual({
      type: 'session',
      version: 1,
      sessionId: 'lead-id',
      agent: 'claude',
      cwd: '/w',
      at: 7,
      parent: 'main-id',
      name: 'bugfix',
      id: 'l1',
      team: 'bugfix',
    });
    expect(
      await record(
        { parent: () => 'lead-id', name: 'tester', id: 'm1' },
        'member-id',
      ),
    ).toStrictEqual({
      type: 'session',
      version: 1,
      sessionId: 'member-id',
      agent: 'claude',
      cwd: '/w',
      at: 7,
      parent: 'lead-id',
      name: 'tester',
      id: 'm1',
    });
  } finally {
    await rm(stateDir, { recursive: true });
  }
});

import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { MCP_CALL } from '../../../src/session/enrich.ts';
import { taskUpdate } from '../../../src/session/tasks.ts';
import type {
  ChordCall,
  Transcript,
  TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import { fold } from './fold.ts';

const ARGS = { agent: 'codex', prompt: 'Fix it', name: 'Fix the tokenizer' };

/** A call as Claude's adapter sends one of an MCP server's. */
function called(
  id: string,
  rawInput: unknown,
  title = 'mcp__chord__spawn_task',
  subagentId?: string,
): TranscriptAction {
  return {
    type: 'update',
    turnId: 't1',
    ...(subagentId === undefined ? {} : { subagentId }),
    update: {
      sessionUpdate: 'tool_call',
      toolCallId: id,
      title,
      kind: 'other',
      status: 'pending',
      rawInput,
    },
  };
}

function finished(id: string): TranscriptAction {
  return {
    type: 'update',
    turnId: 't1',
    update: {
      sessionUpdate: 'tool_call_update',
      toolCallId: id,
      status: 'completed',
      content: [{ type: 'content', content: { type: 'text', text: '{}' } }],
    },
  };
}

function served(call: ChordCall, subagentId?: string): TranscriptAction {
  return {
    type: 'served',
    turnId: 't1',
    call,
    ...(subagentId === undefined ? {} : { subagentId }),
  };
}

const STARTED: TranscriptAction = {
  type: 'update',
  turnId: 't1',
  update: taskUpdate('task-1', 'running', {
    name: 'Fix the tokenizer',
    runtime: 'codex',
    model: 'gpt-5.3-codex',
    prompt: 'Fix it',
  }),
  at: 1000,
};

const SPAWNED: ChordCall = {
  tool: 'spawn_task',
  input: ARGS,
  answer: { id: 'task-1' },
  task: 'task-1',
};

const PROMPT: TranscriptAction = {
  type: 'prompt',
  turnId: 't1',
  text: 'go',
  at: 0,
};

function kinds(transcript: Transcript): string[] {
  return transcript.entries.map((entry) => entry.kind);
}

test('a task stands in place of the spawn_task call that started it, and takes its updates', () => {
  const transcript = fold([
    PROMPT,
    called('c1', ARGS),
    called('c2', { path: 'a' }, 'Read a'),
    STARTED,
    served(SPAWNED),
    finished('c1'),
  ]);

  expect(kinds(transcript)).toStrictEqual(['user', 'subagent', 'tool']);

  const [, entry] = transcript.entries;

  assert(entry?.kind === 'subagent');
  expect(entry.subagent.callId).toStrictEqual('c1');
  expect(entry.subagent.task).toStrictEqual({
    name: 'Fix the tokenizer',
    runtime: 'codex',
    model: 'gpt-5.3-codex',
  });
  expect(entry.subagent.title).toStrictEqual('Fix the tokenizer');
  expect(entry.subagent.description).toStrictEqual('Fix it');
});

test("a task's effort, said once it is up, joins what its block knows of it", () => {
  const transcript = fold([
    PROMPT,
    called('c1', ARGS),
    STARTED,
    served(SPAWNED),
    {
      type: 'update',
      turnId: '',
      update: taskUpdate('task-1', 'running', {
        name: 'Fix the tokenizer',
        runtime: 'codex',
        model: 'gpt-5.3-codex',
        effort: 'high',
        prompt: 'Fix it',
      }),
      at: 2000,
    },
  ]);
  const [, entry] = transcript.entries;

  assert(entry?.kind === 'subagent');
  expect(entry.subagent.task).toStrictEqual({
    name: 'Fix the tokenizer',
    runtime: 'codex',
    model: 'gpt-5.3-codex',
    effort: 'high',
  });
  expect(entry.subagent.startedAt).toStrictEqual(1000);
  expect(entry.subagent.state).toStrictEqual('running');
});

test('a request served before its call came is tied to the call once it does', () => {
  const call: ChordCall = {
    tool: 'list_sessions',
    input: {},
    answer: { sessions: [] },
  };
  const before = fold([PROMPT, served(call)]);

  expect(before.served).toStrictEqual([call]);

  const after = fold([called('c1', {}, 'mcp__chord__list_sessions')], before);
  const [, entry] = after.entries;

  assert(entry?.kind === 'tool');
  expect(entry.call.chord).toStrictEqual(call);
  expect(after.served).toStrictEqual(undefined);
});

test("a call is chord's by its arguments, the one titled with the tool first, never one of the user's", () => {
  const call: ChordCall = { tool: 'list_agents', input: { agent: 'codex' } };
  const transcript = fold([
    PROMPT,
    called('mine', { agent: 'codex' }, 'mcp__chord__list_agents'),
    called('theirs', { agent: 'codex' }, 'mcp__other__lookup'),
    served(call),
  ]);
  const chordOf = (id: string) =>
    transcript.entries.find(
      (entry) => entry.kind === 'tool' && entry.call.id === id,
    );
  const mine = chordOf('mine');
  const theirs = chordOf('theirs');

  assert(mine?.kind === 'tool' && theirs?.kind === 'tool');
  expect(mine.call.chord).toStrictEqual(call);
  expect(theirs.call.chord).toStrictEqual(undefined);
});

test("a task's own call to chord is tied among its work", () => {
  const sent: ChordCall = {
    tool: 'send_message',
    input: { text: 'Found it' },
    answer: { delivered: 'queued' },
    queued: true,
  };
  const transcript = fold([
    PROMPT,
    STARTED,
    called('m1', { text: 'Found it' }, 'mcp__chord__send_message', 'task-1'),
    served(sent, 'task-1'),
  ]);
  const [, entry] = transcript.entries;

  assert(entry?.kind === 'subagent');

  const [call] = entry.subagent.entries;

  assert(call?.kind === 'tool');
  expect(call.call.chord).toStrictEqual(sent);
});

test('a message begins its turn as a row of its own, never the person’s', () => {
  const transcript = fold([
    {
      type: 'prompt',
      turnId: 't2',
      text: 'Fixed it.',
      at: 5,
      from: { name: 'Fix the tokenizer', runtime: 'codex', note: 'report' },
    },
  ]);

  expect(transcript.entries).toStrictEqual([
    {
      kind: 'message',
      turnId: 't2',
      from: { name: 'Fix the tokenizer', runtime: 'codex', note: 'report' },
      text: 'Fixed it.',
    },
  ]);
  expect(transcript.turn).toStrictEqual({
    status: 'working',
    turnId: 't2',
    since: 5,
  });
});

test("a team agent's first message comes after its team part, which is an entry of its own", () => {
  const team = { team: 'bugfix', member: 'tester', text: 'You are tester.' };
  const transcript = fold([
    {
      type: 'prompt',
      turnId: 't1',
      text: 'Write the test.',
      at: 5,
      from: { name: 'bugfix', reachable: true },
      team,
    },
  ]);

  expect(transcript.entries).toStrictEqual([
    { kind: 'team_part', turnId: 't1', part: team },
    {
      kind: 'message',
      turnId: 't1',
      from: { name: 'bugfix', reachable: true },
      text: 'Write the test.',
    },
  ]);
});

test("a task's permission outlives the turn, waits between turns and leaves the session idle once answered", () => {
  const asked: TranscriptAction = {
    type: 'permission_requested',
    turnId: 't1',
    permission: { id: 'p1', subagentId: 'task-1', options: [] },
    at: 2000,
  };
  const ended: TranscriptAction = {
    type: 'result',
    turnId: 't1',
    result: { status: 'completed', stopReason: 'end_turn' },
  };
  const during = fold([PROMPT, STARTED, asked, ended]);

  expect(during.turn).toStrictEqual({
    status: 'awaiting_permission',
    turnId: 't1',
    since: 0,
    permissions: [asked.permission],
    between: true,
  });

  // Asked after the turn ended, it waits as well.
  const after = fold([PROMPT, STARTED, ended, asked]);

  expect(after.turn.status).toStrictEqual('awaiting_permission');

  // A message's turn keeps it waiting; answering it leaves that turn working.
  const next = fold(
    [
      {
        type: 'prompt',
        turnId: 't2',
        text: 'hi',
        at: 3000,
        from: { name: 'chord' },
      },
    ],
    after,
  );

  expect(next.turn.status).toStrictEqual('awaiting_permission');

  expect(
    fold(
      [
        {
          type: 'permission_settled',
          turnId: 't1',
          id: 'p1',
          answer: { type: 'chosen', optionId: 'allow' },
        },
      ],
      after,
    ).turn,
  ).toStrictEqual({ status: 'idle' });
  expect(
    fold(
      [
        {
          type: 'permission_settled',
          turnId: 't1',
          id: 'p1',
          answer: { type: 'chosen', optionId: 'allow' },
        },
      ],
      next,
    ).turn,
  ).toStrictEqual({ status: 'working', turnId: 't2', since: 3000 });
});

test("a subagent of the runtime's own asking outside a turn is still refused", () => {
  const transcript = fold([
    {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', subagentId: 'agent-1', options: [] },
    },
  ]);

  expect(transcript.turn).toStrictEqual({ status: 'idle' });
});

test('an answer served after a pending one takes its place on the call, whether the call came first or not', () => {
  const input = { name: 'bugfix', body: 'How it works' };
  const pending: ChordCall = {
    tool: 'propose_team',
    input,
    answer: { proposal: 'new', files: {} },
    pending: true,
    asked: 'a1',
  };
  const answered: ChordCall = {
    tool: 'propose_team',
    input,
    answer: { proposal: 'new', files: {}, saved: false },
    asked: 'a1',
  };
  const call = called('c1', input, 'mcp__chord__propose_team');

  for (const actions of [
    [PROMPT, call, served(pending), served(answered)],
    [PROMPT, served(pending), call, served(answered)],
    [PROMPT, served(pending), served(answered), call],
  ]) {
    const transcript = fold(actions);
    const [, entry] = transcript.entries;

    assert(entry?.kind === 'tool');
    expect(entry.call.chord).toStrictEqual(answered);
    expect(transcript.served ?? []).toStrictEqual([]);
  }

  // The same team proposed again is a call of its own.
  const pendingAgain = { ...pending, asked: 'a2' };
  const again = fold([
    PROMPT,
    call,
    served(pending),
    served(answered),
    called('c2', input, 'mcp__chord__propose_team'),
    served(pendingAgain),
  ]);
  const tools = again.entries.flatMap((entry) =>
    entry.kind === 'tool' ? [entry.call.chord] : [],
  );

  expect(tools).toStrictEqual([answered, pendingAgain]);
});

test('a message served sent, then again once it went queued after all, is drawn queued on its call, whether the call came first or not', () => {
  const input = { to: 'parser', text: 'Run the tests.' };
  const sent: ChordCall = {
    tool: 'send_message',
    input,
    answer: { delivered: 'sent', to: 'parser' },
    asked: 'm1',
  };
  const queued: ChordCall = { ...sent, queued: true };
  const call = called('c1', input, 'mcp__chord__send_message');

  for (const actions of [
    [PROMPT, call, served(sent), served(queued)],
    [PROMPT, served(sent), call, served(queued)],
    [PROMPT, served(sent), served(queued), call],
  ]) {
    const transcript = fold(actions);
    const [, entry] = transcript.entries;

    assert(entry?.kind === 'tool');
    expect(entry.call.chord).toStrictEqual(queued);
    expect(transcript.served ?? []).toStrictEqual([]);
  }
});

test('two proposals of the same team waiting at once each keep their own, and each answer goes to its own call', () => {
  const input = { name: 'bugfix', body: 'How it works' };
  const pending = (asked: string): ChordCall => ({
    tool: 'propose_team',
    input,
    answer: { proposal: 'new', files: {} },
    pending: true,
    asked,
  });
  const answered = (asked: string, saved: boolean): ChordCall => ({
    tool: 'propose_team',
    input,
    answer: { proposal: 'new', files: {}, saved },
    asked,
  });
  const first = called('c1', input, 'mcp__chord__propose_team');
  const second = called('c2', input, 'mcp__chord__propose_team');
  const chords = (transcript: ReturnType<typeof fold>) =>
    transcript.entries.flatMap((entry) =>
      entry.kind === 'tool' ? [[entry.call.id, entry.call.chord]] : [],
    );

  for (const waiting of [
    [first, served(pending('a1')), second, served(pending('a2'))],
    [served(pending('a1')), served(pending('a2')), first, second],
  ]) {
    expect(chords(fold([PROMPT, ...waiting]))).toStrictEqual([
      ['c1', pending('a1')],
      ['c2', pending('a2')],
    ]);

    // The second box answered first: each answer finds its own.
    const transcript = fold([
      PROMPT,
      ...waiting,
      served(answered('a2', true)),
      served(answered('a1', false)),
    ]);

    expect(chords(transcript)).toStrictEqual([
      ['c1', answered('a1', false)],
      ['c2', answered('a2', true)],
    ]);
    expect(transcript.served ?? []).toStrictEqual([]);
  }

  // Both calls came before either was served: nothing tells which is which,
  // so each draws one proposal, and its answer is the one asked with it.
  const both = [PROMPT, first, second];
  const shown = chords(
    fold([...both, served(pending('a1')), served(pending('a2'))]),
  );
  const settled = chords(
    fold([
      ...both,
      served(pending('a1')),
      served(pending('a2')),
      served(answered('a2', true)),
      served(answered('a1', false)),
    ]),
  );
  const asked = (rows: typeof shown) =>
    rows.map(([, chord]) => (chord as ChordCall).asked).toSorted();

  expect(asked(shown)).toStrictEqual(['a1', 'a2']);
  expect(asked(settled)).toStrictEqual(['a1', 'a2']);
  expect(
    settled.map(([id, chord]) => [id, (chord as ChordCall).asked]),
  ).toStrictEqual(shown.map(([id, chord]) => [id, (chord as ChordCall).asked]));
  expect(
    settled.every(([, chord]) => (chord as ChordCall).pending !== true),
  ).toBeTruthy();
});

test("chord's own question leaves no record of its answer: the call says it", () => {
  const asked: TranscriptAction = {
    type: 'permission_requested',
    turnId: 't1',
    permission: {
      id: 'p1',
      options: [{ optionId: 'change', name: 'No', kind: 'reject_once' }],
      save: { question: 'Save team bugfix?', files: {}, escape: 'no' },
    },
  };
  const transcript = fold([
    PROMPT,
    asked,
    {
      type: 'permission_settled',
      turnId: 't1',
      id: 'p1',
      answer: { type: 'rejected' },
    },
  ]);

  expect(kinds(transcript)).toStrictEqual(['user']);
  expect(transcript.turn.status).toStrictEqual('working');
});

/** A call as codex-acp sends one of an MCP server's, once enriched. */
function wrapped(
  id: string,
  server: string,
  tool: string,
  args: Record<string, unknown>,
): TranscriptAction {
  return {
    type: 'update',
    turnId: 't1',
    update: {
      sessionUpdate: 'tool_call',
      toolCallId: id,
      title: `mcp.${server}.${tool}`,
      kind: 'execute',
      status: 'in_progress',
      rawInput: { server, tool, arguments: args },
      _meta: {
        is_mcp_tool_call: true,
        [MCP_CALL]: { server, tool, arguments: args },
      },
    },
  };
}

test("a request chord served ties to Codex's call by the tool and arguments it wrapped", () => {
  const message: ChordCall = {
    tool: 'send_message',
    input: { to: 'ship', text: 'Tester ready.' },
    answer: { to: 'ship' },
  };
  const listed: ChordCall = { tool: 'list_agents', input: {}, answer: {} };
  const transcript = fold([
    { type: 'prompt', turnId: 't1', text: 'go', at: 0 },
    wrapped(
      'exec-1',
      'chord',
      'send_message',
      message.input as Record<string, unknown>,
    ),
    served(message),
    // Served before its call came, as list_agents can be.
    served(listed),
    wrapped('exec-2', 'chord', 'list_agents', {}),
  ]);
  const calls = transcript.entries.flatMap((entry) =>
    entry.kind === 'tool' ? [entry.call] : [],
  );

  expect(calls.map((call) => call.chord)).toStrictEqual([message, listed]);
  expect(transcript.served).toStrictEqual(undefined);
});

test('a call of another tool with the same arguments is not tied, whatever server it names', () => {
  const listed: ChordCall = { tool: 'list_agents', input: {}, answer: {} };
  const transcript = fold([
    { type: 'prompt', turnId: 't1', text: 'go', at: 0 },
    wrapped('exec-1', 'notes', 'list_notes', {}),
    wrapped('exec-2', 'chord', 'list_sessions', {}),
    served(listed),
  ]);
  const calls = transcript.entries.flatMap((entry) =>
    entry.kind === 'tool' ? [entry.call] : [],
  );

  expect(calls.map((call) => call.chord)).toStrictEqual([undefined, undefined]);
  expect(transcript.served).toStrictEqual([listed]);
});

describe('CHD-377 tester: neutral MCP matching isolation', () => {
  for (const servedFirst of [false, true]) {
    test(`tool and deep arguments match independently of server, servedFirst=${servedFirst}`, () => {
      const message: ChordCall = {
        tool: 'send_message',
        input: {
          to: 'reviewer',
          text: 'ready',
          nested: { a: [1, 2], b: true },
        },
        answer: { to: 'reviewer' },
      };
      const calls = [
        wrapped('wrong-args', 'chord', 'send_message', {
          to: 'reviewer',
          text: 'different',
          nested: { a: [1, 2], b: true },
        }),
        wrapped(
          'wrong-tool',
          'chord',
          'close_agent',
          message.input as Record<string, unknown>,
        ),
        wrapped('accepted', 'another-server', 'send_message', {
          nested: { b: true, a: [1, 2] },
          text: 'ready',
          to: 'reviewer',
        }),
      ];
      const state = fold([
        PROMPT,
        ...(servedFirst
          ? [served(message), ...calls]
          : [...calls, served(message)]),
      ]);
      const shown = state.entries.flatMap((entry) =>
        entry.kind === 'tool' ? [entry.call] : [],
      );

      expect(shown.map((call) => [call.id, call.chord])).toEqual([
        ['wrong-args', undefined],
        ['wrong-tool', undefined],
        ['accepted', message],
      ]);
      expect(shown[2]?.rawInput).toEqual({
        server: 'another-server',
        tool: 'send_message',
        arguments: {
          nested: { b: true, a: [1, 2] },
          text: 'ready',
          to: 'reviewer',
        },
      });
    });
  }

  test('metadata arriving only in an update links a request that was already served', () => {
    const input = { to: 'reviewer', text: 'ready' };
    const rawInput = {
      server: 'chord',
      tool: 'send_message',
      arguments: input,
    };
    const message: ChordCall = { tool: 'send_message', input, answer: {} };
    const before = fold([
      PROMPT,
      called('late', rawInput, 'mcp.chord.send_message'),
      served(message),
    ]);
    const old = before.entries.find((entry) => entry.kind === 'tool');

    assert(old?.kind === 'tool');
    expect(old.call.chord).toBeUndefined();

    const after = fold(
      [
        {
          type: 'update',
          turnId: 't1',
          update: {
            sessionUpdate: 'tool_call_update',
            toolCallId: 'late',
            _meta: { [MCP_CALL]: { tool: 'send_message', arguments: input } },
          },
        },
      ],
      before,
    );
    const linked = after.entries.find((entry) => entry.kind === 'tool');

    assert(linked?.kind === 'tool');
    expect(linked.call.chord).toEqual(message);
    expect(linked.call.rawInput).toEqual(rawInput);
    expect(linked.call.mcp).toEqual({ tool: 'send_message', input });
    expect(after.served).toBeUndefined();
    // The older, unenriched record is intentionally unchanged by CHD-377.
    expect(old.call.mcp).toBeUndefined();
    expect(old.call.chord).toBeUndefined();
  });

  test('a parent served request never consumes the same call in its child', () => {
    const message: ChordCall = {
      tool: 'send_message',
      input: { to: 'reviewer', text: 'ready' },
      answer: {},
    };
    const childCall = wrapped(
      'same-id',
      'chord',
      'send_message',
      message.input as Record<string, unknown>,
    );

    assert(childCall.type === 'update');

    const state = fold([
      PROMPT,
      STARTED,
      { ...childCall, subagentId: 'task-1' },
      served(message),
    ]);
    const child = state.entries.find((entry) => entry.kind === 'subagent');

    assert(child?.kind === 'subagent');
    expect(
      child.subagent.entries.flatMap((entry) =>
        entry.kind === 'tool' ? [entry.call.chord] : [],
      ),
    ).toEqual([undefined]);
    expect(state.served).toEqual([message]);

    const after = fold([served(message, 'task-1')], state);
    const linked = after.entries.find((entry) => entry.kind === 'subagent');

    assert(linked?.kind === 'subagent');
    expect(
      linked.subagent.entries.flatMap((entry) =>
        entry.kind === 'tool' ? [entry.call.chord] : [],
      ),
    ).toEqual([message]);
    expect(after.served).toEqual([message]);
  });
});

/** What the window says of a session's task agents and messages. */
import { expect, test } from 'bun:test';
import {
  emptyTranscript,
  type Entry,
  type Transcript,
} from '../../../src/session/transcript/types.ts';
import { busyOf } from '../../../src/ui/app/closing.ts';
import { chordLine, chordRow } from '../../../src/ui/pickers/mcp.ts';
import { queueRows, restoredDraft } from '../../../src/ui/prompt/queue.ts';
import {
  agentGroup,
  agentHeadline,
  askerRow,
  blockFold,
  groupRow,
} from '../../../src/ui/transcript/agents/subagents.ts';
import {
  foldMessage,
  inArrow,
  outArrow,
  teamPartLine,
} from '../../../src/ui/transcript/message.ts';
import {
  chordHeadline,
  chordLines,
} from '../../../src/ui/transcript/tools/chord.ts';

const TASK = {
  id: 'task-1',
  title: 'Fix the tokenizer',
  state: 'running' as const,
  entries: [],
  plan: [],
  task: { name: 'Fix the tokenizer', runtime: 'codex', model: 'gpt-5.3-codex' },
};

const task = (state: 'running' | 'completed' = 'running'): Entry => ({
  kind: 'subagent',
  turnId: 't',
  subagent: { ...TASK, state },
});

const FROM = { name: 'parser', runtime: 'codex' };

function withEntries(entries: Entry[]): Transcript {
  return { ...emptyTranscript, entries };
}

test('a running task agent makes its session busy, after the person’s queued prompts, ahead of the turn', () => {
  const two = busyOf({
    transcript: {
      ...withEntries([task(), task(), task('completed')]),
      turn: { status: 'working', turnId: 't', since: 0 },
    },
    queue: [{ turnId: 'q', text: 'x', from: FROM }],
  });

  expect(two).toStrictEqual({ kind: 'tasks', count: 2 });
  expect(
    busyOf({
      transcript: withEntries([task()]),
      queue: [{ turnId: 'q', text: 'x' }],
    }),
  ).toStrictEqual({ kind: 'queued', count: 1 });
  expect(
    busyOf({ transcript: withEntries([task('completed')]), queue: [] }),
  ).toStrictEqual(undefined);
});

test('a queued message is a row of its own after ←, and Esc never takes it into the draft', () => {
  const queue = [
    { turnId: 'a', text: 'and keep the old name' },
    { turnId: 'b', text: 'Ran the tests.\nTwo fail.', from: FROM },
  ];

  expect(queueRows(queue, 4)).toStrictEqual([
    { kind: 'prompt', text: 'and keep the old name' },
    {
      kind: 'message',
      header: 'from parser · codex: ',
      text: 'Ran the tests. …',
    },
  ]);
  expect(restoredDraft(queue, 'typed')).toStrictEqual(
    'and keep the old name\ntyped',
  );
});

test("chord's calls read as verbs, with what was said or answered under them", () => {
  expect(chordHeadline({ tool: 'list_agents', input: {} })).toStrictEqual({
    name: 'List agents',
  });
  expect(
    chordHeadline({ tool: 'list_agents', input: { agent: 'codex' } }),
  ).toStrictEqual({ name: 'List agents', arg: 'codex' });
  expect(
    chordHeadline({
      tool: 'send_message',
      input: { text: 'hi' },
      queued: true,
    }),
  ).toStrictEqual({ name: 'main', sent: true, note: ' · queued' });
  expect(
    chordHeadline({
      tool: 'send_message',
      input: { to: 'parser', text: 'hi' },
    }),
  ).toStrictEqual({ name: 'parser', sent: true });
  expect(
    chordHeadline({
      tool: 'spawn_task',
      input: { agent: 'codx', prompt: 'Fix it\nall', model: 'm' },
      error: 'No agent named codx',
    }),
  ).toStrictEqual({ name: 'Agent', arg: 'Fix it', note: ' · codx · m' });

  const agents = Array.from({ length: 7 }, (_, n) => ({ name: `r${n}` }));

  expect(
    chordLines({ tool: 'list_agents', input: {}, answer: { agents } }),
  ).toStrictEqual(['7 runtimes · r0, r1, r2, r3, +3 more']);
  expect(
    chordLines({
      tool: 'list_agents',
      input: { agent: 'codex' },
      answer: {
        agents: [{ name: 'codex', models: [{ id: 'a' }, { id: 'b' }] }],
      },
    }),
  ).toStrictEqual(['2 models · a, b']);
  // An answer from 0.57.0 has a tab number, which says nothing now.
  expect(
    chordLines({
      tool: 'list_sessions',
      input: {},
      answer: {
        sessions: [
          { tab: 1, runtime: 'claude', you: true },
          {
            tab: 2,
            runtime: 'codex',
          },
        ],
      },
    }),
  ).toStrictEqual(['2 open · claude (you), codex']);
  // One now: the session, its agents counted (CHD-493).
  expect(
    chordLines({
      tool: 'list_sessions',
      input: {},
      answer: {
        sessions: [
          {
            runtime: 'claude',
            you: true,
            agents: [
              { id: 'a', name: 'parser', runtime: 'codex' },
              { id: 'b', name: 'docs', runtime: 'claude' },
            ],
          },
        ],
      },
    }),
  ).toStrictEqual(['1 open · claude (you), 2 agents']);
  // Before the answer, nothing of its own: the call says it is running.
  expect(chordLines({ tool: 'list_sessions', input: {} })).toStrictEqual([]);
  expect(
    chordLines({ tool: 'send_message', input: { text: 'one\ntwo' } }),
  ).toStrictEqual(['one', 'two']);
  expect(
    chordLines({
      tool: 'spawn_task',
      input: {},
      error: 'No agent named codx',
    }),
  ).toStrictEqual(['No agent named codx']);
});

test('a message folds after six lines, all of them under ctrl+o', () => {
  const lines = Array.from({ length: 8 }, (_, n) => `line ${n + 1}`);

  expect(foldMessage(lines, false)).toStrictEqual({
    lines: lines.slice(0, 6),
    hidden: 2,
  });
  expect(foldMessage([...lines, ''], true)).toStrictEqual({ lines, hidden: 0 });
});

test('a message never folds on a blank line; the blank goes into the count', () => {
  const lines = ['one', '', '1. a', '2. b', '3. c', '', 'last'];

  expect(foldMessage(lines, false)).toStrictEqual({
    lines: lines.slice(0, 5),
    hidden: 2,
  });
});

test('a task block says its runtime and model after the title; a row of a group keeps them, wrapping after a ` · ` (CHD-473)', () => {
  const subagent = TASK;

  expect(agentHeadline(subagent)).toStrictEqual({
    name: 'Agent',
    arg: 'Fix the tokenizer',
    note: ' · codex · gpt-5.3-codex',
  });
  expect(
    groupRow(subagent, 46).map((runs) => runs.map(({ text }) => text).join('')),
  ).toStrictEqual([
    'Agent(Fix the tokenizer) · codex ·',
    'gpt-5.3-codex · 0 tool uses',
  ]);
  expect(
    askerRow([subagent])
      .map((piece) => piece.text)
      .join(''),
  ).toStrictEqual('Agent(Fix the tokenizer) · codex asks');
});

test('a task block says its effort after its model, left out where the model is', () => {
  const subagent = { ...TASK, task: { ...TASK.task, effort: 'high' } };

  expect(agentHeadline(subagent)).toStrictEqual({
    name: 'Agent',
    arg: 'Fix the tokenizer',
    note: ' · codex · gpt-5.3-codex · high',
  });
  expect(agentHeadline(subagent, false)).toStrictEqual({
    name: 'Agent',
    arg: 'Fix the tokenizer',
    note: ' · codex',
  });
});

test('spawn_task and open_agent say the effort asked for until chord answers with the one the agent started on', () => {
  const input = {
    agent: 'fake',
    model: 'fake-small',
    effort: 'max',
    name: 'tuner',
    prompt: 'x',
  };

  expect(chordHeadline({ tool: 'open_agent', input })).toStrictEqual({
    name: 'Open',
    arg: 'tuner',
    note: ' · fake · fake-small · max',
  });
  expect(
    chordHeadline({
      tool: 'open_agent',
      input,
      answer: { id: 'a1', name: 'tuner', agent: 'fake', effort: 'medium' },
    }),
  ).toStrictEqual({
    name: 'Open',
    arg: 'tuner',
    note: ' · fake · fake-small · medium',
  });
  expect(
    chordHeadline({
      tool: 'spawn_task',
      input,
      answer: { id: 't1', name: 'tuner', agent: 'fake' },
    }),
  ).toStrictEqual({
    name: 'Agent',
    arg: 'tuner',
    note: ' · fake · fake-small',
  });
});

test("task agents and the runtime's own subagents never share a group", () => {
  const own: Entry = {
    kind: 'subagent',
    turnId: 't',
    subagent: { id: 'own', state: 'running', entries: [], plan: [] },
  };
  const entries = [task(), task(), own];

  expect(agentGroup(entries, 0)?.length).toStrictEqual(2);
  expect(agentGroup(entries, 1)).toStrictEqual([]);
  expect(agentGroup(entries, 2)?.map((agent) => agent.id)).toStrictEqual([
    'own',
  ]);
});

test("/mcp lists chord's server first, and says what it gives or why it was not passed", () => {
  const passed = chordRow({
    type: 'http',
    name: 'chord',
    url: 'http://127.0.0.1:1/mcp',
    headers: [],
  });
  const missing = chordRow(undefined);
  const child = chordRow(
    {
      type: 'http',
      name: 'chord',
      url: 'http://127.0.0.1:1/mcp',
      headers: [],
    },
    true,
  );

  expect(passed.server.from).toStrictEqual('chord itself');
  expect(chordLine(child, 'parser')).toStrictEqual(
    "chord's server gives parser list_agents, get_budgets, spawn_task, monitor, " +
      'stop_monitor and list_monitors, and send_message to main only.',
  );
  expect(chordLine(passed, 'claude')).toStrictEqual(
    "chord's server gives claude list_agents, get_budgets, list_sessions, list_teams, " +
      'spawn_task, open_agent, run_team, propose_team, send_message, close_agent, ' +
      'clear_agent, monitor, stop_monitor and list_monitors.',
  );
  expect(
    'url' in missing.server.server ? missing.server.server.url : '',
  ).toStrictEqual('not passed');
  expect(chordLine(missing, 'pi')).toStrictEqual(
    "chord's server was not passed: pi does not take MCP servers over HTTP, so it cannot start other agents.",
  );
});

test('a message that came in is ←, a failed report’s red and chord’s dim; one sent is →, dim until delivered and red when refused', () => {
  expect(inArrow({ ...FROM, note: 'report' })).toStrictEqual('plain');
  expect(inArrow(FROM)).toStrictEqual('plain');
  expect(inArrow({ name: 'main' })).toStrictEqual('plain');
  expect(inArrow({ ...FROM, note: 'failed' })).toStrictEqual('failed');
  expect(inArrow({ name: 'chord' })).toStrictEqual('dim');
  expect(outArrow('pending')).toStrictEqual('dim');
  expect(outArrow('running')).toStrictEqual('dim');
  expect(outArrow('done')).toStrictEqual('plain');
  expect(outArrow('failed')).toStrictEqual('failed');
});

test('a task whose record had gone when its parent was resumed ends with how long it ran, not a count of work it no longer has', () => {
  const ended = {
    ...TASK,
    state: 'completed' as const,
    startedAt: 0,
    endedAt: 41_000,
  };

  expect(blockFold(ended, [])).toStrictEqual({
    kind: 'ended',
    text: 'Done (0 tool uses · 41s)',
    failed: false,
  });

  const lost = { ...ended, task: { ...TASK.task, workLost: true } };

  expect(blockFold(lost, [])).toStrictEqual({
    kind: 'ended',
    text: 'Done (41s)',
    failed: false,
  });

  const { endedAt: _, ...unended } = lost;

  expect(blockFold({ ...unended, state: 'disconnected' }, [])).toStrictEqual({
    kind: 'ended',
    text: 'Disconnected',
    failed: true,
  });
});

test("run_team draws as Team(<run>) on the lead's runtime and model, the job under it", () => {
  const call = {
    tool: 'run_team' as const,
    input: { team: 'bugfix', job: 'Issue 214.\nReport when done.' },
    answer: {
      id: '7f3a9c2e',
      name: 'bugfix 2',
      team: 'bugfix',
      agent: 'claude',
      model: 'opus',
      mode: 'default',
    },
  };

  expect(chordHeadline(call)).toStrictEqual({
    name: 'Team',
    arg: 'bugfix 2',
    note: ' · claude · opus',
  });
  expect(chordLines(call)).toStrictEqual(['Issue 214.', 'Report when done.']);
  expect(
    chordHeadline({ tool: 'run_team', input: { team: 'bugfx', job: 'x' } }),
  ).toStrictEqual({ name: 'Team', arg: 'bugfx' });
});

test("a lead's open_agent draws the member on the file's runtime, model and mode", () => {
  expect(
    chordHeadline({
      tool: 'open_agent',
      input: { member: 'tester', prompt: 'Write the test.' },
      answer: {
        id: 'a1',
        name: 'tester',
        agent: 'claude',
        model: 'sonnet',
        mode: 'acceptEdits',
      },
    }),
  ).toStrictEqual({
    name: 'Open',
    arg: 'tester',
    note: ' · claude · sonnet · acceptEdits',
  });
});

test('list_teams draws as List teams with their names', () => {
  const call = {
    tool: 'list_teams' as const,
    input: {},
    answer: { teams: [{ name: 'bugfix' }, { name: 'review' }] },
  };

  expect(chordHeadline(call)).toStrictEqual({ name: 'List teams' });
  expect(chordLines(call)).toStrictEqual(['2 teams · bugfix, review']);
});

test('a team part draws as one line: whose instructions, for whom, and how long', () => {
  const part = { team: 'bugfix', member: 'tester', text: 'a\nb\nc' };

  expect(teamPartLine(part, false, 'ctrl+o')).toStrictEqual(
    "bugfix's instructions for tester · 3 lines (ctrl+o to expand)",
  );
  expect(
    teamPartLine({ team: 'bugfix', text: 'a' }, true, 'ctrl+o'),
  ).toStrictEqual("bugfix's instructions for the lead · 1 line");
});

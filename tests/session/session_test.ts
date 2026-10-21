import { execFile } from 'node:child_process';
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import process from 'node:process';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { FILLED } from '../../src/session/enrich.ts';
import type { PendingPermission } from '../../src/session/permissions.ts';
import { plainText } from '../../src/session/terminal_text.ts';
import {
  agentEnv,
  besideUsers,
  openSession,
  type Session,
  type Turn,
} from '../../src/session/session.ts';
import { readRecords, type Resume } from '../../src/session/sessions.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import { emptyTranscript } from '../../src/session/transcript/types.ts';
import { FAKE_COMMANDS } from '../fixtures/commands.ts';
import { EDIT_NEW, EDIT_OLD } from '../fixtures/edits.ts';
import { COMPACT_ERROR, COMPACT_SUMMARY } from '../fixtures/compactions.ts';
import { BASH_OUTPUT, SHELL_OUTPUT } from '../fixtures/terminals.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { recordSession } from '../fixtures/records.ts';
import { CRASH_WORDS } from '../fixtures/fake_agent/scenarios/agents.ts';
import { mentionsIn } from '../../src/ui/prompt/mentions.ts';
import { run, said } from '../fixtures/recorder.ts';

function isAlive(pid: number): Promise<boolean> {
  return new Promise((resolve) => {
    execFile('ps', ['-p', String(pid)], (error) => resolve(error === null));
  });
}

/**
 * Opens a session on the fake agent, hands it to `body`, then closes it and
 * proves the agent process is gone, whatever `body` did.
 */
async function withSession(
  body: (session: Session) => Promise<void>,
  scenario?: string,
  ...flags: string[]
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(scenario, ...flags),
  });
  const pids = [...session.agentPids];

  try {
    expect(pids.length).toStrictEqual(1);
    await body(session);
  } finally {
    await session.close();
    expect(session.agentPids.size).toStrictEqual(0);

    for (const pid of pids) {
      expect(!(await isAlive(pid)), `agent ${pid} still running`).toBeTruthy();
    }

    await rm(dir, { recursive: true });
  }
}

/** The updates a prompt brought until the agent answered it. */
async function collect(session: Session, text: string) {
  return (await run(session, text)).updates;
}

/** The tool calls and updates to them among `updates`. */
function calls(updates: readonly SessionUpdate[]) {
  return updates.flatMap((update) =>
    update.sessionUpdate === 'tool_call' ||
    update.sessionUpdate === 'tool_call_update'
      ? [update]
      : [],
  );
}

test('a plain reply streams in several chunks and completes', () =>
  withSession(async (session) => {
    const { updates, result } = await run(session, 'text');

    expect(said(updates)).toStrictEqual([
      'Hello',
      ', world',
      '. This reply',
      ' came in chunks.',
    ]);
    expect(result).toStrictEqual({
      status: 'completed',
      stopReason: 'end_turn',
      usage: {
        inputTokens: 1000,
        outputTokens: 200,
        cachedReadTokens: 800,
        totalTokens: 2000,
      },
    });
  }));

test('thought chunks arrive on their own stream before the reply', () =>
  withSession(async (session) => {
    const updates = await collect(session, 'thought');

    expect(said(updates, 'agent_thought_chunk')).toStrictEqual([
      'Considering',
      ' the question.',
    ]);
    expect(said(updates)).toStrictEqual(['Here is', ' the answer.']);

    const firstOutput = updates.findIndex(
      (e) => e.sessionUpdate === 'agent_message_chunk',
    );

    expect(
      updates
        .slice(firstOutput)
        .every((e) => e.sessionUpdate !== 'agent_thought_chunk'),
    ).toBeTruthy();
  }));

test('a tool call goes pending, in progress, completed under one id', () =>
  withSession(async (session) => {
    const tools = calls(await collect(session, 'tools'));

    expect(tools.map((c) => [c.toolCallId, c.status])).toStrictEqual([
      ['read-1', 'pending'],
      ['read-1', 'in_progress'],
      ['read-1', 'completed'],
    ]);
    expect(tools[0]?.title).toStrictEqual('Read README.md');
    expect(tools[0]?.kind).toStrictEqual('read');
    expect(tools[2]?.content).toStrictEqual([
      {
        type: 'content',
        content: { type: 'text', text: '# chord' },
      },
    ]);
  }));

test('an edit carries its diff', () =>
  withSession(async (session) => {
    const edits = calls(await collect(session, 'edit'));

    expect(edits[0]?.kind).toStrictEqual('edit');
    expect(edits.at(-1)?.content).toStrictEqual([
      {
        type: 'diff',
        path: 'src/greeting.ts',
        oldText: EDIT_OLD,
        newText: EDIT_NEW,
      },
    ]);
  }));

async function answerPermission(
  session: Session,
  answer: (request: PendingPermission) => void,
): Promise<{ events: SessionUpdate[]; request: PendingPermission }> {
  let request: PendingPermission | undefined;

  session.permissions.subscribe((pending) => {
    request = pending;

    expect(session.permissions.pending()).toStrictEqual([pending]);
    // The interface answers later, on a key press, never inside the callback.
    setTimeout(() => answer(pending), 10);
  });

  const events = await collect(session, 'permission');

  assert(request !== undefined);
  expect(session.permissions.pending()).toStrictEqual([]);

  return { events, request };
}

test('a permission request waits for the answer and gets the chosen option', () =>
  withSession(async (session) => {
    const { events, request } = await answerPermission(session, (r) =>
      r.resolve('always'),
    );

    expect(request.toolCall.toolCallId).toStrictEqual('write-1');
    expect(request.options.map((o) => o.optionId)).toStrictEqual([
      'allow',
      'always',
      'deny',
    ]);
    expect(said(events)).toStrictEqual(['Permission: always.']);
    expect(calls(events).at(-1)?.status).toStrictEqual('completed');
  }));

test('a rejected permission request reaches the agent as its reject option', () =>
  withSession(async (session) => {
    const { events } = await answerPermission(session, (r) => r.reject());

    expect(said(events)).toStrictEqual(['Permission: deny.']);
    expect(calls(events).at(-1)?.status).toStrictEqual('failed');
  }));

test('cancelling a turn withdraws its pending permission request', () =>
  withSession(async (session) => {
    const turn = session.prompt('permission');
    const request = await new Promise<PendingPermission>((resolve) =>
      session.permissions.subscribe(resolve),
    );

    await turn.cancel();
    expect(request.signal.aborted).toBeTruthy();
    expect(session.permissions.pending()).toStrictEqual([]);
    expect((await turn.result).status).toStrictEqual('cancelled');
  }));

test('a plan update carries its entries', () =>
  withSession(async (session) => {
    const plan = (await collect(session, 'plan')).find(
      (e) => e.sessionUpdate === 'plan',
    );

    assert(plan?.sessionUpdate === 'plan');
    expect(plan.entries).toStrictEqual([
      { content: 'Read the code', status: 'completed', priority: 'high' },
      {
        content: 'Write the change',
        status: 'in_progress',
        priority: 'medium',
      },
      { content: 'Run the tests', status: 'pending', priority: 'low' },
    ]);
  }));

// Codex's adapter sends its plan by id only to a client that declares
// `clientCapabilities.plan`, and to any other as reply text.
test('an agent that sends plans by id only on request sends chord one', () =>
  withSession(
    async (session) => {
      const updates = await collect(session, 'plan');
      const plan = updates.find((e) => e.sessionUpdate === 'plan_update');

      expect(said(updates)).toStrictEqual([
        'Planned.',
        ' Step 2 done.',
        ' Step 3 done.',
      ]);
      assert(plan?.sessionUpdate === 'plan_update');
      assert(plan.plan.type === 'items');
      expect(plan.plan.entries.map((e) => e.status)).toStrictEqual([
        'completed',
        'in_progress',
        'pending',
      ]);
    },
    undefined,
    '--plan-capability-only',
  ));

/**
 * A session on the fake at a short pace: `proposal`'s 2 s between plan
 * updates are for a person watching `bun dev chord --fake`, and what it sends, in what
 * order, is the same at any pace.
 */
function withProposal(body: (session: Session) => Promise<void>) {
  return withSession(body, undefined, '--step-ms', '1');
}

// Codex's plan mode proposes its plan as markdown, the whole text each time,
// and may withdraw it by id.
test('a proposed plan rewritten and withdrawn leaves the rest of the reply', () =>
  withProposal(async (session) => {
    const updates = await collect(session, 'proposal');
    const transcript = updates.reduce(
      (state, update) =>
        reduceTranscript(state, { type: 'update', turnId: 't1', update }),
      reduceTranscript(emptyTranscript, {
        type: 'prompt',
        turnId: 't1',
        text: 'proposal',
        at: 0,
      }),
    );

    expect(
      updates.flatMap((e) =>
        e.sessionUpdate === 'plan_update' && e.plan.type === 'markdown'
          ? [e.plan.content]
          : [],
      ),
    ).toStrictEqual([
      '1. Read the code',
      '1. Inspect the code',
      '1. Inspect the code\n2. Write the change',
    ]);
    expect(
      transcript.entries.flatMap((e) =>
        e.kind === 'assistant' ? [e.text] : [],
      ),
    ).toStrictEqual([
      "I'll look first.",
      'file:///plans/proposal.md',
      'Plan written. Draft dropped.',
    ]);
  }));

// Each run proposes its own plans, so a second run keeps the first run's.
test('a second proposal in one session leaves the first one in place', () =>
  withProposal(async (session) => {
    let transcript = emptyTranscript;

    for (const turnId of ['t1', 't2']) {
      const updates = await collect(session, 'proposal');

      transcript = updates.reduce(
        (state, update) =>
          reduceTranscript(state, { type: 'update', turnId, update }),
        reduceTranscript(transcript, {
          type: 'prompt',
          turnId,
          text: 'proposal',
          at: 0,
        }),
      );
    }

    const run = [
      "I'll look first.",
      'file:///plans/proposal.md',
      'Plan written. Draft dropped.',
    ];

    expect(
      transcript.entries.flatMap((e) =>
        e.kind === 'assistant' ? [e.text] : [],
      ),
    ).toStrictEqual([...run, ...run]);
  }));

/** The transcript after each of `updates`, folded as one turn's. */
function foldedEach(text: string, updates: readonly SessionUpdate[]) {
  let state = reduceTranscript(emptyTranscript, {
    type: 'prompt',
    turnId: 't1',
    text,
    at: 0,
  });

  return updates.map(
    (update) =>
      (state = reduceTranscript(state, {
        type: 'update',
        turnId: 't1',
        update,
      })),
  );
}

/** The terminals of the one tool call in a transcript's `entries`. */
function terminalsIn({ entries }: ReturnType<typeof reduceTranscript>) {
  return entries.flatMap((entry) =>
    entry.kind === 'tool' ? (entry.call.terminals ?? []) : [],
  );
}

// Codex's adapter streams a command's output to any client as it comes.
test("a command's output streams into its terminal as Codex's adapter sends it, and its failing exit ends it", () =>
  withSession(async (session) => {
    const started = Date.now();
    const arrived: number[] = [];
    const { updates } = await run(session, 'shell', {
      onUpdate: () => arrived.push(Date.now() - started),
    });
    const states = foldedEach('shell', updates);
    const outputs = states.flatMap((state) => {
      const [terminal] = terminalsIn(state);

      return terminal && !terminal.exited ? [terminal.output] : [];
    });

    const [terminal] = terminalsIn(states.at(-1)!);

    // Each piece was there before the command ended, and they came apart.
    expect([...new Set(outputs)]).toStrictEqual(
      SHELL_OUTPUT.slice(0, -1)
        .map((_, index) => plainText(SHELL_OUTPUT.slice(0, index).join('')))
        .concat(plainText(SHELL_OUTPUT.slice(0, -1).join(''))),
    );
    expect(
      arrived.at(-1)! - arrived[0]! >= 1500,
      `took ${arrived.at(-1)}`,
    ).toBeTruthy();
    assert(terminal !== undefined);
    expect(terminal.output).toStrictEqual(plainText(SHELL_OUTPUT.join('')));
    expect(terminal.exited).toStrictEqual(true);
    expect(terminal.exitCode).toStrictEqual(1);
    // The session's own directory, which the command ran in.
    expect(terminal.cwd?.includes('chord-session-')).toBeTruthy();
    expect(
      states.at(-1)!.entries.find((entry) => entry.kind === 'tool'),
    ).toStrictEqual({
      kind: 'tool',
      turnId: 't1',
      call: {
        id: calls(updates)[0]!.toolCallId,
        title: 'Run deno task test',
        kind: 'execute',
        status: 'failed',
        content: [{ type: 'terminal', terminalId: terminal.id }],
        rawInput: { command: ['deno', 'task', 'test'] },
        terminals: [terminal],
      },
    });
  }));

// Claude's adapter sends a command's output as terminal meta only to a client
// that asks for it, which chord does, and then only once it is done.
test("a command's output comes whole at its end as Claude's adapter sends it to chord", () =>
  withSession(async (session) => {
    const updates = await collect(session, 'bash');
    const states = foldedEach('bash', updates);
    const before = states.slice(0, -1).flatMap(terminalsIn);

    expect(before.length > 0, 'the terminal is named up front').toBeTruthy();
    expect(
      before
        .filter((terminal) => terminal.output !== '')
        .every((terminal) => terminal.output === BASH_OUTPUT),
    ).toBeTruthy();
    expect(
      calls(updates).filter(
        (update) => update._meta?.terminal_output_delta !== undefined,
      ).length,
    ).toStrictEqual(1);
    expect(terminalsIn(states.at(-1)!)).toStrictEqual([
      {
        id: calls(updates)[0]!.toolCallId,
        output: BASH_OUTPUT,
        exited: true,
        exitCode: 0,
      },
    ]);
  }));

/** Each call's status and text as the last of its updates left them. */
function endsOf(updates: readonly SessionUpdate[]) {
  return calls(updates)
    .filter((update) => update.status === 'failed')
    .map((update) => ({
      status: update.status,
      text: update.content?.flatMap((block) =>
        block.type === 'content' && block.content.type === 'text'
          ? [block.content.text]
          : [],
      ),
      exit: update._meta?.terminal_exit,
    }));
}

// Claude's adapter ends a call the turn leaves without a result `failed`,
// with a line saying why, and a command's terminal with no exit code.
test("a cancel ends a running command and a call that never ran failed, as Claude's adapter sends them", () =>
  withSession(async (session) => {
    const { updates, result } = await run(session, 'bashcut', {
      onUpdate: (updates, turn) => {
        if (calls(updates).length === 3) {
          void turn.cancel();
        }
      },
    });
    const command = calls(updates)[0]!.toolCallId;

    expect(result.status).toStrictEqual('cancelled');
    expect(endsOf(updates)).toStrictEqual([
      {
        status: 'failed',
        text: [
          'The turn was cancelled before this tool call returned a result.',
        ],
        exit: { terminal_id: command, exit_code: null, signal: null },
      },
      {
        status: 'failed',
        text: ['Claude stopped this tool call before it ran.'],
        exit: undefined,
      },
    ]);
  }));

test("a turn that ends on its own leaves its command failed with Claude's line for no result", () =>
  withSession(
    async (session) => {
      const { updates, result } = await run(session, 'bashcut');

      expect(result.status).toStrictEqual('completed');
      expect(endsOf(updates).map(({ text }) => text)).toStrictEqual([
        ['Claude ended the turn without returning a result for this tool.'],
        ['Claude stopped this tool call before it ran.'],
      ]);
    },
    undefined,
    '--step-ms',
    '1',
  ));

/** The compactions in a transcript's `entries`. */
function compactionsIn({ entries }: ReturnType<typeof reduceTranscript>) {
  return entries.flatMap((entry) =>
    entry.kind === 'compaction' ? [entry.compaction] : [],
  );
}

// Both adapters send compactions by id only to a client that declares
// `session.compaction`, which chord does.
test("a compaction runs, its summary streaming in, and completes as Claude's adapter sends it to chord", () =>
  withSession(async (session) => {
    const started = Date.now();
    const arrived: number[] = [];
    const { updates } = await run(session, 'compact', {
      onUpdate: () => arrived.push(Date.now() - started),
    });
    const states = foldedEach('compact', updates);
    const summaries = states.flatMap((state) =>
      compactionsIn(state)
        .filter((compaction) => compaction.status === 'in_progress')
        .map((compaction) => compaction.summary),
    );

    expect(calls(updates)).toStrictEqual([]);
    expect([...new Set(summaries)]).toStrictEqual(
      COMPACT_SUMMARY.map((_, index) =>
        COMPACT_SUMMARY.slice(0, index).join(''),
      ).concat(COMPACT_SUMMARY.join('')),
    );
    expect(
      arrived.at(-1)! - arrived[0]! >= 1500,
      `took ${arrived.at(-1)}`,
    ).toBeTruthy();
    expect(compactionsIn(states.at(-1)!)).toStrictEqual([
      {
        id:
          updates.find((update) => update.sessionUpdate === 'compaction_update')
            ?.compactionId ?? 'none',
        status: 'completed',
        summary: COMPACT_SUMMARY.join(''),
      },
    ]);
  }));

test("a compaction completes with no summary as Codex's adapter sends it", () =>
  withSession(async (session) => {
    const updates = await collect(session, 'codexcompact');

    expect(
      compactionsIn(foldedEach('codexcompact', updates).at(-1)!).map(
        ({ status, summary }) => ({ status, summary }),
      ),
    ).toStrictEqual([{ status: 'completed', summary: '' }]);
  }));

test('a compaction that fails says why', () =>
  withSession(async (session) => {
    const updates = await collect(session, 'compactfail');

    expect(
      compactionsIn(foldedEach('compactfail', updates).at(-1)!).map(
        ({ status, error }) => ({ status, error }),
      ),
    ).toStrictEqual([{ status: 'failed', error: COMPACT_ERROR }]);
  }));

test('a compaction its turn was cancelled under is cancelled', () =>
  withSession(async (session) => {
    const { updates } = await run(session, 'compact', {
      onUpdate: (updates, turn) => {
        if (updates.length === 2) {
          void turn.cancel();
        }
      },
    });

    expect(
      compactionsIn(foldedEach('compact', updates).at(-1)!)[0]?.status,
    ).toStrictEqual('cancelled');
  }));

test('the agent starts with the task list tools turned on', () =>
  withSession(async (session) => {
    const own = process.env.CLAUDE_CODE_ENABLE_TODO_TOOLS ?? '1';

    expect(said(await collect(session, 'todos'))).toStrictEqual([
      `todo tools: ${own}`,
    ]);
  }));

test('the task list tools stay off when the person turned them off', () => {
  expect(agentEnv({ CLAUDE_CODE_ENABLE_TODO_TOOLS: '0' })).toStrictEqual({});
  expect(agentEnv({})).toStrictEqual({ CLAUDE_CODE_ENABLE_TODO_TOOLS: '1' });
});

test('usage and mode updates come through as the agent sent them', () =>
  withSession(async (session) => {
    const { updates, result } = await run(session, 'status');
    const mode = updates.find((e) => e.sessionUpdate === 'current_mode_update');
    const usage = updates.find((e) => e.sessionUpdate === 'usage_update');

    expect(mode?.currentModeId).toStrictEqual('plan');
    expect([usage?.used, usage?.size]).toStrictEqual([1200, 200000]);
    expect(usage?.cost).toStrictEqual({ amount: 0.01, currency: 'USD' });
    assert(result.status === 'completed');
    expect(result.usage).not.toBeNil();
    // The mode the agent moved to by the update alone is the one it is in.
    expect(session.modes()?.current).toStrictEqual('plan');
  }));

test("each turn's answer carries its tokens, and usage_update the session's cost", () =>
  withSession(async (session) => {
    const turn = {
      inputTokens: 1000,
      outputTokens: 200,
      cachedReadTokens: 800,
      totalTokens: 2000,
    };
    const costs: unknown[] = [];

    for (const prompt of ['text', 'tools']) {
      const { updates, result } = await run(session, prompt);

      assert(result.status === 'completed');
      expect(result.usage).toStrictEqual(turn);
      costs.push(
        ...updates.flatMap((e) =>
          e.sessionUpdate === 'usage_update' ? [e.cost] : [],
        ),
      );
    }

    expect(costs).toStrictEqual([
      { amount: 0.0125, currency: 'USD' },
      { amount: 0.025, currency: 'USD' },
    ]);
  }));

const FAKE_MODES = [
  { id: 'default', name: 'Default' },
  { id: 'acceptEdits', name: 'Accept edits' },
  { id: 'plan', name: 'Plan' },
];

test("the agent's modes come in its order, with the one it starts in", () =>
  withSession(async (session) => {
    expect(await session.modes()).toStrictEqual({
      available: FAKE_MODES,
      current: 'default',
    });
  }));

test('the commands the agent advertises after the session starts are read', () =>
  withSession(async (session) => {
    const deadline = Date.now() + 5_000;
    let commands = await session.commands();

    // The agent sends them after its reply to session/new, as Claude's does.
    while (commands.length === 0 && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 20));

      commands = await session.commands();
    }

    expect(commands).toStrictEqual(FAKE_COMMANDS);
  }));

test("an agent's command goes to it as a prompt", () =>
  withSession(async (session) => {
    expect(said(await collect(session, '/greet'))).toStrictEqual([
      'Hello',
      ' from the fake agent.',
    ]);
    expect(said(await collect(session, '/echo two words'))).toStrictEqual([
      'two words',
    ]);
  }));

test('a mode change reaches the agent, and its answer is read back', () =>
  withSession(async (session) => {
    for (const mode of ['acceptEdits', 'plan', 'default']) {
      await session.setMode(mode);
      expect((await session.modes())?.current).toStrictEqual(mode);
    }
  }));

test('a mode the agent does not offer is refused, and nothing moves', () =>
  withSession(async (session) => {
    await expect(session.setMode('yolo')).rejects.toThrow();
    expect((await session.modes())?.current).toStrictEqual('default');
  }));

test("a mode change is read back before a prompt from an agent that answers it with nothing, as Codex's does", () =>
  withSession(
    async (session) => {
      for (const mode of ['plan', 'acceptEdits', 'default']) {
        await session.setMode(mode);
        expect((await session.modes())?.current).toStrictEqual(mode);
      }
    },
    undefined,
    '--silent-set-mode',
  ));

test('a mode change the agent refuses leaves the mode it holds', () =>
  withSession(
    async (session) => {
      await session.setMode('plan');
      await collect(session, 'lock');

      const refused = session.setMode('acceptEdits');

      await expect(refused).rejects.toThrow(Error);
      await expect(refused).rejects.toThrow('holds its mode');
      expect((await session.modes())?.current).toStrictEqual('plan');
    },
    undefined,
    '--silent-set-mode',
  ));

test('an agent that offers no mode config option is asked through set_mode', () =>
  withSession(
    async (session) => {
      expect(await session.modes()).toStrictEqual(undefined);

      // The fake refuses set_mode then, as an agent without modes would; its
      // words show that the older call is the one that reached it.
      const refused = session.setMode('plan');

      await expect(refused).rejects.toThrow(Error);
      await expect(refused).rejects.toThrow('session/set_mode');
    },
    undefined,
    '--no-modes',
  ));

test('a mode the agent leaves by itself is read back after the turn', () =>
  withSession(async (session) => {
    await session.setMode('plan');
    await collect(session, 'exitplan');
    expect((await session.modes())?.current).toStrictEqual('default');
  }));

const FAKE_MODELS = [
  { id: 'fake-large', name: 'Fake Large with a 1M context window' },
  { id: 'fake-small', name: 'Fake Small' },
];

test("the agent's models come in its order, with the one it uses", () =>
  withSession(async (session) => {
    expect(await session.models()).toStrictEqual({
      available: FAKE_MODELS,
      current: 'fake-large',
    });
  }));

test('a model change reaches the agent, and its answer is read back', () =>
  withSession(async (session) => {
    await session.setModel('fake-small');
    expect((await session.models())?.current).toStrictEqual('fake-small');

    // A turn after it leaves the model where it was put.
    await collect(session, 'text');
    expect((await session.models())?.current).toStrictEqual('fake-small');
  }));

test('a model the agent does not offer is refused, and nothing moves', () =>
  withSession(async (session) => {
    await expect(session.setModel('fake-huge')).rejects.toThrow();
    expect((await session.models())?.current).toStrictEqual('fake-large');
  }));

const EFFORT = {
  id: 'effort',
  name: 'Effort',
  values: [
    { value: 'low', name: 'Low' },
    { value: 'medium', name: 'Medium' },
    { value: 'high', name: 'High' },
  ],
  current: 'medium',
};

test("the agent's other config options come without its mode and model", () =>
  withSession(async (session) => {
    expect(await session.options()).toStrictEqual([EFFORT]);
  }));

test('a config option change reaches the agent, and its answer is read back', () =>
  withSession(async (session) => {
    await session.setOption('effort', 'high');
    expect(await session.options()).toStrictEqual([
      { ...EFFORT, current: 'high' },
    ]);

    // A turn after it leaves the option where it was put.
    await collect(session, 'text');
    expect((await session.options())[0]?.current).toStrictEqual('high');
  }));

test('a config option change the agent refuses moves nothing', () =>
  withSession(
    async (session) => {
      const refused = session.setOption('effort', 'high');

      await expect(refused).rejects.toThrow(Error);
      await expect(refused).rejects.toThrow('The fake agent holds its effort.');
      expect(await session.options()).toStrictEqual([EFFORT]);
    },
    undefined,
    '--refuse-config',
  ));

test('an agent with no other config options offers none', () =>
  withSession(
    async (session) => {
      expect(await session.options()).toStrictEqual([]);
      expect((await session.models())?.current).toStrictEqual('fake-large');
    },
    undefined,
    '--no-config',
  ));

/** What the fake said it received as links, for a prompt typed as `text`. */
async function linksSent(session: Session, text: string) {
  const { updates } = await run(session, text, { mentions: mentionsIn(text) });

  return said(updates).filter((line) => line.startsWith('Received a link'));
}

test("a prompt's mentions of files go after its text as resource links, once each", () =>
  withSession(async (session) => {
    const { cwd } = session;
    const uri = (path: string) => pathToFileURL(join(cwd, path)).href;

    await mkdir(join(cwd, 'src'));
    await writeFile(join(cwd, 'src/a.ts'), '');
    await writeFile(join(cwd, 'my notes.md'), '');

    expect(
      await linksSent(session, 'see @src/a.ts and @"my notes.md", @src/a.ts'),
    ).toStrictEqual([
      `Received a link: src/a.ts, ${uri('src/a.ts')}\n\n`,
      `Received a link: my notes.md, ${uri('my notes.md')}\n\n`,
    ]);
    expect(await linksSent(session, 'text')).toStrictEqual([]);
  }));

test('a mention of what is not a file @ offers sends no link', () =>
  withSession(async (session) => {
    const { cwd } = session;

    await mkdir(join(cwd, 'src'));
    await mkdir(join(cwd, 'dist'));
    await writeFile(join(cwd, 'dist/out.js'), '');
    await writeFile(join(cwd, '.gitignore'), 'dist/\n');

    expect(
      await linksSent(
        session,
        'see @src @missing.ts @../outside.ts @dist/out.js',
      ),
    ).toStrictEqual([]);
  }));

test('a turn says which links went with its prompt, and none went when a cancel came before the walk ended', () =>
  withSession(async (session) => {
    const { cwd } = session;

    await writeFile(join(cwd, 'a.ts'), '');

    const { turn } = await run(session, 'see @a.ts', { mentions: ['a.ts'] });

    expect(await turn.sent).toStrictEqual([
      {
        type: 'resource_link',
        name: 'a.ts',
        uri: pathToFileURL(join(cwd, 'a.ts')).href,
      },
    ]);

    const held = session.prompt('see @a.ts', [], ['a.ts']);

    await held.cancel();

    expect(await held.sent).toStrictEqual(undefined);
    expect((await held.result).status).toStrictEqual('cancelled');
    expect(await linksSent(session, 'text')).toStrictEqual([]);
  }));

// The agent may take the next prompt before a cancel sent ahead of it, so a
// cancel for a prompt it never got could stop the next turn (Q42).
test('a cancel before the walk ended tells the agent nothing, so it cannot land on the next turn', () =>
  withSession(async (session) => {
    await writeFile(join(session.cwd, 'a.ts'), '');

    const held = session.prompt('see @a.ts', [], ['a.ts']);

    await held.cancel();
    expect((await held.result).status).toStrictEqual('cancelled');

    const { updates, result } = await run(session, 'cancels');

    expect(result.status).toStrictEqual('completed');
    expect(said(updates).join('')).toStrictEqual('Cancels with no turn: 0.');
  }));

test('a failed turn says why, and the session takes the next prompt', () =>
  withSession(async (session) => {
    const { updates, result } = await run(session, 'error');

    expect(said(updates)).toStrictEqual(['About to fail.']);
    assert(result.status === 'failed');
    expect(result.error.message).toStrictEqual(
      'The fake agent failed on purpose.',
    );
    expect((await run(session, 'text')).result.status).toStrictEqual(
      'completed',
    );
    // The agent is still up: the failure is the turn's, not an exit.
    expect(session.gone()).toStrictEqual(undefined);
  }));

test('an agent that exits mid-turn fails the turn, and its last words are what it left on stderr', () =>
  withSession(async (session) => {
    expect(session.gone()).toStrictEqual(undefined);

    const { result } = await run(session, 'crash');

    expect(result.status === 'failed').toBeTruthy();
    expect(session.gone()).toStrictEqual(CRASH_WORDS);
    await session.exited;
  }));

async function cancelSlowTurn(
  session: Session,
  cancel: (turn: Turn) => Promise<void>,
) {
  const { updates, result } = await run(session, 'slow', {
    onUpdate: (so, turn) => {
      if (so.length === 3) {
        void cancel(turn);
      }
    },
  });

  expect(result.status).toStrictEqual('cancelled');
  // The fake turn is a thousand chunks long; stopping early is the agent
  // honouring cancel.
  expect(
    updates.length < 100,
    `${updates.length} updates after cancel`,
  ).toBeTruthy();
}

test('a slow turn stops when the turn is cancelled', () =>
  withSession((session) => cancelSlowTurn(session, (turn) => turn.cancel())));

test('a slow turn stops when the session cancels its active turn', () =>
  withSession((session) => cancelSlowTurn(session, () => session.cancel())));

test('closing mid-turn ends the turn and the agent', () =>
  withSession(async (session) => {
    const first = Promise.withResolvers<void>();
    const unsubscribe = session.subscribe(() => first.resolve());
    const turn = session.prompt('slow');

    await first.promise;
    unsubscribe();
    await session.close();
    expect((await turn.result).status !== 'completed').toBeTruthy();
  }));

test("the scenario can come from the agent's command line", () =>
  withSession(async (session) => {
    expect(said(await collect(session, 'anything'))).toStrictEqual([
      'Here is',
      ' the answer.',
    ]);
  }, 'thought'));

test('an agent that cannot start fails the open and leaves nothing running', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));

  await expect(
    openSession({
      agent: 'missing',
      cwd: dir,
      agentCommand: [join(dir, 'no-such-agent')],
    }),
  ).rejects.toThrow();
  await rm(dir, { recursive: true });
});

test('an agent command given as one string is split the way a shell would', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand()
      .map((arg) => `'${arg}'`)
      .join(' '),
  });

  try {
    expect(said(await collect(session, 'text')).length).toStrictEqual(4);
  } finally {
    await session.close();
    await rm(dir, { recursive: true });
  }
});

/** The pids of every process whose command line holds `tag`. */
function tagged(tag: string): Promise<number[]> {
  // pgrep exits 1 when nothing matches, which is an answer too.
  return new Promise((resolve) => {
    execFile('pgrep', ['-f', tag], (_error, stdout) =>
      resolve(stdout.split('\n').filter(Boolean).map(Number)),
    );
  });
}

/**
 * Opens a session on a fake agent that wedges at `step`, plays `body` into it,
 * and proves the close comes back within the bound with the agent gone.
 */
async function quitsWedged(step: string, body: (session: Session) => void) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(undefined, '--hang', step),
  });
  const pids = [...session.agentPids];

  try {
    body(session);
    // Long enough for the request to be out to the agent.
    await new Promise((resolve) => setTimeout(resolve, 200));

    const started = Date.now();

    await session.close();
    expect(
      Date.now() - started < 10_000,
      'the close was not bounded',
    ).toBeTruthy();
    expect(session.agentPids.size).toStrictEqual(0);

    for (const pid of pids) {
      expect(!(await isAlive(pid)), `agent ${pid} still running`).toBeTruthy();
    }
  } finally {
    await rm(dir, { recursive: true });
  }
}

test('closing comes back and kills an agent that never answers a config change', () =>
  quitsWedged('config', (session) => {
    session.setOption('effort', 'high').catch(() => {});
  }));

test('closing comes back and kills an agent whose turn ignores its cancel', () =>
  quitsWedged('turn', (session) => {
    const turn = session.prompt('text');

    turn.result.catch(() => {});

    session.cancel().catch(() => {});
  }));

test('an open given up while the agent never answers its start leaves nothing running', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));
  const tag = `chord-wedged-${crypto.randomUUID()}`;
  const stop = new AbortController();
  const opening = openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(undefined, '--hang', 'start', tag),
    signal: stop.signal,
  });

  try {
    while ((await tagged(tag)).length === 0) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }

    const started = Date.now();

    stop.abort(new Error('given up'));
    await expect(opening).rejects.toThrow(Error);
    await expect(opening).rejects.toThrow('given up');
    expect(
      Date.now() - started < 10_000,
      'the open did not give up in time',
    ).toBeTruthy();
    expect(await tagged(tag)).toStrictEqual([]);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("an agent that reports tokens alone gets a cost and a window, marked as chord's", () =>
  withSession(
    async (session) => {
      const { updates, result } = await run(session, 'text');
      const usage = updates.filter(
        (update) => update.sessionUpdate === 'usage_update',
      );

      expect(result.status === 'completed' && result.usage).toStrictEqual({
        inputTokens: 1000,
        outputTokens: 200,
        cachedReadTokens: 800,
        totalTokens: 2000,
      });
      expect(usage.length).toStrictEqual(1);
      expect(
        usage[0]?.sessionUpdate === 'usage_update' && {
          used: usage[0].used,
          size: usage[0].size,
          currency: usage[0].cost?.currency,
          filled: usage[0]._meta?.[FILLED],
        },
      ).toStrictEqual({
        used: 2000,
        size: 400_000,
        currency: 'USD',
        filled: ['used', 'cost', 'size'],
      });
    },
    undefined,
    '--tokens-only',
  ));

/** chord's own server as a session would get it, at a URL nothing serves. */
const CHORD_SERVER = {
  type: 'http' as const,
  name: 'chord',
  url: 'http://127.0.0.1:9/mcp',
  headers: [{ name: 'Authorization', value: 'Bearer token' }],
};

/** The MCP servers the fake agent says its session was opened with. */
async function serversGiven(...flags: string[]): Promise<unknown> {
  const dir = await mkdtemp(join(tmpdir(), 'chord-session-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(undefined, ...flags),
    mcpServers: [{ name: 'docs', command: 'docs-server', args: [], env: [] }],
    chordServer: CHORD_SERVER,
  });

  try {
    const reply = said((await run(session, 'mcp')).updates).join('');

    return JSON.parse(reply.replace(/^```json\n|\n```$/g, ''));
  } finally {
    await session.close();
    await rm(dir, { recursive: true });
  }
}

test("chord's server goes after the user's to an agent that takes HTTP", async () => {
  expect(await serversGiven()).toStrictEqual([
    { name: 'docs', command: 'docs-server', args: [], env: [] },
    CHORD_SERVER,
  ]);
});

test("an agent that does not take HTTP gets the user's servers alone", async () => {
  expect(await serversGiven('--no-http')).toStrictEqual([
    { name: 'docs', command: 'docs-server', args: [], env: [] },
  ]);
});

test("chord's server takes the first free name when the user's has chord's", () => {
  const user = (name: string) => ({ ...CHORD_SERVER, name, url: 'u' });

  expect(besideUsers([user('docs')], CHORD_SERVER)).toStrictEqual([
    user('docs'),
    CHORD_SERVER,
  ]);
  expect(
    besideUsers([user('chord'), user('chord-2')], CHORD_SERVER),
  ).toStrictEqual([
    user('chord'),
    user('chord-2'),
    { ...CHORD_SERVER, name: 'chord-3' },
  ]);
});

/** Claude's adapter's prompt suggestions off, as chord opens its sessions. */
const NO_SUGGESTIONS = {
  claudeCode: { options: { promptSuggestions: false } },
};

/**
 * The request that opened a session in `dir`, and its `_meta`, as the fake
 * agent says them; opened again from `resume` when there is one.
 */
async function openedBy(
  dir: string,
  flags: readonly string[],
  resume?: Resume,
): Promise<unknown> {
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(undefined, ...flags),
    ...(resume === undefined ? {} : { resume }),
  });

  try {
    const reply = said((await run(session, 'opened')).updates).join('');

    return JSON.parse(reply.replace(/^```json\n|\n```$/g, ''));
  } finally {
    await session.close();
  }
}

describe("Claude's prompt suggestions are off in every session chord opens (CHD-439)", () => {
  const inDir = async (body: (dir: string) => Promise<void>) => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-opened-'));

    try {
      await body(dir);
    } finally {
      await rm(dir, { recursive: true });
    }
  };

  test('a new Claude session asks for none, and a Codex or other one is sent no _meta', () =>
    inDir(async (dir) => {
      expect(await openedBy(dir, ['--adapter', 'claude'])).toStrictEqual({
        method: 'session/new',
        meta: NO_SUGGESTIONS,
      });
      expect(await openedBy(dir, ['--steering', 'codex'])).toStrictEqual({
        method: 'session/new',
      });
      expect(await openedBy(dir, [])).toStrictEqual({
        method: 'session/new',
      });
    }));

  test('a Claude session loaded again asks for none, and a Codex one is sent no _meta', () =>
    inDir(async (dir) => {
      const resume = { sessionId: crypto.randomUUID(), cwd: dir };

      expect(
        await openedBy(dir, ['--adapter', 'claude'], resume),
      ).toStrictEqual({ method: 'session/load', meta: NO_SUGGESTIONS });
      expect(
        await openedBy(dir, ['--steering', 'codex'], resume),
      ).toStrictEqual({ method: 'session/load' });
    }));

  test('a Claude session resumed from its record asks for none, and a Codex one is sent no _meta', () =>
    inDir(async (dir) => {
      const stateDir = join(dir, 'state');

      for (const flags of [
        ['--adapter', 'claude'],
        ['--steering', 'codex'],
      ]) {
        await rm(stateDir, { recursive: true, force: true });

        const sessionId = await recordSession({
          stateDir,
          cwd: dir,
          command: fakeAgentCommand(undefined, ...flags),
          prompts: ['text'],
        });
        const [record] = await readRecords(stateDir);

        assert(record !== undefined);
        expect(
          await openedBy(dir, [...flags, '--resume-only'], {
            sessionId,
            cwd: dir,
            record: record.path,
          }),
        ).toStrictEqual(
          flags[0] === '--adapter'
            ? { method: 'session/resume', meta: NO_SUGGESTIONS }
            : { method: 'session/resume' },
        );
      }
    }));
});

describe('CHD-439 tester: adapter identity across session openings', () => {
  const inDir = async (body: (dir: string) => Promise<void>) => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-opening-meta-'));

    try {
      await body(dir);
    } finally {
      await rm(dir, { recursive: true });
    }
  };

  test('simultaneous Claude and other sessions keep their opening metadata separate', () =>
    inDir(async (dir) => {
      const resume = { sessionId: crypto.randomUUID(), cwd: dir };
      const results = await Promise.allSettled([
        openedBy(dir, ['--adapter', 'claude']),
        openedBy(dir, ['--steering', 'codex']),
        openedBy(dir, ['--adapter', 'claude'], resume),
        openedBy(dir, [], resume),
      ]);

      expect(results).toStrictEqual([
        {
          status: 'fulfilled',
          value: { method: 'session/new', meta: NO_SUGGESTIONS },
        },
        { status: 'fulfilled', value: { method: 'session/new' } },
        {
          status: 'fulfilled',
          value: { method: 'session/load', meta: NO_SUGGESTIONS },
        },
        { status: 'fulfilled', value: { method: 'session/load' } },
      ]);
    }));

  for (const { name, previous, next, expected } of [
    {
      name: 'recorded Claude history still gets the option through load when resume is unavailable',
      previous: ['--adapter', 'claude'],
      next: ['--adapter', 'claude'],
      expected: { method: 'session/load', meta: NO_SUGGESTIONS },
    },
    {
      name: 'a different current adapter gets no Claude options from recorded history',
      previous: ['--adapter', 'claude'],
      next: ['--steering', 'codex', '--resume-only'],
      expected: { method: 'session/resume' },
    },
    {
      name: 'a current Claude adapter gets the option when the recorded agent was different',
      previous: [],
      next: ['--adapter', 'claude', '--resume-only'],
      expected: { method: 'session/resume', meta: NO_SUGGESTIONS },
    },
  ]) {
    test(name, () =>
      inDir(async (dir) => {
        const stateDir = join(dir, 'state');
        const sessionId = await recordSession({
          stateDir,
          cwd: dir,
          command: fakeAgentCommand(undefined, ...previous),
          prompts: ['text'],
        });
        const [record] = await readRecords(stateDir);

        assert(record !== undefined);
        expect(
          await openedBy(dir, next, {
            sessionId,
            cwd: dir,
            record: record.path,
          }),
        ).toStrictEqual(expected);
      }),
    );
  }
});

describe('CHD-246 tester: large MCP permission fixture', () => {
  test.each(['allow', 'always', 'deny', 'cancel'])(
    'preserves the complete request when the answer is %s',
    (answer) =>
      withSession(async (session) => {
        let request: PendingPermission | undefined;
        const unsubscribe = session.permissions.subscribe((pending) => {
          request = pending;

          setTimeout(() => {
            if (answer === 'cancel') {
              void session.cancel();
            } else {
              pending.resolve(answer);
            }
          }, 10);
        });

        try {
          const { updates, result } = await run(session, 'bigask');

          assert(request);
          expect(request.toolCall.title).toBe('mcp__files__write_file');
          expect(request.toolCall.toolCallId).toBe('write_file-1');
          expect(request.toolCall.content).toBeUndefined();

          const input = request.toolCall.rawInput as {
            path: string;
            content: string;
            mode: string;
          };

          expect(input.path).toBe('docs/release.md');
          expect(input.mode).toBe('overwrite');
          expect(input.content.split('\n')).toHaveLength(37);
          expect(input.content).toStartWith('# Release 0.56.0\n\n');
          expect(input.content.split('\n')[2]?.length).toBeGreaterThan(200);
          expect(input.content).toEndWith(
            '- Change 30: tests run in parallel\n',
          );
          expect(request.options.map((option) => option.optionId)).toEqual([
            'allow',
            'always',
            'deny',
          ]);
          expect(request.options[1]?.name).toContain('files - write_file');
          expect(session.permissions.pending()).toEqual([]);

          if (answer === 'cancel') {
            expect(result.status).toBe('cancelled');
            expect(request.signal.aborted).toBe(true);
            expect(said(updates)).toEqual([]);
          } else {
            expect(result.status).toBe('completed');
            expect(calls(updates).at(-1)?.status).toBe(
              answer === 'deny' ? 'failed' : 'completed',
            );
            expect(said(updates)).toEqual([`Permission: ${answer}.`]);
          }
        } finally {
          unsubscribe();
        }
      }),
  );
});

describe('CHD-393 tester: headline scenario payloads', () => {
  test('sends four complete arguments and matching completion outputs', () =>
    withSession(async (session) => {
      const { updates, result } = await run(session, 'headlines');
      const events = calls(updates);
      const starts = events.filter(
        (event) => event.sessionUpdate === 'tool_call',
      );
      const ends = events.filter(
        (event) => event.sessionUpdate === 'tool_call_update',
      );

      expect(result.status).toBe('completed');
      expect(starts).toHaveLength(4);
      expect(ends.map((event) => [event.toolCallId, event.status])).toEqual(
        starts.map((event) => [event.toolCallId, 'completed']),
      );
      expect(new Set(starts.map((event) => event.toolCallId)).size).toBe(4);
      expect(starts.map((event) => event.status)).toEqual(
        Array.from({ length: 4 }, () => 'in_progress'),
      );

      const commands = starts
        .filter((event) => event.kind === 'execute')
        .map((event) => {
          const input = event.rawInput as { command: string };

          expect(event.title).toBe('`' + input.command + '`');

          return input.command;
        });

      expect(commands[0]?.split('\n')).toHaveLength(13);
      expect(commands[0]).toContain('\n\n');
      expect(commands[0]).toEndWith('\nEOF');
      expect(commands[1]?.length).toBeGreaterThan(200);
      expect(commands[1]).not.toContain('\n');
      expect(commands[1]).toEndWith('src/ui/transcript/tools/');
      expect(commands[2]?.split('\n')).toHaveLength(300);
      expect(commands[2]).toEndWith('line 298 of the long command\nEOF');

      const mcp = starts.find((event) => event.kind === 'other');

      assert(mcp);
      expect(mcp.title).toBe('mcp__chord__send_message');
      expect(mcp.rawInput).toEqual({
        to: 'reviewer',
        text: expect.stringContaining('a command of 300 lines'),
      });
      expect(ends.map((event) => event.content?.length)).toEqual([1, 1, 1, 1]);
      expect(said(updates)).toEqual(['Four calls with long headlines.']);
    }));

  test('can cancel between calls and play the complete scenario next turn', () =>
    withSession(
      async (session) => {
        const cancelled = await run(session, 'headlines', {
          onUpdate: (updates, turn) => {
            if (calls(updates).length === 1) {
              void turn.cancel();
            }
          },
        });

        expect(cancelled.result.status).toBe('cancelled');
        expect(said(cancelled.updates)).toEqual([]);
        expect((await run(session, 'headlines')).result.status).toBe(
          'completed',
        );
      },
      undefined,
      '--step-ms',
      '20',
    ));
});

describe('Q42 tester: prompt-send cancellation boundaries', () => {
  test('repeated cancellation of several unsent prompts leaves the next turn and stray counter untouched', () =>
    withSession(async (session) => {
      await writeFile(join(session.cwd, 'a.ts'), '');

      for (let index = 0; index < 6; index++) {
        const held = session.prompt('held mention', [], ['a.ts']);

        await Promise.all([held.cancel(), held.cancel()]);
        expect(await held.sent).toBeUndefined();
        expect((await held.result).status).toBe('cancelled');
      }

      const next = await run(session, 'cancels');

      expect(next.result.status).toBe('completed');
      expect(
        said(next.updates)
          .filter((line) => line.startsWith('Cancels with no turn:'))
          .join(''),
      ).toBe('Cancels with no turn: 0.');
    }));

  test('cancelling an unsent turn again cannot withdraw a later turn permission', () =>
    withSession(async (session) => {
      await writeFile(join(session.cwd, 'a.ts'), '');

      const waiting = Promise.withResolvers<PendingPermission>();
      const unsubscribe = session.permissions.subscribe((request) =>
        waiting.resolve(request),
      );

      try {
        const held = session.prompt('held mention', [], ['a.ts']);

        await held.cancel();
        expect(await held.sent).toBeUndefined();
        expect((await held.result).status).toBe('cancelled');

        const active = session.prompt('permission');
        const request = await waiting.promise;

        await held.cancel();
        expect(request.signal.aborted).toBe(false);
        request.resolve('allow');
        expect((await active.result).status).toBe('completed');

        const next = await run(session, 'cancels');

        expect(next.result.status).toBe('completed');
        expect(
          said(next.updates)
            .filter((line) => line.startsWith('Cancels with no turn:'))
            .join(''),
        ).toBe('Cancels with no turn: 0.');
      } finally {
        unsubscribe();
      }
    }));

  for (const mentions of [[], ['a.ts']]) {
    test(`an already-sent prompt ${mentions.length === 0 ? 'without' : 'with'} mentions still cancels its active permission`, () =>
      withSession(async (session) => {
        await writeFile(join(session.cwd, 'a.ts'), '');

        const waiting = Promise.withResolvers<PendingPermission>();
        const unsubscribe = session.permissions.subscribe((request) =>
          waiting.resolve(request),
        );

        try {
          const active = session.prompt('permission', [], mentions);
          const request = await waiting.promise;

          expect(await active.sent).toHaveLength(mentions.length);
          await active.cancel();
          expect(request.signal.aborted).toBe(true);
          expect((await active.result).status).toBe('cancelled');

          const next = await run(session, 'cancels');

          expect(next.result.status).toBe('completed');
          expect(
            said(next.updates)
              .filter((line) => line.startsWith('Cancels with no turn:'))
              .join(''),
          ).toMatch(/^Cancels with no turn: [01]\.$/);
        } finally {
          unsubscribe();
        }
      }));
  }
});

describe('CHD-407 R1 tester: screenshot model selection', () => {
  test('tokens-only keeps the original defaults and accepts both screenshot models', () =>
    withSession(
      async (session) => {
        const models = await session.models();

        expect(models?.current).toBe('gpt-5.3-codex');
        expect(models?.available.map(({ id }) => id)).toEqual([
          'gpt-5.3-codex',
          'claude-haiku-4-5',
          'claude-opus-5-5',
          'gpt-6.1-sol',
        ]);

        for (const model of ['claude-opus-5-5', 'gpt-6.1-sol']) {
          await session.setModel(model);

          const { updates, result } = await run(session, 'text');
          const usage = updates.find(
            (update) => update.sessionUpdate === 'usage_update',
          );

          expect(result.status).toBe('completed');
          expect((await session.models())?.current).toBe(model);
          assert(usage?.sessionUpdate === 'usage_update');
          expect(usage.cost?.amount).toBeGreaterThan(0);
          expect(usage.size).toBeGreaterThan(0);
        }
      },
      undefined,
      '--tokens-only',
    ));
});

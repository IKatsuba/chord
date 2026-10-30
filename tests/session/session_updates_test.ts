/**
 * What a session hears from the fake agent in a turn: a reply's chunks,
 * thoughts, tool calls, permissions, plans, commands' output and
 * compactions.
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import process from 'node:process';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import type { PendingPermission } from '../../src/session/permissions.ts';
import { plainText } from '../../src/session/terminal_text.ts';
import { agentEnv, type Session } from '../../src/session/session.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import { emptyTranscript } from '../../src/session/transcript/types.ts';
import { MARKDOWN_WRAP } from '../fixtures/markdown.ts';
import { EDIT_NEW, EDIT_OLD } from '../fixtures/edits.ts';
import { COMPACT_ERROR, COMPACT_SUMMARY } from '../fixtures/compactions.ts';
import { BASH_OUTPUT, SHELL_OUTPUT } from '../fixtures/terminals.ts';
import { run, said } from '../fixtures/recorder.ts';
import { withSession, collect, calls } from './session_fake.ts';

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
        title: 'Run bun dev test',
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

describe('CHD-396 tester: markdownwrap fake reply', () => {
  test('the named prompt sends the exact sample and completes without a tool or thought', () =>
    withSession(async (session) => {
      const { updates, result } = await run(session, 'markdownwrap');

      expect(said(updates)).toStrictEqual([MARKDOWN_WRAP]);
      expect(said(updates, 'agent_thought_chunk')).toStrictEqual([]);
      expect(calls(updates)).toStrictEqual([]);
      expect(said(updates).join('')).toContain(
        'Soft\nbreak and a hard  \nbreak here.',
      );
      expect(result.status).toBe('completed');
      assert(result.status === 'completed');
      expect(result.stopReason).toBe('end_turn');

      const next = await run(session, 'text');

      expect(said(next.updates).join('')).toBe(
        'Hello, world. This reply came in chunks.',
      );
      expect(next.result.status).toBe('completed');
    }));
});

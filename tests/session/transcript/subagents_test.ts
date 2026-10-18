import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import type { ContentBlock, SessionUpdate } from '@agentclientprotocol/sdk';
import { subagentsIn } from '../../../src/session/subagents.ts';
import type {
  Entry,
  Subagent,
  Transcript,
  TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import { fold } from './fold.ts';

const TURN = 't1';

const PROMPT: TranscriptAction = {
  type: 'prompt',
  turnId: TURN,
  text: 'look',
  at: 1,
};

/** A subagent announced from the session, or from `from`. */
function spawned(id: string, title: string, from?: string): TranscriptAction {
  return {
    type: 'update',
    turnId: TURN,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: id,
      title,
      description: `${title}, short`,
      state: { state: 'running' },
    },
    ...(from === undefined ? {} : { subagentId: from }),
  };
}

/** A `session_message` heard on the subagent `to`'s session. */
function message(
  to: string,
  messageId: string,
  content: ContentBlock[] | null | undefined,
  senderSessionId?: string,
): TranscriptAction {
  return {
    type: 'update',
    turnId: TURN,
    subagentId: to,
    update: {
      sessionUpdate: 'session_message',
      messageId,
      recipientSessionId: to,
      ...(content === undefined ? {} : { content }),
      ...(senderSessionId === undefined ? {} : { senderSessionId }),
    },
  };
}

function text(value: string): ContentBlock[] {
  return [{ type: 'text', text: value }];
}

function only(transcript: Transcript, id: string): Subagent {
  const found = subagentsIn(transcript.entries).find((each) => each.id === id);

  assert(found, `no subagent ${id}`);

  return found;
}

/** A subagent's messages among its work: who from, and what they say. */
function messages(subagent: Subagent) {
  return subagent.entries.flatMap((entry: Entry) =>
    entry.kind === 'message'
      ? [
          {
            from: entry.byAgent ? 'agent' : entry.from.name,
            text: entry.text,
          },
        ]
      : [],
  );
}

test("a subagent's first message is its whole task, which a later upsert of it replaces or clears", () => {
  const told = fold([
    PROMPT,
    spawned('a', 'explorer (Explore)'),
    message('a', 'call-1', text('Find the session layer.\n\nIn full.'), 's'),
  ]);

  expect(only(told, 'a').prompt).toStrictEqual(
    'Find the session layer.\n\nIn full.',
  );
  expect(messages(only(told, 'a'))).toStrictEqual([]);
  expect(
    only(fold([message('a', 'call-1', text('Rewritten.'))], told), 'a').prompt,
  ).toStrictEqual('Rewritten.');
  // Content left out keeps it.
  expect(
    only(fold([message('a', 'call-1', undefined)], told), 'a').prompt,
  ).toStrictEqual('Find the session layer.\n\nIn full.');

  const cleared = only(fold([message('a', 'call-1', null)], told), 'a');

  expect(cleared.prompt).toStrictEqual(undefined);
  expect(cleared.description).toStrictEqual('explorer (Explore), short');
});

test("a later message is a row among the subagent's work where it came, upserted by its id", () => {
  const work: TranscriptAction = {
    type: 'update',
    turnId: TURN,
    subagentId: 'a',
    update: {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: 'Found it.' },
    },
  };
  const told = fold([
    PROMPT,
    spawned('a', 'explorer (Explore)'),
    spawned('g', 'reader', 'a'),
    message('a', 'call-1', text('Find it.'), 's'),
    work,
    message('a', 'call-2', text('Now the tests.'), 's'),
    message('g', 'call-3', text('Read the tests.'), 'a'),
    message('g', 'call-4', text('And the docs.'), 'a'),
  ]);

  expect(only(told, 'a').entries.map((entry) => entry.kind)).toStrictEqual([
    'subagent',
    'assistant',
    'message',
  ]);
  // From the transcript's own agent, or another subagent, named as its block.
  expect(messages(only(told, 'a'))).toStrictEqual([
    { from: 'agent', text: 'Now the tests.' },
  ]);
  expect(messages(only(told, 'g'))).toStrictEqual([
    { from: 'Agent(explorer (Explore))', text: 'And the docs.' },
  ]);
  expect(only(told, 'g').prompt).toStrictEqual('Read the tests.');

  // Replaced in place, its sender kept when left out, and gone once cleared.
  const replaced = fold(
    [message('g', 'call-4', text('And the README.'))],
    told,
  );

  expect(messages(only(replaced, 'g'))).toStrictEqual([
    { from: 'Agent(explorer (Explore))', text: 'And the README.' },
  ]);
  expect(
    messages(only(fold([message('g', 'call-4', [])], replaced), 'g')),
  ).toStrictEqual([]);
});

test("a later message cleared leaves the subagent's plan where it first came among its work", () => {
  const child = (update: SessionUpdate): TranscriptAction => ({
    type: 'update',
    turnId: TURN,
    subagentId: 'a',
    update,
  });
  const told = fold([
    PROMPT,
    spawned('a', 'explorer'),
    message('a', 'call-1', text('Find it.'), 's'),
    message('a', 'call-2', text('Then the tests.'), 's'),
    child({
      sessionUpdate: 'plan',
      entries: [
        { content: 'Find it', priority: 'medium', status: 'in_progress' },
      ],
    }),
    child({
      sessionUpdate: 'tool_call',
      toolCallId: 'c1',
      title: 'Read c1',
      status: 'in_progress',
    }),
    message('a', 'call-3', text('And the docs.'), 's'),
  ]);
  const work = (transcript: Transcript) => {
    const { entries, planAt } = only(transcript, 'a');

    return { kinds: entries.map((entry) => entry.kind), planAt };
  };

  expect(work(told)).toStrictEqual({
    kinds: ['message', 'tool', 'message'],
    planAt: 1,
  });
  // Before the plan, its place moves with the work; after it, it stays.
  expect(work(fold([message('a', 'call-2', null)], told))).toStrictEqual({
    kinds: ['tool', 'message'],
    planAt: 0,
  });
  expect(work(fold([message('a', 'call-3', null)], told))).toStrictEqual({
    kinds: ['message', 'tool'],
    planAt: 1,
  });
});

describe('CHD-432 tester: message identity and nested routing', () => {
  test('the same message id in two subagents replaces and clears only its recipient', () => {
    const before = fold([
      PROMPT,
      spawned('a', 'A'),
      spawned('b', 'B'),
      message('a', 'task', text('Task A')),
      message('b', 'task', text('Task B')),
      message('a', 'followup', text('For A')),
      message('b', 'followup', text('For B')),
    ]);
    const after = fold(
      [
        message('a', 'task', []),
        message('a', 'followup', text('Rewritten A')),
        message('b', 'followup', null),
      ],
      before,
    );

    expect(only(after, 'a').prompt).toBeUndefined();
    expect(only(after, 'a').description).toBe('A, short');
    expect(only(after, 'b').prompt).toBe('Task B');
    expect(messages(only(after, 'a'))).toStrictEqual([
      { from: 'agent', text: 'Rewritten A' },
    ]);
    expect(messages(only(after, 'b'))).toStrictEqual([]);
    expect(only(before, 'a').prompt).toBe('Task A');
    expect(messages(only(before, 'b'))).toStrictEqual([
      { from: 'agent', text: 'For B' },
    ]);
  });

  test('clearing a task keeps its id so a new followup never becomes the task', () => {
    const transcript = fold([
      PROMPT,
      spawned('a', 'A'),
      message('a', 'task', text('Original task')),
      message('a', 'task', null),
      message('a', 'later', text('Followup')),
      message('a', 'task', [
        { type: 'text', text: 'Restored' },
        { type: 'text', text: ' task' },
      ]),
    ]);

    expect(only(transcript, 'a').prompt).toBe('Restored task');
    expect(messages(only(transcript, 'a'))).toStrictEqual([
      { from: 'agent', text: 'Followup' },
    ]);
  });

  test('a nested sender is named on another branch and a later explicit sender replaces it', () => {
    const before = fold([
      PROMPT,
      spawned('a', 'A'),
      spawned('g', 'Nested', 'a'),
      spawned('b', 'B'),
      message('b', 'task', text('Task B')),
      message('b', 'later', text('From nested'), 'g'),
    ]);

    expect(messages(only(before, 'b'))).toStrictEqual([
      { from: 'Agent(Nested)', text: 'From nested' },
    ]);
    expect(
      messages(
        only(
          fold([message('b', 'later', text('From runtime'), 'root')], before),
          'b',
        ),
      ),
    ).toStrictEqual([{ from: 'agent', text: 'From runtime' }]);
    expect(fold([message('missing', 'id', text('No leak'))], before)).toBe(
      before,
    );
  });
});

test('a subagent waits while its agent says requires_action, and keeps having offered a cancel it lost', () => {
  const stood = (
    state: { state: string } | undefined,
    at: number,
    capabilities?: { cancel?: object } | null,
  ): TranscriptAction => ({
    type: 'update',
    turnId: TURN,
    at,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: 'a',
      ...(state === undefined ? {} : { state: state as never }),
      ...(capabilities === undefined ? {} : { capabilities }),
    },
  });
  const after = (...actions: TranscriptAction[]) =>
    only(
      fold([
        PROMPT,
        { ...spawned('a', 'explorer'), at: 5 } as TranscriptAction,
        stood(undefined, 5, { cancel: {} }),
        ...actions,
      ]),
      'a',
    );

  expect(after(stood({ state: 'requires_action' }, 9)).waiting).toStrictEqual({
    since: 9,
  });
  // A second one keeps the first time; a patch with no state keeps it.
  expect(
    after(
      stood({ state: 'requires_action' }, 9),
      stood({ state: 'requires_action' }, 12),
      stood(undefined, 14),
    ).waiting,
  ).toStrictEqual({ since: 9 });
  expect(
    after(
      stood({ state: 'requires_action' }, 9),
      stood({ state: 'running' }, 12),
    ).waiting,
  ).toStrictEqual(undefined);

  const lost = after(stood(undefined, 9, null));

  expect([lost.cancellable, lost.offeredCancel]).toStrictEqual([
    undefined,
    true,
  ]);
});

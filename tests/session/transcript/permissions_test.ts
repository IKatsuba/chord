import { expect, test } from 'bun:test';
import type { TranscriptAction } from '../../../src/session/transcript/types.ts';
import { fold } from './fold.ts';

const FORM_WAIT = {
  id: 'e1',
  mode: 'form',
  message: 'Set up the deploy target',
  schema: { type: 'object', properties: {} },
} as const;

const ASKED: TranscriptAction[] = [
  { type: 'prompt', turnId: 't1', text: 'form', at: 0 },
  { type: 'elicitation_requested', turnId: 't1', elicitation: FORM_WAIT },
];

test('a form asked for waits apart from the turn, which keeps working', () => {
  const transcript = fold(ASKED);

  expect(transcript.asking).toStrictEqual([FORM_WAIT]);
  expect(transcript.turn.status).toStrictEqual('working');
  // Asked again, it is the same form.
  expect(fold([ASKED[1]!], transcript)).toStrictEqual(transcript);
});

test('each answer to a form leaves its record, and the form goes', () => {
  for (const [answer, outcome] of [
    [{ type: 'accepted', content: { name: 'web-app' } }, 'accepted'],
    [{ type: 'declined' }, 'declined'],
    [{ type: 'cancelled' }, 'cancelled'],
    // Its turn ended or the session closed under it.
    [{ type: 'withdrawn' }, 'cancelled'],
  ] as const) {
    const transcript = fold([
      ...ASKED,
      {
        type: 'elicitation_settled',
        turnId: 't1',
        id: 'e1',
        answer,
      },
    ]);

    expect(transcript.asking).toStrictEqual([]);
    expect(transcript.entries.at(-1)).toStrictEqual({
      kind: 'elicitation',
      turnId: 't1',
      wait: FORM_WAIT,
      outcome,
      ...('content' in answer ? { content: answer.content } : {}),
    });
  }
});

test('a turn that ends under an open form records it cancelled', () => {
  const transcript = fold([
    ...ASKED,
    {
      type: 'result',
      turnId: 't1',
      result: { status: 'cancelled', stopReason: 'cancelled' },
    },
  ]);

  expect(transcript.asking).toStrictEqual([]);
  expect(
    transcript.entries.map((entry) =>
      entry.kind === 'elicitation' ? entry.outcome : entry.kind,
    ),
  ).toStrictEqual(['user', 'cancelled', 'cancelled']);
});

test('a form asked by a turn that is no longer current is not shown', () => {
  const transcript = fold([
    { type: 'prompt', turnId: 't2', text: 'next', at: 0 },
    { type: 'elicitation_requested', turnId: 't1', elicitation: FORM_WAIT },
  ]);

  expect(transcript.asking).toStrictEqual([]);
});

test('a box of questions answered out of a tool call marks that call as asked; a plain form leaves it', () => {
  const call: TranscriptAction = {
    type: 'update',
    turnId: 't1',
    update: {
      sessionUpdate: 'tool_call',
      toolCallId: 'ask-1',
      title: 'Asking for your input',
      kind: 'other',
      status: 'pending',
    },
  };
  const settled = (questions: boolean) =>
    fold([
      { type: 'prompt', turnId: 't1', text: 'askclaude', at: 0 },
      call,
      {
        type: 'elicitation_requested',
        turnId: 't1',
        elicitation: {
          ...FORM_WAIT,
          toolCallId: 'ask-1',
          ...(questions
            ? { questions: { agent: 'claude', questions: [] } }
            : {}),
        },
      },
      {
        type: 'elicitation_settled',
        turnId: 't1',
        id: 'e1',
        answer: { type: 'declined' },
      },
    ]).entries.find((entry) => entry.kind === 'tool');

  expect(settled(true)).toMatchObject({ call: { id: 'ask-1', asked: true } });
  // Marked from when the box opens.
  expect(
    fold([
      { type: 'prompt', turnId: 't1', text: 'askclaude', at: 0 },
      call,
      {
        type: 'elicitation_requested',
        turnId: 't1',
        elicitation: {
          ...FORM_WAIT,
          toolCallId: 'ask-1',
          questions: { agent: 'claude', questions: [] },
        },
      },
    ]).entries.find((entry) => entry.kind === 'tool'),
  ).toMatchObject({ call: { asked: true } });
  expect(settled(false)).not.toMatchObject({ call: { asked: true } });
});

test("a task's box of questions marks its own call, never a call of the session's with the same id", () => {
  const tool = (subagentId?: string): TranscriptAction => ({
    type: 'update',
    turnId: 't1',
    update: {
      sessionUpdate: 'tool_call',
      toolCallId: 'ask-1',
      title: 'Asking for your input',
      kind: 'other',
      status: 'pending',
    },
    ...(subagentId === undefined ? {} : { subagentId }),
  });
  const transcript = fold([
    { type: 'prompt', turnId: 't1', text: 'task', at: 0 },
    tool(),
    {
      type: 'update',
      turnId: 't1',
      update: {
        sessionUpdate: 'subagent_update',
        sessionId: 'task-1',
        title: 'Ask',
        state: { state: 'running' },
      },
    },
    tool('task-1'),
    {
      type: 'elicitation_requested',
      turnId: 't1',
      elicitation: {
        ...FORM_WAIT,
        toolCallId: 'ask-1',
        subagentId: 'task-1',
        questions: { agent: 'claude', questions: [] },
      },
    },
  ]);
  const own = transcript.entries.find((entry) => entry.kind === 'tool');
  const task = transcript.entries.find((entry) => entry.kind === 'subagent');

  expect(own).not.toMatchObject({ call: { asked: true } });
  expect(
    task?.kind === 'subagent' &&
      task.subagent.entries.find((entry) => entry.kind === 'tool'),
  ).toMatchObject({ call: { id: 'ask-1', asked: true } });
});

test("a task's box of questions is recorded under its call among the task's work, not the session's", () => {
  const transcript = fold([
    { type: 'prompt', turnId: 't1', text: 'taskask', at: 0 },
    {
      type: 'update',
      turnId: 't1',
      update: {
        sessionUpdate: 'subagent_update',
        sessionId: 'task-1',
        title: 'Ask',
        state: { state: 'running' },
      },
    },
    {
      type: 'update',
      turnId: 't1',
      subagentId: 'task-1',
      update: {
        sessionUpdate: 'tool_call',
        toolCallId: 'ask-1',
        title: 'Asking for your input',
        kind: 'other',
        status: 'pending',
      },
    },
    {
      type: 'elicitation_requested',
      turnId: 't1',
      elicitation: {
        ...FORM_WAIT,
        toolCallId: 'ask-1',
        subagentId: 'task-1',
        questions: { agent: 'claude', questions: [] },
      },
    },
    {
      type: 'elicitation_settled',
      turnId: 't1',
      id: 'e1',
      answer: { type: 'declined' },
    },
  ]);
  const task = transcript.entries.find((entry) => entry.kind === 'subagent');

  expect(transcript.entries.map((entry) => entry.kind)).toStrictEqual([
    'user',
    'subagent',
  ]);
  expect(
    task?.kind === 'subagent' &&
      task.subagent.entries.map((entry) => entry.kind),
  ).toStrictEqual(['tool', 'elicitation']);
});

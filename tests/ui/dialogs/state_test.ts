import { expect, test } from 'bun:test';
import {
  emptyTranscript,
  type PlanAsk,
  type Transcript,
} from '../../../src/session/transcript/types.ts';
import {
  askedIds,
  askedInput,
  askedPlan,
  asksPerson,
  shownPermission,
} from '../../../src/ui/dialogs/state.ts';

test('the plan on screen is the oldest unanswered one, after any permission, and it asks the person (CHD-437)', () => {
  const wait = (id: string) =>
    ({ id, agent: 'grok', toolCallId: 'c' }) as const;
  const asks: PlanAsk[] = [
    { turnId: 't', wait: wait('a'), answer: { type: 'accepted' } },
    { turnId: 't', wait: wait('b') },
    { turnId: 't', wait: wait('c') },
  ];
  const transcript: Transcript = { ...emptyTranscript, planAsks: asks };

  expect(askedPlan(transcript)?.wait.id).toBe('b');
  expect(asksPerson(transcript)).toBe(true);
  expect(askedIds(transcript)).toStrictEqual(['b', 'c']);
  expect(asksPerson(emptyTranscript)).toBe(false);
});

test('a plan ranks with the permissions, the oldest first; forms, questions and links wait for both (CHD-437)', () => {
  const permission = { id: 'p1', toolCallId: 'c', options: [] };
  const waiting = (asks: PlanAsk[]): Transcript => ({
    ...emptyTranscript,
    turn: {
      status: 'awaiting_permission',
      turnId: 't',
      since: 0,
      permissions: [permission],
    },
    planAsks: asks,
    asking: [
      {
        id: 'e1',
        mode: 'form',
        message: 'Go?',
        schema: { type: 'object', properties: {} },
      },
    ],
  });
  const plan = { id: 'b', agent: 'grok', toolCallId: 'c' } as const;

  // The plan came first: it is shown, the later permission waits.
  const before = waiting([{ turnId: 't', wait: plan }]);

  expect(askedPlan(before)?.wait.id).toBe('b');
  expect(shownPermission(before)).toBe(undefined);
  expect(askedInput(before)).toBe(undefined);

  // The permission was waiting when the plan came: it goes first.
  const after = waiting([{ turnId: 't', wait: plan, after: ['p1'] }]);

  expect(askedPlan(after)).toBe(undefined);
  expect(shownPermission(after)?.id).toBe('p1');
  expect(askedInput(after)).toBe(undefined);

  // A plan waiting holds a form back, though no permission does.
  expect(
    askedInput({
      ...before,
      turn: { status: 'working', turnId: 't', since: 0 },
    }),
  ).toBe(undefined);
});

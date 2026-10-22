import { expect, test } from 'bun:test';
import {
  emptyTranscript,
  type PlanAsk,
  type Transcript,
} from '../../../src/session/transcript/types.ts';
import {
  askedIds,
  askedPlan,
  asksPerson,
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
  expect(
    askedPlan({
      ...transcript,
      turn: {
        status: 'awaiting_permission',
        turnId: 't',
        since: 0,
        permissions: [],
      },
    }),
  ).toBe(undefined);
  expect(asksPerson(emptyTranscript)).toBe(false);
});

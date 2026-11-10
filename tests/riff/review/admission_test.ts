import { expect, test } from 'bun:test';
import { ReviewTurn } from '../../../src/riff/review/admission.ts';
import type { ReviewEvidence } from '../../../src/riff/review/input.ts';

const signal = new AbortController().signal;
const evidence: ReviewEvidence = {
  action: { tool: 'shell', command: 'pwd', cwd: '/project' },
  requests: { current: 'request', first: 'request', recent: [] },
  results: [],
};

test('exact repeated calls share one review, including concurrent calls and cautions', async () => {
  let reviews = 0;
  const turn = new ReviewTurn(() => {
    reviews++;

    return Promise.resolve({ outcome: 'caution', rationale: 'held' });
  });

  expect(
    await Promise.all([
      turn.run({ command: 'pwd' }, evidence, signal),
      turn.run({ command: 'pwd' }, evidence, signal),
    ]),
  ).toEqual([
    { outcome: 'caution', rationale: 'held' },
    { outcome: 'caution', rationale: 'held' },
  ]);
  expect(reviews).toBe(1);
});

test('the per-turn budget permits 64 reviews and asks after that', async () => {
  let reviews = 0;
  const turn = new ReviewTurn(() => {
    reviews++;

    return Promise.resolve({ outcome: 'clear' });
  });

  for (let index = 0; index < 65; index++) {
    const result = await turn.run({ index }, evidence, signal);

    expect(result.outcome).toBe(index < 64 ? 'clear' : 'incomplete');
  }

  expect(reviews).toBe(64);
  expect((await turn.run({ index: 0 }, evidence, signal)).outcome).toBe(
    'clear',
  );
});

test('incomplete actions are cached without sending, and new turns have fresh authority', async () => {
  let reviews = 0;
  const send = () => {
    reviews++;

    return Promise.resolve({ outcome: 'clear' as const });
  };

  const turn = new ReviewTurn(send);
  const incomplete: ReviewEvidence = {
    ...evidence,
    action: {
      ...evidence.action,
      tool: 'shell',
      command: 'x'.repeat(65537),
      cwd: '/project',
    },
  };

  expect((await turn.run({}, incomplete, signal)).outcome).toBe('incomplete');
  expect((await turn.run({}, incomplete, signal)).outcome).toBe('incomplete');
  expect(reviews).toBe(0);

  await turn.run({}, evidence, signal);
  await new ReviewTurn(send).run({}, evidence, signal);

  expect(reviews).toBe(2);
});

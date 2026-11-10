import { expect, test } from 'bun:test';
import { Buffer } from 'node:buffer';
import { reviewDecision } from '../../../src/riff/review/decision.ts';

test('review decisions accept clear and caution, ignore extra fields and bound rationale bytes', () => {
  expect(reviewDecision({ decision: 'clear', extra: 'ignored' })).toEqual({
    outcome: 'clear',
  });
  expect(
    reviewDecision({ decision: 'caution', rationale: 'destructive' }),
  ).toEqual({
    outcome: 'caution',
    rationale: 'destructive',
  });

  const caution = reviewDecision({
    decision: 'caution',
    rationale: '🙂'.repeat(100),
  });

  expect(caution?.outcome).toBe('caution');

  if (caution?.outcome === 'caution') {
    expect(Buffer.byteLength(caution.rationale)).toBe(240);
    expect(caution.rationale).not.toContain('\ufffd');
  }
});

test('text, bad JSON, unknown decisions and wrong field types are malformed', () => {
  for (const value of [
    'clear',
    '{',
    {},
    { decision: 'allow' },
    { decision: 'clear', rationale: 1 },
    null,
  ]) {
    expect(reviewDecision(value)).toBeUndefined();
  }
});

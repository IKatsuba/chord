import { describe, expect, test } from 'bun:test';
import { planFetch } from '../../src/riff/qa_provider.ts';

describe('QA plan fetch boundary', () => {
  test('unknown URLs fail locally without a network fallback', async () => {
    const fixture = planFetch({ plan: 'codex' });

    await expect(
      fixture.fetch('https://fixture.invalid/unexpected', {}),
    ).rejects.toThrow('Unexpected fixture URL');
    expect(fixture.urls).toEqual(['https://fixture.invalid/unexpected']);
  });
});

import { describe, expect, test } from 'bun:test';
import { contextWindow, turnCost } from '../../src/session/prices.ts';

test("genai-prices' data names the models chord meets: Claude Opus 5.5, GPT-6.1 Sol and Codex's ids", () => {
  for (const model of [
    'claude-opus-5-5',
    'gpt-6.1-sol',
    'gpt-5.3-codex',
    'gpt-5.2-codex',
    'gpt-5.1-codex',
    'gpt-5-codex',
  ]) {
    expect(
      turnCost(model, { inputTokens: 1000, outputTokens: 1000 }),
      model,
    ).toBeGreaterThan(0);
    expect(contextWindow(model), model).toBeGreaterThan(0);
  }
});

describe('CHD-381 P1 tester: price data compatibility', () => {
  for (const model of ['claude-opus-5-5', 'gpt-6.1-sol']) {
    test(`${model}: adapter names keep the same price and window`, () => {
      const tokens = { inputTokens: 1000, outputTokens: 200 };
      const cost = turnCost(model, tokens);
      const size = contextWindow(model);

      expect(cost).toBeGreaterThan(0);
      expect(Number.isFinite(cost)).toBe(true);
      expect(size).toBeGreaterThan(0);

      for (const named of [
        model + '/medium',
        'provider/' + model,
        model + '[1m]',
      ]) {
        expect(turnCost(named, tokens)).toBe(cost);
        expect(contextWindow(named)).toBe(size);
      }

      expect(turnCost(model, { inputTokens: 0, outputTokens: 0 })).toBe(0);
      expect(turnCost(model, { inputTokens: 2000, outputTokens: 400 })).toBe(
        cost! * 2,
      );
    });
  }

  test('unknown and empty model names leave estimates absent', () => {
    for (const model of ['', 'chord-unknown-price-model']) {
      expect(
        turnCost(model, { inputTokens: 1000, outputTokens: 200 }),
      ).toBeUndefined();
      expect(contextWindow(model)).toBeUndefined();
    }
  });
});

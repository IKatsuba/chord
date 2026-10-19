import { expect, test } from 'bun:test';
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

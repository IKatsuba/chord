import { describe, expect, test } from 'bun:test';
import {
  defaultConfig,
  planModels,
  setOption,
  windowOf,
} from '../../src/riff/models.ts';

describe("riff's models, efforts and modes", () => {
  test("each plan's default model comes first, with a window", () => {
    for (const plan of ['codex', 'grok', 'fake'] as const) {
      const [first] = planModels(plan);

      expect(defaultConfig(plan)).toStrictEqual({
        model: first?.id ?? '',
        effort: 'default',
        mode: 'ask',
      });
      expect(planModels(plan).every(({ window }) => window > 0)).toBe(true);
    }
  });

  test('the fake provider offers its one model alone', () => {
    expect(planModels('fake')).toStrictEqual([{ id: 'fake', window: 128_000 }]);
    expect(windowOf('fake', 'fake')).toBe(128_000);
  });

  test('an option takes only what riff offers', () => {
    const config = defaultConfig('codex');

    expect(setOption('codex', config, 'effort', 'xhigh')?.effort).toBe('xhigh');
    expect(setOption('codex', config, 'mode', 'auto')?.mode).toBe('auto');
    expect(setOption('codex', config, 'model', 'grok-4.7')).toBeUndefined();
    expect(setOption('codex', config, 'effort', 'max')).toBeUndefined();
    expect(setOption('codex', config, 'colour', 'red')).toBeUndefined();
    expect(setOption('codex', config, 'mode', true)).toBeUndefined();
  });
});

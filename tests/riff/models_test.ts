import { describe, expect, test } from 'bun:test';
import {
  configOptions,
  defaultConfig,
  planModels,
  setOption,
  windowOf,
} from '../../src/riff/models.ts';

const UP_TO_ULTRA = ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'] as const;
const UP_TO_MAX = ['low', 'medium', 'high', 'xhigh', 'max'] as const;
const UP_TO_XHIGH = ['low', 'medium', 'high', 'xhigh'] as const;

/** The effort option's values for `model` on `plan`. */
function efforts(plan: 'codex' | 'grok', model: string): string[] {
  const option = configOptions(plan, { ...defaultConfig(plan), model }).find(
    ({ id }) => id === 'effort',
  );

  return option?.type === 'select'
    ? option.options.flatMap((value) => ('value' in value ? [value.value] : []))
    : [];
}

describe("riff's models, efforts and modes", () => {
  test("each plan's default model comes first, with a window", () => {
    for (const plan of ['codex', 'grok', 'fake'] as const) {
      const [first] = planModels(plan);

      expect(defaultConfig(plan)).toStrictEqual({
        model: first?.id ?? '',
        effort: 'default',
        mode: 'auto',
      });
      expect(planModels(plan).every(({ window }) => window > 0)).toBe(true);
    }
  });

  test("the ChatGPT plan's models, in its order, with their windows and levels", () => {
    expect(planModels('codex')).toStrictEqual([
      { id: 'gpt-6.1-sol', window: 500_000, levels: UP_TO_ULTRA },
      { id: 'gpt-6-astra', window: 272_000, levels: UP_TO_ULTRA },
      { id: 'gpt-6.1-terra', window: 500_000, levels: UP_TO_ULTRA },
      { id: 'gpt-6-sol', window: 272_000, levels: UP_TO_ULTRA },
      { id: 'gpt-6-luna', window: 272_000, levels: UP_TO_MAX },
      { id: 'gpt-5.6-sol', window: 272_000, levels: UP_TO_ULTRA },
      { id: 'gpt-5.6-terra', window: 272_000, levels: UP_TO_ULTRA },
      { id: 'gpt-5.6-luna', window: 272_000, levels: UP_TO_MAX },
    ]);
  });

  test("the Grok plan's models, in its order, with their windows and levels", () => {
    expect(planModels('grok')).toStrictEqual([
      { id: 'grok-4.7', window: 256_000, levels: UP_TO_XHIGH },
      { id: 'grok-4.7-build-fast', window: 256_000, levels: UP_TO_XHIGH },
      { id: 'grok-4.6', window: 256_000, levels: UP_TO_XHIGH },
      { id: 'grok-4.5', window: 256_000, levels: ['low', 'medium', 'high'] },
    ]);
  });

  test('the fake provider offers its one model alone', () => {
    expect(planModels('fake')).toStrictEqual([
      { id: 'fake', window: 128_000, levels: UP_TO_XHIGH },
    ]);
    expect(windowOf('fake', 'fake')).toBe(128_000);
  });

  test("the effort option offers default and the current model's levels", () => {
    expect(efforts('codex', 'gpt-6.1-sol')).toStrictEqual([
      'default',
      ...UP_TO_ULTRA,
    ]);
    expect(efforts('codex', 'gpt-6-luna')).toStrictEqual([
      'default',
      ...UP_TO_MAX,
    ]);
    expect(efforts('grok', 'grok-4.5')).toStrictEqual([
      'default',
      'low',
      'medium',
      'high',
    ]);
  });

  test('an option takes only what riff offers', () => {
    const config = defaultConfig('codex');

    expect(setOption('codex', config, 'effort', 'ultra')?.effort).toBe('ultra');
    expect(setOption('codex', config, 'mode', 'auto')?.mode).toBe('auto');
    expect(setOption('codex', config, 'model', 'grok-4.7')).toBeUndefined();
    expect(setOption('codex', config, 'colour', 'red')).toBeUndefined();
    expect(setOption('codex', config, 'mode', true)).toBeUndefined();
  });

  test('an effort the current model does not take is refused', () => {
    const luna = { ...defaultConfig('codex'), model: 'gpt-6-luna' };
    const old = { ...defaultConfig('grok'), model: 'grok-4.5' };

    expect(setOption('codex', luna, 'effort', 'ultra')).toBeUndefined();
    expect(setOption('codex', luna, 'effort', 'max')?.effort).toBe('max');
    expect(setOption('grok', old, 'effort', 'xhigh')).toBeUndefined();
  });

  test('a model without the current effort resets it to default', () => {
    const ultra = { ...defaultConfig('codex'), effort: 'ultra' as const };

    expect(setOption('codex', ultra, 'model', 'gpt-6-luna')).toStrictEqual({
      ...ultra,
      model: 'gpt-6-luna',
      effort: 'default',
    });
    expect(setOption('codex', ultra, 'model', 'gpt-6-sol')).toStrictEqual({
      ...ultra,
      model: 'gpt-6-sol',
    });
  });
});

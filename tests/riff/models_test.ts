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

describe('CHD-611 tester: model and effort boundaries', () => {
  test('every model transition retains only an effort the destination offers', () => {
    for (const plan of ['codex', 'grok'] as const) {
      for (const source of planModels(plan)) {
        for (const effort of ['default', ...source.levels] as const) {
          const config = { model: source.id, effort, mode: 'ask' as const };

          for (const destination of planModels(plan)) {
            const changed = setOption(plan, config, 'model', destination.id);
            const expected = efforts(plan, destination.id);

            expect(changed).toStrictEqual({
              model: destination.id,
              effort: expected.includes(effort) ? effort : 'default',
              mode: 'ask',
            });
            expect(config).toStrictEqual({
              model: source.id,
              effort,
              mode: 'ask',
            });
          }
        }
      }
    }
  });

  test('the picker and accepted efforts agree for every listed model', () => {
    const levels = [
      'default',
      'low',
      'medium',
      'high',
      'xhigh',
      'max',
      'ultra',
    ] as const;

    for (const plan of ['codex', 'grok'] as const) {
      for (const model of planModels(plan)) {
        const config = { ...defaultConfig(plan), model: model.id };
        const offered = efforts(plan, model.id);

        expect(offered).toStrictEqual(['default', ...model.levels]);
        expect(new Set(offered).size).toBe(offered.length);
        expect(windowOf(plan, model.id)).toBe(model.window);

        for (const effort of levels) {
          const result = setOption(plan, config, 'effort', effort);

          if (offered.includes(effort)) {
            expect(result).toStrictEqual({ ...config, effort });
          } else {
            expect(result).toBeUndefined();
          }
        }
      }
    }
  });

  test('hidden, API-only and other-plan ids cannot enter a plan picker', () => {
    for (const plan of ['codex', 'grok'] as const) {
      const config = defaultConfig(plan);
      const rejected = [
        'gpt-reserve',
        'codex-auto-review',
        'grok-4.3',
        'grok-4.20',
        'grok-code-fast-1',
        'fake',
        ...(plan === 'codex'
          ? planModels('grok').map(({ id }) => id)
          : planModels('codex').map(({ id }) => id)),
      ];

      for (const id of rejected) {
        expect(planModels(plan).some((model) => model.id === id)).toBe(false);
        expect(setOption(plan, config, 'model', id)).toBeUndefined();
      }
    }
  });
});

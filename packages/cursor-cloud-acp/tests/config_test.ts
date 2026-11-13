import { describe, expect, test } from 'bun:test';
import type { ModelListItem } from '@cursor/sdk';
import {
  type Choice,
  choose,
  chosen,
  configOptions,
  CURSORS_DEFAULT,
  sdkMode,
  selection,
  startingParams,
} from '../src/config.ts';

/** A model with `reasoning` and `context`, whose variants pair them unevenly. */
const GPT: ModelListItem = {
  id: 'gpt-5',
  displayName: 'GPT-5',
  parameters: [
    {
      id: 'reasoning',
      displayName: 'Reasoning',
      values: [
        { value: 'low', displayName: 'Low' },
        { value: 'medium' },
        { value: 'high', displayName: 'High' },
      ],
    },
    { id: 'context', values: [{ value: '200k' }, { value: '1m' }] },
  ],
  variants: [
    {
      displayName: 'GPT-5 Low',
      params: [
        { id: 'reasoning', value: 'low' },
        { id: 'context', value: '200k' },
      ],
    },
    {
      displayName: 'GPT-5',
      isDefault: true,
      params: [
        { id: 'reasoning', value: 'medium' },
        { id: 'context', value: '200k' },
      ],
    },
    {
      displayName: 'GPT-5 High 1M',
      params: [
        { id: 'reasoning', value: 'high' },
        { id: 'context', value: '1m' },
      ],
    },
    {
      displayName: 'GPT-5 Medium 1M',
      params: [
        { id: 'reasoning', value: 'medium' },
        { id: 'context', value: '1m' },
      ],
    },
  ],
};
const COMPOSER: ModelListItem = {
  id: 'composer-2',
  displayName: 'Composer 2',
  variants: [{ displayName: 'Composer 2', params: [] }],
};
const MODELS = [COMPOSER, GPT];

const optionIds = (choice: Choice, offered = true) =>
  configOptions(choice, MODELS, offered).map((each) => each.id);
const option = (choice: Choice, id: string, offered = true) =>
  configOptions(choice, MODELS, offered).find((each) => each.id === id)!;
const values = (choice: Choice, id: string, offered = true) =>
  (option(choice, id, offered).options as { value: string }[]).map(
    (each) => each.value,
  );

describe('mode', () => {
  test("default and plan, Agent being the SDK's agent", () => {
    expect(option({ mode: 'default' }, 'mode')).toEqual({
      id: 'mode',
      name: 'Mode',
      category: 'mode',
      type: 'select',
      currentValue: 'default',
      options: [
        { value: 'default', name: 'Agent' },
        { value: 'plan', name: 'Plan' },
      ],
    });
    expect(sdkMode({ mode: 'default' })).toBe('agent');
    expect(sdkMode({ mode: 'plan' })).toBe('plan');
  });
});

describe('model', () => {
  test("one option per model, Cursor's default first while the agent's model is unset", () => {
    expect(option({ mode: 'default' }, 'model')).toEqual({
      id: 'model',
      name: 'Model',
      category: 'model',
      type: 'select',
      currentValue: CURSORS_DEFAULT,
      options: [
        { value: CURSORS_DEFAULT, name: "Cursor's default" },
        { value: 'composer-2', name: 'Composer 2' },
        { value: 'gpt-5', name: 'GPT-5' },
      ],
    });
    expect(optionIds({ mode: 'default' })).toEqual(['mode', 'model']);
  });

  test("Cursor's default stays while the agent's model is unset, a model chosen or not", () => {
    const choice = choose({ mode: 'default' }, MODELS, true, 'model', 'gpt-5')!;

    expect(values(choice, 'model')).toEqual([
      CURSORS_DEFAULT,
      'composer-2',
      'gpt-5',
    ]);
    expect(option(choice, 'model').currentValue).toBe('gpt-5');
  });

  test("Cursor's default leaves once the agent's model is set, with no way back", () => {
    const choice = {
      mode: 'default',
      model: { id: 'composer-2', params: {} },
    } as const;

    expect(values(choice, 'model', false)).toEqual(['composer-2', 'gpt-5']);
    expect(
      choose(choice, MODELS, false, 'model', CURSORS_DEFAULT),
    ).toBeUndefined();
  });

  test('a model Cursor ran that the list lacks is added under its own id', () => {
    const choice: Choice = {
      mode: 'default',
      model: chosen({ id: 'claude-x' }),
    };

    expect(option(choice, 'model', false).options).toContainEqual({
      value: 'claude-x',
      name: 'claude-x',
    });
    expect(optionIds(choice, false)).toEqual(['mode', 'model']);
  });

  test('a failed list leaves the current model alone', () => {
    const choice: Choice = {
      mode: 'default',
      model: { id: 'gpt-5', params: { reasoning: 'high' } },
    };

    expect(configOptions(choice, [], false)[1]).toMatchObject({
      currentValue: 'gpt-5',
      options: [{ value: 'gpt-5', name: 'gpt-5' }],
    });
  });
});

describe('parameters', () => {
  test('start from a variant that is not max mode where the model has one', () => {
    const variant = (value: string, extra: object = {}) => ({
      displayName: value,
      params: [{ id: 'mode', value }],
      ...extra,
    });
    const starting = (...variants: ReturnType<typeof variant>[]) =>
      startingParams({ id: 'grok', displayName: 'Grok', variants });

    // The default is max mode: the first that is not.
    expect(
      starting(
        variant('max', { isDefault: true, isMaxMode: true }),
        variant('max2', { isMaxMode: true }),
        variant('fast'),
        variant('slow'),
      ),
    ).toEqual({ mode: 'fast' });
    // The default is not max mode: the default.
    expect(
      starting(variant('fast'), variant('slow', { isDefault: true })),
    ).toEqual({ mode: 'slow' });
    // Nothing but max mode: the default, else the first.
    expect(
      starting(
        variant('max', { isMaxMode: true }),
        variant('max2', { isDefault: true, isMaxMode: true }),
      ),
    ).toEqual({ mode: 'max2' });
    expect(starting(variant('max', { isMaxMode: true }))).toEqual({
      mode: 'max',
    });
  });

  test('start from the isDefault variant, else the first', () => {
    expect(startingParams(GPT)).toEqual({
      reasoning: 'medium',
      context: '200k',
    });
    expect(
      startingParams({
        ...GPT,
        variants: GPT.variants!.map(({ isDefault: _, ...rest }) => rest),
      }),
    ).toEqual({ reasoning: 'low', context: '200k' });
    expect(startingParams(COMPOSER)).toEqual({});
  });

  test('one option per parameter, named by its displayName else id', () => {
    const choice = choose({ mode: 'default' }, MODELS, true, 'model', 'gpt-5')!;

    expect(configOptions(choice, MODELS, true).slice(2)).toEqual([
      {
        id: 'parameter:reasoning',
        name: 'Reasoning',
        type: 'select',
        currentValue: 'medium',
        options: [
          { value: 'low', name: 'Low' },
          { value: 'medium', name: 'medium' },
        ],
      },
      {
        id: 'parameter:context',
        name: 'context',
        category: 'model_config',
        _meta: { 'chord/parameter': 'context' },
        type: 'select',
        currentValue: '200k',
        options: [
          { value: '200k', name: '200k' },
          { value: '1m', name: '1m' },
        ],
      },
    ]);
  });

  test("Cursor's recorded ids are marked, any other id is not", () => {
    const cursor: ModelListItem = {
      id: 'gpt-5.5',
      displayName: 'GPT-5.5',
      parameters: [
        { id: 'context', values: [{ value: '256k' }, { value: '500k' }] },
        {
          id: 'reasoning_effort',
          values: ['low', 'medium', 'high', 'xhigh'].map((value) => ({
            value,
          })),
        },
        { id: 'fast', values: [{ value: 'false' }, { value: 'true' }] },
        { id: 'thinking', values: [{ value: 'on' }] },
      ],
      variants: [
        {
          displayName: 'GPT-5.5',
          isDefault: true,
          params: [
            { id: 'context', value: '256k' },
            { id: 'reasoning_effort', value: 'medium' },
            { id: 'fast', value: 'false' },
            { id: 'thinking', value: 'on' },
          ],
        },
      ],
    };
    const choice = choose(
      { mode: 'default' },
      [cursor],
      true,
      'model',
      'gpt-5.5',
    )!;
    const marks = configOptions(choice, [cursor], true)
      .slice(2)
      .map(({ id, category, _meta }) => ({ id, category, _meta }));

    expect(marks).toEqual([
      {
        id: 'parameter:context',
        category: 'model_config',
        _meta: { 'chord/parameter': 'context' },
      },
      {
        id: 'parameter:reasoning_effort',
        category: 'thought_level',
        _meta: undefined,
      },
      {
        id: 'parameter:fast',
        category: 'model_config',
        _meta: { 'chord/parameter': 'fast' },
      },
      { id: 'parameter:thinking', category: undefined, _meta: undefined },
    ]);
  });

  test('offer only values some variant holds with the others chosen', () => {
    const at1m = choose(
      choose({ mode: 'default' }, MODELS, true, 'model', 'gpt-5')!,
      MODELS,
      false,
      'parameter:context',
      '1m',
    )!;

    expect(at1m.model).toEqual({
      id: 'gpt-5',
      params: { reasoning: 'medium', context: '1m' },
    });
    expect(values(at1m, 'parameter:reasoning', false)).toEqual([
      'medium',
      'high',
    ]);
    expect(
      choose(at1m, MODELS, false, 'parameter:reasoning', 'low'),
    ).toBeUndefined();
    expect(
      selection(choose(at1m, MODELS, false, 'parameter:reasoning', 'high')!),
    ).toEqual({
      id: 'gpt-5',
      params: [
        { id: 'reasoning', value: 'high' },
        { id: 'context', value: '1m' },
      ],
    });
  });

  test("a model change replaces the old model's parameters with the new one's", () => {
    const gpt = choose({ mode: 'plan' }, MODELS, true, 'model', 'gpt-5')!;
    const composer = choose(gpt, MODELS, true, 'model', 'composer-2')!;

    expect(composer).toEqual({
      mode: 'plan',
      model: { id: 'composer-2', params: {} },
    });
    expect(optionIds(composer)).toEqual(['mode', 'model']);
    expect(choose(composer, MODELS, true, 'model', CURSORS_DEFAULT)).toEqual({
      mode: 'plan',
    });
  });

  test("Cursor's default has no parameter options and no selection", () => {
    expect(optionIds({ mode: 'default' })).toEqual(['mode', 'model']);
    expect(selection({ mode: 'default' })).toBeUndefined();
  });
});

test('a selection given back by the SDK becomes the choice it was', () => {
  expect(
    chosen({ id: 'gpt-5', params: [{ id: 'reasoning', value: 'high' }] }),
  ).toEqual({ id: 'gpt-5', params: { reasoning: 'high' } });
  expect(
    selection({ mode: 'default', model: { id: 'composer-2', params: {} } }),
  ).toEqual({
    id: 'composer-2',
  });
});

describe('a selection the SDK reports without some parameter', () => {
  const partial: Choice = { mode: 'default', model: chosen({ id: 'gpt-5' }) };

  test('shows no option for the missing parameters', () => {
    expect(optionIds(partial, false)).toEqual(['mode', 'model']);
  });

  test('choosing the same model starts its parameters', () => {
    const seeded = choose(partial, MODELS, false, 'model', 'gpt-5')!;

    expect(seeded.model).toEqual({
      id: 'gpt-5',
      params: { reasoning: 'medium', context: '200k' },
    });
    expect(optionIds(seeded, false)).toEqual([
      'mode',
      'model',
      'parameter:reasoning',
      'parameter:context',
    ]);
  });

  test('choosing the same model with every parameter changes nothing', () => {
    const full = choose(partial, MODELS, false, 'model', 'gpt-5')!;
    const high = choose(full, MODELS, false, 'parameter:context', '1m')!;

    expect(choose(high, MODELS, false, 'model', 'gpt-5')).toBe(high);
  });
});

test('choose refuses an option or value not offered', () => {
  expect(
    choose({ mode: 'default' }, MODELS, true, 'mode', 'yolo'),
  ).toBeUndefined();
  expect(
    choose({ mode: 'default' }, MODELS, true, 'speed', 'fast'),
  ).toBeUndefined();
  expect(
    choose({ mode: 'default' }, MODELS, true, 'parameter:reasoning', 'high'),
  ).toBeUndefined();
});

describe('CHD-622 tester: config roundtrip boundaries', () => {
  test('model choice and partial reselection use the entire non-max variant without changing Cursor default', () => {
    const model: ModelListItem = {
      ...GPT,
      variants: [
        {
          displayName: 'Max default',
          isDefault: true,
          isMaxMode: true,
          params: [
            { id: 'reasoning', value: 'high' },
            { id: 'context', value: '1m' },
          ],
        },
        {
          displayName: 'Standard',
          isMaxMode: false,
          params: [
            { id: 'reasoning', value: 'low' },
            { id: 'context', value: '200k' },
          ],
        },
      ],
    };
    const initial: Choice = { mode: 'plan' };
    const partial: Choice = {
      mode: 'plan',
      model: { id: GPT.id, params: { reasoning: 'high' } },
    };
    const expected: Choice = {
      mode: 'plan',
      model: { id: GPT.id, params: { reasoning: 'low', context: '200k' } },
    };

    expect(choose(initial, [model], true, 'model', GPT.id)).toEqual(expected);
    expect(choose(partial, [model], false, 'model', GPT.id)).toEqual(expected);
    expect(choose(initial, [model], true, 'model', CURSORS_DEFAULT)).toEqual({
      mode: 'plan',
    });
    expect(selection(initial)).toBeUndefined();
  });

  test('reselecting a partially reported model replaces all parameters with one valid default', () => {
    const partial: Choice = Object.freeze({
      mode: 'plan',
      model: Object.freeze({
        id: 'gpt-5',
        params: Object.freeze({ reasoning: 'high' }),
      }),
    });

    expect(optionIds(partial, false)).toEqual([
      'mode',
      'model',
      'parameter:reasoning',
    ]);
    expect(choose(partial, MODELS, false, 'model', 'gpt-5')).toEqual({
      mode: 'plan',
      model: {
        id: 'gpt-5',
        params: { reasoning: 'medium', context: '200k' },
      },
    });
    expect(partial.model?.params).toEqual({ reasoning: 'high' });
  });

  test('every offered parameter change stays within a published variant', () => {
    for (const variant of GPT.variants ?? []) {
      const current: Choice = {
        mode: 'plan',
        model: chosen({ id: GPT.id, params: variant.params }),
      };

      for (const parameter of GPT.parameters ?? []) {
        for (const value of values(
          current,
          `parameter:${parameter.id}`,
          false,
        )) {
          const next = choose(
            current,
            MODELS,
            false,
            `parameter:${parameter.id}`,
            value,
          )!;

          expect(next.mode).toBe('plan');
          expect(
            GPT.variants?.some((candidate) =>
              candidate.params.every(
                (pair) => next.model?.params[pair.id] === pair.value,
              ),
            ),
          ).toBe(true);
          expect(current.model).toEqual(
            chosen({ id: GPT.id, params: variant.params }),
          );
        }
      }
    }
  });

  test('an unlisted SDK selection roundtrips without inventing parameters or losing them', () => {
    const reported = {
      id: 'vendor-model:v1',
      params: [{ id: 'unlisted:parameter', value: 'value/one' }],
    };
    const current: Choice = { mode: 'default', model: chosen(reported) };

    expect(configOptions(current, [], false).map((each) => each.id)).toEqual([
      'mode',
      'model',
    ]);
    expect(choose(current, [], false, 'model', reported.id)).toBe(current);
    expect(selection(current)).toEqual(reported);
    expect(choose(current, [], false, 'mode', 'plan')?.model).toBe(
      current.model,
    );
  });
});

describe('CHD-626 tester: parameter recognition boundaries', () => {
  test('display names, near matches and inherited object keys never mark an unknown id', () => {
    const ids = ['Fast', 'context_size', 'effort', 'constructor', '__proto__'];
    const model: ModelListItem = {
      id: 'unknown-parameters',
      displayName: 'Unknown parameters',
      parameters: ids.map((id) => ({
        id,
        displayName: 'Fast context reasoning_effort',
        values: [{ value: 'on' }],
      })),
      variants: [
        {
          displayName: 'Default',
          params: ids.map((id) => ({ id, value: 'on' })),
        },
      ],
    };
    const choice = choose(
      { mode: 'default' },
      [model],
      true,
      'model',
      model.id,
    )!;
    const parameters = configOptions(choice, [model], true).slice(2);

    expect(parameters.map((each) => each.id)).toEqual(
      ids.map((id) => `parameter:${id}`),
    );

    for (const parameter of parameters) {
      expect(parameter).not.toHaveProperty('category');
      expect(parameter).not.toHaveProperty('_meta');
    }
  });

  test('dependent choices retain marks while refusing a value outside the current variants', () => {
    const model: ModelListItem = {
      id: 'dependent',
      displayName: 'Dependent',
      parameters: [
        {
          id: 'reasoning_effort',
          values: [{ value: 'low' }, { value: 'high' }],
        },
        { id: 'fast', values: [{ value: 'false' }, { value: 'true' }] },
      ],
      variants: [
        {
          displayName: 'Low',
          params: [
            { id: 'reasoning_effort', value: 'low' },
            { id: 'fast', value: 'false' },
          ],
        },
        {
          displayName: 'High',
          params: [
            { id: 'reasoning_effort', value: 'high' },
            { id: 'fast', value: 'false' },
          ],
        },
        {
          displayName: 'Fast',
          params: [
            { id: 'reasoning_effort', value: 'low' },
            { id: 'fast', value: 'true' },
          ],
        },
      ],
    };
    const initial = choose({ mode: 'plan' }, [model], true, 'model', model.id)!;
    const fast = choose(initial, [model], true, 'parameter:fast', 'true')!;
    const parameters = configOptions(fast, [model], true).slice(2);

    expect(parameters).toEqual([
      {
        id: 'parameter:reasoning_effort',
        name: 'reasoning_effort',
        category: 'thought_level',
        type: 'select',
        currentValue: 'low',
        options: [{ value: 'low', name: 'low' }],
      },
      {
        id: 'parameter:fast',
        name: 'fast',
        category: 'model_config',
        _meta: { 'chord/parameter': 'fast' },
        type: 'select',
        currentValue: 'true',
        options: [
          { value: 'false', name: 'false' },
          { value: 'true', name: 'true' },
        ],
      },
    ]);
    expect(
      choose(fast, [model], true, 'parameter:reasoning_effort', 'high'),
    ).toBeUndefined();

    const back = choose(fast, [model], true, 'model', CURSORS_DEFAULT)!;

    expect(back).toEqual({ mode: 'plan' });
    expect(configOptions(back, [model], true).map((each) => each.id)).toEqual([
      'mode',
      'model',
    ]);
    expect(selection(back)).toBeUndefined();
  });
});

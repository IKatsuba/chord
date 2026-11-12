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

  test('one option per parameter, named by its displayName else id, no category', () => {
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
        type: 'select',
        currentValue: '200k',
        options: [
          { value: '200k', name: '200k' },
          { value: '1m', name: '1m' },
        ],
      },
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

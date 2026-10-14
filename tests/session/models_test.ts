import { expect, test } from 'bun:test';
import type { SessionConfigOption } from '@agentclientprotocol/sdk';
import { modelName, modelsFrom, sameModels } from '../../src/session/models.ts';

const MODEL_OPTION: SessionConfigOption = {
  id: 'model',
  name: 'Model',
  category: 'model',
  type: 'select',
  currentValue: 'small',
  options: [
    { value: 'large', name: 'Large' },
    {
      value: 'small',
      name: 'Small',
    },
  ],
};

const BOTH = {
  available: [
    { id: 'large', name: 'Large' },
    { id: 'small', name: 'Small' },
  ],
  current: 'small',
};

test("the models are the agent's model config option's, by their names", () => {
  expect(modelsFrom([MODEL_OPTION], undefined)).toStrictEqual(BOTH);
});

test('an agent with no model option offers the models session/new gave the older way', () => {
  const legacy = {
    currentModelId: 'small',
    availableModels: [
      { modelId: 'large', name: 'Large' },
      {
        modelId: 'small',
        name: 'Small',
      },
    ],
  };

  expect(modelsFrom([], legacy)).toStrictEqual(BOTH);
  // The option wins where an agent sends both, as ACP asks of it.
  expect(
    modelsFrom([{ ...MODEL_OPTION, currentValue: 'large' }], legacy)?.current,
  ).toStrictEqual('large');
});

test('a model the agent gives no name goes by its id', () => {
  expect(
    modelsFrom([], {
      currentModelId: 'large',
      availableModels: [{ modelId: 'large', name: '' }],
    }),
  ).toStrictEqual({
    available: [{ id: 'large', name: 'large' }],
    current: 'large',
  });
});

test('an agent that advertises no model offers none', () => {
  expect(modelsFrom([], undefined)).toStrictEqual(undefined);
  expect(modelsFrom([], { models: 'not a model state' })).toStrictEqual(
    undefined,
  );
  expect(
    modelsFrom([], { currentModelId: '', availableModels: [] }),
  ).toStrictEqual(undefined);
});

test('the model named is the one in use, by its name or else its id', () => {
  const available = [{ id: 'large', name: 'Large' }];

  expect(modelName({ available, current: 'large' })).toStrictEqual('Large');
  expect(modelName({ available, current: 'other' })).toStrictEqual('other');
  expect(modelName({ available })).toStrictEqual(undefined);
  expect(modelName(undefined)).toStrictEqual(undefined);
});

test('two readings are the same when they list and use the same', () => {
  const a = { available: [{ id: 'large', name: 'Large' }], current: 'large' };

  expect(sameModels(a, { ...a, available: [...a.available] })).toStrictEqual(
    true,
  );
  expect(sameModels(a, { ...a, current: 'small' })).toStrictEqual(false);
  expect(sameModels(a, { available: [], current: 'large' })).toStrictEqual(
    false,
  );
  expect(sameModels(a, undefined)).toStrictEqual(false);
  expect(sameModels(undefined, undefined)).toStrictEqual(true);
});

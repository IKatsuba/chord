import { expect, test } from 'bun:test';
import {
  optionsFromConfigOptions,
  sameOptions,
  valueName,
} from '../../src/session/config.ts';

const EFFORT = {
  id: 'effort',
  name: 'Effort',
  category: 'thought_level',
  type: 'select',
  currentValue: 'medium',
  options: [
    { value: 'low', name: 'Low' },
    { value: 'medium', name: 'Medium', description: 'The default' },
    { value: 'high', name: 'High' },
  ],
};

const READ_EFFORT = {
  id: 'effort',
  name: 'Effort',
  values: [
    { value: 'low', name: 'Low' },
    { value: 'medium', name: 'Medium' },
    { value: 'high', name: 'High' },
  ],
  current: 'medium',
};

test('the options are the selects other than the mode and the model', () => {
  expect(
    optionsFromConfigOptions([
      {
        id: 'model',
        name: 'Model',
        category: 'model',
        type: 'select',
        currentValue: 'a',
        options: [{ value: 'a', name: 'A' }],
      },
      // Either is known by its id when it has no category.
      {
        id: 'mode',
        name: 'Mode',
        type: 'select',
        currentValue: 'default',
        options: [{ value: 'default', name: 'Default' }],
      },
      {
        id: 'permissions',
        name: 'Permissions',
        category: 'mode',
        type: 'select',
        currentValue: 'ask',
        options: [{ value: 'ask', name: 'Ask' }],
      },
      EFFORT,
      // A kind with no list of values has nothing to pick.
      { id: 'fast', name: 'Fast', type: 'boolean', currentValue: false },
    ]),
  ).toStrictEqual([READ_EFFORT]);
});

test('grouped values are listed group by group, and an empty select is left out', () => {
  expect(
    optionsFromConfigOptions([
      {
        id: 'style',
        name: 'Style',
        type: 'select',
        currentValue: 'b',
        options: [
          { group: 'one', name: 'One', options: [{ value: 'a', name: 'A' }] },
          { group: 'two', name: 'Two', options: [{ value: 'b', name: 'B' }] },
        ],
      },
      {
        id: 'none',
        name: 'None',
        type: 'select',
        currentValue: '',
        options: [],
      },
    ]),
  ).toStrictEqual([
    {
      id: 'style',
      name: 'Style',
      values: [
        { value: 'a', name: 'A' },
        { value: 'b', name: 'B' },
      ],
      current: 'b',
    },
  ]);
});

test('a record with no config options offers none', () => {
  expect(optionsFromConfigOptions(undefined)).toStrictEqual([]);
  expect(optionsFromConfigOptions({})).toStrictEqual([]);
  expect(optionsFromConfigOptions([])).toStrictEqual([]);
});

test("a value reads as the agent's name for it, or itself", () => {
  expect(valueName(READ_EFFORT, 'high')).toStrictEqual('High');
  expect(valueName(READ_EFFORT, 'max')).toStrictEqual('max');
});

test('two readings are the same when every option is set the same way', () => {
  expect(sameOptions([READ_EFFORT], [{ ...READ_EFFORT }])).toStrictEqual(true);
  expect(sameOptions([], [])).toStrictEqual(true);
  expect(sameOptions([READ_EFFORT], [])).toStrictEqual(false);
  expect(
    sameOptions([READ_EFFORT], [{ ...READ_EFFORT, current: 'high' }]),
  ).toStrictEqual(false);
  expect(
    sameOptions(
      [READ_EFFORT],
      [
        {
          ...READ_EFFORT,
          values: READ_EFFORT.values.slice(1),
        },
      ],
    ),
  ).toStrictEqual(false);
});

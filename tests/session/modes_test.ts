import { expect, test } from 'bun:test';
import { modesFrom, nextMode, sameModes } from '../../src/session/modes.ts';

const CLAUDE = [
  { id: 'default', name: 'Manual' },
  { id: 'acceptEdits', name: 'Accept edits' },
  { id: 'plan', name: 'Plan' },
  { id: 'auto', name: 'Auto' },
];

test("shift+tab walks the agent's modes in its order and wraps", () => {
  expect(nextMode(CLAUDE, 'default')).toStrictEqual('acceptEdits');
  expect(nextMode(CLAUDE, 'acceptEdits')).toStrictEqual('plan');
  expect(nextMode(CLAUDE, 'plan')).toStrictEqual('auto');
  expect(nextMode(CLAUDE, 'auto')).toStrictEqual('default');
});

test('from a mode the agent does not list, shift+tab goes to its first', () => {
  expect(nextMode(CLAUDE, undefined)).toStrictEqual('default');
  expect(nextMode(CLAUDE, 'dontAsk')).toStrictEqual('default');
});

test('with fewer than two modes there is nowhere to go', () => {
  expect(nextMode([], undefined)).toStrictEqual(undefined);
  expect(
    nextMode([{ id: 'default', name: 'Default' }], 'default'),
  ).toStrictEqual(undefined);
});

test("the modes are read from the agent's mode config option", () => {
  expect(
    modesFrom([
      {
        id: 'model',
        name: 'Model',
        category: 'model',
        type: 'select',
        currentValue: 'large',
        options: [{ value: 'large', name: 'Large' }],
      },
      {
        id: 'mode',
        name: 'Mode',
        category: 'mode',
        type: 'select',
        currentValue: 'plan',
        options: CLAUDE.map(({ id, name }) => ({ value: id, name })),
      },
    ]),
  ).toStrictEqual({ available: CLAUDE, current: 'plan' });
});

test('grouped mode options are walked group by group', () => {
  const modes = modesFrom([
    {
      id: 'permissions',
      name: 'Permissions',
      category: 'mode',
      type: 'select',
      currentValue: 'b',
      options: [
        { group: 'safe', name: 'Safe', options: [{ value: 'a', name: 'A' }] },
        { group: 'fast', name: 'Fast', options: [{ value: 'b', name: 'B' }] },
      ],
    },
  ]);

  expect(modes?.available.map((mode) => mode.id)).toStrictEqual(['a', 'b']);
  expect(nextMode(modes!.available, modes!.current)).toStrictEqual('a');
});

test('an agent with no mode option offers the modes session/new gave the older way', () => {
  expect(
    modesFrom([], {
      currentModeId: 'ask',
      availableModes: [
        { id: 'ask', name: 'Ask' },
        {
          id: 'code',
          name: 'Code',
        },
      ],
    }),
  ).toStrictEqual({
    available: [
      { id: 'ask', name: 'Ask' },
      { id: 'code', name: 'Code' },
    ],
    current: 'ask',
  });
});

test('an agent with no mode option offers no modes', () => {
  expect(modesFrom(undefined)).toStrictEqual(undefined);
  expect(modesFrom([])).toStrictEqual(undefined);
  expect(
    modesFrom([
      {
        id: 'thinking',
        name: 'Thinking',
        type: 'boolean',
        currentValue: true,
      },
    ]),
  ).toStrictEqual(undefined);
});

test('two readings are the same when every mode and the current are', () => {
  const one = { available: CLAUDE, current: 'plan' };

  expect(
    sameModes(one, { available: [...CLAUDE], current: 'plan' }),
  ).toStrictEqual(true);
  expect(sameModes(one, { available: CLAUDE, current: 'auto' })).toStrictEqual(
    false,
  );
  expect(
    sameModes(one, { available: CLAUDE.slice(1), current: 'plan' }),
  ).toStrictEqual(false);
  expect(sameModes(undefined, undefined)).toStrictEqual(true);
  expect(sameModes(one, undefined)).toStrictEqual(false);
});

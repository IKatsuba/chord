import { expect, test } from 'bun:test';
import type { SessionConfigOption } from '@agentclientprotocol/sdk';
import { effortsFrom } from '../../src/session/efforts.ts';

/** Codex's adapter's option, as 2.2.2 sends it. */
const REASONING: SessionConfigOption = {
  id: 'reasoning_effort',
  name: 'Reasoning effort',
  category: 'thought_level',
  type: 'select',
  currentValue: 'medium',
  options: [
    { value: 'low', name: 'Low' },
    { value: 'medium', name: 'Medium' },
    { value: 'high', name: '' },
  ],
};

test("the efforts are the thought_level option's values, under any id, a missing name read as the id", () => {
  expect(effortsFrom([REASONING])).toStrictEqual({
    option: 'reasoning_effort',
    available: [
      { id: 'low', name: 'Low' },
      { id: 'medium', name: 'Medium' },
      { id: 'high', name: 'high' },
    ],
    current: 'medium',
  });
});

test('an option is not taken for effort by its id or name alone', () => {
  expect(
    effortsFrom([
      { ...REASONING, id: 'effort', name: 'Effort', category: null },
    ]),
  ).toStrictEqual(undefined);
  expect(effortsFrom([{ ...REASONING, category: '_effort' }])).toStrictEqual(
    undefined,
  );
});

test('grouped efforts are read group by group, and none offered is no efforts', () => {
  expect(
    effortsFrom([
      {
        ...REASONING,
        options: [
          { group: 'a', name: 'A', options: [{ value: 'low', name: 'Low' }] },
          { group: 'b', name: 'B', options: [{ value: 'high', name: 'High' }] },
        ],
      },
    ])?.available.map((effort) => effort.id),
  ).toStrictEqual(['low', 'high']);
  expect(effortsFrom([{ ...REASONING, options: [] }])).toStrictEqual(undefined);
  expect(effortsFrom(undefined)).toStrictEqual(undefined);
});

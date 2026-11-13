import { describe, expect, test } from 'bun:test';
import type { SessionConfigOption } from '@agentclientprotocol/sdk/unstable';
import {
  choiceNote,
  effortStep,
  type ModelChoice,
  pendingText,
} from '../../src/session/choice.ts';

const efforts = (
  id: string,
  name: string,
  current: string,
  values: readonly string[],
): SessionConfigOption => ({
  id,
  name,
  category: 'thought_level',
  type: 'select',
  currentValue: current,
  options: values.map((value) => ({
    value,
    name: value[0]!.toUpperCase() + value.slice(1),
  })),
});
const MODEL: SessionConfigOption = {
  id: 'model',
  name: 'Model',
  category: 'model',
  type: 'select',
  currentValue: 'opus',
  options: [
    { value: 'opus', name: 'Opus 5.5' },
    { value: 'haiku', name: 'Haiku 5.5' },
  ],
};
/** The large model's set: low…max. */
const OPUS = [
  MODEL,
  efforts('effort', 'Effort', 'medium', ['low', 'medium', 'high', 'max']),
];
/** The small model's set after a switch: low and medium only. */
const HAIKU = [
  { ...MODEL, currentValue: 'haiku' },
  efforts('effort', 'Effort', 'medium', ['low', 'medium']),
];

const HIGH = { option: 'effort', value: 'high', name: 'High' };
const HAIKU_MODEL = { id: 'haiku', name: 'Haiku 5.5' };
const toHaiku: ModelChoice = { model: HAIKU_MODEL, effort: HIGH };

describe('the effort step', () => {
  test('carried to the new model by value id when its set lists it', () => {
    const carried = [
      { ...MODEL, currentValue: 'haiku' },
      efforts('reasoning', 'Reasoning', 'low', ['low', 'high']),
    ];

    expect(effortStep(toHaiku, carried)).toEqual({
      option: 'reasoning',
      value: 'high',
      name: 'Reasoning',
    });
  });

  test('not asked for when the new set does not list it', () => {
    expect(effortStep(toHaiku, HAIKU)).toBeUndefined();
    expect(effortStep(toHaiku, [MODEL])).toBeUndefined();
  });

  test('none when the effort was not moved', () => {
    expect(effortStep({ model: HAIKU_MODEL }, OPUS)).toBeUndefined();
  });

  test('on the same model, only while the option asked is still the effort and lists the value', () => {
    expect(effortStep({ effort: HIGH }, OPUS)).toEqual({
      option: 'effort',
      value: 'high',
      name: 'Effort',
    });
    expect(effortStep({ effort: HIGH }, HAIKU)).toBeUndefined();
    expect(
      effortStep({ effort: HIGH }, [
        MODEL,
        efforts('thinking', 'Thinking', 'high', ['high']),
      ]),
    ).toBeUndefined();
  });
});

describe('the rows', () => {
  test('pending: the model switching, else the effort setting', () => {
    expect(pendingText(toHaiku, OPUS)).toBe('Switching to Haiku 5.5…');
    expect(pendingText({ effort: HIGH }, OPUS)).toBe('Setting Effort to High…');
  });

  test('model refused: stop, its reason', () => {
    expect(
      choiceNote(
        toHaiku,
        { model: 'refused', reason: 'no access' },
        OPUS,
        'Opus 5.5',
      ),
    ).toEqual({
      text: 'Could not switch to Haiku 5.5: no access',
      failed: true,
    });
  });

  test('model switched alone, and with its effort', () => {
    expect(
      choiceNote(
        { model: HAIKU_MODEL },
        { model: 'switched', effort: 'unmoved' },
        HAIKU,
        'Opus 5.5',
      ),
    ).toEqual({ text: 'Switched to Haiku 5.5', failed: false });

    const carried = [
      { ...MODEL, currentValue: 'haiku' },
      efforts('effort', 'Effort', 'high', ['low', 'high']),
    ];

    expect(
      choiceNote(
        toHaiku,
        { model: 'switched', effort: 'set' },
        carried,
        'Opus 5.5',
      ),
    ).toEqual({ text: 'Switched to Haiku 5.5 · High effort', failed: false });
  });

  test('value not offered: the model stays and one note says both', () => {
    expect(
      choiceNote(
        toHaiku,
        { model: 'switched', effort: 'not_offered' },
        HAIKU,
        'Opus 5.5',
      ),
    ).toEqual({
      text: 'Switched to Haiku 5.5; it offers no High effort, it is on Medium.',
      failed: false,
    });
    expect(
      choiceNote(
        toHaiku,
        { model: 'switched', effort: 'not_offered' },
        [MODEL],
        'Opus 5.5',
      ).text,
    ).toBe('Switched to Haiku 5.5; it offers no High effort.');
  });

  test('effort refused after the switch', () => {
    expect(
      choiceNote(
        toHaiku,
        {
          model: 'switched',
          effort: 'refused',
          option: 'Effort',
          reason: 'busy',
        },
        HAIKU,
        'Opus 5.5',
      ),
    ).toEqual({
      text: 'Switched to Haiku 5.5; could not set Effort to High: busy',
      failed: true,
    });
  });

  test('legacy session/set_model: an answer with no options reads as none offered', () => {
    expect(effortStep(toHaiku, undefined)).toBeUndefined();
    expect(
      choiceNote(
        toHaiku,
        { model: 'switched', effort: 'not_offered' },
        undefined,
        'Opus 5.5',
      ).text,
    ).toBe('Switched to Haiku 5.5; it offers no High effort.');
  });

  test("effort alone: set, refused, or taken away before Enter, by the option's own name", () => {
    const high = [
      MODEL,
      efforts('reasoning_effort', 'Reasoning effort', 'high', ['high']),
    ];

    expect(
      choiceNote(
        { effort: { ...HIGH, option: 'reasoning_effort' } },
        { effort: 'set' },
        high,
        'Opus 5.5',
      ).text,
    ).toBe('Reasoning effort set to High');
    expect(
      choiceNote(
        { effort: HIGH },
        { effort: 'refused', option: 'Effort', reason: 'busy' },
        OPUS,
        'Opus 5.5',
      ),
    ).toEqual({ text: 'Could not set Effort to High: busy', failed: true });
    expect(
      choiceNote({ effort: HIGH }, { effort: 'not_offered' }, HAIKU, 'Opus 5.5')
        .text,
    ).toBe(
      'High effort was not sent: Opus 5.5 no longer offers it; it is on Medium.',
    );
  });
});

describe('CHD-626 tester: choice value identity and changing sets', () => {
  test('matching labels never substitute for the requested value id', () => {
    const renamed: SessionConfigOption = {
      ...efforts('thinking', 'Thinking', 'slow', ['slow', 'fast']),
      type: 'select',
      currentValue: 'slow',
      options: [
        { value: 'slow', name: 'Low' },
        { value: 'fast', name: 'High' },
      ],
    };

    expect(effortStep(toHaiku, [renamed])).toBeUndefined();
    expect(
      effortStep({ ...toHaiku, effort: { ...HIGH, value: 'fast' } }, [renamed]),
    ).toEqual({ option: 'thinking', value: 'fast', name: 'Thinking' });
  });

  test('grouped duplicate labels preserve the exact case-sensitive id across model changes', () => {
    const grouped: SessionConfigOption = {
      id: 'reasoning',
      name: 'Reasoning',
      category: 'thought_level',
      type: 'select',
      currentValue: 'low',
      options: [
        {
          group: 'efforts',
          name: 'Efforts',
          options: [
            { value: 'high', name: 'Same' },
            { value: 'High', name: 'Same' },
          ],
        },
      ],
    };

    for (const value of ['high', 'High']) {
      expect(
        effortStep({ model: HAIKU_MODEL, effort: { ...HIGH, value } }, [
          grouped,
        ])?.value,
      ).toBe(value);
    }

    expect(
      effortStep({ model: HAIKU_MODEL, effort: { ...HIGH, value: 'HIGH' } }, [
        grouped,
      ]),
    ).toBeUndefined();
  });

  test('an empty first effort set does not borrow a value from a later effort option', () => {
    const empty = efforts('first', 'First', 'low', []);
    const later = efforts('later', 'Later', 'high', ['high']);

    expect(effortStep(toHaiku, [empty, later])).toBeUndefined();
    expect(effortStep({ effort: HIGH }, [later])).toBeUndefined();
  });

  test('outcomes report the agent-confirmed value rather than the requested display name', () => {
    const confirmed = [efforts('effort', 'Effort', 'low', ['low', 'high'])];

    expect(
      choiceNote(
        toHaiku,
        { model: 'switched', effort: 'set' },
        confirmed,
        'Opus',
      ),
    ).toEqual({ text: 'Switched to Haiku 5.5 · Low effort', failed: false });
    expect(
      choiceNote({ effort: HIGH }, { effort: 'set' }, confirmed, 'Opus'),
    ).toEqual({ text: 'Effort set to Low', failed: false });
    expect(
      choiceNote({ effort: HIGH }, { effort: 'not_offered' }, [], 'Opus'),
    ).toEqual({
      text: 'High effort was not sent: Opus no longer offers it.',
      failed: false,
    });
  });
});

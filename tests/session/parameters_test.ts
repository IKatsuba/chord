import { describe, expect, test } from 'bun:test';
import type { SessionConfigOption } from '@agentclientprotocol/sdk/unstable';
import stringWidth from 'string-width';
import { findAgent } from '../../src/agents.ts';
import {
  effortById,
  fastOption,
  fastToggled,
  hasOtherOptions,
  modelConfigOptions,
  settingsLine,
} from '../../src/session/parameters.ts';

const select = (
  id: string,
  name: string,
  category: string | undefined,
  currentValue: string,
  values: readonly (readonly [string, string])[],
  _meta?: Record<string, unknown>,
): SessionConfigOption => ({
  id,
  name,
  ...(category === undefined ? {} : { category }),
  ...(_meta === undefined ? {} : { _meta }),
  type: 'select',
  currentValue,
  options: values.map(([value, valueName]) => ({ value, name: valueName })),
});
const ON_OFF = [
  ['off', 'Off'],
  ['on', 'On'],
] as const;

/** Claude's adapter's set, as 0.106.0 sends it for Opus. */
const CLAUDE: SessionConfigOption[] = [
  select('mode', 'Mode', 'mode', 'default', [['default', 'Default']]),
  select('model', 'Model', 'model', 'default', [
    ['default', 'Default (recommended)'],
    ['haiku', 'Haiku 5.5'],
  ]),
  select('effort', 'Effort', 'thought_level', 'medium', [
    ['low', 'Low'],
    ['medium', 'Medium'],
    ['high', 'High'],
    ['xhigh', 'Xhigh'],
    ['max', 'Max'],
  ]),
  select('fast', 'Fast', 'model_config', 'off', ON_OFF),
  select('ultracode', 'Ultracode', 'model_config', 'off', ON_OFF),
  select('agent', 'Agent', undefined, 'none', [['none', 'None']]),
];

/** Codex's adapter's set, as 2.6.0 sends it. */
const CODEX: SessionConfigOption[] = [
  select('model', 'Model', 'model', 'gpt-5.5', [['gpt-5.5', 'GPT-5.5']]),
  select('reasoning_effort', 'Reasoning effort', 'thought_level', 'high', [
    ['low', 'Low'],
    ['high', 'High'],
  ]),
  select('fast-mode', 'Fast mode', 'model_config', 'off', ON_OFF),
];

/** fx 0.0.14's: provider and model both `model`, fast and ultrafast too. */
const FX: SessionConfigOption[] = [
  select('provider', 'Provider', 'model', 'openai', [['openai', 'OpenAI']]),
  select('model', 'Model', 'model', 'gpt', [['gpt', 'GPT']]),
  select('mode', 'Mode', 'mode', 'auto', [['auto', 'Auto']]),
  select('effort', 'Effort', 'thought_level', 'auto', [
    ['auto', 'Auto'],
    ['low', 'Low'],
  ]),
  select('fast', 'Fast', 'model', 'false', [
    ['false', 'Off'],
    ['true', 'On'],
  ]),
];

/** cursor-cloud's on a model with Cursor's recorded parameters (CHD-626). */
const CURSOR: SessionConfigOption[] = [
  select('mode', 'Mode', 'mode', 'default', [['default', 'Agent']]),
  select('model', 'Model', 'model', 'gpt-5.5', [
    ['cursor-default', "Cursor's default"],
    ['gpt-5.5', 'GPT-5.5'],
  ]),
  select(
    'parameter:context',
    'Context',
    'model_config',
    '256k',
    [
      ['256k', '256k'],
      ['500k', '500k'],
    ],
    { 'chord/parameter': 'context' },
  ),
  select('parameter:reasoning_effort', 'Reasoning', 'thought_level', 'medium', [
    ['low', 'low'],
    ['medium', 'medium'],
  ]),
  select(
    'parameter:fast',
    'Fast',
    'model_config',
    'false',
    [
      ['false', 'false'],
      ['true', 'true'],
    ],
    { 'chord/parameter': 'fast' },
  ),
];

/** cursor-cloud's on Cursor's default: the mode and the model only. */
const CURSORS_DEFAULT = CURSOR.slice(0, 2);

const line = (
  options: unknown,
  more: {
    highlighted?: string;
    pending?: string;
    width?: number;
    keys?: string | null;
  } = {},
) => settingsLine({ options, inUse: 'Opus 5.5', width: 116, ...more });

describe('the options the settings line shows', () => {
  test('model_config options, in the agent order, under any id', () => {
    expect(modelConfigOptions(CLAUDE).map((option) => option.id)).toEqual([
      'fast',
      'ultracode',
    ]);
    expect(modelConfigOptions(CODEX).map((option) => option.id)).toEqual([
      'fast-mode',
    ]);
    expect(modelConfigOptions(CURSOR).map((option) => option.id)).toEqual([
      'parameter:context',
      'parameter:fast',
    ]);
  });

  test("fx's fast, of category model, is none of them", () => {
    expect(modelConfigOptions(FX)).toEqual([]);
    expect(hasOtherOptions(FX)).toBe(false);
  });

  test('others are what /config has beyond the mode, model, effort and model_config', () => {
    expect(hasOtherOptions(CLAUDE)).toBe(true);
    expect(hasOtherOptions(CODEX)).toBe(false);
    expect(hasOtherOptions(CURSOR)).toBe(false);
  });
});

describe('the fast option', () => {
  test("by the agent entry's recorded id", () => {
    expect(fastOption(CLAUDE, findAgent('claude')?.fastOption)?.id).toBe(
      'fast',
    );
    expect(fastOption(CODEX, findAgent('codex')?.fastOption)?.id).toBe(
      'fast-mode',
    );
  });

  test('by _meta["chord/parameter"], from any agent', () => {
    expect(findAgent('cursor-cloud')?.fastOption).toBeUndefined();
    expect(fastOption(CURSOR)?.id).toBe('parameter:fast');
  });

  test('never by its id or name alone', () => {
    expect(fastOption(CLAUDE)).toBeUndefined();
    expect(fastOption(FX)).toBeUndefined();
    expect(fastOption(CURSORS_DEFAULT)).toBeUndefined();
  });
});

describe('the settings line', () => {
  test('M1: the effort, each model_config option and the /config tail', () => {
    expect(line(CLAUDE)).toEqual({
      text: 'Medium effort  ←/→ to adjust · Fast  Off · Ultracode  Off · /config for all settings',
      dim: false,
      narrow: false,
    });
  });

  test('M2: a moved effort waits marked', () => {
    expect(line(CLAUDE, { pending: 'high' })?.text).toBe(
      'High effort •  ←/→ to adjust · Fast  Off · Ultracode  Off · /config for all settings',
    );
    expect(line(CLAUDE, { pending: 'medium' })?.text).toStartWith(
      'Medium effort  ←/→',
    );
  });

  test('N1: the narrow text where the wide one does not fit', () => {
    expect(line(CLAUDE, { width: 76 })?.text).toBe(
      'Medium effort ←/→ · Fast Off · Ultracode Off · /config…',
    );
    expect(line(CLAUDE, { width: 76 })?.narrow).toBe(true);
    expect(line(CLAUDE)?.narrow).toBe(false);
  });

  test('then cut with … from the right, the effort last to go', () => {
    expect(line(CLAUDE, { width: 30 })?.text).toBe(
      'Medium effort ←/→ · Fast Off …',
    );
    expect(line(CLAUDE, { width: 10 })?.text).toBe('Medium ef…');
  });

  test('M3 and N2: another model highlighted, the effort moved', () => {
    expect(
      line(CLAUDE, { highlighted: 'Haiku 5.5', pending: 'high' })?.text,
    ).toBe(
      'High effort •  ←/→ to adjust · asked for once Haiku 5.5 is in use, if it offers High',
    );
    expect(
      line(CLAUDE, { highlighted: 'Haiku 5.5', pending: 'high', width: 76 })
        ?.text,
    ).toBe('High effort • ←/→ · asked for on Haiku 5.5, if offered');
  });

  test("another model highlighted, the effort not moved: the effort alone, not the model in use's values", () => {
    expect(line(CLAUDE, { highlighted: 'Haiku 5.5' })?.text).toBe(
      'Medium effort  ←/→ to adjust',
    );
  });

  test('Codex-, fx- and cursor-cloud-shaped sets, by their own names', () => {
    expect(line(CODEX)?.text).toBe(
      'High effort  ←/→ to adjust · Fast mode  Off',
    );
    expect(line(FX)?.text).toBe('Auto effort  ←/→ to adjust');
    expect(line(CURSOR)?.text).toBe(
      'medium effort  ←/→ to adjust · Context  256k · Fast  false',
    );
  });

  test("M4 and N3: Cursor's default has nothing to change, dim", () => {
    expect(
      settingsLine({
        options: CURSORS_DEFAULT,
        inUse: "Cursor's default",
        width: 76,
      }),
    ).toEqual({
      text: "Cursor's default has no effort or settings to change",
      dim: true,
      narrow: false,
    });
  });

  test('a model with only uncategorised options: the /config tail alone', () => {
    const options = [
      ...CURSORS_DEFAULT,
      select('inference', 'Inference', undefined, 'fast', [['fast', 'Fast']]),
    ];

    expect(line(options)).toEqual({
      text: '/config for all settings',
      dim: false,
      narrow: false,
    });
  });

  test('M5: models the older way and nothing else, no line', () => {
    expect(line([])).toBeUndefined();
    expect(line(undefined)).toBeUndefined();
    expect(
      line([select('mode', 'Mode', 'mode', 'default', [['default', 'D']])]),
    ).toBeUndefined();
  });

  test('the keys as bound: one direction alone, or none and no cue', () => {
    expect(line(CLAUDE, { keys: 'h' })?.text).toStartWith(
      'Medium effort  h to adjust · Fast  Off',
    );
    expect(line(CLAUDE, { keys: null })?.text).toBe(
      'Medium effort · Fast  Off · Ultracode  Off · /config for all settings',
    );
    expect(line(CLAUDE, { keys: null, width: 60 })?.text).toBe(
      'Medium effort · Fast Off · Ultracode Off · /config…',
    );
  });

  test('a moved effort the agent no longer lists shows the one in use, unmarked', () => {
    expect(line(CLAUDE, { pending: 'gone' })?.text).toStartWith(
      'Medium effort  ←/→',
    );
  });
});

describe('CHD-626 tester: parameter reader boundaries', () => {
  test('metadata takes precedence over a recorded id; other metadata never guesses fast', () => {
    const recorded = select(
      'known-fast',
      'Fast',
      'model_config',
      'off',
      ON_OFF,
    );
    const marked = select('speed', 'Speed', 'model_config', 'on', ON_OFF, {
      'chord/parameter': 'fast',
    });

    expect(fastOption([recorded, marked], 'known-fast')?.id).toBe('speed');

    for (const marker of ['context', 'Fast', true, null, { fast: true }]) {
      const other = select('speed', 'Fast', 'model_config', 'on', ON_OFF, {
        'chord/parameter': marker,
      });

      expect(fastOption([other])).toBeUndefined();
      expect(fastOption([other, recorded], 'known-fast')?.id).toBe(
        'known-fast',
      );
    }
  });

  test('grouped model settings preserve value order and fall back to an unlisted current id', () => {
    const grouped: SessionConfigOption = {
      id: 'context',
      name: 'Context',
      category: 'model_config',
      type: 'select',
      currentValue: 'server-selected',
      options: [
        {
          group: 'Small',
          name: 'Small',
          options: [{ value: '256k', name: 'Standard' }],
        },
        {
          group: 'Large',
          name: 'Large',
          options: [{ value: '500k', name: 'Extended' }],
        },
      ],
    };
    const options = [...CURSORS_DEFAULT, grouped];

    expect(modelConfigOptions(options)).toEqual([
      {
        id: 'context',
        name: 'Context',
        current: 'server-selected',
        values: [
          { value: '256k', name: 'Standard' },
          { value: '500k', name: 'Extended' },
        ],
      },
    ]);
    expect(hasOtherOptions(options)).toBe(false);
    expect(line(options)?.text).toBe('Context  server-selected');
  });

  test('only the first thought-level option is the effort; another remains reachable through config', () => {
    const extra = select(
      'secondary',
      'Secondary',
      'thought_level',
      'on',
      ON_OFF,
    );

    expect(hasOtherOptions([...CODEX, extra])).toBe(true);
    expect(line([...CODEX, extra])?.text).toBe(
      'High effort  ←/→ to adjust · Fast mode  Off · /config for all settings',
    );
    expect(line([...CODEX, extra], { pending: 'on' })?.text).not.toContain('•');
  });

  test('wide characters and combining marks fit each positive terminal width', () => {
    const options = [
      ...CURSORS_DEFAULT,
      select('effort', 'Effort', 'thought_level', 'high', [
        ['high', '高 e\u0301'],
        ['low', '低'],
      ]),
      select('context', '窗口', 'model_config', 'large', [['large', '長い値']]),
    ];

    for (const width of [1, 2, 3, 8, 20, 76, 116]) {
      for (const more of [
        {},
        { pending: 'low', highlighted: '模型 e\u0301' },
      ]) {
        const result = line(options, { ...more, width })!;

        expect(stringWidth(result.text)).toBeLessThanOrEqual(width);
        expect(result.text).not.toContain('\n');
      }

      const empty = settingsLine({
        options: CURSORS_DEFAULT,
        inUse: '模型 e\u0301',
        width,
      })!;

      expect(stringWidth(empty.text)).toBeLessThanOrEqual(width);
      expect(empty.dim).toBe(true);
    }
  });
});

describe("/fast's toggle and /effort's id (CHD-626)", () => {
  test("the other value of an on/off select, by the agent's ids", () => {
    const fast = fastOption(CLAUDE, 'fast')!;

    expect(fastToggled(fast)).toEqual({ value: 'on', name: 'On' });
    expect(fastToggled({ ...fast, current: 'on' })).toEqual({
      value: 'off',
      name: 'Off',
    });
    expect(fastToggled(fastOption(CURSOR)!)).toEqual({
      value: 'true',
      name: 'true',
    });
  });

  test('none where the value in use is not listed once, or the two are the same', () => {
    const fast = fastOption(CLAUDE, 'fast')!;

    expect(fastToggled({ ...fast, current: 'auto' })).toBeUndefined();
    expect(
      fastToggled({
        ...fast,
        values: [
          { value: 'off', name: 'Off' },
          { value: 'off', name: 'Off too' },
        ],
      }),
    ).toBeUndefined();
  });

  test('none for an option of more or fewer than two values', () => {
    const fast = fastOption(CLAUDE, 'fast')!;

    expect(
      fastToggled({
        ...fast,
        values: [...fast.values, { value: 'x', name: 'X' }],
      }),
    ).toBeUndefined();
    expect(fastToggled({ ...fast, values: [fast.values[0]!] })).toBeUndefined();
  });

  test('an effort by its id exactly, never by its name', () => {
    expect(effortById(CLAUDE, 'high')).toEqual({
      option: 'effort',
      value: 'high',
      name: 'High',
    });
    expect(effortById(CLAUDE, 'High')).toBeUndefined();
    expect(effortById(CLAUDE, 'ultra')).toBeUndefined();
    expect(effortById(CURSORS_DEFAULT, 'high')).toBeUndefined();
  });
});

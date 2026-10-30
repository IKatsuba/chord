import { expect, test } from 'bun:test';
import {
  agentColour,
  background,
  colorFgBg,
  paletteOf,
  PALETTES,
  PLAIN,
  resolveTheme,
  THEME_SETTINGS,
  themeChoices,
  themeLabel,
  themePickerLayout,
} from '../../../src/ui/theme/theme.ts';

/** WCAG's contrast ratio of two `#rrggbb` colours. */
function contrast(a: string, b: string): number {
  const luminance = (hex: string) => {
    const [r, g, b] = [1, 3, 5].map((at) => {
      const channel = parseInt(hex.slice(at, at + 2), 16) / 255;

      return channel <= 0.03928
        ? channel / 12.92
        : ((channel + 0.055) / 1.055) ** 2.4;
    });

    return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!;
  };

  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);

  return (light! + 0.05) / (dark! + 0.05);
}

test("the terminal's answer decides, then COLORFGBG, then dark", () => {
  expect(background(false, '15;0')).toStrictEqual({
    tone: 'light',
    from: 'terminal',
  });
  expect(background(true, '0;15')).toStrictEqual({
    tone: 'dark',
    from: 'terminal',
  });
  expect(background(null, '0;15')).toStrictEqual({
    tone: 'light',
    from: 'COLORFGBG',
  });
  expect(background(null, '15;default;0')).toStrictEqual({
    tone: 'dark',
    from: 'COLORFGBG',
  });
  expect(background(null, undefined)).toStrictEqual({
    tone: 'dark',
    from: 'default',
  });
  expect(colorFgBg('0;7')).toStrictEqual('light');
  expect(colorFgBg('7;8')).toStrictEqual('dark');
  expect(colorFgBg('default')).toStrictEqual(undefined);
});

test('auto comes to the background; a named theme is itself', () => {
  const light = { tone: 'light', from: 'terminal' } as const;

  expect(resolveTheme('auto', light)).toStrictEqual('light');
  expect(resolveTheme('dark', light)).toStrictEqual('dark');
  expect(resolveTheme('light-ansi', light)).toStrictEqual('light-ansi');
});

test('Auto says what it found and where', () => {
  expect(themeLabel('auto', { tone: 'light', from: 'terminal' })).toStrictEqual(
    'Auto (light, from the terminal)',
  );
  expect(themeLabel('auto', { tone: 'dark', from: 'default' })).toStrictEqual(
    'Auto (dark: the terminal did not say)',
  );
});

test("/theme lists Claude Code's seven ids, the one in use marked", () => {
  const choices = themeChoices('light', { tone: 'dark', from: 'terminal' });

  expect(choices.map(({ value }) => value)).toStrictEqual([...THEME_SETTINGS]);
  expect(choices.map(({ label }) => label)).toStrictEqual([
    'Auto (dark, from the terminal)',
    'Dark',
    'Light ✔',
    'Dark, colour-blind friendly',
    'Light, colour-blind friendly',
    "Dark, the terminal's 16 colours",
    "Light, the terminal's 16 colours",
  ]);
  expect(choices.filter(({ current }) => current).length).toStrictEqual(1);
});

test('CHD-70: the light diff is pale tints under dark text', () => {
  const { tint } = PALETTES.light.diff;

  expect(tint).toStrictEqual({
    added: '#dcf5e0',
    removed: '#fde2e2',
    text: '#1f2328',
  });
  expect(
    contrast(tint!.added, '#ffffff') < 1.3,
    'a wash, not a block',
  ).toBeTruthy();
  expect(contrast(tint!.text, tint!.added) > 12).toBeTruthy();
  expect(contrast(PALETTES.light.diff.added!, tint!.added) >= 4.5).toBeTruthy();
});

test('every light colour reads on white, every dark one on black', () => {
  const roles = [
    'accent',
    'permission',
    'inlineCode',
    'link',
    'bash',
    'plan',
    'edits',
    'auto',
    'error',
    'warning',
    'success',
  ] as const;

  for (const [name, ground] of [
    ['light', '#ffffff'],
    ['dark', '#000000'],
  ] as const) {
    const palette = PALETTES[name];

    for (const role of roles) {
      expect(
        contrast(palette[role]!, ground) >= 4.5,
        `${name} ${role} on ${ground}`,
      ).toBeTruthy();
    }

    for (const tone of Object.values(palette.code!.terminal)) {
      expect(
        contrast(tone!, ground) >= 4.5,
        `${name} ${tone} on ${ground}`,
      ).toBeTruthy();
    }

    for (const tint of [palette.diff.tint!.added, palette.diff.tint!.removed]) {
      for (const tone of Object.values(palette.code!.tint!)) {
        expect(
          contrast(tone!, tint) >= 4.1,
          `${name} ${tone} on ${tint}`,
        ).toBeTruthy();
      }
    }
  }
});

test('the 16-colour themes have no tint and no hex', () => {
  for (const name of ['dark-ansi', 'light-ansi'] as const) {
    const palette = PALETTES[name];

    expect(palette.diff.tint).toStrictEqual(undefined);
    expect(!JSON.stringify(palette).includes('#')).toBeTruthy();
  }

  expect(PALETTES['dark-ansi'].diff.added).toStrictEqual('greenBright');
  expect(PALETTES['light-ansi'].diff.removed).toStrictEqual('red');
});

test('colour-blind themes move only the diff, off red and green', () => {
  const { diff, ...rest } = PALETTES['light-daltonized'];
  const { diff: _, ...light } = PALETTES.light;

  expect(rest).toStrictEqual(light);
  expect(diff.tint?.added).toStrictEqual('#dbeeff');
  expect(diff.tint?.removed).toStrictEqual('#fde8d4');
});

test('no colour leaves no role painted', () => {
  expect(paletteOf('light', false)).toStrictEqual(PLAIN);
  expect(paletteOf('light', true)).toStrictEqual(PALETTES.light);
});

test("/theme fits a 24-row window's room with its sample; a shorter room drops it, then choices, keeping the title and hint (CHD-545)", () => {
  // 40 rows and 24 rows, five of them under the layer.
  expect(themePickerLayout(35)).toStrictEqual({ choices: 7, sample: true });
  expect(themePickerLayout(19)).toStrictEqual({ choices: 7, sample: true });
  expect(themePickerLayout(18)).toStrictEqual({ choices: 7, sample: true });
  expect(themePickerLayout(17)).toStrictEqual({ choices: 7, sample: false });
  expect(themePickerLayout(14)).toStrictEqual({ choices: 7, sample: false });
  // Fewer: the row that counts the hidden ones takes one of theirs.
  expect(themePickerLayout(13)).toStrictEqual({ choices: 5, sample: false });
  expect(themePickerLayout(9)).toStrictEqual({ choices: 1, sample: false });
  // Not one: the list goes.
  expect(themePickerLayout(7)).toStrictEqual({ choices: 0, sample: false });
});

test("every theme gives a session's agents six colours, and no colour leaves them none", () => {
  for (const [name, palette] of Object.entries(PALETTES)) {
    expect(palette.agents?.length, name).toStrictEqual(6);
  }

  expect(agentColour(PALETTES.dark, 0)).toStrictEqual('#6cb6ff');
  expect(agentColour(PALETTES.light, 7)).toStrictEqual('#7a3fd6');
  expect(agentColour(PALETTES['dark-ansi'], 5)).toStrictEqual('redBright');
  expect(agentColour(PLAIN, 0)).toStrictEqual(undefined);
  expect(agentColour(PALETTES.dark, undefined)).toStrictEqual(undefined);
});

test('every theme paints a selection, plain included: slate on dark, pale on light (CHD-172)', () => {
  expect(PALETTES.dark.selection).toStrictEqual('ansi256(66)');
  expect(PALETTES['dark-daltonized'].selection).toStrictEqual('ansi256(66)');
  expect(PALETTES['dark-ansi'].selection).toStrictEqual('ansi256(66)');
  expect(PALETTES.light.selection).toStrictEqual('ansi256(152)');
  expect(PALETTES['light-daltonized'].selection).toStrictEqual('ansi256(152)');
  expect(PALETTES['light-ansi'].selection).toStrictEqual('ansi256(152)');
  expect(paletteOf('light', false).selection).toStrictEqual('ansi256(66)');
});

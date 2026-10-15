/**
 * chord's themes: every colour it paints, by role, in each theme; which theme
 * `auto` comes to on the terminal's background; and `/theme`'s choices. Plain
 * and dim text are never painted, so they stay the terminal's own whatever
 * the theme. The values and their contrast ratios are docs/design/CHD-87.md's.
 */
import type { MarkStops } from '../header/mark_rows.ts';
import type { PickerChoice } from '../pickers/picker.ts';

/** The `theme` setting's values: Claude Code's ids for its own themes. */
export const THEME_SETTINGS = [
  'auto',
  'dark',
  'light',
  'dark-daltonized',
  'light-daltonized',
  'dark-ansi',
  'light-ansi',
] as const;

export type ThemeSetting = (typeof THEME_SETTINGS)[number];

/** A theme that is drawn; `auto` comes to one of these. */
export type ThemeName = Exclude<ThemeSetting, 'auto'>;

/**
 * A token's colour in each of the classes a highlight sheet tells apart, as
 * a hex or one of the terminal's named colours; a class left out is drawn in
 * the text's own colour.
 */
export interface Tones {
  readonly keyword?: string;
  readonly string?: string;
  readonly number?: string;
  readonly comment?: string;
  readonly title?: string;
  readonly type?: string;
  readonly name?: string;
  readonly meta?: string;
}

/** Code's tokens on the terminal's background, and on a diff's tint if any. */
export interface CodeTones {
  readonly terminal: Tones;
  readonly tint?: Tones;
}

/**
 * A changed row's background, the sign on it and the code's plain text,
 * which is set rather than left to the terminal, since the tint is the
 * theme's and the terminal's text may not read on it.
 */
export interface DiffTint {
  readonly added: string;
  readonly removed: string;
  readonly text: string;
}

/**
 * The startup header's mark: its gradient where the terminal has 256 colours
 * or more, and the one tone it takes in 16, where a two-tone split would read
 * as a fault. A theme for the terminal's 16 colours has no stops.
 */
export interface MarkTones {
  readonly stops?: MarkStops;
  readonly tone: string;
}

/**
 * Every colour a theme paints. A role left out is not painted: under
 * NO_COLOR none is.
 */
export interface Palette {
  /** The working line, the scroll rule's news, a running call's `⏺`. */
  readonly accent?: string;
  /** The permission prompt and the pickers: border, title, `❯`, highlight. */
  readonly permission?: string;
  readonly inlineCode?: string;
  readonly link?: string;
  /** Bash mode's `!`, its border and its status. */
  readonly bash?: string;
  /** The modes on the status line. */
  readonly plan?: string;
  readonly edits?: string;
  readonly auto?: string;
  readonly error?: string;
  readonly warning?: string;
  readonly success?: string;
  /**
   * A session's long-lived agents, each taking the next in the order they
   * opened, round again past the last: its name in the list under the
   * prompt, the box's border while it is picked, and its messages' arrows.
   * `main` takes none. CHD-167's six: blue, purple, cyan, green, yellow,
   * pink.
   */
  readonly agents?: readonly string[];
  /** The startup header's mark. */
  readonly mark?: MarkTones;
  /**
   * The background of the cells a drag selects. Every theme has one, plain
   * included: without it OpenTUI swaps a text's colours, and the terminal's
   * own foreground swapped draws nothing (CHD-172).
   */
  readonly selection: string;
  /**
   * Code's tokens on the terminal's background and on a diff's tint; none
   * where code is not coloured.
   */
  readonly code?: CodeTones;
  /**
   * A changed row: with `tint`, on its background with `added` and `removed`
   * for the signs; without, the whole row in `added` or `removed`, as
   * `git diff` draws it.
   */
  readonly diff: {
    readonly added?: string;
    readonly removed?: string;
    readonly tint?: DiffTint;
  };
}

/** Tokens where the background is dark; today's set, made for black. */
const DARK_CODE: Tones = {
  keyword: '#d7a6ff',
  string: '#f2d38a',
  number: '#ffb07a',
  comment: '#8f96a0',
  title: '#8cc8ff',
  type: '#7fe0e8',
  name: '#f5a3c7',
  meta: '#b4bcff',
};

/** The same hues darkened to 4.5:1 or more on white. */
const LIGHT_CODE: Tones = {
  keyword: '#8250df',
  string: '#7d5200',
  number: '#a94800',
  comment: '#6e7781',
  title: '#0b5cad',
  type: '#00727a',
  name: '#b0306f',
  meta: '#4a50c4',
};

/** A step darker again, for 4.3:1 or more on every pale tint. */
const LIGHT_ON_TINT: Tones = {
  keyword: '#7a45d0',
  string: '#6e4900',
  number: '#9a4200',
  comment: '#626b75',
  title: '#0a55a0',
  type: '#00666d',
  name: '#a32a66',
  meta: '#4248b5',
};

/** The selection's background on a dark terminal, and where colour is off. */
const SLATE = 'ansi256(66)';

const DARK: Palette = {
  accent: '#47e7a5',
  permission: '#b1b9f9',
  inlineCode: '#b1b9f9',
  link: '#8cc8ff',
  bash: '#fd5db1',
  plan: '#48968c',
  edits: '#af87ff',
  auto: '#ffd700',
  error: '#ff6b80',
  warning: '#ffc107',
  success: '#4eba65',
  // Lighter than the accent, so a name never sinks into the border.
  agents: ['#6cb6ff', '#c49cff', '#56d4dd', '#7ccf7f', '#e8c95a', '#f59ac6'],
  mark: { stops: ['#89f5b3', '#47e7a5', '#15c7a2'], tone: 'greenBright' },
  // Claude Code's slate, `48;5;66`.
  selection: SLATE,
  code: { terminal: DARK_CODE, tint: DARK_CODE },
  diff: {
    added: '#86e08a',
    removed: '#ff8e8e',
    tint: { added: '#1f3b24', removed: '#4a1f27', text: '#e4e4e4' },
  },
};

const LIGHT: Palette = {
  accent: '#147d55',
  permission: '#4a5ae0',
  inlineCode: '#4a5ae0',
  link: '#0b5cad',
  bash: '#d1006f',
  plan: '#006b66',
  edits: '#7a3fd6',
  auto: '#8a6100',
  error: '#c4162a',
  warning: '#8a5a00',
  success: '#2c7a39',
  // 4.5:1 or more on white, the code tones' own hues.
  agents: ['#0a5bc4', '#7a3fd6', '#00727a', '#2c7a39', '#8a6100', '#b0306f'],
  // 3.6:1 or more on white; the middle is Chorded's own colour for the mark
  // on a light background.
  mark: { stops: ['#1e9a5e', '#147d55', '#0a5e57'], tone: 'green' },
  selection: 'ansi256(152)',
  code: { terminal: LIGHT_CODE, tint: LIGHT_ON_TINT },
  // CHD-70: pale washes, where the dark theme's tints are blocks on white.
  diff: {
    added: '#17702f',
    removed: '#c4162a',
    tint: { added: '#dcf5e0', removed: '#fde2e2', text: '#1f2328' },
  },
};

/**
 * The 16-colour themes: the terminal's own palette decides each colour.
 * Without a tint, which taken from 16 is a loud block, a changed row is drawn
 * green or red with no tokens.
 */
function sixteen(bright: boolean): Palette {
  const tone = (name: string) => (bright ? `${name}Bright` : name);

  return {
    accent: tone('yellow'),
    permission: tone('blue'),
    inlineCode: tone('blue'),
    link: tone('blue'),
    bash: tone('magenta'),
    plan: tone('cyan'),
    edits: tone('magenta'),
    auto: tone('yellow'),
    error: tone('red'),
    warning: tone('yellow'),
    success: tone('green'),
    agents: ['blue', 'magenta', 'cyan', 'green', 'yellow', 'red'].map(tone),
    mark: { tone: tone('green') },
    // A slate still, where the sixteen have none that reads under text.
    selection: bright ? SLATE : 'ansi256(152)',
    code: {
      terminal: {
        keyword: tone('magenta'),
        string: tone('yellow'),
        number: tone('yellow'),
        comment: 'gray',
        title: tone('blue'),
        type: tone('cyan'),
        meta: tone('blue'),
      },
    },
    diff: { added: tone('green'), removed: tone('red') },
  };
}

/** The palette of each theme there is. */
export const PALETTES: Record<ThemeName, Palette> = {
  dark: DARK,
  light: LIGHT,
  // For red–green colour blindness only the diff changes: blue and orange,
  // the pair that stays apart, and the signs still say which is which.
  'dark-daltonized': {
    ...DARK,
    diff: {
      added: '#6cb6ff',
      removed: '#ffb15c',
      tint: { added: '#16304f', removed: '#4a2a12', text: '#e4e4e4' },
    },
  },
  'light-daltonized': {
    ...LIGHT,
    diff: {
      added: '#0a5bc4',
      removed: '#a34a00',
      tint: { added: '#dbeeff', removed: '#fde8d4', text: '#1f2328' },
    },
  },
  'dark-ansi': sixteen(true),
  'light-ansi': sixteen(false),
};

/**
 * What NO_COLOR, or a terminal that takes no colour, leaves: nothing but the
 * selection, which would not show at all without one.
 */
export const PLAIN: Palette = { selection: SLATE, diff: {} };

/** A child's colour, by its place among the session's children. */
export function agentColour(
  palette: Palette,
  colour: number | undefined,
): string | undefined {
  const all = palette.agents;

  return colour === undefined || all === undefined || all.length === 0
    ? undefined
    : all[colour % all.length];
}

/** The palette `name` is drawn in, or none at all where colour is off. */
export function paletteOf(name: ThemeName, colour: boolean): Palette {
  return colour ? PALETTES[name] : PLAIN;
}

/** The terminal's background as `auto` reads it, and what said so. */
export interface Background {
  readonly tone: 'dark' | 'light';
  /** The terminal's answer, `COLORFGBG`, or neither and dark by default. */
  readonly from: 'terminal' | 'COLORFGBG' | 'default';
}

/**
 * `COLORFGBG`'s background, where rxvt and Konsole set it: `7` or `15` last
 * is light, any other number dark; none when it is not set or says no number.
 */
export function colorFgBg(
  value: string | undefined,
): 'dark' | 'light' | undefined {
  const last = value?.split(';').at(-1)?.trim() ?? '';

  if (!/^\d+$/.test(last)) {
    return undefined;
  }

  return last === '7' || last === '15' ? 'light' : 'dark';
}

/**
 * The background from the terminal's answer to OSC 11, else `COLORFGBG`,
 * else dark, which is how chord looked before it asked.
 */
export function background(
  dark: boolean | null,
  colorfgbg: string | undefined,
): Background {
  if (dark !== null) {
    return { tone: dark ? 'dark' : 'light', from: 'terminal' };
  }

  const tone = colorFgBg(colorfgbg);

  return tone === undefined
    ? { tone: 'dark', from: 'default' }
    : { tone, from: 'COLORFGBG' };
}

/** The theme drawn for `setting`: `auto` is the background's. */
export function resolveTheme(
  setting: ThemeSetting,
  found: Background,
): ThemeName {
  return setting === 'auto' ? found.tone : setting;
}

const LABELS: Record<ThemeName, string> = {
  dark: 'Dark',
  light: 'Light',
  'dark-daltonized': 'Dark, colour-blind friendly',
  'light-daltonized': 'Light, colour-blind friendly',
  'dark-ansi': "Dark, the terminal's 16 colours",
  'light-ansi': "Light, the terminal's 16 colours",
};

/** A theme as `/theme` lists it; Auto says what it found and where. */
export function themeLabel(setting: ThemeSetting, found: Background): string {
  if (setting !== 'auto') {
    return LABELS[setting];
  }

  switch (found.from) {
    case 'terminal':
      return `Auto (${found.tone}, from the terminal)`;
    case 'COLORFGBG':
      return `Auto (${found.tone}, from COLORFGBG)`;
    case 'default':
      return 'Auto (dark: the terminal did not say)';
  }
}

/** A theme as a sentence names it: `Auto`, `Light`. */
export function themeName(setting: ThemeSetting): string {
  return setting === 'auto' ? 'Auto' : LABELS[setting];
}

/** `/theme`'s rows, the setting in use marked as `/model` marks its model. */
export function themeChoices(
  current: ThemeSetting,
  found: Background,
): PickerChoice[] {
  return THEME_SETTINGS.map((setting) => ({
    key: setting,
    label: `${themeLabel(setting, found)}${setting === current ? ' ✔' : ''}`,
    value: setting,
    current: setting === current,
  }));
}

/** Whether `value` is one of the setting's ids. */
export function isThemeSetting(value: string): value is ThemeSetting {
  return (THEME_SETTINGS as readonly string[]).includes(value);
}

/** The sample `/theme` draws under its choices, in the theme highlighted. */
export const THEME_SAMPLE = {
  path: 'greet.js',
  old: 'function greet(name) {\n  return "hello " + name;\n}\n',
  new: 'function greet(name) {\n  return `hello, ${name}`;\n}\n',
} as const;

/**
 * Where `/theme` sits in a window `rows` tall: how many choices it shows,
 * whether the diff sample fits, and whether there is a row for the gap above
 * it. Around it the window keeps its header, the prompt box with its gap and
 * the status line; a window too short for everything drops the gap, then the
 * sample, then choices.
 */
export function themePickerLayout(rows: number): {
  readonly choices: number;
  readonly sample: boolean;
  readonly gap: boolean;
} {
  const room = rows - 6;
  // Border, title, the line under it and the gap before the choices, the
  // gap before the hint and the hint itself.
  const frame = 7;
  const count = THEME_SETTINGS.length;
  const withSample = frame + count + 4;

  if (room > withSample) {
    return { choices: count, sample: true, gap: true };
  }

  if (room === withSample) {
    return { choices: count, sample: true, gap: false };
  }

  return {
    choices: Math.max(3, Math.min(count, room - frame)),
    sample: false,
    gap: room > frame + count,
  };
}

/**
 * What chord's components hand OpenTUI's `<text>` and `<span>`: the
 * palette's colours as OpenTUI takes them, the props every text is drawn
 * with, and a string's own SGR (markdansi's, emphasize's, the diff's) read
 * into runs a `<span>` each.
 */
import { RGBA, TextAttributes } from '@opentui/core';
import { parse } from '@ansi-tools/parser';

/**
 * chalk's names for the terminal's sixteen colours, which chord's palette
 * uses beside hexes: each stays the terminal's own, by its index.
 */
const NAMED: Record<string, number> = {
  black: 0,
  red: 1,
  green: 2,
  yellow: 3,
  blue: 4,
  magenta: 5,
  cyan: 6,
  white: 7,
  gray: 8,
  grey: 8,
  blackBright: 8,
  redBright: 9,
  greenBright: 10,
  yellowBright: 11,
  blueBright: 12,
  magentaBright: 13,
  cyanBright: 14,
  whiteBright: 15,
};

const ANSI256 = /^ansi256\((\d{1,3})\)$/;

/**
 * A palette colour as OpenTUI takes it: a hex, one of chalk's names, or
 * chalk's `ansi256(n)`, which the header's mark is painted in on a
 * 256-colour terminal and which OpenTUI's hex reader takes for magenta.
 */
export function colour(name: string): RGBA;
export function colour(name: string | undefined): RGBA | undefined;

export function colour(name: string | undefined): RGBA | undefined {
  if (name === undefined) {
    return undefined;
  }

  const index = NAMED[name] ?? ANSI256.exec(name)?.[1];

  return index === undefined
    ? RGBA.fromHex(name)
    : RGBA.fromIndex(Number(index));
}

/** A palette colour as a `<text>`'s or a `<span>`'s `fg`; none for none. */
export function fg(name: string | undefined): { fg?: RGBA } {
  const value = colour(name);

  return value === undefined ? {} : { fg: value };
}

/**
 * Every `<text>`'s: the terminal's own foreground, where OpenTUI's is a hard
 * white, and not selectable. It wraps at words, OpenTUI's default.
 *
 * Not selectable is for chord's furniture: gutters, the mark, line numbers,
 * the fold marker, the status line, lists and boxes. A drag that crosses it
 * copies none of it, and two renderables on a row are glued with no gap in
 * a copy, which is why a gutter must not come along (CHD-172). What the
 * agent or the person wrote adds `app/context.ts`'s `useSelectable()`
 * on top, so a new text is furniture until someone decides otherwise.
 */
export const TEXT = {
  fg: RGBA.defaultForeground(),
  selectable: false,
} as const;

/**
 * A `<text>` that wraps beside a gutter and takes the rest of the row.
 * OpenTUI measures a text in a row as no taller than the room above it
 * until the row settles its width, so a reply longer than the transcript's
 * view was laid out as tall as the view, and the view stopped following
 * the stream (CHD-311).
 */
export const FILL = { ...TEXT, flexGrow: 1 } as const;

/**
 * A `<text>` laid out into its rows already, by `wrapLine`, beside a gutter:
 * OpenTUI wraps nothing, so a row as wide as its room never gains an empty
 * one under it, and nothing is cut.
 */
export const ROWS = { ...FILL, wrapMode: 'none' } as const;

/** A `<text>` that stays one row, cut at its edge by OpenTUI. */
export const CUT = { ...TEXT, wrapMode: 'none', truncate: true } as const;

/**
 * A dim border's colour. OpenTUI's border takes a colour and no attributes,
 * so dim is a fixed grey: palette colour 8 is the background in some themes
 * (Solarized Dark's base03), and 244 reads on dark and on light, as Claude
 * Code's prompt border does.
 */
export const DIM_BORDER = RGBA.fromIndex(244);

/** The dim attribute, which most of chord's quieter text is drawn in. */
export const DIM = TextAttributes.DIM;

export const BOLD = TextAttributes.BOLD;

/** A run of a string in one style; what it leaves unset its text gives. */
export interface Run {
  readonly text: string;
  readonly fg?: RGBA | undefined;
  readonly bg?: RGBA | undefined;
  readonly attributes: number;
}

/**
 * A string as runs, its SGR read into each run's style: @ansi-tools/parser
 * finds the escapes, and every one that is not SGR is left out, as OpenTUI
 * draws cells and would put an escape's bytes in them as text. A reset goes
 * back to nothing set, which a `<span>` takes from the text around it.
 */
export function runs(text: string): Run[] {
  if (!text.includes('\x1b')) {
    return [{ text, attributes: 0 }];
  }

  const found: Run[] = [];
  let style: Style = { attributes: 0 };

  for (const code of parse(text)) {
    if (code.type === 'TEXT') {
      found.push({ text: code.raw, ...style });
    } else if (code.type === 'CSI' && code.command === 'm') {
      style = sgr(code.raw, style);
    }
  }

  return found;
}

interface Style {
  readonly fg?: RGBA | undefined;
  readonly bg?: RGBA | undefined;
  readonly attributes: number;
}

const ON: Record<number, number> = {
  1: TextAttributes.BOLD,
  2: TextAttributes.DIM,
  3: TextAttributes.ITALIC,
  4: TextAttributes.UNDERLINE,
  7: TextAttributes.INVERSE,
  9: TextAttributes.STRIKETHROUGH,
};
const OFF: Record<number, number> = {
  22: TextAttributes.BOLD | TextAttributes.DIM,
  23: TextAttributes.ITALIC,
  24: TextAttributes.UNDERLINE,
  27: TextAttributes.INVERSE,
  29: TextAttributes.STRIKETHROUGH,
};

/**
 * One SGR applied to `style`, read from the escape as it was sent. The
 * parser's own parameters are not read, as it writes `38;2;r;g;b` in
 * T.416's longer form when nothing follows it and leaves it be when
 * something does.
 */
function sgr(raw: string, style: Style): Style {
  // Between the introducer, `ESC [` or its one-byte form, and the `m`.
  const sent = raw.slice(raw.startsWith('\x9b') ? 1 : 2, -1);
  // Each `;` separates a parameter; a `:` its parts, T.416's colour form.
  const groups = (sent === '' ? '0' : sent)
    .split(';')
    .map((group) => group.split(':').map((part) => Number(part) || 0));
  let { fg, bg, attributes } = style;

  for (let at = 0; at < groups.length; at++) {
    const [code = 0, ...parts] = groups[at]!;

    if (code === 0) {
      fg = undefined;
      bg = undefined;
      attributes = 0;
    } else if (ON[code] !== undefined) {
      // `4:0` is underline off, as T.416 says it with a part.
      attributes =
        code === 4 && parts[0] === 0
          ? attributes & ~TextAttributes.UNDERLINE
          : attributes | ON[code];
    } else if (OFF[code] !== undefined) {
      attributes &= ~OFF[code];
    } else if (code >= 30 && code <= 37) {
      fg = RGBA.fromIndex(code - 30);
    } else if (code >= 90 && code <= 97) {
      fg = RGBA.fromIndex(code - 90 + 8);
    } else if (code >= 40 && code <= 47) {
      bg = RGBA.fromIndex(code - 40);
    } else if (code >= 100 && code <= 107) {
      bg = RGBA.fromIndex(code - 100 + 8);
    } else if (code === 39) {
      fg = undefined;
    } else if (code === 49) {
      bg = undefined;
    } else if (code === 38 || code === 48) {
      // `38:2:r:g:b`, `38:2::r:g:b` with a colour space, or `38;2;r;g;b`.
      const rest =
        parts.length > 0
          ? parts
          : groups.slice(at + 1).map(([value = 0]) => value);
      const [mode, ...values] = rest;
      let value: RGBA | undefined;
      let used = 0;

      if (mode === 5) {
        value = RGBA.fromIndex(values[0] ?? 0);
        used = 2;
      } else if (mode === 2) {
        const rgb = parts.length >= 5 ? values.slice(-3) : values.slice(0, 3);

        value = RGBA.fromInts(rgb[0] ?? 0, rgb[1] ?? 0, rgb[2] ?? 0);
        used = 4;
      }

      if (parts.length === 0) {
        at += used;
      }

      if (code === 38) {
        fg = value;
      } else {
        bg = value;
      }
    }
  }

  return { fg, bg, attributes };
}

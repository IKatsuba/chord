/**
 * An agent's reply as terminal markdown: markdansi's ANSI rendering, laid out
 * to the width the reply is drawn in.
 */
import { lexer, type Token, type Tokens } from 'marked';
import process from 'node:process';
import { render, type RenderOptions, type Theme } from 'markdansi';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import wrapAnsi from 'wrap-ansi';
import { fenceLanguage, highlightLines } from './highlight.ts';
import { type Palette, PALETTES, PLAIN } from '../theme/theme.ts';

/**
 * How a reply is coloured: in a theme's palette, which under NO_COLOR is
 * PLAIN and keeps only weight, slant and dim; or, undefined, not at all, as
 * where stdout is not a terminal.
 */
type Paint = Palette | undefined;

type Colour = NonNullable<NonNullable<Theme['link']>['color']>;

/**
 * Claude Code's look rather than markdansi's: headings and emphasis by weight
 * and slant, inline code and links in the theme's colours. Code blocks are
 * drawn and highlighted here, not by markdansi. An H1 outweighs the bold the
 * other headings carry, as in Claude Code.
 */
function themeOf(paint: Paint, h1 = false): Theme {
  // markdansi types only the eight base names, but takes any chalk has,
  // such as the 16-colour themes' `blueBright`.
  const colour = (role: string | undefined) =>
    role === undefined ? {} : { color: role as Colour };

  return {
    heading: h1 ? { bold: true, underline: true } : { bold: true },
    strong: { bold: true },
    emph: { italic: true },
    inlineCode: colour(paint?.inlineCode),
    blockCode: {},
    link: { ...colour(paint?.link), underline: true },
    quote: { dim: true, italic: true },
    hr: { dim: true },
    listMarker: { dim: true },
    tableHeader: { bold: true },
    tableCell: {},
  };
}

/** Cells a code box takes beside its lines: a border and a space each side. */
const CODE_INSET = 4;

/** One top-level block of a reply, rendered. */
export interface Block {
  /** A block quote, whose bar the component draws beside `text`. */
  readonly quote: boolean;
  readonly text: string;
}

/**
 * A block of a reply for OpenTUI to wrap: its text, a quote's beside its
 * bar, a code block for a box of OpenTUI's to hold, or a list laid out as
 * items.
 */
export type Soft =
  | { readonly kind: 'text' | 'quote'; readonly text: string }
  | Code
  | {
      readonly kind: 'list';
      /** A blank row between items, and between an item's blocks. */
      readonly loose: boolean;
      readonly items: readonly Item[];
    };

/**
 * A list item: its marker, dim, and its blocks, which hang beside the marker
 * as wide as it is.
 */
export interface Item {
  readonly marker: string;
  readonly blocks: readonly Soft[];
}

/**
 * A code block as its box's parts: the border, its padding and the label on
 * it are OpenTUI's, so a drag over the box copies the code alone (Q150).
 */
export interface Code {
  readonly kind: 'code';
  /** The fence's language, its first word; empty for none. */
  readonly label: string;
  /** The code, highlighted, its lines whole for OpenTUI to cut at the edge. */
  readonly code: string;
  /**
   * Cells the box takes: its widest line beside the borders and padding, as
   * wide as the label needs for OpenTUI to draw it, and as its buttons need
   * beside the label, and no wider than `width`.
   */
  readonly width: number;
  /**
   * The buttons on its top border, right of the label: `copy` on every
   * closed block, `run` too on an `sh` or `bash` one; none while its fence
   * is open, its text not final, and only those its `width` holds
   * (docs/design/CHD-394.md §1).
   */
  readonly buttons: readonly Button[];
  /** What its `[copy]` takes: its `CodeBlock`'s `text`. */
  readonly copy: string;
  /** What its `[run]` puts into the prompt, on an `sh` or `bash` block. */
  readonly run?: string;
}

/** A code box's button, drawn as its bracketed word. */
export type Button = 'copy' | 'run';

/** Cells a quote's bar takes: the bar and a space. */
export const QUOTE_INSET = 2;

/**
 * A code block of a reply as the transcript draws it, for a button or a key
 * to find and act on (CHD-394).
 */
export interface CodeBlock {
  /** Its place among the reply's code blocks, from 0, in the order drawn. */
  readonly index: number;
  /** The line of the reply's text its block starts on, from 0. */
  readonly line: number;
  /** The fence's language, its first word, as the box's label; empty for none. */
  readonly label: string;
  /**
   * The code as written, unhighlighted, its lines joined with newlines and
   * none after the last: what a copy of it takes (docs/design/CHD-394.md §2).
   */
  readonly text: string;
  /**
   * Labelled `sh` or `bash`, the blocks with a `[run]` button; a
   * `console` block mixes commands with their output, and it and an
   * unlabelled one get `[copy]` only (the owner, 2026-10-25).
   */
  readonly runnable: boolean;
  /**
   * In a quote, drawn into the quote's text beside its bar, where every
   * other block is a box of its own.
   */
  readonly quoted: boolean;
}

/** The labels of the blocks with a `[run]` button (the owner, CHD-394). */
const RUNNABLE: ReadonlySet<string> = new Set(['sh', 'bash']);

/**
 * `text`'s code blocks, a reply's as `softMarkdown` lays it out: those at
 * its top, in its lists and in its quotes, in the order written, which is
 * the order drawn. A fence still open, mid-stream, is a block to the end.
 */
export function codeBlocks(text: string): CodeBlock[] {
  return blockCode(lexer(text), 0).map(({ token, line, quoted }, index) => {
    const label = labelOf(token);

    return {
      index,
      line,
      label,
      text: copyOf(token),
      runnable: RUNNABLE.has(label),
      quoted,
    };
  });
}

/**
 * `text` as its top-level blocks, rendered to lines no wider than `width`
 * cells. markdansi puts no blank line between blocks, so paragraphs would run
 * together; the component puts one between these. Each call renders the whole
 * reply again, so a reply cut mid-stream reads as markdown cut there: an open
 * fence is a code block to the end, and an unclosed `**` stays as typed until
 * its pair arrives. Colour follows whether stdout is a terminal, unless
 * `color` says, and is `palette`'s; NO_COLOR leaves none of it.
 */
export function markdown(
  text: string,
  width: number,
  color?: boolean,
  palette: Palette = PALETTES.dark,
): Block[] {
  return laid(text, width, paint(color, palette), false).flatMap((block) =>
    block.kind === 'list' || block.kind === 'code'
      ? []
      : [{ quote: block.kind === 'quote', text: block.text }],
  );
}

/**
 * `text` as `markdown` lays it out, but with a paragraph, a heading, a
 * quote's paragraphs and a list item's text each one line, for OpenTUI to
 * wrap: its soft wraps join again in a copy, where markdansi's line breaks
 * would copy as newlines and a list's hang as spaces (CHD-396). A list comes
 * as its items, for the component to set each beside its marker.
 */
export function softMarkdown(
  text: string,
  width: number,
  color?: boolean,
  palette: Palette = PALETTES.dark,
): Soft[] {
  return laid(text, width, paint(color, palette), true);
}

/**
 * Resolved here rather than by markdansi, since the code box and the table
 * borders are drawn here too.
 */
function paint(color: boolean | undefined, palette: Palette): Paint {
  return (color ?? process.stdout.isTTY === true)
    ? process.env['NO_COLOR']
      ? PLAIN
      : palette
    : undefined;
}

/** `text`'s blocks, `soft` or in rows. */
function laid(text: string, width: number, on: Paint, soft: boolean): Soft[] {
  const tokens = lexer(text);
  // A reference link resolves against definitions anywhere in the reply, but
  // each block goes to markdansi alone, so every block takes them along.
  const references = tokens
    .filter((token) => token.type === 'def')
    .map((token) => token.raw.trimEnd())
    .join('\n');

  return blocksOf(tokens, width, on, references, soft);
}

function blocksOf(
  tokens: readonly Token[],
  width: number,
  on: Paint,
  references: string,
  soft: boolean,
): Soft[] {
  const block = (raw: string, width: number, options: RenderOptions = {}) =>
    renderBlock(raw, width, on, { wrap: !soft, ...options }, references);

  return tokens.flatMap((token): Soft[] => {
    if (token.type === 'space' || token.type === 'checkbox') {
      return [];
    }

    if (soft && token.type === 'list') {
      return [listOf(token as Tokens.List, width, on, references)];
    }

    if (soft && token.type === 'code') {
      return [codeOf(token as Tokens.Code, width, on)];
    }

    const quote = token.type === 'blockquote';
    const rendered = quote
      ? // markdansi wraps a quote's paragraph at the full width and then again
        // inside its bar, which strands words on lines of their own; with no
        // bar it wraps once, at the width left beside the reply's own.
        renderHoled(
          token.raw,
          blockCode((token as Tokens.Blockquote).tokens, 0),
          width - QUOTE_INSET,
          on,
          { quotePrefix: '', wrap: !soft },
          references,
        )
      : token.type === 'table'
        ? renderTable(token.raw, width, on, references)
        : token.type === 'code'
          ? renderCode(token as Tokens.Code, width, on)
          : token.type === 'list'
            ? renderHoled(
                token.raw,
                listCode((token as Tokens.List).items, 0),
                width,
                on,
                {},
                references,
              )
            : token.type === 'heading' && (token as Tokens.Heading).depth === 1
              ? block(token.raw, width, { theme: themeOf(on, true) })
              : token.type === 'def'
                ? // The definitions show, as markdansi shows them in a whole reply.
                  renderBlock(token.raw, width, on, { wrap: !soft })
                : block(token.raw, width);

    return rendered === ''
      ? []
      : [{ kind: quote ? 'quote' : 'text', text: rendered }];
  });
}

/**
 * A list as its items: each item's marker as markdansi draws it, a bullet,
 * the number it is written with counted on from the list's first, or a
 * task's box, and its blocks laid out in the width left beside the marker.
 */
function listOf(
  list: Tokens.List,
  width: number,
  on: Paint,
  references: string,
): Soft {
  return {
    kind: 'list',
    loose: list.loose,
    items: list.items.map((item, index) => {
      const marker = `${
        item.task
          ? `[${item.checked === true ? 'x' : ' '}]`
          : list.ordered
            ? `${Number(list.start === '' ? 1 : list.start) + index}.`
            : '-'
      } `;

      return {
        marker: dim(marker, on),
        blocks: blocksOf(
          item.tokens,
          Math.max(1, width - stringWidth(marker)),
          on,
          references,
          true,
        ),
      };
    }),
  };
}

/**
 * A code block's label and its lines, highlighted. markdansi highlights a
 * block a line at a time, which loses a comment or a string that runs on to
 * the next line, so the code is highlighted whole here. Blank lines at
 * either end of the code are the agent's, so it is not trimmed as other
 * blocks are.
 */
function highlighted(
  token: Tokens.Code,
  color: Paint,
): { label: string; lines: readonly string[] } {
  const label = labelOf(token);
  const language = color?.code && fenceLanguage(label);

  return {
    label,
    lines: highlightLines(token.text, language, color?.code?.terminal),
  };
}

/**
 * A code block for OpenTUI's box: as wide as its widest line, or as its
 * label, which OpenTUI leaves out of a box narrower than the label and 4,
 * unless that is wider than `width`.
 */
function codeOf(token: Tokens.Code, width: number, color: Paint): Code {
  const { label, lines } = highlighted(token, color);
  const widest = Math.max(...lines.map((line) => stringWidth(line)));
  const labelled = label === '' ? 0 : stringWidth(label) + 2 + CODE_INSET;
  // Never narrower than its buttons need: they give way, run first, only
  // where the transcript itself is narrower than that.
  const buttons = fitting(
    label,
    !closed(token) ? [] : RUNNABLE.has(label) ? ['copy', 'run'] : ['copy'],
    width,
  );

  return {
    kind: 'code',
    label,
    code: lines.join('\n'),
    width: Math.max(
      1,
      Math.min(
        width,
        Math.max(
          widest + CODE_INSET,
          labelled,
          buttons.length === 0 ? 0 : leastWidth(label, buttons),
        ),
      ),
    ),
    buttons,
    copy: copyOf(token),
    ...(RUNNABLE.has(label) ? { run: runCommand(copyOf(token)) } : {}),
  };
}

/** A code block's text as a copy takes it: no line break after its last. */
function copyOf(token: Tokens.Code): string {
  return token.text.replace(/\n+$/, '');
}

/**
 * The buttons of `wanted` a box in `width` cells holds: all of them where
 * their least width fits, else with `run` given way first, then `copy`.
 */
function fitting(
  label: string,
  wanted: readonly Button[],
  width: number,
): Button[] {
  for (let count = wanted.length; count > 0; count--) {
    const kept = wanted.slice(0, count);

    if (leastWidth(label, kept) <= width) {
      return kept;
    }
  }

  return [];
}

/**
 * The least cells a box holding `buttons` takes, corners included:
 * `┌─ sh ─[copy]─[run]─┐`, the label between rules, a `─` between the
 * bracketed words and `─┐` after the last; no blank cell beside a button,
 * which OpenTUI would draw with the border's `─` through it (the owner,
 * CHD-394 §1's table).
 */
export function leastWidth(label: string, buttons: readonly Button[]): number {
  const labelled = label === '' ? 1 : stringWidth(label) + 4;

  return (
    1 +
    labelled +
    buttons.reduce((sum, button) => sum + button.length + 2, 0) +
    Math.max(buttons.length - 1, 0) +
    2
  );
}

/**
 * Whether a code block is whole: an indented one always, a fenced one once
 * its closing fence has come, as one still open mid-stream is not.
 */
function closed(token: Tokens.Code): boolean {
  const marks = fence(token.raw);

  if (marks === undefined) {
    return true;
  }

  const own = token.raw.replace(/\n+$/, '').split('\n');
  const closer = new RegExp(`^\\s*${marks[0]}{${marks.length},}\\s*$`);

  return own.length > 1 && closer.test(own.at(-1)!);
}

/**
 * A code block in a box of its own, whatever its length: markdansi boxes only
 * a block of two lines or more, which leaves a one-line command, the commonest
 * block an agent sends, looking like prose, and a fence that has just opened
 * unboxed until its second line comes. The box takes the language as a
 * label, without markdansi's brackets, and the code is coloured by it when
 * highlight.js knows it. A line too long for the box is cut at its edge and
 * goes on below, as markdansi cuts one.
 */
function renderCode(token: Tokens.Code, width: number, color: Paint): string {
  const { label, lines } = highlighted(token, color);
  // Highlighted whole, and only then cut to the box.
  const code = lines.flatMap((line) =>
    wrapAnsi(line, Math.max(1, width - CODE_INSET), {
      hard: true,
      wordWrap: false,
      trim: false,
    }).split('\n'),
  );
  const inner = Math.max(
    ...code.map((line) => stringWidth(line)),
    label === '' ? 0 : stringWidth(label) + 2,
  );
  const top =
    label === ''
      ? `┌${'─'.repeat(inner + 2)}┐`
      : `┌ ${label} ${'─'.repeat(inner - stringWidth(label))}┐`;
  const bar = dim('│', color);

  return [
    dim(top, color),
    ...code.map(
      (line) => `${bar} ${line}${' '.repeat(inner - stringWidth(line))} ${bar}`,
    ),
    dim(`└${'─'.repeat(inner + 2)}┘`, color),
  ].join('\n');
}

/**
 * A list or a quote whose code blocks are boxed as a top-level block is:
 * markdansi draws a code block in a list as bare lines in the item's hang,
 * where a command reads as more of the item's text, and in either it boxes
 * the code its own way, uncoloured. Each block's code is swapped for a hole,
 * one character markdansi cannot wrap, so markdansi still lays out the
 * markers, the numbering, the hang and the quote's bars; the box then takes
 * the hole's line, at the indent markdansi gave it and in the width left
 * beside that indent.
 */
function renderHoled(
  text: string,
  found: readonly HeldCode[],
  width: number,
  color: Paint,
  options: RenderOptions,
  references: string,
): string {
  const codes = found.slice(0, HOLES.size);
  const raw = holed(text, codes);
  const draw = (codeBox: boolean) =>
    renderBlock(raw, width, color, { ...options, codeBox }, references);
  // markdansi's own box stays on for any code it is left to draw; but a list
  // made only of code blocks it merges into one, and would box the holes
  // together, so that list goes without.
  const boxed = draw(true);
  const rendered = boxed
    .split('\n')
    .some(
      (line) => line.includes('│') && [...line].some((char) => HOLES.has(char)),
    )
    ? draw(false)
    : boxed;

  return rendered
    .split('\n')
    .flatMap((line) => {
      const [hole] = [...line].filter((char) => HOLES.has(char));
      const code = hole === undefined ? undefined : HOLES.get(hole)!(codes);

      if (code === undefined) {
        return [line];
      }

      const indent = line.slice(0, line.indexOf(hole!));
      const inset = stringWidth(indent);
      // The box's lower rows hang under its first: a marker gives way to
      // spaces, but the bar of a quote the box is in goes on beside it.
      const hang = stripAnsi(indent)
        .replace(/[^│\s]/g, ' ')
        .replace(/│/g, (bar) => dim(bar, color));

      return renderCode(code.token, width - inset, color)
        .split('\n')
        .map((row, i) => `${i === 0 ? indent : hang}${row}`);
    })
    .join('\n');
}

/**
 * The first code point of Unicode's last private use plane, which no font
 * draws and no agent sends; the n-th code block's hole is the n-th from it.
 */
const FIRST_HOLE = 0x100000;

/** Each hole character, to the code block among a list's whose hole it is. */
const HOLES = new Map(
  Array.from({ length: 256 }, (_, n) => [
    String.fromCodePoint(FIRST_HOLE + n),
    <T>(codes: readonly T[]) => codes[n],
  ]),
);

/**
 * What `[run]` puts into the prompt from a block's `text`: every line, in
 * order, each one that starts with a `$ ` prompt without it, the rest as
 * written (the owner, 2026-10-25; docs/design/CHD-394.md §5).
 */
export function runCommand(text: string): string {
  return text
    .split('\n')
    .map((line) => (line.startsWith('$ ') ? line.slice(2) : line))
    .join('\n');
}

/** A code block's label: its fence's language, its first word. */
function labelOf(token: Tokens.Code): string {
  return token.lang?.trim().split(/\s+/)[0] ?? '';
}

/**
 * A code block in a list or a quote, and the line of the list's or the
 * quote's `raw` it starts on; whether a quote holds it.
 */
interface HeldCode {
  readonly token: Tokens.Code;
  readonly line: number;
  readonly quoted: boolean;
}

/**
 * The code blocks in `items`, which start on line `line` of their list, and
 * in the lists and quotes inside them, in the order they are written. marked
 * hands an item's blocks over with its indent taken off but its lines kept,
 * so a block's line is the lines of the blocks before it.
 */
function listCode(
  items: readonly Tokens.ListItem[],
  line: number,
  quoted = false,
): HeldCode[] {
  let at = line;

  return items.flatMap((item) => {
    const start = at;

    at += lineBreaks(item.raw);

    return blockCode(item.tokens, start, quoted);
  });
}

/**
 * The code blocks among `tokens`, which start on line `line`, and in the
 * lists and quotes among them. A quote's blocks, like an item's, keep their
 * lines with the `>` taken off.
 */
function blockCode(
  tokens: readonly Token[],
  line: number,
  quoted = false,
): HeldCode[] {
  let at = line;

  return tokens.flatMap((token) => {
    const start = at;

    at += lineBreaks(token.raw);

    return token.type === 'list'
      ? listCode((token as Tokens.List).items, start, quoted)
      : token.type === 'blockquote'
        ? blockCode((token as Tokens.Blockquote).tokens, start, true)
        : token.type === 'code'
          ? [{ token: token as Tokens.Code, line: start, quoted }]
          : [];
  });
}

/** How many line breaks `text` has. */
function lineBreaks(text: string): number {
  return text.split('\n').length - 1;
}

/** The backticks or tildes that open a fenced code block's `raw`. */
function fence(raw: string): string | undefined {
  return raw.match(/^ {0,3}(`{3,}|~{3,})/)?.[1];
}

/**
 * `raw`, a list or a quote as written, with the lines of each of `codes`
 * replaced by its hole: a fenced block keeps its fences, with the hole at the
 * code's column and inside the quotes the fence is in, and an indented one
 * keeps its indent. A block whose first line is not where
 * marked said is left as it is.
 */
function holed(raw: string, codes: readonly HeldCode[]): string {
  const lines = raw.split('\n');

  // From the last, so a splice leaves the lines of the blocks before it be.
  [...codes.entries()].reverse().forEach(([n, { token, line }]) => {
    const hole = String.fromCodePoint(FIRST_HOLE + n);
    const own = token.raw.replace(/\n+$/, '').split('\n');
    const first = own[0]!.trimStart();

    if (first === '' || !lines[line]?.endsWith(first)) {
      return;
    }

    const before = lines[line]!.slice(0, -first.length);
    const marks = fence(own[0]!);

    if (marks === undefined) {
      lines.splice(line, own.length, `${before}${hole}`);

      return;
    }

    const closer = new RegExp(`^\\s*${marks[0]}{${marks.length},}\\s*$`);
    const closed = own.length > 1 && closer.test(own.at(-1)!);

    // The code's column: a fence on its bullet's line starts past the marker,
    // and a quote's `>` stays, or the hole would end the quote.
    lines.splice(
      line + 1,
      own.length - 1 - (closed ? 1 : 0),
      `${before.replace(/[^>\s]/g, ' ')}${hole}`,
    );
  });

  return lines.join('\n');
}

/**
 * A table whose cells wrap inside their columns, unless a word too long for
 * its column would push the borders out of line; then each cell is cut to
 * one line with an ellipsis instead.
 */
function renderTable(
  text: string,
  width: number,
  color: Paint,
  references: string,
): string {
  const wrapped = renderBlock(
    text,
    width,
    color,
    { tableTruncate: false },
    references,
  );
  const table = wrapped.split('\n').every((line) => stringWidth(line) <= width)
    ? wrapped
    : renderBlock(text, width, color, {}, references);

  return dimBorders(table, color);
}

/**
 * The borders of a table dimmed, as a code box's are, so the grid sits behind
 * its cells instead of being the loudest thing on screen. markdansi styles
 * each cell on its own, so a border is never inside a cell's style and
 * dimming it ends no style the cell began.
 */
function dimBorders(table: string, color: Paint): string {
  return color
    ? table.replace(/[─│┌┐└┘├┤┬┴┼]+/g, (border) => dim(border, color))
    : table;
}

/** `text` faint, when there is colour. */
function dim(text: string, color: Paint): string {
  return color ? `\x1b[2m${text}\x1b[22m` : text;
}

/**
 * `text` rendered alone. Given the reply's link `references`, it is rendered
 * with them after it, so its reference links resolve, and their own lines,
 * which markdansi draws as they would be drawn alone, are cut off again.
 */
function renderBlock(
  text: string,
  width: number,
  color: Paint,
  options: RenderOptions = {},
  references = '',
): string {
  const draw = (markdown: string) =>
    render(markdown, { ...renderOptions(width, color), ...options })
      .replace(/^\n+/, '')
      .trimEnd();

  if (references === '') {
    return draw(text);
  }

  const rendered = draw(`${text}\n\n${references}`);
  const tail = draw(references);

  return rendered.endsWith(tail)
    ? rendered.slice(0, -tail.length).trimEnd()
    : rendered;
}

function renderOptions(width: number, color: Paint): RenderOptions {
  return {
    width: Math.max(1, width),
    color: color !== undefined,
    // The address printed after the link text reads in every terminal and in
    // a captured screen; an OSC 8 link hides it.
    hyperlinks: false,
    theme: themeOf(color),
  };
}

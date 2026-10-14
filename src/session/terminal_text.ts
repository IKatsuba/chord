/**
 * What a command an agent ran wrote, as plain text: the output a terminal
 * would leave on screen, folded one delta at a time. The cursor controls a
 * progress line uses are applied where they land, and every other escape is
 * dropped as it arrives, so the state a tool call's terminal keeps holds no
 * escape for a later cut to split. An escape a delta ends inside is carried
 * to the next as the parser state it left, never as its bytes, so however
 * long it runs, what is held stays within a constant.
 *
 * The escapes are read as DEC's VT500 parser reads them (Paul Williams's
 * state machine, which xterm and every other emulator follow): a C1 byte, a
 * CAN, a SUB or an `ESC` ends whatever was open, a string (OSC, DCS, SOS,
 * PM, APC) runs to its BEL or ST, and C0 controls inside an escape still act.
 */
import stringWidth from 'string-width';

/** Where tab stops fall, as a terminal sets them unless told otherwise. */
const TAB_STOP = 8;

/**
 * The most of a CSI's parameters kept while it is open. The controls applied
 * take a number or two; a longer run is no control chord applies, so the
 * sequence is dropped whole and its parameters stop growing.
 */
export const PARAMS_LIMIT = 16;

/**
 * The furthest right a cursor control or a tab takes the cursor. A terminal
 * stops it at its right margin; this state has no width, so the margin is
 * one wider than any screen, and a move of a billion columns pads no line
 * with a billion blanks. Text itself still runs past it.
 */
export const COLUMN_LIMIT = 1000;

/** Where the next character lands, when that is not the output's end. */
export interface TerminalCursor {
  /** The line it is on, counted up from the last, so a cut leaves it be. */
  readonly row: number;
  /** The column, in cells: a wide character takes two. */
  readonly column: number;
}

/**
 * The escape a delta ended inside, as far as the parser read it: its kind
 * and what the controls applied need, never a string's body.
 */
export type OpenEscape =
  | { readonly kind: 'escape'; readonly intermediates?: true }
  | { readonly kind: 'csi'; readonly params: string; readonly ignored?: true }
  | { readonly kind: 'string' };

/** A terminal's output as text, and what the next delta goes on from. */
export interface TerminalText {
  /** Plain text, lines split by `\n`; no other control character. */
  readonly output: string;
  /** Absent while the cursor sits at the output's end. */
  readonly cursor?: TerminalCursor;
  readonly escape?: OpenEscape;
  /** Output ran past the bound and its start was dropped. */
  readonly truncated?: boolean;
}

/** A terminal that has written nothing. */
export const EMPTY_TEXT: TerminalText = { output: '' };

/**
 * `text` with `data` written after it, then cut to the last `limit`
 * characters: from a line's start where one falls inside them, so no line is
 * kept in pieces; within the last line only when it alone outruns the bound.
 */
export function writeText(
  text: TerminalText,
  data: string,
  limit: number,
): TerminalText {
  const screen = new Screen(text);

  screen.write(data);

  return screen.result(limit, text.truncated === true);
}

/** `data` as a terminal would leave it, with nothing before or after. */
export function plainText(data: string): string {
  return writeText(EMPTY_TEXT, data, Infinity).output;
}

/** The lines being written, and the parser's state between characters. */
class Screen {
  private readonly lines: string[];
  /** Lines rewritten as cells, by index, joined back at the end. */
  private readonly cells = new Map<number, string[]>();
  private row: number;
  /**
   * The cursor's column; none while it is at its line's end, so text that
   * only appends never measures the line it lands on.
   */
  private at: number | undefined;
  private escape: OpenEscape | undefined;

  constructor(text: TerminalText) {
    this.lines = text.output.split('\n');
    this.row = this.lines.length - 1 - (text.cursor?.row ?? 0);
    this.at = text.cursor?.column;
    this.escape = text.escape;
  }

  private get column(): number {
    this.at ??= width(this.lines[this.row]!);

    return this.at;
  }

  private set column(column: number) {
    this.at = column;
  }

  write(data: string): void {
    let printable = '';
    const flush = () => {
      if (printable !== '') {
        this.print(printable);

        printable = '';
      }
    };

    for (const char of data) {
      const code = char.codePointAt(0)!;

      if (this.escape === undefined && isPrintable(code)) {
        printable += char;

        continue;
      }

      flush();
      this.read(char, code);
    }

    flush();
  }

  /** One character that is a control, or comes inside an escape. */
  private read(char: string, code: number): void {
    // What ends whatever is open, wherever it comes.
    if (code === 0x18 || code === 0x1a) {
      this.escape = undefined;

      return;
    }

    if (code === 0x1b) {
      this.escape = { kind: 'escape' };

      return;
    }

    if (code >= 0x80 && code <= 0x9f) {
      this.escape =
        code === 0x9b
          ? { kind: 'csi', params: '' }
          : [0x90, 0x98, 0x9d, 0x9e, 0x9f].includes(code)
            ? { kind: 'string' }
            : undefined;

      return;
    }

    const escape = this.escape;

    if (escape?.kind === 'string') {
      if (code === 0x07) {
        this.escape = undefined;
      }

      return;
    }

    if (code < 0x20) {
      this.control(code);

      return;
    }

    if (code === 0x7f || escape === undefined) {
      return;
    }

    if (code > 0x7f) {
      // Not part of any escape: the sequence was broken off, and this is text.
      this.escape = undefined;

      this.print(char);

      return;
    }

    if (escape.kind === 'escape') {
      this.escape = afterEscape(escape, char, code);

      return;
    }

    this.escape = undefined;

    if (code >= 0x40) {
      if (!escape.ignored) {
        this.csi(escape.params, char);
      }

      return;
    }

    // A private marker or an intermediate makes it a control chord does not
    // apply, and so does a run of parameters past the bound.
    const kept = /[\d;]/.test(char) && escape.params.length < PARAMS_LIMIT;

    this.escape = {
      kind: 'csi',
      params: kept ? escape.params + char : escape.params,
      ...(escape.ignored || !kept ? { ignored: true } : {}),
    };
  }

  /** A C0 control: the few that move the cursor act, the rest go. */
  private control(code: number): void {
    switch (code) {
      case 0x0a:
        // A new line's end is its start; an existing one's start is not.
        this.at = this.row === this.lines.length - 1 ? undefined : 0;

        if (this.row === this.lines.length - 1) {
          this.lines.push('');
        }

        this.row += 1;

        break;
      case 0x0d:
        this.column = 0;

        break;
      case 0x08:
        this.column = Math.max(0, this.column - 1);

        break;
      case 0x09:
        this.column = rightTo(
          this.column,
          (Math.floor(this.column / TAB_STOP) + 1) * TAB_STOP,
        );

        break;
    }
  }

  /** A CSI sequence ended by `final`: the cursor and erase controls act. */
  private csi(params: string, final: string): void {
    const [first] = params.split(';');
    const value = first === undefined || first === '' ? 0 : Number(first);
    const count = Math.max(1, value);
    const top = 0;
    const bottom = this.lines.length - 1;

    // The column holds across a move to another line, whatever its end.
    this.at = this.column;

    switch (final) {
      case 'A':
        this.row = Math.max(top, this.row - count);

        break;
      case 'B':
        this.row = Math.min(bottom, this.row + count);

        break;
      case 'C':
        this.column = rightTo(this.column, this.column + count);

        break;
      case 'D':
        this.column = Math.max(0, this.column - count);

        break;
      case 'E':
        this.row = Math.min(bottom, this.row + count);
        this.column = 0;

        break;
      case 'F':
        this.row = Math.max(top, this.row - count);
        this.column = 0;

        break;
      case 'G':
        this.column = Math.min(count - 1, COLUMN_LIMIT);

        break;
      case 'K':
        this.erase(value);
        break;
    }
  }

  /** Erase in line: after the cursor, up to it, or the whole line. */
  private erase(mode: number): void {
    const cells = this.line();

    if (mode === 0) {
      cleave(cells, this.column);

      cells.length = Math.min(cells.length, this.column);
    } else if (mode === 1) {
      cleave(cells, this.column + 1);

      for (let at = 0; at <= this.column && at < cells.length; at++) {
        cells[at] = ' ';
      }
    } else if (mode === 2) {
      cells.length = 0;
    }
  }

  /** Text, written over what the line holds from the cursor on. */
  private print(text: string): void {
    const line = this.lines[this.row]!;

    if (this.at === undefined && !this.cells.has(this.row)) {
      this.lines[this.row] = line + text;

      return;
    }

    if (!this.cells.has(this.row) && isAscii(text) && isAscii(line)) {
      // The usual case, a cell a character, without splitting graphemes.
      this.lines[this.row] =
        line.padEnd(this.column, ' ').slice(0, this.column) +
        text +
        line.slice(this.column + text.length);
      this.column += text.length;

      return;
    }

    const cells = this.line();
    const before =
      cells[this.column - 1] === '' ? this.column - 2 : this.column - 1;
    let segments: Iterable<{ segment: string }> = graphemes(text);

    if (before >= 0 && before < cells.length) {
      // What a delta begins with may still belong to the character before
      // the cursor (a mark, a joiner, an emoji's other half, a surrogate's
      // second), or take back what was kept with it (a high surrogate a
      // flag's next half follows), so the two are read as one, as they
      // would be whole.
      const joined = [...graphemes(cells[before]! + text)];

      if (joined[0]!.segment !== cells[before]) {
        cleave(cells, before + 1);
        cells.splice(before, 1, ' ');

        this.column = before;
        segments = joined;
      }
    }

    for (const { segment } of segments) {
      const size = stringWidth(segment);

      if (size === 0) {
        // A mark that combines with what was written before it.
        const at =
          cells[this.column - 1] === '' ? this.column - 2 : this.column - 1;

        if (at >= 0 && at < cells.length) {
          cells[at] += segment;

          continue;
        }
      }

      while (cells.length < this.column) {
        cells.push(' ');
      }

      cleave(cells, this.column);
      cleave(cells, this.column + Math.max(1, size));
      cells.splice(
        this.column,
        Math.max(1, size),
        segment,
        ...(size > 1 ? [''] : []),
      );

      this.column += Math.max(1, size);
    }
  }

  /** The cursor's line as cells, a wide character's second one empty. */
  private line(): string[] {
    const known = this.cells.get(this.row);

    if (known) {
      return known;
    }

    const cells: string[] = [];

    for (const { segment } of graphemes(this.lines[this.row]!)) {
      const size = stringWidth(segment);
      const at =
        cells[cells.length - 1] === '' ? cells.length - 2 : cells.length - 1;

      if (size === 0 && at >= 0) {
        // Kept with the character before it, as it was written.
        cells[at] += segment;
      } else {
        cells.push(segment, ...(size > 1 ? [''] : []));
      }
    }

    this.cells.set(this.row, cells);

    return cells;
  }

  result(limit: number, truncated: boolean): TerminalText {
    for (const [row, cells] of this.cells) {
      this.lines[row] = cells.join('');
    }

    let output = this.lines.join('\n');
    let row = this.lines.length - 1 - this.row;
    const end = row === 0 && this.at === undefined;
    let column = end ? 0 : this.column;

    if (output.length > limit) {
      truncated = true;

      const from = output.length - limit;
      const start = output.indexOf('\n', from);

      if (start >= 0) {
        output = output.slice(start + 1);
      } else {
        const line = output.slice(output.lastIndexOf('\n') + 1);
        const cut = graphemeAfter(line, line.length - limit);

        if (row === 0 && !end) {
          column = Math.max(0, column - width(line.slice(0, cut)));
        }

        output = line.slice(cut);
      }

      row = Math.min(row, output.split('\n').length - 1);
    }

    return {
      output,
      ...(end ? {} : { cursor: { row, column } }),
      ...(this.escape === undefined ? {} : { escape: this.escape }),
      ...(truncated ? { truncated } : {}),
    };
  }
}

/** The state after an `ESC` and what came after it, given one more byte. */
function afterEscape(
  escape: { readonly intermediates?: true },
  char: string,
  code: number,
): OpenEscape | undefined {
  if (code < 0x30) {
    return { kind: 'escape', intermediates: true };
  }

  if (escape.intermediates) {
    return undefined;
  }

  if (char === '[') {
    return { kind: 'csi', params: '' };
  }

  return ']PX^_'.includes(char) ? { kind: 'string' } : undefined;
}

/**
 * Before `at`, a wide character `at` falls inside of is half overwritten:
 * what is left of it is a blank, as a terminal leaves it.
 */
function cleave(cells: string[], at: number): void {
  if (cells[at] === '' && at > 0) {
    cells[at - 1] = ' ';
    cells[at] = ' ';
  }
}

/**
 * The first grapheme boundary in `line` at or after `from`, where a cut
 * leaves no character in halves: a cluster that does not fit whole goes
 * whole, however long its run of marks.
 */
function graphemeAfter(line: string, from: number): number {
  if (isAscii(line.slice(from - 1, from + 1))) {
    return from;
  }

  const around = graphemes(line).containing(from);

  return around === undefined || around.index === from
    ? from
    : around.index + around.segment.length;
}

/** A move right from `column` to `to`, stopped at the margin. */
function rightTo(column: number, to: number): number {
  return Math.max(column, Math.min(to, COLUMN_LIMIT));
}

function isPrintable(code: number): boolean {
  return (code >= 0x20 && code < 0x7f) || code > 0x9f;
}

function isAscii(text: string): boolean {
  return /^[\x20-\x7e]*$/.test(text);
}

function width(line: string): number {
  return isAscii(line) ? line.length : stringWidth(line);
}

const segmenter = new Intl.Segmenter();

function graphemes(text: string): Intl.Segments {
  return segmenter.segment(text);
}

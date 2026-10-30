/**
 * The start screen's page: which art a window has room for, the rows its list
 * gets and where the page starts. The window alone sets the step; the list's
 * length only sets its rows, so a long list never moves a window to another
 * step.
 */
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';
import { type MarkColour, markPaint, MIDDLE } from '../header/mark_rows.ts';
import { cutPath } from '../pickers/mcp.ts';
import { type PickerChoice, pickerLayout } from '../pickers/picker.ts';

/** What the page draws above its picker, from the most to nothing. */
export type StartStep = 'full' | 'compact' | 'line' | 'none';

/** The rows of the art and words of each step. */
const ART: Readonly<Record<StartStep, number>> = {
  full: 11,
  compact: 5,
  line: 1,
  none: 0,
};

/** Past this many rows `full` stops being a title page; the list scrolls. */
const LIST_CAP = 14;

/** The agents' column and resume's frame, in columns, in a wide window. */
const COLUMN = 62;
const FRAME = 84;

/** The README's own line, under the full step's art. */
export const TAGLINE = 'One terminal for every coding agent.';

/** The width of the agents' column or resume's frame, from the window alone. */
export function startColumn(columns: number, framed: boolean): number {
  return Math.max(1, Math.min(columns - 2, framed ? FRAME : COLUMN));
}

/** The rows a hint takes where the picker wraps it, at its spaces. */
export function hintRows(hint: string, width: number): number {
  return wrapAnsi(hint, Math.max(1, width), { hard: true, trim: true }).split(
    '\n',
  ).length;
}

/**
 * What a whole list takes in a box of `width`, its wrapped labels counted.
 * Laid out unscrolled, as it is where it fits; where it does not, scrolling
 * only narrows its labels, and it still does not.
 */
export function listLines(
  choices: readonly PickerChoice[],
  width: number,
): number {
  const laid = pickerLayout(choices, Number.POSITIVE_INFINITY, width);

  return Math.max(
    1,
    laid === undefined
      ? choices.length
      : laid.reduce((sum, each) => sum + each.length, 0),
  );
}

/**
 * The wordmark's solid letters and shadow lines, following the terminal's
 * depth as the mark does; none where the mark has no colour, as OpenTUI's font
 * takes a real one only.
 */
export function wordmarkColours(
  colour: MarkColour,
): readonly [string, string] | undefined {
  if (colour.level === 'none') {
    return undefined;
  }

  if (colour.level === '16') {
    return [colour.tone, colour.tone];
  }

  const paint = markPaint(colour.stops, colour.level);

  return [paint(MIDDLE), paint(1)];
}

/** The page for one window. */
export function startLayout(page: {
  columns: number;
  rows: number;
  /** What the whole list takes: agents, or sessions' wrapped lines. */
  lines: number;
  /** Resume's frame around the list, rather than the agents' bare column. */
  framed: boolean;
  /** The hint's rows, wrapped at the column's inner width. */
  hintRows: number;
}): { step: StartStep; listRows: number; top: number; column: number } {
  const { columns, rows, lines, framed, hintRows } = page;
  // The picker around its list: the agents' title, gap, gap and hint; the
  // frame's two borders, title, sentence, gap and gap, and its hint.
  const around = (framed ? 6 : 3) + hintRows;
  // One gap above the picker, one row left as a margin.
  const room = (art: number) => rows - art - 1 - around - 1;
  const step: StartStep =
    rows >= 32 && columns >= 60
      ? 'full'
      : rows >= 18 && columns >= 40
        ? 'compact'
        : room(ART.line) >= 3
          ? 'line'
          : 'none';
  const cap = step === 'full' ? LIST_CAP : Infinity;
  // `none` gives up the margin too; the frame keeps its row above.
  const fits =
    step === 'none' ? rows - (framed ? 1 : 0) - around : room(ART[step]);
  const whole = lines <= Math.min(fits, cap);
  // Where it is not whole, `… +N more` takes a row of its own.
  const listRows = whole
    ? Math.max(lines, 1)
    : Math.max(1, Math.min(cap, fits - 1));
  const pageRows =
    ART[step] +
    (step === 'none' && !framed ? 0 : 1) +
    around +
    listRows +
    (whole ? 0 : 1);

  return {
    step,
    listRows,
    top: Math.max(0, Math.floor((rows - pageRows) / 2)),
    column: startColumn(columns, framed),
  };
}

/**
 * The version line in `width`: the agent stays named and the directory is cut
 * first, from the left. A rest wider than `width` stays whole for the text's
 * own cut, with one column of the directory beside it.
 */
export function versionLine(line: {
  version: string;
  /** Resume names the agent it resumes; the agents' page has none yet. */
  agent?: string | undefined;
  directory: string;
  width: number;
}): string {
  const { version, agent, directory, width } = line;
  const rest = `v${version} · ${agent === undefined ? '' : `${agent} · `}`;

  return `${rest}${cutPath(directory, Math.max(1, width - stringWidth(rest)))}`;
}

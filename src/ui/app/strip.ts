/**
 * The header's strip of tabs, once two or more sessions are open: each tab's
 * number, agent and state, the one in front marked, and the window's
 * directory once on the right. A narrow window gets a shorter strip, never a
 * second row or a hidden tab.
 */
import stringWidth from 'string-width';
import type { TabWait } from '../../session/tabs.ts';
import { cutPath } from '../pickers/mcp.ts';

/** What a tab behind says of its session, most urgent first. */
export type TabGlyph = 'asking' | 'failed' | 'replied' | 'working';

/** How each state is marked; `✻` stands still, as a spinner here would not. */
export const GLYPHS: Record<TabGlyph, string> = {
  asking: '●',
  failed: '✗',
  replied: '✓',
  working: '✻',
};

/**
 * The glyph a tab's wait earns: a permission or form first, as it blocks the
 * turn, then a failure, a reply not yet seen, and a turn running.
 */
export function tabGlyph(wait: TabWait): TabGlyph | undefined {
  return wait.asking
    ? 'asking'
    : wait.unseen?.kind === 'failed'
      ? 'failed'
      : wait.unseen
        ? 'replied'
        : wait.working === undefined
          ? undefined
          : 'working';
}

/** One tab as the strip is asked to draw it. */
export interface StripTab {
  /** Its place in the strip, the number its direct key uses. */
  readonly number: number;
  readonly agent: string;
  readonly front: boolean;
  readonly glyph?: TabGlyph | undefined;
}

/** A run of the strip's text, drawn as one. */
export type StripPiece =
  | { readonly kind: 'gap'; readonly text: string }
  /** The tab in front, padded by a space each side, inverse and bold. */
  | { readonly kind: 'front'; readonly text: string }
  /** A tab behind, dim, and its glyph after it in the glyph's colour. */
  | {
      readonly kind: 'tab';
      readonly text: string;
      readonly glyph?: TabGlyph | undefined;
    };

export interface StripView {
  /** What follows ` chord` on the left. */
  readonly pieces: readonly StripPiece[];
  readonly directory: string;
}

/** Columns ` chord` takes, and the least between the tabs and the directory. */
const CHORD = 'chord';
const MIN_GAP = 2;

/**
 * The gap before a tab: three spaces after the name and around the front
 * tab's padding, so it reads as four; four between tabs behind, or three
 * once they are short.
 */
function gapBefore(
  previous: StripTab | undefined,
  tab: StripTab,
  short: boolean,
): string {
  if (previous === undefined) {
    return tab.front ? '  ' : '   ';
  }

  return previous.front || tab.front || short ? '   ' : '    ';
}

function piecesOf(tabs: readonly StripTab[], short: boolean): StripPiece[] {
  return tabs.flatMap((tab, index): StripPiece[] => {
    const gap: StripPiece = {
      kind: 'gap',
      text: gapBefore(tabs[index - 1], tab, short),
    };

    if (tab.front) {
      return [gap, { kind: 'front', text: ` ${tab.number} ${tab.agent} ` }];
    }

    return [
      gap,
      {
        kind: 'tab',
        text: short ? `${tab.number}` : `${tab.number} ${tab.agent}`,
        glyph: tab.glyph,
      },
    ];
  });
}

function piecesWidth(pieces: readonly StripPiece[]): number {
  return pieces.reduce(
    (sum, piece) =>
      sum +
      stringWidth(piece.text) +
      (piece.kind === 'tab' && piece.glyph ? 2 : 0),
    stringWidth(CHORD),
  );
}

/** The last segment of `directory`, as far as it is ever cut: `…/app`. */
function floorOf(directory: string): string {
  const last = directory.slice(
    directory.lastIndexOf('/', directory.length - 2),
  );

  return last.length < directory.length ? `…${last}` : directory;
}

/**
 * The strip for `width` cells inside the header's padding, or none while a
 * single session is open and the header is as it always was. It shrinks in
 * this order: the directory is cut at a `/`, down to its last segment; then
 * the tabs behind drop their agent's names, all together so the strip reads
 * evenly. The tab in front keeps its name. Nine short tabs fit 80 columns.
 */
export function stripLayout(
  tabs: readonly StripTab[],
  directory: string,
  width: number,
): StripView | undefined {
  if (tabs.length < 2) {
    return undefined;
  }

  const floor = floorOf(directory);

  for (const short of [false, true]) {
    const pieces = piecesOf(tabs, short);
    const room = width - piecesWidth(pieces) - MIN_GAP;

    if (room >= stringWidth(directory)) {
      return { pieces, directory };
    }

    if (room >= stringWidth(floor)) {
      return { pieces, directory: cutPath(directory, room) };
    }
  }

  const pieces = piecesOf(tabs, true);
  const room = width - piecesWidth(pieces) - MIN_GAP;

  return {
    pieces,
    directory: room < 1 ? '' : cutPath(directory, room),
  };
}

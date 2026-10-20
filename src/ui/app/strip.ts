/**
 * The header's strip of tabs, once two or more sessions are open: each tab's
 * number, agent and state, the one in front marked, and the window's
 * directory once on the right. A narrow window gets a shorter strip, never a
 * second row or a hidden tab.
 */
import stringWidth from 'string-width';
import { failureOf, type TabWait } from '../../session/tabs.ts';
import { cutPath } from '../pickers/mcp.ts';

/** What a tab behind says of its session: its state, then what is not yet seen. */
export type TabGlyph = 'asking' | 'failed' | 'replied' | 'working' | 'message';

/** How each is marked; `✻` stands still, as a spinner here would not. */
export const GLYPHS: Record<TabGlyph, string> = {
  asking: '●',
  failed: '✗',
  replied: '✓',
  working: '✻',
  message: '←',
};

/**
 * A tab's glyphs (CHD-471): its state, asking, gone or working, none while
 * it is idle, as the strip is for what calls the person; then what of it is
 * not yet seen, a failed turn, a reply or a message.
 */
export interface TabGlyphs {
  readonly state?: 'asking' | 'failed' | 'working';
  readonly mark?: 'failed' | 'replied' | 'message';
}

/** The glyphs a tab's wait earns, as the agents list words its state and mark. */
export function tabGlyphs(wait: TabWait): TabGlyphs {
  const failure = wait.exited ? 'exited' : failureOf(wait);
  const state = wait.asking
    ? 'asking'
    : failure === 'exited' || failure === 'start'
      ? 'failed'
      : wait.working === undefined
        ? undefined
        : 'working';
  const mark =
    wait.unseen === undefined
      ? undefined
      : wait.unseen.kind === 'failed'
        ? failure === 'turn'
          ? 'failed'
          : undefined
        : wait.unseen.kind;

  return {
    ...(state === undefined ? {} : { state }),
    ...(mark === undefined ? {} : { mark }),
  };
}

/** The glyphs drawn, in order, state first. */
export function glyphsOf(glyphs: TabGlyphs | undefined): TabGlyph[] {
  return [glyphs?.state, glyphs?.mark].filter(
    (glyph): glyph is TabGlyph => glyph !== undefined,
  );
}

/** One tab as the strip is asked to draw it. */
export interface StripTab {
  /** Its place in the strip, the number its direct key uses. */
  readonly number: number;
  readonly agent: string;
  readonly front: boolean;
  readonly glyphs?: TabGlyphs | undefined;
}

/** A run of the strip's text, drawn as one. */
export type StripPiece =
  | { readonly kind: 'gap'; readonly text: string }
  /** The tab in front, padded by a space each side, inverse and bold. */
  | { readonly kind: 'front'; readonly text: string }
  /** A tab behind, dim, and its glyphs after it, each in its colour. */
  | {
      readonly kind: 'tab';
      readonly text: string;
      readonly glyphs?: TabGlyphs | undefined;
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
        glyphs: tab.glyphs,
      },
    ];
  });
}

function piecesWidth(pieces: readonly StripPiece[]): number {
  return pieces.reduce(
    (sum, piece) =>
      sum +
      stringWidth(piece.text) +
      (piece.kind === 'tab'
        ? // A space, then each glyph.
          ((count) => (count === 0 ? 0 : 1 + count))(
            glyphsOf(piece.glyphs).length,
          )
        : 0),
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

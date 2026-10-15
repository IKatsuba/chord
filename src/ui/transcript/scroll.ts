/**
 * Where the transcript's view is. chord draws on the alternate screen, which
 * has no scrollback, so the window scrolls its own transcript: it follows the
 * bottom, or it is scrolled back to a row that new output does not move.
 */
import stringWidth from 'string-width';

export interface Scroll {
  /** Rows the transcript takes, as last measured. */
  readonly content: number;
  /** Rows the transcript area has, the indicator's row included. */
  readonly view: number;
  /**
   * The view shows the transcript's end: all of it, from the top, while it
   * fits, and its bottom on the view's once it does not.
   */
  readonly following: boolean;
  /** Rows above the view while scrolled back; unused while following. */
  readonly top: number;
  /** Output arrived since the view left the bottom. */
  readonly news: boolean;
  /**
   * A drag holds the view where it is, even over a transcript that fits,
   * so the text under the pointer never moves until the release (CHD-172).
   */
  readonly held?: true;
}

export const initialScroll: Scroll = {
  content: 0,
  view: 0,
  following: true,
  top: 0,
  news: false,
};

export type ScrollStep =
  'page_up' | 'page_down' | 'line_up' | 'line_down' | 'top' | 'bottom';

export type ScrollAction =
  | {
      readonly type: 'scroll_measured';
      readonly content: number;
      readonly view: number;
      /** The row to keep at the top, once a relayout has moved it. */
      readonly top?: number;
    }
  | { readonly type: 'scrolled'; readonly step: ScrollStep }
  /**
   * A drag began: a following view stays where it is, so new output goes
   * below it rather than moving the text under the pointer (CHD-172).
   */
  | { readonly type: 'scroll_held' }
  /** The drag ended: the view is the person's to move again. */
  | { readonly type: 'scroll_released' };

/** The furthest the view goes down: its bottom on the transcript's. */
function bottomTop({ content, view }: Scroll): number {
  return Math.max(0, content - view);
}

function fits(scroll: Scroll): boolean {
  return scroll.content <= scroll.view;
}

function following(scroll: Scroll): Scroll {
  return scroll.following && !scroll.news
    ? scroll
    : { ...scroll, following: true, news: false };
}

/** One page: the view less two rows, so a line of the last page stays. */
export function pageRows(scroll: Scroll): number {
  return Math.max(1, scroll.view - 2);
}

export function reduceScroll(scroll: Scroll, action: ScrollAction): Scroll {
  switch (action.type) {
    case 'scroll_measured': {
      const same =
        action.content === scroll.content &&
        action.view === scroll.view &&
        (action.top === undefined || action.top === scroll.top);

      if (same) {
        return scroll;
      }

      const next = { ...scroll, content: action.content, view: action.view };

      if (fits(next) && !next.held) {
        return following(next);
      }

      if (next.following) {
        return next;
      }

      const top = Math.min(action.top ?? scroll.top, bottomTop(next));

      return { ...next, top: Math.max(0, top) };
    }
    case 'scrolled':
      return scrolled(scroll, action.step);
    case 'scroll_held':
      return scroll.following
        ? {
            ...scroll,
            following: false,
            top: bottomTop(scroll),
            news: false,
            held: true,
          }
        : { ...scroll, held: true };
    case 'scroll_released': {
      if (!scroll.held) {
        return scroll;
      }

      const { held: _, ...released } = scroll;

      // Left over a transcript that fits, it follows as one always does.
      return fits(released) ? following(released) : released;
    }
  }
}

/**
 * The bottom: followed, or while a drag holds the view, its last row with
 * nothing more following, until the release.
 */
function atBottom(scroll: Scroll): Scroll {
  return scroll.held
    ? { ...scroll, following: false, top: bottomTop(scroll), news: false }
    : following(scroll);
}

function scrolled(scroll: Scroll, step: ScrollStep): Scroll {
  if (step === 'bottom') {
    return atBottom(scroll);
  }

  // Nothing to scroll: no indicator, and nothing moves.
  if (fits(scroll)) {
    return scroll;
  }

  const bottom = bottomTop(scroll);
  const from = scroll.following ? bottom : scroll.top;
  const by = {
    page_up: -pageRows(scroll),
    page_down: pageRows(scroll),
    line_up: -1,
    line_down: 1,
    top: -from,
  }[step];
  const to = Math.min(bottom, Math.max(0, from + by));

  if (by > 0) {
    if (scroll.following) {
      return scroll;
    }

    return to >= bottom ? atBottom(scroll) : { ...scroll, top: to };
  }

  if (to === from && !scroll.following) {
    return scroll;
  }

  return { ...scroll, following: false, top: to };
}

/**
 * Rows below the view while scrolled back, counting the row the indicator
 * covers; nothing while following, nor while a press holds the view at the
 * bottom, where nothing is below until output arrives under it (CHD-397).
 */
export function rowsBelow(scroll: Scroll): number | undefined {
  if (scroll.following || (scroll.held && scroll.top >= bottomTop(scroll))) {
    return undefined;
  }

  return Math.max(1, scroll.content - scroll.top - (scroll.view - 1));
}

/** A piece of the indicator, and whether it is drawn in the accent. */
export interface Segment {
  readonly text: string;
  readonly accent: boolean;
}

const RULE = '─';
const NEWS = '↓ new output';

/**
 * The rule that takes the transcript's last row while scrolled back, cut to
 * `width` cells: how much is below, whether any of it is new, and the key
 * back, `bottomKey`, when one is bound. The key goes first when the words do
 * not fit.
 */
export function indicator(
  scroll: Scroll,
  width: number,
  bottomKey: string | undefined,
): Segment[] {
  const below = rowsBelow(scroll);

  if (below === undefined) {
    return [];
  }

  const count = `${below} ${below === 1 ? 'line' : 'lines'} below`;
  const words = scroll.news ? `${NEWS} · ${count}` : `↓ ${count}`;
  const back =
    bottomKey === undefined ? '' : ` · ${bottomKey} to jump to the bottom`;
  const whole = `${RULE}${RULE} ${words}${back} `;
  const text = stringWidth(whole) < width ? whole : `${RULE}${RULE} ${words} `;
  const line = text + RULE.repeat(Math.max(0, width - stringWidth(text)));

  if (!scroll.news) {
    return [{ text: line, accent: false }];
  }

  const at = line.indexOf(NEWS);

  return [
    { text: line.slice(0, at), accent: false },
    { text: NEWS, accent: true },
    { text: line.slice(at + NEWS.length), accent: false },
  ];
}

/** An entry's place in the transcript, in rows. */
export interface Placed {
  readonly top: number;
  readonly height: number;
}

/** The entry at row `top`, and how far into it that row is. */
export interface Anchor {
  readonly entry: number;
  readonly within: number;
}

/**
 * Which entry row `top` falls in, so that a relayout (ctrl+o, a resize) can
 * keep that entry at the top of the view.
 */
export function anchorAt(
  top: number,
  entries: readonly Placed[],
): Anchor | undefined {
  for (let entry = entries.length - 1; entry >= 0; entry--) {
    const placed = entries[entry]!;

    if (placed.top <= top) {
      return { entry, within: top - placed.top };
    }
  }

  return undefined;
}

/** The row `anchor` is at now; as far into its entry as it still reaches. */
export function topOf(
  anchor: Anchor,
  entries: readonly Placed[],
): number | undefined {
  const placed = entries[anchor.entry];

  if (placed === undefined) {
    return undefined;
  }

  return placed.top + Math.min(anchor.within, Math.max(0, placed.height - 1));
}

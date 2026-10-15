/**
 * Which of a transcript's entries are mounted. Only its tail is, while the
 * view follows the bottom, and the rest are only state, as OpenTUI lays out
 * and keeps in memory every renderable mounted. Scrolled back, the entries
 * mounted are held, and the next older ones mount, a chunk at a time, as the
 * view nears the top of them; back at the bottom, the window is the tail
 * again. An entry is mounted whole or not at all: nothing stands in for the
 * rows of one that is not.
 */
import type { Entry } from '../../session/transcript/types.ts';
import { agentGroup, workOf } from './agents/subagents.ts';
import type { Scroll } from './scroll.ts';

/** What the tail mounts while the view follows the bottom, in weight. */
export const TAIL_ENTRIES = 40;

/** What mounts above the window at once as the view nears its top. */
export const BACKFILL_ENTRIES = 60;

/** A session's transcript as it is mounted. */
export interface Mounting {
  readonly transcript: { readonly entries: readonly Entry[] };
  /** ctrl+o's view, which opens a subagent group into its work. */
  readonly expanded: boolean;
  readonly scroll: Scroll;
  /**
   * The first entry mounted while scrolled back, held so that new output
   * does not unmount what is on screen; none while following.
   */
  readonly mounted?: number;
  /**
   * The window's selection: one dragged or shown holds the mounted entries
   * as scrolling back does, so the text it covers is not unmounted under it
   * when the view follows again (CHD-172).
   */
  readonly selection?: { readonly kind: string };
}

/** Whether a selection holds the mounted entries where they are. */
function selecting(state: Mounting): boolean {
  return state.selection !== undefined && state.selection.kind !== 'none';
}

/**
 * What the entry at `index` costs to mount: one for most, as one is drawn;
 * a subagent group one while folded and one more for each block of its
 * agents' work once ctrl+o opens it; nothing for a subagent its group
 * further up draws.
 */
export function entryWeight(
  entries: readonly Entry[],
  index: number,
  expanded: boolean,
): number {
  const group = agentGroup(entries, index);

  if (group === undefined) {
    return 1;
  }

  if (group.length === 0) {
    return 0;
  }

  return expanded
    ? group.reduce((sum, subagent) => sum + workOf(subagent).length, 1)
    : 1;
}

/** The first entry such that the entries from it up to `end` cost `budget`. */
export function entriesBefore(
  entries: readonly Entry[],
  end: number,
  budget: number,
  expanded: boolean,
): number {
  let index = Math.min(end, entries.length);

  for (let spent = 0; index > 0 && spent < budget;) {
    spent += entryWeight(entries, --index, expanded);
  }

  return index;
}

/**
 * The first entry of the tail. At least as many as the view has rows, so the
 * tail always overflows a tall view and can be scrolled back at all, as each
 * entry drawn takes a row.
 */
export function tailStart(state: Mounting): number {
  return entriesBefore(
    state.transcript.entries,
    state.transcript.entries.length,
    Math.max(TAIL_ENTRIES, state.scroll.view + 1),
    state.expanded,
  );
}

/**
 * The first entry mounted: the tail's while following, and while scrolled
 * back the held one, or the tail's where ctrl+o has opened the tail past it.
 */
export function firstMounted(state: Mounting): number {
  return Math.min(state.mounted ?? Infinity, tailStart(state));
}

/**
 * The entry held as the first mounted once `after` follows from `before`:
 * none while following with no selection, the very first for home, which
 * goes to the top, and the tail's first as the view leaves the bottom or a
 * selection starts, held from then on.
 */
export function heldMount(
  before: Mounting,
  after: Mounting,
  home: boolean,
): number | undefined {
  if (after.scroll.following && !selecting(after)) {
    return undefined;
  }

  if (home) {
    return 0;
  }

  return after.mounted ?? firstMounted(before);
}

/**
 * The first entry mounted once the next older chunk is, as the view nears
 * the top of the window starting at `from`; undefined when `from` is not the
 * window's first any more, as a measure asks again until React draws it.
 */
export function backfilled(state: Mounting, from: number): number | undefined {
  if (state.scroll.following || from !== firstMounted(state) || from === 0) {
    return undefined;
  }

  return entriesBefore(
    state.transcript.entries,
    from,
    BACKFILL_ENTRIES,
    state.expanded,
  );
}

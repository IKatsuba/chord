/**
 * What the transcript and its area measure once a frame has laid the window
 * out, for the scroll to work from.
 */
import type { BoxRenderable, Renderable } from '@opentui/core';
import { useRenderer } from '@opentui/react';
import {
  type Dispatch,
  type RefObject,
  useCallback,
  useLayoutEffect,
  useMemo,
  useRef,
} from 'react';
import {
  type Anchor,
  anchorAt,
  type Placed,
  rowsBelow,
  topOf,
} from '../transcript/scroll.ts';
import type { AppState, WindowedAction } from './state.ts';

/**
 * How far into an entry's box the row a jump goes to is: the first drawn
 * row of the box with id `target` in it, where one is drawn, else of the
 * entry's own; past the blank line each keeps above it, so its own first
 * line goes on top.
 */
function rowOf(entry: Renderable, target: string | undefined): number {
  const found =
    target === undefined ? undefined : entry.findDescendantById(target);
  let row = 0;

  // Up from the box found to the entry's, each box placed in its parent.
  for (let at = found; at && at !== entry; at = at.parent ?? undefined) {
    row += at.getLayout().top;
  }

  for (
    let at = (found ?? entry).getChildren()[0];
    at;
    at = at.getChildren()[0]
  ) {
    row += at.getLayout().top;
  }

  return row;
}

export interface Measured {
  /** The transcript's area, which shows part of it. */
  viewport: RefObject<BoxRenderable | null>;
  /** The transcript, whole. */
  content: RefObject<BoxRenderable | null>;
  /**
   * The ref for the box of the entry at `index`, which keeps each entry's
   * box by its place in the transcript; the same function for an index on
   * every draw, as a new one would be detached and attached again.
   */
  place: (index: number) => (node: BoxRenderable | null) => void;
  /**
   * Reads them all, and moves the view onto its entry in the same frame;
   * the transcript's `onSizeChange`, which a frame calls as it lays out a
   * new size, and its `renderAfter`, for a relayout that keeps the size.
   */
  measure: () => void;
}

/**
 * After every frame: what the transcript and its area measure, and, while
 * scrolled back, the entry at the top of the view, which stays there
 * whatever lays the rows above it out again: ctrl+o, a resize, an entry
 * above that grows. OpenTUI lays a resize out over several frames, as a
 * text is cut to the width its box was given in the one before, so the view
 * is held on its entry rather than re-read from a frame half laid out.
 */
export function useMeasured(
  state: AppState,
  /** The session in front, whose transcript is drawn: main or a child. */
  front: number,
  /** The first of its entries mounted (`mount.ts`). */
  first: number,
  dispatch: Dispatch<WindowedAction>,
): Measured {
  const renderer = useRenderer();
  const viewport = useRef<BoxRenderable>(null);
  const content = useRef<BoxRenderable>(null);
  // The boxes the native scene culls by, as `Clip` mounts them anew when its
  // area comes back from no rows.
  const culled = useRef<BoxRenderable | null>(null);
  const placedRefs = useRef<(BoxRenderable | null)[]>([]);
  const placers = useRef<((node: BoxRenderable | null) => void)[]>([]);
  // The frame reads what React last drew, outside any render.
  const latest = useRef({ state, front, first });
  // Each session's entry the view is held on, the row it put the view at,
  // and the row before, which the window still has until React draws the
  // move: any other top is the person's own scroll, and the entry is read
  // again. By session, as another's top can be the same row of other
  // entries, and one shown again finds its entry where a resize meanwhile
  // moved it.
  const anchors = useRef(
    new Map<number, { at: Anchor; top: number; from: number }>(),
  );
  // The window a backfill was last asked for from, until React mounts it or
  // the view follows again; the same window held later asks anew.
  const asked = useRef<{ front: number; first: number }>(undefined);
  // A shift React set that a drag's selection must be read against, once
  // the frame has laid the transcript out under it.
  const shifted = useRef(false);

  latest.current = { state, front, first };

  const measure = useMemo(
    () => () => {
      if (!viewport.current || !content.current) {
        return;
      }

      // What OpenTUI's ScrollBox does for `viewportCulling`: the native scene
      // paints none of the transcript's entries that fall outside its area.
      // Layout is still the whole transcript's.
      if (culled.current !== content.current) {
        renderer.nativeScene.setViewport(content.current, viewport.current);

        culled.current = content.current;
      }

      const {
        state: { scroll, transcript, jump },
        front,
        first,
      } = latest.current;
      // A drag's focus is a screen cell: once the text under it has moved,
      // OpenTUI reads that cell again only on the next motion, so it is
      // asked to now (CHD-172).
      const reselect = () => {
        if (latest.current.state.selection?.kind === 'dragging') {
          renderer.requestSelectionUpdate();
        }
      };

      if (shifted.current) {
        shifted.current = false;

        reselect();
      }

      const whole = content.current.getLayout();
      const view =
        viewport.current.getLayout().height +
        // The indicator's row is the transcript's while it is drawn, and
        // a press held at the bottom draws none (CHD-397).
        (rowsBelow(scroll) === undefined ? 0 : 1);

      if (
        scroll.following ||
        (asked.current !== undefined &&
          (asked.current.front !== front || asked.current.first !== first))
      ) {
        asked.current = undefined;
      }

      if (scroll.following) {
        anchors.current.delete(front);

        if (whole.height !== scroll.content || view !== scroll.view) {
          dispatch({ type: 'scroll_measured', content: whole.height, view });
        }

        return;
      }

      // From the first entry mounted; an anchor's entry is the
      // transcript's, counted from its very first.
      const placed = placedRefs.current
        .slice(first, transcript.entries.length)
        .map((node): Placed => {
          const { top, height } = node ? node.getLayout() : whole;

          return { top: node ? top : 0, height };
        });

      // An entry asked for goes on top once React has mounted it, as far
      // down as the view goes; one gone from the transcript is let go.
      const box =
        jump === undefined || jump.entry < first
          ? undefined
          : placedRefs.current[jump.entry];
      const jumped =
        jump === undefined || jump.entry >= transcript.entries.length
          ? undefined
          : box
            ? Math.min(
                box.getLayout().top + rowOf(box, jump.target),
                Math.max(0, whole.height - view),
              )
            : null;

      if (jump !== undefined && jumped !== null) {
        dispatch({ type: 'jump_done' });
      }

      const kept =
        typeof jumped === 'number' ? undefined : anchors.current.get(front);
      const held =
        kept !== undefined &&
        (kept.top === scroll.top || kept.from === scroll.top)
          ? kept
          : undefined;
      const still =
        held && topOf({ ...held.at, entry: held.at.entry - first }, placed);
      const top =
        (typeof jumped === 'number' ? jumped : undefined) ??
        still ??
        scroll.top;
      const read = anchorAt(top, placed);
      const at =
        held !== undefined && still !== undefined
          ? held.at
          : read && { ...read, entry: read.entry + first };

      if (at === undefined) {
        anchors.current.delete(front);
      } else {
        anchors.current.set(front, {
          at,
          top,
          // Until React draws a move the window has the top before it.
          from:
            held !== undefined && held.top !== scroll.top
              ? held.from
              : scroll.top,
        });
      }

      // Set from inside the frame that laid it out, the frame draws it
      // already, where a prop React sets would wait for the next frame.
      if (top !== scroll.top) {
        content.current.translateY = -top;

        reselect();
      }

      if (
        whole.height !== scroll.content ||
        view !== scroll.view ||
        top !== scroll.top
      ) {
        dispatch({
          type: 'scroll_measured',
          content: whole.height,
          view,
          top,
        });
      }

      // Within a view of the top of what is mounted, the older entries
      // mount; the view stays on its entry as they push it down.
      if (first > 0 && top < view && asked.current === undefined) {
        asked.current = { front, first };

        dispatch({ type: 'backfilled', from: first });
      }
    },
    [dispatch, renderer],
  );

  // The transcript drawn from its row on top, as React last drew the scroll:
  // a box's `translateY`, which OpenTUI's props for a `<box>` leave out.
  const shift = state.scroll.following ? 0 : -state.scroll.top;

  useLayoutEffect(() => {
    if (content.current && content.current.translateY !== shift) {
      content.current.translateY = shift;

      // As above: a wheel step during a drag extends the selection. Read in
      // the frame, not here: the press that stops the view following also
      // moves the transcript from the bottom to the top, which only the
      // frame lays out, and a selection read before it reaches to the end
      // of the transcript (CHD-410).
      shifted.current = true;
    }
  }, [shift]);

  const place = useCallback(
    (index: number) =>
      (placers.current[index] ??= (node) => {
        placedRefs.current[index] = node;
      }),
    [],
  );

  return { viewport, content, place, measure };
}

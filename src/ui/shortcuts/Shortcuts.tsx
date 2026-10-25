import {
  type BoxRenderable,
  LinearScrollAccel,
  type MouseEvent,
  type ScrollBoxRenderable,
} from '@opentui/core';
import {
  type RefObject,
  useCallback,
  useContext,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import { Keys, useHintKey } from '../app/context.ts';
import type { RequestScroller } from '../dialogs/Permission.tsx';
import {
  hiddenRows,
  requestRule,
  requestStep,
  requestView,
} from '../dialogs/permission.ts';
import type { ScrollStep } from '../transcript/scroll.ts';
import { CUT, DIM } from '../theme/text.ts';
import {
  columnCount,
  PANEL_PADDING,
  panelRows,
  shortcutLine,
  shortcuts,
} from './keys.ts';

/**
 * The `?` panel in place of the status line, in as many of Claude Code's three
 * columns as fit the window unfolded. Taller than the rows the window has
 * left it, it scrolls as an overflowing permission request does: in
 * OpenTUI's scrollbox, by the wheel over it and the scroll keys the window
 * hands it, a dim rule saying how many rows are out of view above and below
 * (CHD-378, the owner's Q217).
 */
export function Shortcuts({
  width,
  scroller,
  onOverflow,
}: {
  width: number;
  scroller?: RefObject<RequestScroller | undefined>;
  onOverflow?: (overflows: boolean) => void;
}) {
  const lines = shortcuts(useContext(Keys)).map(shortcutLine);
  const rows = panelRows(lines, columnCount(lines, width));
  const view = useRef<ScrollBoxRenderable | null>(null);
  const area = useRef<BoxRenderable | null>(null);
  const [room, setRoom] = useState(Number.POSITIVE_INFINITY);
  const [top, setTop] = useState(0);
  const total = rows.length;
  const overflows = total > room;
  const shown = requestView(total, room, top);
  const hidden = hiddenRows(total, shown.top, shown.shown);
  const pageUp = useHintKey('scroll:pageUp');
  const pageDown = useHintKey('scroll:pageDown');
  // From the panel's indent to the window's edge, as the box above it runs.
  const ruled = width - PANEL_PADDING;
  const scroll = useCallback(
    (step: ScrollStep) => {
      const box = view.current;

      if (box !== null) {
        box.scrollTo(requestStep(step, total, room, box.scrollTop));
      }
    },
    [total, room],
  );

  // The wheel can leave the scrollbox past a view there is, and a resize
  // moves the end: the view goes back to the row it may show.
  useEffect(() => {
    const box = view.current;

    if (box !== null && box.scrollTop !== shown.top) {
      box.scrollTo(shown.top);
    }
  }, [shown.top]);

  useEffect(() => {
    onOverflow?.(overflows);
  }, [onOverflow, overflows]);

  useEffect(() => {
    if (scroller === undefined) {
      return;
    }

    scroller.current = scroll;

    return () => {
      scroller.current = undefined;
    };
  }, [scroller, scroll]);

  // The scrollbox moves by itself under the wheel; its scrollbar says where.
  useLayoutEffect(() => {
    const bar = view.current?.verticalScrollBar;
    const moved = ({ position }: { position: number }) => setTop(position);

    bar?.on('change', moved);

    return () => {
      bar?.off('change', moved);
    };
  }, []);

  return (
    <box
      paddingLeft={PANEL_PADDING}
      flexBasis={total}
      // Not 1: Yoga leaves an item at its basis rather than shrink it to
      // exactly its minimum.
      minHeight={0}
      flexShrink={1}
      overflow='hidden'
      ref={area}
      onSizeChange={() => setRoom(area.current?.getLayout().height ?? total)}
    >
      {shown.above && (
        <Rule text={requestRule('↑', hidden.above, pageUp, ruled)} />
      )}
      <scrollbox
        ref={view}
        visible={shown.shown > 0}
        // Flex sizing put the rule on the viewport's last row in a short
        // window. Pin the reserved rows so both use the same boundary.
        height={shown.shown}
        flexShrink={0}
        minHeight={0}
        focusable={false}
        scrollAcceleration={WHEEL}
        verticalScrollbarOptions={{ visible: false }}
        // Over a panel that scrolls, the wheel is its own, not the view's.
        onMouseScroll={(event: MouseEvent) => {
          if (overflows) {
            event.stopPropagation();
          }
        }}
      >
        {rows.map((row, index) => (
          <text key={index} {...CUT} attributes={DIM} flexShrink={0}>
            {row === '' ? ' ' : row}
          </text>
        ))}
      </scrollbox>
      {shown.below && (
        <Rule text={requestRule('↓', hidden.below, pageDown, ruled)} />
      )}
    </box>
  );
}

function Rule({ text }: { text: string }) {
  return (
    <text {...CUT} attributes={DIM} flexShrink={0}>
      {text}
    </text>
  );
}

/** A row a wheel report moves the panel, as it moves the transcript. */
const WHEEL = new LinearScrollAccel();

import type { BoxRenderable, OptimizedBuffer } from '@opentui/core';
import type { BoxProps } from '@opentui/react';
import { useRef, useState } from 'react';

/**
 * A `<box>` that clips what it holds, as the transcript's area does,
 * drawing nothing while the layout gives it no rows or no columns. OpenTUI
 * draws every renderable at least one cell high, so a box laid out to
 * nothing would still draw a row, with everything in it laid out to nothing
 * too and drawn on that one row.
 */
export function Clip({ ref, children, renderAfter, ...props }: BoxProps) {
  const node = useRef<BoxRenderable | null>(null);
  const [empty, setEmpty] = useState(false);
  // What the last read said, so a read that finds the same asks nothing.
  const shown = useRef(empty);

  shown.current = empty;

  /** Yoga's size for the box, read again: none, or some. */
  const read = () => {
    const laid = node.current?.getLayout();
    const nothing =
      laid !== undefined && (laid.height === 0 || laid.width === 0);

    if (nothing !== shown.current) {
      shown.current = nothing;

      setEmpty(nothing);
    }
  };

  return (
    <box
      {...props}
      overflow='hidden'
      ref={(box: BoxRenderable | null) => {
        node.current = box;

        if (typeof ref === 'function') {
          ref(box);
        } else if (ref) {
          ref.current = box;
        }
      }}
      // A size laid out to nothing is drawn as one cell, so a change to or
      // from nothing is a change OpenTUI reports, but it is read off Yoga.
      onSizeChange={read}
      // Except from one row to none: drawn one cell high either way, OpenTUI
      // reports no change, so Yoga is read again after each frame drawn
      // (the owner's Q57, CHD-158).
      renderAfter={function (
        this: BoxRenderable,
        buffer: OptimizedBuffer,
        deltaTime: number,
      ) {
        read();
        renderAfter?.call(this, buffer, deltaTime);
      }}
    >
      {empty ? null : children}
    </box>
  );
}

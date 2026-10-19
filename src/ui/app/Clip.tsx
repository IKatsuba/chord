import type { BoxRenderable } from '@opentui/core';
import type { BoxProps } from '@opentui/react';
import { useRef, useState } from 'react';

/**
 * A `<box>` that clips what it holds, as the transcript's area does,
 * drawing nothing while the layout gives it no rows or no columns. OpenTUI
 * draws every renderable at least one cell high, so a box laid out to
 * nothing would still draw a row, with everything in it laid out to nothing
 * too and drawn on that one row.
 */
export function Clip({ ref, children, ...props }: BoxProps) {
  const node = useRef<BoxRenderable | null>(null);
  const [empty, setEmpty] = useState(false);

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
      onSizeChange={() => {
        const laid = node.current?.getLayout();

        setEmpty(laid !== undefined && (laid.height === 0 || laid.width === 0));
      }}
    >
      {empty ? null : children}
    </box>
  );
}

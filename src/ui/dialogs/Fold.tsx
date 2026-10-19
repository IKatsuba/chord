import type { BoxRenderable } from '@opentui/core';
import { type ReactNode, useRef, useState } from 'react';
import { DIM, TEXT } from '../theme/text.ts';
import { foldOf, moreLines } from './fold.ts';

/**
 * A held box's lines above its hint, which give way where the window has no
 * room for them: the transcript goes first, then these fold from the bottom
 * under `… N more lines` (CHD-158 §8). Not held, they are drawn whole, as the
 * box always drew them.
 */
export function Fold({
  held,
  children,
}: {
  held: boolean;
  children: ReactNode;
}) {
  const area = useRef<BoxRenderable | null>(null);
  const body = useRef<BoxRenderable | null>(null);
  const [room, setRoom] = useState(Number.POSITIVE_INFINITY);
  const [lines, setLines] = useState(0);

  // Not held, nothing folds; the boxes stay, so the lines are not mounted
  // anew as the keys come into the box.
  const { shown, more } = held
    ? foldOf(lines, room)
    : { shown: lines, more: 0 };

  return (
    <box
      ref={area}
      // Held, its own lines are its basis, so Yoga takes from it only what
      // the window lacks.
      flexBasis={held && lines > 0 ? lines : 'auto'}
      minHeight={0}
      flexShrink={held ? 1 : 0}
      overflow={held ? 'hidden' : 'visible'}
      onSizeChange={() =>
        setRoom(area.current?.getLayout().height ?? Number.POSITIVE_INFINITY)
      }
    >
      <box
        height={more > 0 ? shown : 'auto'}
        // Laid out to no rows, a box is still drawn a row high.
        visible={more === 0 || shown > 0}
        flexShrink={0}
        overflow={more > 0 ? 'hidden' : 'visible'}
      >
        <box
          ref={body}
          flexShrink={0}
          onSizeChange={() => setLines(body.current?.getLayout().height ?? 0)}
        >
          {children}
        </box>
      </box>
      {more > 0 && (
        <text {...TEXT} attributes={DIM} flexShrink={0}>
          {`  ${moreLines(more)}`}
        </text>
      )}
    </box>
  );
}

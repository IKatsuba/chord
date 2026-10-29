import { RGBA } from '@opentui/core';
import { type ReactNode, useState } from 'react';
import { CUT, DIM } from '../theme/text.ts';
import { overlayRoom, overlayRule } from './overlay.ts';

/**
 * Where the lists that open while the prompt is edited are drawn: a layer
 * over the transcript's bottom rows, its bottom edge where this anchor sits,
 * right above the prompt, so the transcript keeps its rows and scroll and
 * the prompt and the rows under it stay put (CHD-545). The anchor takes no
 * row; it stays mounted with nothing open so its place is known before a
 * list opens. A frameless list has a dim rule on top. The list is handed
 * the rows it may take: a box laid out over the transcript sizes a child to
 * what it draws, not to its flex basis, so a list cannot measure its room
 * (CHD-545, Q315).
 */
export function Overlay({
  columns,
  ruled,
  children,
}: {
  columns: number;
  ruled: boolean;
  /** The list, or none while nothing is open, given the rows it may take. */
  children: (room: number) => ReactNode;
}) {
  const [edge, setEdge] = useState(0);
  const room = overlayRoom(edge);
  const list = children(Math.max(0, room - Number(ruled)));
  const open = list !== undefined && list !== null && list !== false;

  return (
    <box
      height={0}
      flexShrink={0}
      // Above its siblings, the transcript and the Working line, which
      // would otherwise paint over it.
      zIndex={1}
      renderAfter={function () {
        if (this.y !== edge) {
          setEdge(this.y);
        }
      }}
    >
      {open && (
        <box
          position='absolute'
          bottom={0}
          left={0}
          width={columns}
          maxHeight={room}
          // Above the transcript, and filled, so none of it shows through
          // the cells the list leaves blank.
          zIndex={1}
          backgroundColor={RGBA.defaultBackground()}
          flexDirection='column'
        >
          {ruled && (
            <box paddingX={1} height={1} flexShrink={0}>
              <text {...CUT} attributes={DIM}>
                {overlayRule(columns - 2)}
              </text>
            </box>
          )}
          {list}
        </box>
      )}
    </box>
  );
}

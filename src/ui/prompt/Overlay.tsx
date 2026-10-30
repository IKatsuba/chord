import { RGBA } from '@opentui/core';
import { type ReactNode, useState } from 'react';
import { CUT, DIM } from '../theme/text.ts';
import { overlayRoom, overlayRule } from './overlay.ts';

/** Whether a render gave anything to draw. */
const drawn = (node: ReactNode) =>
  node !== undefined && node !== null && node !== false;

/**
 * Where the lists that open while the prompt is edited, and the command
 * pickers, are drawn: a layer over the transcript's bottom rows, its bottom
 * edge where this anchor sits, right above the prompt, so the transcript
 * keeps its rows and scroll and the prompt and the rows under it stay put
 * (CHD-545). The anchor takes no row; it stays mounted with nothing open so
 * its place is known before anything opens.
 *
 * A picker goes on top, its frame the layer's edge; a list without one has
 * a dim rule there. Each is handed the rows it may take, as a box laid out
 * over the transcript sizes a child to what it draws, not to its flex basis,
 * so neither can measure its room (Q315): the picker the whole room, the
 * list what the picker leaves, as when they took the transcript's rows.
 */
export function Overlay({
  columns,
  picker,
  list,
}: {
  columns: number;
  /** The picker open, or none, given the rows it may take. */
  picker: (room: number) => ReactNode;
  /** The list open next to the prompt, or none, given the rows it may take. */
  list: (room: number) => ReactNode;
}) {
  const [edge, setEdge] = useState(0);
  // The rows the picker draws, which the list may not take.
  const [taken, setTaken] = useState(0);
  const room = overlayRoom(edge);
  const top = picker(room);
  const framed = drawn(top);
  const below = list(Math.max(0, room - (framed ? taken : 1)));
  const open = framed || drawn(below);

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
          // Nothing it holds paints past its edge onto the prompt, the gap
          // row above it or the rows under it, whatever the room.
          overflow='hidden'
          // Above the transcript, and filled, so none of it shows through
          // the cells the list leaves blank.
          zIndex={1}
          backgroundColor={RGBA.defaultBackground()}
          flexDirection='column'
        >
          {framed ? (
            <box
              // A picker taller than the room fits it as its frame says how:
              // its body is cut, its title and hint stay. It keeps its rows
              // before the list does, as in the window's flow.
              flexShrink={0}
              maxHeight={room}
              renderAfter={function () {
                if (this.height !== taken) {
                  setTaken(this.height);
                }
              }}
            >
              {top}
            </box>
          ) : (
            <box paddingX={1} height={1} flexShrink={0}>
              <text {...CUT} attributes={DIM}>
                {overlayRule(columns - 2)}
              </text>
            </box>
          )}
          <box flexShrink={1} minHeight={0} overflow='hidden'>
            {below}
          </box>
        </box>
      )}
    </box>
  );
}

import { useContext } from 'react';
import { Keys } from '../app/context.ts';
import { DIM, TEXT } from '../theme/text.ts';
import {
  columnCount,
  inColumns,
  PANEL_GAP,
  PANEL_PADDING,
  shortcutLine,
  shortcuts,
} from './keys.ts';

/**
 * The `?` panel in place of the status line, in as many of Claude Code's three
 * columns as fit the window unfolded.
 */
export function Shortcuts({ width }: { width: number }) {
  const lines = shortcuts(useContext(Keys)).map(shortcutLine);

  return (
    <box
      flexDirection='row'
      paddingLeft={PANEL_PADDING}
      gap={PANEL_GAP}
      flexShrink={0}
    >
      {inColumns(lines, columnCount(lines, width)).map((column, index) => (
        <box key={index} flexShrink={1}>
          {column.map((line) => (
            <text key={line} {...TEXT} attributes={DIM}>
              {line}
            </text>
          ))}
        </box>
      ))}
    </box>
  );
}

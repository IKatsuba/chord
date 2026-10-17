import { TextAttributes } from '@opentui/core';
import { useColours } from '../app/context.ts';
import { DIM, fg, TEXT } from '../theme/text.ts';
import type { Palette } from '../theme/theme.ts';
import {
  type BackgroundItem,
  summaryGroups,
  summaryLines,
  type SummaryPiece,
} from './background.ts';

/** A group's colour: its state's role, or dim for those at work or stopped. */
function pieceColour(
  tone: SummaryPiece['tone'],
  colours: Palette,
): string | undefined {
  switch (tone) {
    case 'asking':
      return colours.warning;
    case 'failed':
      return colours.error;
    case 'done':
      return colours.success;
    default:
      return undefined;
  }
}

/**
 * The background's summary line, the last of the area under the status
 * line, after the agents list: `background`, then a group per state,
 * wrapped between groups and never cut. It takes no keys itself; the window
 * routes them.
 */
export function SummaryLine({
  items,
  width,
  focused,
}: {
  items: readonly BackgroundItem[];
  /** Cells inside the list's padding. */
  width: number;
  /** It has the `❯` while the list has the keys. */
  focused: boolean;
}) {
  const colours = useColours();

  if (items.length === 0) {
    return null;
  }

  // Past the `❯` and its space, which every line keeps room for.
  const lines = summaryLines(summaryGroups(items), Math.max(1, width - 2));

  return (
    <box paddingX={2} flexShrink={0}>
      {lines.map((line, index) => (
        <text key={index} {...TEXT}>
          <span {...fg(colours.permission)}>
            {focused && index === 0 ? '❯ ' : '  '}
          </span>
          {line.map((piece, at) => {
            const colour = pieceColour(piece.tone, colours);

            return (
              <span
                key={at}
                {...fg(colour)}
                attributes={
                  piece.tone === 'label' && focused
                    ? TextAttributes.BOLD
                    : colour === undefined
                      ? DIM
                      : 0
                }
              >
                {piece.text}
              </span>
            );
          })}
        </text>
      ))}
    </box>
  );
}

import { TextAttributes } from '@opentui/core';
import { hintOf, useColours, useHintKey } from '../app/context.ts';
import { useAgentsClock } from '../agents/Agents.tsx';
import { DIM, fg, TEXT } from '../theme/text.ts';
import { agentColour, type Palette } from '../theme/theme.ts';
import type { BackgroundGroup, BackgroundItem } from './background.ts';
import { type ItemRef, type ViewCell, viewRows, viewWindow } from './view.ts';

/** A state's colour: its group's role, or dim for those at work or stopped. */
function groupColour(
  group: BackgroundGroup | undefined,
  colours: Palette,
): string | undefined {
  switch (group) {
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

/** The lines the title, the gap under it and the hint with its gap take. */
const CHROME = 4;

/**
 * The background view: the whole window, with no header, transcript, prompt
 * or status line, a row per item of the tab, the `❯` on one. It takes no
 * keys itself; the window routes them.
 */
export function BackgroundView({
  items,
  focus,
  columns,
  rows,
}: {
  items: readonly BackgroundItem[];
  focus: ItemRef | undefined;
  columns: number;
  rows: number;
}) {
  const colours = useColours();
  // Times count a second at a time while the view is drawn.
  const now = useAgentsClock(true);
  const laid = viewRows(items, { width: columns - 4, focus, now });
  const shown = viewWindow(laid, Math.max(1, rows - CHROME));
  const stop = useHintKey('agents:close');
  const close = useHintKey('select:cancel');
  const cell = (piece: ViewCell, item: BackgroundItem, focused: boolean) => {
    switch (piece.role) {
      case 'mark':
        return { ...fg(colours.permission), attributes: 0 };
      case 'name':
        return { attributes: focused ? TextAttributes.BOLD : 0 };
      case 'state': {
        const colour = groupColour(piece.group, colours);

        return { ...fg(colour), attributes: colour === undefined ? DIM : 0 };
      }
      case 'owner': {
        const colour = agentColour(colours, item.owner?.colour);

        return { ...fg(colour), attributes: colour === undefined ? DIM : 0 };
      }
      default:
        return { attributes: DIM };
    }
  };

  return (
    <box width={columns} height={rows} flexShrink={0}>
      <box paddingX={1} flexShrink={0}>
        <text {...TEXT}>
          <span attributes={TextAttributes.BOLD}>Background</span>
          <span attributes={DIM}>{` · ${items.length} in this tab`}</span>
        </text>
      </box>
      <box height={1} flexShrink={0} />
      <box paddingX={2} flexGrow={1} flexShrink={1}>
        {shown.above > 0 && (
          <text {...TEXT} attributes={DIM}>{`  … ${shown.above} above`}</text>
        )}
        {shown.rows.map((row) =>
          row.lines.map((line, index) => (
            <text key={`${row.item.key}:${row.item.id}:${index}`} {...TEXT}>
              {line.map((piece, at) => (
                <span key={at} {...cell(piece, row.item, row.focused)}>
                  {piece.text}
                </span>
              ))}
            </text>
          )),
        )}
        {shown.below > 0 && (
          <text {...TEXT} attributes={DIM}>{`  … ${shown.below} below`}</text>
        )}
      </box>
      <box paddingX={1} flexShrink={0}>
        <text {...TEXT} attributes={DIM}>
          {hintOf(
            '↑ ↓ to move',
            'enter to go to its call',
            stop && `${stop} to stop`,
            close && `${close} to close`,
          )}
        </text>
      </box>
    </box>
  );
}

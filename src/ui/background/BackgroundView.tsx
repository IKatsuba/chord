import { TextAttributes } from '@opentui/core';
import {
  hintOf,
  useCloseHint,
  useColours,
  useHintKey,
} from '../app/context.ts';
import { useAgentsClock } from '../agents/Agents.tsx';
import { borderOf } from '../pickers/Pickers.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import { DIM, fg, TEXT } from '../theme/text.ts';
import { agentColour, type Palette } from '../theme/theme.ts';
import type { BackgroundGroup, BackgroundItem } from './background.ts';
import {
  edgeMarked,
  hintLines,
  type ItemRef,
  laidAt,
  type ViewAt,
  type ViewCell,
  viewRows,
  viewWindow,
} from './view.ts';

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

/**
 * The frame's lines besides its rows: the border, the title and the gap
 * under it, and the hint with the gap above it.
 */
const CHROME = 6;

/**
 * The lines the frame's rows take at most: half the window less its other
 * lines (CHD-462), a hint of `hintHeight` lines among them; the rows give
 * way to a hint that wraps, never the hint (CHD-473).
 */
export function backgroundRowLimit(windowRows: number, hintHeight = 1): number {
  return Math.max(1, Math.floor(windowRows / 2) - CHROME - (hintHeight - 1));
}

/**
 * What the frame says under its rows: `hint`, an agent's stop error, in
 * place of its keys, or the keys.
 */
export function useBackgroundHint(hint: string | undefined): string {
  const stop = useHintKey('agents:close');
  const close = useCloseHint();

  return (
    hint ?? hintOf('Enter to go to its call', stop && `${stop} to stop`, close)
  );
}

/**
 * The background view: the pickers' frame above the prompt, full width, a
 * row per item of the tab, the `❯` on one, as tall as its rows up to half
 * the window (CHD-462). It takes no keys itself; the window routes them.
 */
export function BackgroundView({
  items,
  focus,
  at,
  hint,
  columns,
  rows,
}: {
  items: readonly BackgroundItem[];
  focus: ItemRef | undefined;
  /** Where in a focused row taller than the frame it is (CHD-430). */
  at?: ViewAt | undefined;
  /** Said in place of the keys, of the focused item's stop. */
  hint?: string | undefined;
  /** The window's width; the frame takes all of it. */
  columns: number;
  /** The window's height, half of which the frame takes at most. */
  rows: number;
}) {
  const colours = useColours();
  // Times count a second at a time while the view is drawn.
  const now = useAgentsClock(true);
  const laid = viewRows(items, { width: columns - 4, focus, now });
  // The hint, or an error in its place, whole on as many lines as it takes.
  const said = hintLines(useBackgroundHint(hint), columns - 4);
  const height = backgroundRowLimit(rows, said.length);
  const lines = edgeMarked(
    viewWindow(laid, height, at, laidAt(columns - 4, height)),
  );
  const cell = (piece: ViewCell, item: BackgroundItem, focused: boolean) => {
    switch (piece.role) {
      case 'mark':
        return { ...fg(colours.permission), attributes: 0 };
      case 'edge':
        return { attributes: DIM };
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
    <box
      {...borderOf(colours.permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      <text {...TEXT}>
        <span {...fg(colours.permission)} attributes={TextAttributes.BOLD}>
          Background
        </span>
        <span attributes={DIM}>{` · ${items.length} in this tab`}</span>
      </text>
      <box marginTop={1} flexShrink={0}>
        {lines.map(({ row, cells }, index) => (
          <text key={index} {...TEXT}>
            {cells.map((piece, at) => (
              <span key={at} {...cell(piece, row.item, row.focused)}>
                {piece.text}
              </span>
            ))}
          </text>
        ))}
      </box>
      <box marginTop={1} flexShrink={0}>
        {said.map((line, at) => (
          <text key={at} {...TEXT} attributes={DIM}>
            <Ansi text={line} />
          </text>
        ))}
      </box>
    </box>
  );
}

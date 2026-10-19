import { TextAttributes } from '@opentui/core';
import { useEffect, useState } from 'react';
import { useColours } from '../app/context.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { CUT, DIM, fg, TEXT } from '../theme/text.ts';
import { agentColour, type Palette } from '../theme/theme.ts';
import {
  type AgentRow,
  agentsLayout,
  type AgentTone,
  childLine,
  listTimed,
} from './agents.ts';

const clockListeners = new Set<(now: number) => void>();
let clockTimer: ReturnType<typeof setInterval> | undefined;

/**
 * The time the list's rows and a child's opening line count on, a second at
 * a time while either is drawn, and one timer for both, so the ages on
 * screen move together.
 */
export function useAgentsClock(on: boolean): number {
  const [now, setNow] = useState(Date.now);

  useEffect(() => {
    if (!on) {
      return;
    }

    setNow(Date.now());
    clockListeners.add(setNow);

    if (clockTimer === undefined) {
      clockTimer = setInterval(() => {
        const at = Date.now();

        for (const listener of clockListeners) {
          listener(at);
        }
      }, 1000);
    }

    return () => {
      clockListeners.delete(setNow);

      if (clockListeners.size === 0) {
        clearInterval(clockTimer);

        clockTimer = undefined;
      }
    };
  }, [on]);

  return now;
}

export function toneColour(
  tone: AgentTone,
  colours: Palette,
): string | undefined {
  return tone === 'dim' ? undefined : colours[tone];
}

/**
 * The session's agents under the status line, the last rows of the window:
 * `main`, then each long-lived child, drawn only while there is a child,
 * a team's members under its lead. The list takes no keys itself; the
 * window routes them.
 */
export function AgentsList({
  rows,
  limit,
  width,
  focused,
}: {
  rows: readonly AgentRow[];
  limit: number;
  /** Cells inside the list's padding. */
  width: number;
  focused: boolean;
}) {
  const colours = useColours();
  // The times on the rows go on counting, as the working line's does.
  const now = useAgentsClock(listTimed(rows));

  if (rows.length === 0) {
    return null;
  }

  const layout = agentsLayout(rows, { limit, width, focused, now });

  return (
    <box paddingX={2} flexShrink={0}>
      {layout.rows.map((laid) => {
        const { row } = laid;
        const colour = agentColour(colours, row.colour);

        return (
          <text key={row.key} {...CUT}>
            <span {...fg(colours.permission)}>{laid.mark}</span>
            {laid.branch && <span attributes={DIM}>{laid.branch}</span>}
            <span
              {...fg(colour)}
              attributes={row.picked ? TextAttributes.BOLD : 0}
            >
              <Ansi text={laid.name} />
            </span>
            <span attributes={DIM}>
              <Ansi text={`  ${laid.detail}`} />
            </span>
            {laid.state && (
              <span
                {...fg(toneColour(laid.state.tone, colours))}
                attributes={laid.state.tone === 'dim' ? DIM : 0}
              >
                {`  ${laid.state.text}`}
              </span>
            )}
            {laid.unseen && (
              <span
                {...fg(toneColour(laid.unseen.tone, colours))}
                attributes={laid.unseen.tone === 'dim' ? DIM : 0}
              >
                {`  ${laid.unseen.text}`}
              </span>
            )}
          </text>
        );
      })}
      {layout.more > 0 && (
        <text {...TEXT} attributes={DIM}>
          {`  … +${layout.more} more`}
        </text>
      )}
    </box>
  );
}

/**
 * The line a child's transcript opens with, in place of the startup header:
 * `parser · codex · gpt-5.3-codex · opened by main 4m ago`.
 */
export function ChildLine({
  child,
  model,
}: {
  child: {
    readonly name: string;
    readonly runtime: string;
    readonly openedAt: number;
    readonly colour: number;
    readonly team?: string | undefined;
    readonly leadName?: string | undefined;
  };
  model: string | undefined;
}) {
  const colours = useColours();
  // Its age goes on with the TUI idle, on the list's clock.
  const line = childLine(child, model, useAgentsClock(true));

  return (
    <box flexDirection='row' flexShrink={0}>
      <text {...CUT}>
        <span
          attributes={TextAttributes.BOLD}
          {...fg(agentColour(colours, child.colour))}
        >
          <Ansi text={line.name} />
        </span>
        <span attributes={DIM}>
          <Ansi text={line.rest} />
        </span>
      </text>
    </box>
  );
}

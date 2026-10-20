import { TextAttributes } from '@opentui/core';
import { Fragment, useEffect, useState } from 'react';
import { useColours } from '../app/context.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { CUT, DIM, fg, TEXT } from '../theme/text.ts';
import { agentColour, type Palette } from '../theme/theme.ts';
import {
  type AgentRow,
  agentsLayout,
  type AgentsView,
  type AgentTone,
  childLine,
  listTimed,
  type Toned,
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
  view,
}: {
  rows: readonly AgentRow[];
  limit: number;
  /** Cells inside the list's padding. */
  width: number;
  focused: boolean;
  /** Where the lines start on a picked row taller than the list. */
  view?: AgentsView | undefined;
}) {
  const colours = useColours();
  // The times on the rows go on counting, as the working line's does.
  const now = useAgentsClock(listTimed(rows));

  if (rows.length === 0) {
    return null;
  }

  const layout = agentsLayout(rows, { limit, width, focused, now, view });

  return (
    <box paddingX={2} flexShrink={0}>
      {layout.rows.map((laid) => {
        const { row } = laid;
        const colour = agentColour(colours, row.colour);
        const toned = ({ text, tone }: Toned, key: string) => (
          <span
            key={key}
            {...fg(toneColour(tone, colours))}
            attributes={tone === 'dim' ? DIM : 0}
          >
            {text}
          </span>
        );
        const name = (text: string) => (
          <span
            {...fg(colour)}
            attributes={row.picked ? TextAttributes.BOLD : 0}
          >
            <Ansi text={text} />
          </span>
        );

        // The `❯` in its colour; a `↑` or `↓` for lines out of sight, dim.
        const gutter = (text: string) =>
          text === laid.mark ? (
            <span {...fg(colours.permission)}>{text}</span>
          ) : (
            <span attributes={DIM}>{text}</span>
          );

        return (
          <Fragment key={row.key}>
            {laid.lines.map(({ at, gutter: beside }) => {
              if (at === 0) {
                return (
                  <text key={at} {...CUT}>
                    {gutter(beside)}
                    {laid.branch && <span attributes={DIM}>{laid.branch}</span>}
                    {name(laid.name)}
                    <span attributes={DIM}>
                      <Ansi text={`  ${laid.detail}`} />
                    </span>
                    {laid.state &&
                      toned(
                        { ...laid.state, text: `  ${laid.state.text}` },
                        'state',
                      )}
                    {laid.unseen &&
                      toned(
                        { ...laid.unseen, text: `  ${laid.unseen.text}` },
                        'unseen',
                      )}
                  </text>
                );
              }

              // Under the name its next line, or as many spaces, then what
              // went under the detail.
              const under = laid.names[at - 1];
              const below = laid.below[at - 1] ?? [];

              return (
                <text key={at} {...CUT}>
                  {gutter(beside)}
                  {under === undefined ? (
                    ' '.repeat(laid.nameWidth)
                  ) : (
                    <>
                      <span attributes={DIM}>{under.tree}</span>
                      {name(under.text)}
                    </>
                  )}
                  {below.length > 0 && '  '}
                  {below.map((run, index) => toned(run, String(index)))}
                </text>
              );
            })}
          </Fragment>
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

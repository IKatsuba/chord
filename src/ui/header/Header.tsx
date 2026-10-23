import chalk from 'chalk';
import { TextAttributes } from '@opentui/core';
import { useMemo } from 'react';
import { useColours, useSelectable } from '../app/context.ts';
import { colour as rgba, CUT, DIM, fg, TEXT } from '../theme/text.ts';
import {
  type HeaderFacts,
  headerLines,
  MARK_GAP,
  markColour,
  RESUMED_LINE,
  textWidth,
} from './header.ts';
import { MARK } from './mark.ts';
import { markRows } from './mark_rows.ts';

/**
 * The startup header, the first thing in a session's transcript: Chorded's
 * mark and the session's lines beside it.
 */
export function Header({
  facts,
  columns,
}: {
  facts: HeaderFacts;
  /** The window's width, which the lines are cut to. */
  columns: number;
}) {
  const { mark: tones } = useColours();
  // Coloured to the depth chalk found the terminal takes, as the rest of
  // chord's colours are.
  const colour = useMemo(() => markColour(tones, chalk.level), [tones]);
  // The transcript draws again on every tick of the working line; the
  // nearest 256 colour is looked up once per half cell, not on each.
  const painted = useMemo(() => markRows(MARK, colour), [colour]);
  const lines = headerLines(facts, textWidth(columns), Date.now());
  const selectable = useSelectable();

  return (
    <box flexDirection='row' flexShrink={0}>
      <box flexShrink={0} marginRight={MARK_GAP}>
        {painted.map((row, index) => (
          <text key={index} {...TEXT}>
            {row.map((segment, at) => (
              <span
                key={at}
                {...fg(segment.color)}
                {...(segment.backgroundColor === undefined
                  ? {}
                  : { bg: rgba(segment.backgroundColor) })}
              >
                {segment.text}
              </span>
            ))}
          </text>
        ))}
      </box>
      <box flexShrink={1}>
        {lines.map((line, index) => (
          <text
            key={index}
            // The agent's title for a resumed session wraps under its own
            // start, never cut (CHD-445); the rest is cut at the edge.
            {...(index === RESUMED_LINE && facts.resumed?.titled === true
              ? TEXT
              : CUT)}
            {...selectable}
          >
            {line.map((part, at) => (
              <span key={at} attributes={part.bold ? TextAttributes.BOLD : DIM}>
                {part.text}
              </span>
            ))}
          </text>
        ))}
      </box>
    </box>
  );
}

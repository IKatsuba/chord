import chalk from 'chalk';
import { useMemo } from 'react';
import { useColours } from '../app/context.ts';
import { colour as rgba, fg, TEXT } from '../theme/text.ts';
import { markColour } from './header.ts';
import { MARK, type MarkGrid } from './mark.ts';
import { markRows } from './mark_rows.ts';

/** Chorded's mark, a row of text for each of its rows, for a box to hold. */
export function Mark({ grid = MARK }: { grid?: MarkGrid }) {
  const { mark: tones } = useColours();
  // Coloured to the depth chalk found the terminal takes, as the rest of
  // chord's colours are.
  const colour = useMemo(() => markColour(tones, chalk.level), [tones]);
  // The transcript draws again on every tick of the working line; the
  // nearest 256 colour is looked up once per half cell, not on each.
  const painted = useMemo(() => markRows(grid, colour), [grid, colour]);

  return painted.map((row, index) => (
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
  ));
}

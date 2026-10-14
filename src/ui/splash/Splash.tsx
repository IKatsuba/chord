import { useEffect, useMemo, useState } from 'react';
import { markRows } from '../header/mark_rows.ts';
import { CUT, DIM, TEXT } from '../theme/text.ts';
import {
  SPLASH_STEP_MS,
  splashFrame,
  splashLayout,
  splashLines,
  splashMark,
} from './splash.ts';

/**
 * The startup splash, alone on the screen until the first session is up:
 * the mark, dim on the terminal's own foreground, and its lines.
 */
export function Splash({
  agent,
  armed,
  closing,
  columns,
  rows,
}: {
  agent: string;
  /** An armed quit's question, which the first line says instead. */
  armed: string | undefined;
  closing: boolean;
  columns: number;
  rows: number;
}) {
  const [opened] = useState(Date.now);
  const [step, setStep] = useState(0);

  // One timer for the drift and the seconds, which draw only when it ticks.
  useEffect(() => {
    const timer = setInterval(() => setStep((at) => at + 1), SPLASH_STEP_MS);

    return () => clearInterval(timer);
  }, []);

  const grid = splashMark(columns, rows);
  const box = useMemo(
    () =>
      grid &&
      markRows(splashFrame(grid, step), { level: 'none' }).map((row) =>
        row.map((segment) => segment.text).join(''),
      ),
    [grid, step],
  );
  const lines = splashLines({
    agent,
    elapsed: Date.now() - opened,
    armed,
    closing,
  });
  const { top, markLeft, lineLefts } = splashLayout(columns, rows, grid, lines);

  return (
    <box width={columns} height={rows} flexShrink={1}>
      <box height={top} flexShrink={0} />
      {box && (
        <box flexShrink={0} marginLeft={markLeft} marginBottom={1}>
          {box.map((row, index) => (
            <text key={index} {...TEXT} attributes={DIM}>
              {row}
            </text>
          ))}
        </box>
      )}
      {lines.map((line, index) => (
        <box
          key={index}
          flexDirection='row'
          flexShrink={0}
          marginLeft={lineLefts[index] ?? 0}
        >
          <text {...CUT} attributes={DIM}>
            {line}
          </text>
        </box>
      ))}
    </box>
  );
}

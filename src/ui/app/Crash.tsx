/**
 * chord's crash screen (`docs/design/CHD-468.md`): a boundary around the
 * window that, when the tree throws while drawing, shows the error and
 * quits on any key, where OpenTUI's own boundary left no way out (Q78).
 */
import { useTerminalDimensions } from '@opentui/react';
import type { ReactNode } from 'react';
import { ErrorBoundary } from 'react-error-boundary';
import { CUT, DIM, fg } from '../theme/text.ts';
import { paletteOf } from '../theme/theme.ts';
import { caughtByBoundary } from './caught.ts';
import { COLOUR, drawnColours } from './context.ts';
import { crashRows } from './crash.ts';
import { usePress } from './input.ts';

/**
 * `children`, or once they throw, the crash screen for what they threw,
 * which hands it to `quit` on the first key.
 */
export function CrashBoundary({
  quit,
  children,
}: {
  quit: (error: unknown) => void;
  children?: ReactNode;
}) {
  return (
    <ErrorBoundary
      fallbackRender={({ error }) => {
        // In the render that draws the screen, ahead of the commit in which
        // React logs what was caught, so the log is known as this one's.
        caughtByBoundary(error);

        return <CrashScreen error={error} quit={quit} />;
      }}
    >
      {children}
    </ErrorBoundary>
  );
}

function CrashScreen({
  error,
  quit,
}: {
  error: unknown;
  quit: (error: unknown) => void;
}) {
  const { width, height } = useTerminalDimensions();
  // The theme the window was drawn in, or one that reads on any background
  // when chord broke before it had one.
  const colours = drawnColours.current ?? paletteOf('dark-ansi', COLOUR);

  // Any key, a modifier alone aside, which `usePress` never hands on.
  usePress(() => {
    quit(error);

    return true;
  });

  return (
    <box flexDirection='column'>
      {crashRows(error, width, height).map((row, index) => (
        <text
          key={index}
          {...CUT}
          {...(row.role === 'error'
            ? fg(colours.error)
            : row.role === 'dim'
              ? { attributes: DIM }
              : {})}
        >
          {row.text}
        </text>
      ))}
    </box>
  );
}

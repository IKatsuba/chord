/**
 * The window with chord's server and the fake its one runtime, which the
 * background view's tests share: `BackgroundView_test.tsx` and the files
 * split from it (CHD-501).
 */
import { serveChord } from '../../../src/server/server.ts';
import { type Window, withWindow } from '../app/render.tsx';

/**
 * Runs `body` in a window with chord's server, the fake its one runtime,
 * 120×40 unless `size` says otherwise.
 */
export async function withBackground(
  body: (window: Window) => Promise<void>,
  size = { rows: 40, columns: 120 },
) {
  const server = serveChord();

  try {
    await withWindow(body, {
      server,
      runtimes: ['fake'],
      ...size,
    });
  } finally {
    await server.close();
  }
}

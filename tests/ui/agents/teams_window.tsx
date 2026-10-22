/**
 * The team and the window the team tests share: `Teams_test.tsx` and the
 * files split from it (CHD-501).
 */
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { type ChordServer, serveChord } from '../../../src/server/server.ts';
import { ready, send, type Window, withWindow } from '../app/render.tsx';

export const BUGFIX = await readFile(
  fileURLToPath(
    new URL('../../fixtures/teams/fake/bugfix.md', import.meta.url),
  ),
  'utf8',
);

/** Runs `body` in a window with chord's server and `teams` saved. */
export async function withTeams(
  body: (window: Window) => Promise<void>,
  teams: Readonly<Record<string, string>> = { bugfix: BUGFIX },
  server: ChordServer = serveChord(),
) {
  try {
    await withWindow(body, {
      server,
      runtimes: ['fake'],
      rows: 80,
      columns: 120,
      teams,
    });
  } finally {
    await server.close();
  }
}

/** `team`, until the lead has reported and tester asks the person. */
export async function started(window: Window): Promise<void> {
  await ready(window);
  await send(window, 'team');
  await window.shows('Team(bugfix) · fake · fake-large');
  await window.shows('← from @bugfix · fake');
  await window.shows('● tester needs your permission');
  await window.shows('└─ coder ');
}

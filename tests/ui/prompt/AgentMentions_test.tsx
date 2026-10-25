/** Agent completion is a prompt list; sending it leaves routing to the agent. */
import { describe, expect, test } from 'bun:test';
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import type { WindowedState } from '../../../src/ui/app/state.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  ESC,
  promptRow,
  ready,
  send,
  TAB,
  until,
  withWindow,
  type Window,
} from '../app/render.tsx';
import { BUGFIX } from '../agents/teams_window.tsx';

const listed = (window: Window, name: string) =>
  window
    .frame()
    .split('\n')
    .some((line) => line.trimEnd() === `  ${name}`);

async function clear(window: Window) {
  await window.press(ESC);
  await window.press('\x15');
}

for (const [columns, rows] of [
  [120, 40],
  [80, 24],
] as const) {
  describe(`agent completions at ${columns}x${rows} (CHD-519)`, () => {
    test('empty states, dismiss, Tab and literal Enter', () =>
      withWindow(
        async (window) => {
          await ready(window);
          await writeFile(
            join(window.dir, '@parser'),
            'not an agent attachment',
          );
          await window.type('@@');
          await window.shows('No agents to mention');
          await window.press(TAB);
          expect(promptRow(window)).toContain('@@');
          await window.press(ESC);
          expect(window.frame()).not.toContain('No agents to mention');
          await window.press('\r');
          await window.shows('› @@');
          await window.shows('Hello, world. This reply came in chunks.');
          expect(window.frame()).not.toContain('Received @');
        },
        { columns, rows },
      ));

    test('main, child, lead and member share current recipients and quoted picks', async () => {
      const server = serveChord();
      let state: WindowedState | undefined;

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'agentmentions');
            await window.shows('Agent completion sessions opened.');
            await until(
              'all fixture agents started',
              () => window.pids.length === 9,
            );
            await until(
              'main turn ended',
              () =>
                state?.sessions[state.front]?.transcript.turn.status === 'idle',
            );
            await window.type('@@');
            await until('main candidates', () =>
              ['parser', 'docs', 'bugfix', 'bugfix 2'].every((name) =>
                listed(window, name),
              ),
            );
            expect(listed(window, 'tester')).toBe(false);
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press(TAB);
            expect(promptRow(window)).toContain('@@"bugfix 2" ');
            expect(window.frame()).not.toContain('No matching agents');
            await clear(window);
            await window.type('@@zzz');
            await window.shows('No matching agents');
            await window.press(TAB);
            expect(promptRow(window)).toContain('@@zzz');
            await clear(window);

            // With no draft, the list starts at main, then parser.
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('╭─ parser ─');
            await window.type('@@');
            await until('child candidates', () => listed(window, 'main'));
            expect(listed(window, 'bugfix')).toBe(false);
            await clear(window);
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('╭─ bugfix ─');
            await window.type('@@');
            await until('lead candidates', () =>
              ['main', 'tester', 'coder', 'bugfix 2'].every((name) =>
                listed(window, name),
              ),
            );
            expect(listed(window, 'parser')).toBe(false);
            await clear(window);
            // Attention picks the first tester; it has a plain text turn here.
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('╭─ tester · bugfix ─');
            await window.type('@@');
            await until('member candidates', () =>
              ['bugfix', 'coder'].every((name) => listed(window, name)),
            );
            expect(listed(window, 'main')).toBe(false);
            expect(listed(window, 'bugfix 2')).toBe(false);
            await clear(window);
          },
          {
            server,
            columns,
            rows,
            runtimes: ['fake'],
            teams: { bugfix: BUGFIX },
            agentCommand: fakeAgentCommand(undefined, '--tester-plays', 'text'),
            onState: (next) => {
              state = next;
            },
          },
        );
      } finally {
        await server.close();
      }
    });
  });
}

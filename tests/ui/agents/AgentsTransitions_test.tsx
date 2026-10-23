/**
 * Closed children across session transitions: what /clear and /resume picks
 * forget of them, and what they keep.
 */
import { describe, expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import { readRecords } from '../../../src/session/sessions.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { opened, withAgents } from './agents_window.tsx';

describe('CHD-493 U11 tester: each session transition forgets closed children', () => {
  const mainIdle = (window: Window) =>
    until(
      'main is idle',
      () =>
        window.frame().split('\n').at(-1)?.includes('? for shortcuts') ===
          true || /main\s+fake.*◦ idle/.test(window.frame()),
    );

  for (const columns of [80, 120]) {
    test(`/clear alone forgets a same-session close at ${columns} columns`, () =>
      withAgents(async (window) => {
        await window.resize({ columns, rows: 40 });
        await opened(window);
        await send(window, 'agentclose');
        await window.shows('parser is closed; open_agent starts another');
        await mainIdle(window);

        const old = window.session()?.id;

        await send(window, '/clear');
        await until(
          'the replacement session',
          () => window.session()?.id !== old,
        );
        await mainIdle(window);
        await send(window, 'agentsendrefused');
        await window.shows('No agent parser is open in this session;');
        expect(window.frame()).not.toContain('parser is closed;');
        expect(window.frame()).not.toContain('parser was closed when');
      }));

    test(`a direct /resume pick replaces a populated closed list at ${columns} columns`, () =>
      withAgents(async (window) => {
        await window.resize({ columns, rows: 40 });
        await mainIdle(window);

        const target = window.session()!.id;

        await opened(window);

        await send(window, '/clear');
        await until(
          'a different session',
          () => window.session()?.id !== target,
        );
        await mainIdle(window);
        await opened(window);
        await send(window, 'agentclose');
        await window.shows('parser is closed; open_agent starts another');
        await mainIdle(window);
        await send(window, '/resume');
        await window.shows('Resume a session');

        // The current main is excluded; select the earlier main, not a child.
        for (
          let row = 0;
          !/❯ \d+\. .* {2}agents\s*│/.test(window.frame());
          row++
        ) {
          expect(row).toBeLessThan(8);
          await window.press(DOWN);
        }

        await window.press('\r');
        await until(
          'the original session',
          () => window.session()?.id === target,
        );
        await mainIdle(window);
        await send(window, 'agentsendrefused');
        await window.shows(
          'parser was closed when this session was left; open_agent starts another',
        );
        expect(window.frame()).not.toContain('parser is closed;');
      }));

    if (columns === 120) {
      continue;
    }

    for (const pick of ['child', 'elsewhere'] as const) {
      test(`a ${pick} pick preserves same-session closed names at ${columns} columns`, async () => {
        const server = serveChord();

        try {
          await withWindow(
            async (window) => {
              await opened(window);
              await send(window, 'agentclose');
              await window.shows('parser is closed; open_agent starts another');
              await mainIdle(window);

              const main = window.session()!.id;

              await send(window, '/resume');
              await window.shows('Resume a session');

              if (pick === 'elsewhere') {
                await window.press('\x01');
                await window.shows('elsewhere');
              }

              await window.press('\r');

              if (pick === 'child') {
                await window.shows('╭─ docs');
                // Finish its permission before navigating back to main.
                await window.press('3');
                await until('docs is idle', () =>
                  /docs\s+fake.*◦ idle/.test(window.frame()),
                );
                await window.press(DOWN);
                await window.press(UP);
                await window.shows('Close(parser)');
                await window.press('\r');
              } else {
                await window.shows('chord fake');
              }

              expect(window.session()?.id).toBe(main);
              await mainIdle(window);
              await send(window, 'agentsendrefused');
              await window.shows('parser is closed; open_agent starts another');
            },
            {
              columns,
              rows: 40,
              server,
              runtimes: ['fake'],
              agentCommand: fakeAgentCommand(),
              readRecords: async (dir) =>
                (await readRecords(dir))
                  .filter((record) => record.name === 'docs')
                  .map((record) =>
                    pick === 'elsewhere'
                      ? {
                          ...record,
                          sessionId: 'elsewhere',
                          cwd: record.cwd + '-elsewhere',
                        }
                      : record,
                  ),
            },
          );
        } finally {
          await server.close();
        }
      });
    }
  }
});

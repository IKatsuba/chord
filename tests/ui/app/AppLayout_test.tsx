/**
 * Transient prompt lists float over the transcript, above a steady input
 * and status (CHD-525, CHD-545).
 */
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { describe, expect, test } from 'bun:test';
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { WindowedState } from '../../../src/ui/app/state.ts';
import stripAnsi from 'strip-ansi';
import { openOther, withChild } from './child_window.tsx';
import { send } from './render.tsx';
import { BUGFIX } from '../agents/teams_window.tsx';
import { BACKSPACE, files } from '../prompt/prompt_window.tsx';
import {
  CTRL_R,
  DOWN,
  ESC,
  PAGE_UP,
  ready,
  until,
  withWindow,
  type Window,
} from './render.tsx';

function borders(window: Window) {
  const lines = stripAnsi(window.frame()).split('\n');

  return {
    top: lines.findIndex((line) => line.startsWith('╭')),
    bottom: lines.findIndex((line) => line.startsWith('╰')),
  };
}

function row(window: Window, text: string) {
  return stripAnsi(window.frame())
    .split('\n')
    .findIndex((line) => line.includes(text));
}

for (const [columns, rows] of [
  [80, 24],
  [120, 40],
] as const) {
  describe(`steady prompt at ${columns}x${rows} (CHD-525)`, () => {
    for (const [draft, label] of [
      ['/', '/clear'],
      ['/g', '/greet'],
      ['/new ', 'fixture'],
      ['/team run ', 'bugfix'],
      ['@', 'layout-file.ts'],
      ['@@', 'No agents to mention'],
    ]) {
      test(`${draft} stays above the same draft through dismiss and reopen`, () =>
        withWindow(
          async (window) => {
            await ready(window);
            await files(window, 'layout-file.ts');
            await window.type(draft!);
            await window.shows(label!);

            const opened = borders(window);

            expect(opened.top).toBeGreaterThan(0);
            expect(row(window, label!)).toBeLessThan(opened.top);
            expect(opened.bottom).toBe(rows - 2);
            await window.press(ESC);
            await until('list dismissed', () => row(window, label!) < 0);
            expect(borders(window)).toEqual(opened);
            await window.press(BACKSPACE);
            await window.type(draft!.slice(-1));
            await window.shows(label!);
            expect(borders(window)).toEqual(opened);
            expect(row(window, label!)).toBeLessThan(opened.top);
            await window.press(ESC);
            await until('list dismissed again', () => row(window, label!) < 0);
            expect(borders(window)).toEqual(opened);
          },
          {
            columns,
            rows,
            teams: { bugfix: BUGFIX },
            runtimes: ['fake', 'fixture'],
            listed: [
              {
                name: 'fixture',
                title: undefined,
                start: 'fake',
                from: 'settings',
              },
            ],
          },
        ));
    }

    test('help and history search keep both borders and the permanent status below', () =>
      withWindow(
        async (window) => {
          await ready(window);

          const empty = borders(window);

          await window.type('?');
          await window.shows('enter to send');
          expect(borders(window)).toEqual(empty);
          expect(row(window, 'enter to send')).toBeLessThan(empty.top);
          await window.press(ESC);
          await until('help dismissed', () => row(window, 'enter to send') < 0);
          expect(borders(window)).toEqual(empty);
          await window.type('same draft');

          const draft = borders(window);

          await window.press(CTRL_R);
          await window.shows('search prompts:');
          expect(borders(window)).toEqual(draft);
          expect(row(window, 'search prompts:')).toBeLessThan(draft.top);
          expect(draft.bottom).toBe(rows - 2);
          await window.press(ESC);
          await until(
            'search dismissed',
            () => row(window, 'search prompts:') < 0,
          );
          expect(borders(window)).toEqual(draft);
        },
        { columns, rows },
      ));
  });
}

for (const [columns, rows] of [
  [80, 24],
  [120, 40],
] as const) {
  describe(`a list floats over the transcript at ${columns}x${rows} (CHD-545)`, () => {
    for (const scrolled of [false, true]) {
      for (const [open, label] of [
        ['/', '/clear'],
        ['@', 'layout-file.ts'],
        ['?', 'enter to send'],
        [CTRL_R, 'search prompts:'],
      ] as const) {
        test(`${JSON.stringify(open)}, ${scrolled ? 'scrolled back' : 'following'}: the transcript keeps its rows and scroll, the prompt its row`, async () => {
          let latest: WindowedState | undefined;
          const current = () => latest!.sessions[latest!.front]!;
          const lines = (window: Window) =>
            stripAnsi(window.frame()).split('\n');

          await withWindow(
            async (window) => {
              await ready(window);
              await files(window, 'layout-file.ts');
              await send(window, 'markdown');
              await until(
                'the reply ended',
                () => current().transcript.turn.status === 'idle',
              );
              await window.shows('built $bin');
              await until('Working gone', () => row(window, 'Working') < 0);

              if (scrolled) {
                await window.press(PAGE_UP);
                await until('scrolled back', () => !current().scroll.following);
              }

              const closed = lines(window);
              const scroll = current().scroll;
              const prompt = borders(window);

              if (open === CTRL_R) {
                await window.press(CTRL_R);
              } else {
                await window.type(open);
              }

              await window.shows(label);

              const opened = lines(window);
              // The list's rule, on the row above its first, the window's
              // first where the list takes every row above the prompt.
              const rule = opened.findIndex((line) => line.startsWith(' ──'));

              expect(rule).toBeGreaterThanOrEqual(0);
              expect(row(window, label)).toBeGreaterThan(rule);
              expect(row(window, label)).toBeLessThan(prompt.top);
              expect(borders(window)).toEqual(prompt);
              expect(current().scroll).toEqual(scroll);
              // What is above the list is what was there before it opened.
              expect(opened.slice(0, rule)).toEqual(closed.slice(0, rule));
              await window.press(ESC);
              await until('list closed', () => row(window, label) < 0);
              expect(borders(window)).toEqual(prompt);
              expect(current().scroll).toEqual(scroll);
              expect(lines(window).slice(0, prompt.top)).toEqual(
                closed.slice(0, prompt.top),
              );
            },
            {
              columns,
              rows,
              onState: (next) => {
                latest = next;
              },
            },
          );
        });
      }
    }
  });
}

for (const [columns, rows] of [
  [80, 24],
  [120, 40],
] as const) {
  describe(`a framed picker floats over the transcript at ${columns}x${rows} (CHD-545)`, () => {
    for (const [command, title] of [
      ['/model', 'Select model'],
      ['/config', 'Settings'],
      ['/resume', 'Resume a session'],
      ['/theme', 'Theme'],
      ['/team', 'Teams'],
      ['/mcp', 'MCP servers'],
    ] as const) {
      test(`${command}: in its frame alone, the transcript keeps its rows and scroll, the prompt its row`, async () => {
        let latest: WindowedState | undefined;
        const current = () => latest!.sessions[latest!.front]!;
        const lines = (window: Window) => stripAnsi(window.frame()).split('\n');
        // The prompt's frame, the last on screen: a picker's is above it.
        const prompt = (window: Window) => {
          const all = lines(window);

          return {
            top: all.findLastIndex((line) => line.startsWith('╭')),
            bottom: all.findLastIndex((line) => line.startsWith('╰')),
          };
        };

        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'markdown');
            await until(
              'the reply ended',
              () => current().transcript.turn.status === 'idle',
            );
            await window.shows('built $bin');
            await until('Working gone', () => row(window, 'Working') < 0);

            const closed = lines(window);
            // A command's own line may add to the transcript; its view, its
            // offset and whether it follows stay.
            const view = () => {
              const { view, top, following } = current().scroll;

              return { view, top, following };
            };

            const scroll = view();
            const at = prompt(window);

            await window.type(command);
            await window.press('\r');
            await window.shows(title);

            const opened = lines(window);
            const frame = row(window, title) - 1;

            expect(opened[frame]).toStartWith('╭');
            expect(frame).toBeGreaterThanOrEqual(0);
            // No rule: the frame is the layer's edge.
            expect(opened.some((line) => line.startsWith(' ──'))).toBe(false);
            expect(prompt(window)).toEqual(at);
            // The frame's bottom touches the prompt's gap row.
            expect(opened[at.top - 2]).toStartWith('╰');
            expect(view()).toEqual(scroll);

            // What is above the frame is the transcript as it was; /team's
            // own line pushes it up a row.
            if (command !== '/team') {
              expect(opened.slice(0, frame)).toEqual(closed.slice(0, frame));
            }

            await window.press(ESC);
            await until('picker closed', () => row(window, title) < 0);
            expect(prompt(window)).toEqual(at);
            expect(view()).toEqual(scroll);
          },
          {
            columns,
            rows,
            teams: { bugfix: BUGFIX },
            // An earlier session elsewhere, so /resume opens its list.
            readRecords: () =>
              Promise.resolve([
                {
                  path: '/records/earlier.jsonl',
                  sessionId: 'earlier',
                  agent: 'fake',
                  cwd: '/elsewhere',
                  lastUsedAt: 1,
                  prompt: 'earlier work',
                },
              ]),
            onState: (next) => {
              latest = next;
            },
          },
        );
      });
    }
  });
}

for (const [columns, rows] of [
  [80, 24],
  [120, 40],
] as const) {
  test(`at ${columns}x${rows}, a list shrunk to no rows comes back whole when the window grows (CHD-545)`, async () => {
    let latest: WindowedState | undefined;

    await withWindow(
      async (window) => {
        await ready(window);
        await files(window, 'visible.ts');
        await window.type('@');
        await window.shows('visible.ts');
        await window.resize({ columns, rows: 4 });
        await until(
          'no room for the list',
          () => latest?.window.completionHidden === true,
        );
        await window.resize({ columns, rows });
        await until(
          'room again',
          () => latest?.window.completionHidden !== true,
        );
        await window.shows('visible.ts');
        expect(window.frame()).not.toContain('not enough space');
      },
      {
        columns,
        rows,
        onState: (next) => {
          latest = next;
        },
      },
    );
  });
}

test('short of room, a framed picker gives up list rows and keeps its whole frame, title and hint above the prompt (CHD-545)', async () => {
  let here = '';

  await withWindow(
    async (window) => {
      here = window.dir;

      await ready(window);
      await window.type('/resume');
      await window.press('\r');
      await window.shows('Resume a session');

      const all = stripAnsi(window.frame()).split('\n');
      const prompt = all.findLastIndex((line) => line.startsWith('╭'));
      const title = all.findIndex((line) => line.includes('Resume a session'));
      const hint = all.findIndex((line) => line.includes('Enter to resume'));

      // Nine rows above the prompt's gap: the frame's seven around one
      // session, and a row kept for the count of those hidden, which a
      // session's lines show as a ↓ instead.
      expect(title - 1).toBeGreaterThanOrEqual(0);
      expect(all[title - 1]).toStartWith('╭');
      expect(all.some((line) => line.includes('earlier work 9'))).toBe(true);
      expect(hint).toBeGreaterThan(title);
      expect(all[hint + 1]).toStartWith('╰');
      expect(hint + 1).toBe(prompt - 2);
    },
    {
      columns: 80,
      rows: 14,
      readRecords: () =>
        Promise.resolve(
          Array.from({ length: 10 }, (_, i) => ({
            path: `/records/${i}.jsonl`,
            sessionId: `earlier-${i}`,
            agent: 'fake',
            cwd: here,
            lastUsedAt: i + 1,
            prompt: `earlier work ${i}`,
          })),
        ),
    },
  );
});

for (const rows of [12, 16]) {
  for (const [command, title, hint] of [
    ['/theme', 'Theme', 'Esc to go back'],
    ['/mcp', 'MCP servers', 'Esc to close'],
    ['/config', 'Settings', 'Esc to close'],
    ['/model', 'Select model', 'Esc to close'],
  ] as const) {
    test(`${command} at 80x${rows} never covers the prompt, its gap or the strip, and keeps its title and hint (CHD-545)`, () =>
      withWindow(
        async (window) => {
          await ready(window);

          const lines = () => stripAnsi(window.frame()).split('\n');
          const before = lines();
          const prompt = before.findLastIndex((line) => line.startsWith('╭'));

          await window.type(command);
          await window.press('\r');
          await window.shows(title);

          const after = lines();

          // The prompt, its gap row above and the strip below, as they were.
          expect(after.slice(prompt - 1)).toEqual(before.slice(prompt - 1));

          const at = after.findIndex((line) => line.includes(title));

          expect(at).toBeGreaterThanOrEqual(1);
          expect(after[at - 1]).toStartWith('╭');
          expect(after[prompt - 3]).toContain(hint);
          expect(after[prompt - 2]).toStartWith('╰');

          // Inside the frame, what a row draws past its borders.
          const drawn = (at: number) => after[at]!.replace(/[│\s]/g, '');

          // One gap before the hint, cut or not.
          expect(drawn(prompt - 4)).toBe('');
          expect(drawn(prompt - 5)).not.toBe('');

          // With no row for its list, its hint names Esc alone, the one key
          // that acts (CHD-545).
          if (rows === 12 && command !== '/mcp') {
            expect(after[prompt - 3]).not.toMatch(/Enter|↑↓/);
          }
        },
        { columns: 80, rows },
      ));
  }
}

for (const mode of ['one-row', 'crowded', 'resize'] as const) {
  test(`reachable pressure ${mode}: the list floats with its highlight in sight, the prompt and permanent rows still (CHD-545)`, async () => {
    let latest: WindowedState | undefined;
    const crowded = mode !== 'one-row';
    const draft = `${Array.from({ length: 7 }, (_, i) => `draft ${i}`).join('\n')}\n@`;
    const current = () => latest!.sessions[latest!.front]!;
    const permanent = (window: Window) =>
      stripAnsi(window.frame())
        .split('\n')
        .map((line, at) => ({ line: line.replace(/\d+s/g, 'Ns'), at }))
        .filter(({ line }) => /^ {4}(main|other|parser|docs|…)/.test(line));

    await withChild(
      async (window) => {
        await ready(window);

        if (crowded) {
          await send(window, 'agentmentions');
          await window.shows('Agent completion sessions opened.');
          await until('fixture children', () => window.pids.length === 9);
          await until('fixture children idle', () =>
            Object.entries(latest!.sessions).every(
              ([key, session]) =>
                Number(key) === latest!.front ||
                session.transcript.turn.status === 'idle',
            ),
          );
        } else {
          await openOther(window);
        }

        await send(window, 'planshrinkgated');
        await window.shows('Read the code');

        for (let i = 0; i < 4; i++) {
          await send(window, `queued ${i}`);
        }

        await files(
          window,
          ...Array.from({ length: 6 }, (_, i) => `pressure-file${i}.ts`),
        );
        await window.paste(draft);
        await until('draft pasted', () => current().draft === draft);
        await until(
          'permanent fixture rows painted',
          () => permanent(window).length === (crowded ? 3 : 2),
        );
        await window.shows('pressure-file0.ts');
        expect(latest?.window.completionHidden).not.toBe(true);

        const opened = borders(window);
        const pinned = permanent(window);
        const cursor = current().cursor;

        for (let i = 0; i < 5; i++) {
          await window.press(DOWN);
        }

        await window.shows('pressure-file5.ts');
        expect(latest?.window.finder.highlighted).toBe(5);
        expect(row(window, 'pressure-file5.ts')).toBeLessThan(opened.top);

        if (mode === 'resize') {
          await window.resize({ rows: 25 });
          await window.shows('pressure-file5.ts');
          await window.resize({ rows: 24 });
          await window.shows('pressure-file5.ts');
          expect(latest?.window.finder.highlighted).toBe(5);
          expect(borders(window)).toEqual(opened);
          expect(permanent(window)).toEqual(pinned);
        }

        await window.press(ESC);
        await until(
          'finder dismissed',
          () => latest?.window.finder.dismissed === true,
        );
        expect(current().draft).toBe(draft);
        expect(current().cursor).toEqual(cursor);
        await until(
          'the list gone from the screen',
          () => !window.frame().includes('pressure-file'),
        );
        expect(borders(window)).toEqual(opened);
        expect(permanent(window)).toEqual(pinned);
        await window.press(BACKSPACE);
        await window.type('@');
        await window.shows('pressure-file0.ts');
        expect(current().draft).toBe(draft);
        expect(borders(window)).toEqual(opened);
        expect(permanent(window)).toEqual(pinned);
        await window.press('\t');
        await until(
          'visible highlight accepted',
          () => current().draft === `${draft}pressure-file0.ts `,
        );
      },
      {
        columns: 80,
        rows: 24,
        teams: { bugfix: BUGFIX },
        agentCommand: fakeAgentCommand(undefined, '--tester-plays', 'text'),
        startupOf: () => ({
          agentCommand: fakeAgentCommand(undefined, '--tester-plays', 'text'),
        }),
        onState: (next) => {
          latest = next;
        },
      },
    );
  });
}

describe('CHD-545 U1 tester: zero room and output under an open list', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a pending file pick cannot land after resize to zero room at ${columns}x${rows}`, async () => {
      let latest: WindowedState | undefined;
      const current = () => latest!.sessions[latest!.front]!;
      const pending = Promise.withResolvers<readonly string[]>();

      await withWindow(
        async (window) => {
          await ready(window);
          await files(window, 'needle.ts');
          await window.type('@');
          await window.shows('needle.ts');
          await window.type('needle');
          await window.press('\r');
          await until(
            'file pick pending',
            () => latest?.window.awaitedPick !== undefined,
          );
          await window.resize({ rows: 4 });
          await until(
            'zero completion room',
            () => latest?.window.completionHidden === true,
          );

          const draft = current().draft;
          const highlight = latest!.window.finder.highlighted;

          pending.resolve(['needle.ts']);
          await until(
            'match settled while hidden',
            () => latest?.window.matched?.query === 'needle',
          );
          await until(
            'pending pick settled',
            () => latest?.window.awaitedPick === undefined,
          );
          await window.press('\t');
          expect(current().draft).toBe(draft);
          expect(latest!.window.finder.highlighted).toBe(highlight);
          expect(window.frame()).not.toContain('needle.ts');
          await window.resize({ rows });
          await window.shows('needle.ts');
          await until(
            'completion room restored',
            () => latest?.window.completionHidden !== true,
          );
          await window.press('\t');
          await until(
            'visible file accepted',
            () => current().draft === '@needle.ts ',
          );
        },
        {
          columns,
          rows,
          match: (names, query) =>
            query === 'needle' ? pending.promise : Promise.resolve(names),
          onState: (next) => {
            latest = next;
          },
        },
      );
    });

    for (const scrolled of [false, true]) {
      test(`new output stays ${scrolled ? 'scrolled back' : 'following'} under slash completion at ${columns}x${rows}`, async () => {
        let latest: WindowedState | undefined;
        const current = () => latest!.sessions[latest!.front]!;

        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'markdown');
            await until(
              'markdown complete',
              () => current().transcript.turn.status === 'idle',
            );
            await send(window, 'callchildgated');
            await window.shows('deno task test');

            if (scrolled) {
              await window.press(PAGE_UP);
              await until(
                'view scrolled back',
                () => !current().scroll.following,
              );
            }

            const before = current().scroll;
            const prompt = borders(window);

            await window.type('/');
            await window.shows('/clear');
            expect(current().scroll).toEqual(before);
            expect(borders(window)).toEqual(prompt);
            await writeFile(join(window.dir, '.fake-gate', 'release'), '');
            await until(
              'gated output completed',
              () => current().transcript.turn.status === 'idle',
            );
            await until(
              'Working area released',
              () => current().scroll.view > before.view,
            );
            expect(current().scroll.following).toBe(!scrolled);

            if (scrolled) {
              expect(current().scroll.top).toBe(before.top);
            }

            const afterOutput = current().scroll;

            expect(window.frame()).toContain('/clear');
            expect(borders(window)).toEqual(prompt);
            await window.press(ESC);
            await until(
              'overlay closed',
              () => !window.frame().includes('/clear'),
            );
            expect(current().scroll).toEqual(afterOutput);
            expect(borders(window)).toEqual(prompt);

            if (!scrolled) {
              await window.shows('The tests pass.');
            }
          },
          {
            columns,
            rows,
            onState: (next) => {
              latest = next;
            },
          },
        );
      });
    }
  }
});

describe('CHD-545 U2 tester: fixture resume, notice and combined layers', () => {
  const screen = (window: Window) => stripAnsi(window.frame()).split('\n');
  const promptAt = (window: Window) => ({
    top: screen(window).findLastIndex((line) => line.startsWith('╭')),
    bottom: screen(window).findLastIndex((line) => line.startsWith('╰')),
  });

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a populated resume picker keeps the scrolled transcript and prompt fixed at ${columns}x${rows}`, async () => {
      let latest: WindowedState | undefined;
      let cwd = '';
      const current = () => latest!.sessions[latest!.front]!;

      await withWindow(
        async (window) => {
          cwd = window.dir;

          await ready(window);
          await send(window, 'markdown');
          await until(
            'reply complete',
            () => current().transcript.turn.status === 'idle',
          );
          await until('Working area removed', () => row(window, 'Working') < 0);
          await window.press(PAGE_UP);
          await until(
            'transcript scrolled back',
            () => !current().scroll.following,
          );

          const before = current().scroll;
          const prompt = promptAt(window);

          await send(window, '/resume');
          await window.shows('saved work 19');
          expect(promptAt(window)).toEqual(prompt);
          expect(current().scroll).toEqual(before);
          expect(screen(window).some((line) => line.startsWith(' ──'))).toBe(
            false,
          );
          await window.press(DOWN);
          await until('next saved session highlighted', () =>
            screen(window).some(
              (line) => line.includes('❯') && line.includes('saved work 18'),
            ),
          );
          expect(current().scroll).toEqual(before);
          await window.press(ESC);
          await until(
            'resume picker closed',
            () => row(window, 'Resume a session') < 0,
          );
          expect(promptAt(window)).toEqual(prompt);
          expect(current().scroll).toEqual(before);
        },
        {
          columns,
          rows,
          readRecords: () =>
            Promise.resolve(
              Array.from({ length: 20 }, (_, i) => ({
                path: `/records/saved-${i}.jsonl`,
                sessionId: `saved-${i}`,
                agent: 'fake',
                cwd,
                lastUsedAt: i + 1,
                prompt: `saved work ${i}`,
              })),
            ),
          onState: (next) => {
            latest = next;
          },
        },
      );
    });

    for (const help of [false, true]) {
      test(`notice ${help ? 'with shortcuts' : 'alone'} preserves the transcript budget and prompt at ${columns}x${rows}`, async () => {
        let latest: WindowedState | undefined;
        const current = () => latest!.sessions[latest!.front]!;

        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'markdown');
            await until(
              'reply complete',
              () => current().transcript.turn.status === 'idle',
            );
            await until(
              'Working area removed',
              () => row(window, 'Working') < 0,
            );

            const before = current().scroll;
            const prompt = promptAt(window);

            if (help) {
              await window.type('?');
              await window.shows('enter to send');
              expect(
                screen(window).some((line) => line.startsWith(' ──')),
              ).toBe(true);
            }

            await window.session()!.prompt('fullaccess').result;
            await window.shows('dimcode can start other agents');
            expect(promptAt(window)).toEqual(prompt);
            expect(current().scroll.view).toBe(before.view);
            expect(current().scroll.following).toBe(before.following);
            expect(current().scroll.top).toBe(before.top);
            expect(screen(window).some((line) => line.startsWith(' ──'))).toBe(
              false,
            );

            const title = row(window, 'dimcode can start other agents');

            expect(screen(window)[title - 1]).toStartWith('╭');

            if (help) {
              await window.press(ESC);
              await until(
                'shortcuts take Escape first as before',
                () => latest?.window.help === false,
              );
              expect(window.frame()).toContain(
                'dimcode can start other agents',
              );
              expect(promptAt(window)).toEqual(prompt);
            }

            await window.press(ESC);
            await until(
              'notice closed',
              () => row(window, 'dimcode can start other agents') < 0,
            );
            expect(promptAt(window)).toEqual(prompt);
            expect(current().scroll.view).toBe(before.view);

            expect(promptAt(window)).toEqual(prompt);
            expect(current().scroll.view).toBe(before.view);
          },
          {
            agent: 'dimcode',
            agentCommand: fakeAgentCommand(
              undefined,
              '--dimcode-permission',
              'read-only',
            ),
            configHome: (dir) => join(dir, 'config'),
            columns,
            rows,
            onState: (next) => {
              latest = next;
            },
          },
        );
      });
    }
  }
});

describe('CHD-545 U2 tester: short notice preserves both choices', () => {
  for (const rows of [12, 16]) {
    for (const help of [false, true]) {
      test(`80x${rows}, notice ${help ? 'with shortcuts' : 'alone'} clips its body above the fixed prompt`, async () => {
        let latest: WindowedState | undefined;
        const current = () => latest!.sessions[latest!.front]!;
        const lines = (window: Window) => stripAnsi(window.frame()).split('\n');

        await withWindow(
          async (window) => {
            await ready(window);

            const before = lines(window);
            const prompt = before.findLastIndex((line) => line.startsWith('╭'));
            const bottom = before.findLastIndex((line) => line.startsWith('╰'));
            const view = current().scroll.view;

            if (help) {
              await window.type('?');
              await until(
                'shortcuts opened',
                () => latest?.window.help === true,
              );
            }

            await window.session()!.prompt('fullaccess').result;
            await window.shows('dimcode can start other agents');
            await window.shows("1. Got it, don't show this again");
            await window.shows('2. Show it again next time');

            const opened = lines(window);
            const title = opened.findIndex((line) =>
              line.includes('dimcode can start other agents'),
            );

            expect(opened[title - 1]).toStartWith('╭');
            expect(opened[prompt - 2]).toStartWith('╰');
            expect(opened.slice(prompt - 1, bottom + 1)).toEqual(
              before.slice(prompt - 1, bottom + 1),
            );
            expect(opened.some((line) => line.startsWith(' ──'))).toBe(false);
            expect(current().scroll.view).toBe(view);

            if (help) {
              await window.press(ESC);
              await until(
                'shortcuts closed first',
                () => latest?.window.help === false,
              );
              expect(window.frame()).toContain(
                'dimcode can start other agents',
              );
            }

            await window.press('2');
            await until(
              'second notice choice closes it',
              () => !window.frame().includes('dimcode can start other agents'),
            );
            expect(lines(window).slice(prompt - 1, bottom + 1)).toEqual(
              before.slice(prompt - 1, bottom + 1),
            );
            expect(current().scroll.view).toBe(view);
          },
          {
            agent: 'dimcode',
            agentCommand: fakeAgentCommand(
              undefined,
              '--dimcode-permission',
              'read-only',
            ),
            columns: 80,
            rows,
            configHome: (dir) => join(dir, 'config'),
            onState: (next) => {
              latest = next;
            },
          },
        );
      });
    }
  }
});

describe('CHD-545 tester: last fix retains only working hint keys', () => {
  for (const rows of [12, 24]) {
    test(`resume scope still works without a local choice at 80x${rows}`, async () => {
      let latest: WindowedState | undefined;
      const current = () => latest!.sessions[latest!.front]!;

      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/resume');
          await window.shows('Resume a session');
          expect(window.frame()).toContain('Ctrl+a');
          expect(window.frame()).not.toContain('Enter to resume');

          const id = window.session()!.id;
          const scroll = current().scroll;

          await window.press('\r');
          await window.press('1');
          expect(window.session()!.id).toBe(id);
          expect(window.pids).toHaveLength(1);
          await window.press('\x01');
          await until(
            'all-directory scope',
            () => latest?.window.resumePicker?.everywhere === true,
          );
          expect(window.frame()).toContain('Ctrl+a');

          if (rows === 12) {
            expect(window.frame()).not.toMatch(/Enter to resume|↑↓/);
            await window.press('\r');
            expect(window.session()!.id).toBe(id);
            expect(window.pids).toHaveLength(1);
          } else {
            await window.shows('saved elsewhere');
            expect(window.frame()).toContain('Enter to resume');
          }

          expect(current().scroll).toEqual(scroll);
          await window.press(ESC);
          await until(
            'resume closed',
            () => !window.frame().includes('Resume a session'),
          );
          expect(current().scroll).toEqual(scroll);
        },
        {
          columns: 80,
          rows,
          readRecords: () =>
            Promise.resolve([
              {
                path: '/records/elsewhere.jsonl',
                sessionId: 'elsewhere',
                agent: 'fake',
                cwd: '/elsewhere',
                lastUsedAt: 1,
                prompt: 'saved elsewhere',
              },
            ]),
          onState: (next) => {
            latest = next;
          },
        },
      );
    });
  }

  test('MCP body keeps one hint gap through repeated height changes', async () => {
    let latest: WindowedState | undefined;
    const current = () => latest!.sessions[latest!.front]!;
    const lines = (window: Window) => stripAnsi(window.frame()).split('\n');

    await withWindow(
      async (window) => {
        await ready(window);

        for (const rows of [12, 16, 24, 12]) {
          await window.resize({ rows });
          await send(window, '/mcp');
          await window.shows('Esc to close');
          await until(
            'prompt resized',
            () =>
              lines(window).findLastIndex((line) => line.startsWith('╭')) ===
              rows - 4,
          );

          const shown = lines(window);
          const hint = shown.findIndex((line) => line.includes('Esc to close'));
          const text = (at: number) => shown[at]!.replace(/[│\s]/g, '');
          const scroll = current().scroll;

          expect(text(hint - 1)).toBe('');
          expect(text(hint - 2)).not.toBe('');
          expect(shown[rows - 5]!.trim()).toBe('');
          await window.press(ESC);
          await until(
            'MCP panel closed',
            () => !window.frame().includes('Esc to close'),
          );
          expect(current().scroll).toEqual(scroll);
          expect(
            lines(window).findLastIndex((line) => line.startsWith('╭')),
          ).toBe(rows - 4);
        }
      },
      {
        columns: 80,
        rows: 24,
        onState: (next) => {
          latest = next;
        },
      },
    );
  });
});

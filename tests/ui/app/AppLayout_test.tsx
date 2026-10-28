/** Transient prompt chrome borrows rows above a steady input and status. */
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { describe, expect, test } from 'bun:test';
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

for (const mode of ['one-row', 'zero-submit', 'zero-resize'] as const) {
  test(`reachable pressure ${mode} preserves draft and visible selection (CHD-525)`, async () => {
    let latest: WindowedState | undefined;
    const crowded = mode !== 'one-row';
    const draft = `${Array.from({ length: 7 }, (_, i) => `draft ${i}`).join('\n')}\n@`;
    const current = () => latest!.sessions[latest!.front]!;
    const permanent = (window: Window) =>
      stripAnsi(window.frame())
        .split('\n')
        .map((line, at) => ({ line: line.replace(/\d+s/g, 'Ns'), at }))
        .filter(({ line }) => /^ {4}(main|other|parser|…)/.test(line));

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
        await until(
          'draft and completion room measured',
          () =>
            current().draft === draft &&
            Boolean(latest?.window.completionHidden) === crowded,
        );
        await until(
          'permanent fixture rows painted',
          () => permanent(window).length === (crowded ? 3 : 2),
        );

        const opened = borders(window);
        const pinned = permanent(window);
        const cursor = current().cursor;

        if (crowded) {
          await window.shows('not enough space');
          expect(window.frame()).not.toContain('pressure-file');
          await window.press('\t');
          expect(current().draft).toBe(draft);
          expect(current().cursor).toEqual(cursor);
        } else {
          await window.shows('pressure-file0.ts');

          for (let i = 0; i < 5; i++) {
            await window.press(DOWN);
          }

          await window.shows('pressure-file5.ts');
          expect(latest?.window.finder.highlighted).toBe(5);
        }

        await window.press(ESC);
        await until(
          'finder dismissed',
          () => latest?.window.finder.dismissed === true,
        );
        expect(current().draft).toBe(draft);
        expect(current().cursor).toEqual(cursor);
        expect(borders(window)).toEqual(opened);
        expect(permanent(window)).toEqual(pinned);
        await window.press(BACKSPACE);
        await window.type('@');
        await until(
          'finder reopened',
          () =>
            !latest?.window.finder.dismissed &&
            Boolean(latest?.window.completionHidden) === crowded,
        );
        expect(current().draft).toBe(draft);
        expect(current().cursor).toEqual(cursor);
        expect(borders(window)).toEqual(opened);
        expect(permanent(window)).toEqual(pinned);

        if (mode === 'zero-submit') {
          await window.press('\r');
          await until(
            'literal draft queued',
            () => current().queue.at(-1)?.text === draft,
          );
          expect(current().draft).toBe('');
          expect(current().queue.at(-1)?.text).not.toContain('pressure-file');
        } else if (mode === 'zero-resize') {
          await window.resize({ rows: 25 });
          await until(
            'one row restores completion',
            () => !latest?.window.completionHidden,
          );
          await window.shows('pressure-file0.ts');

          for (let i = 0; i < 5; i++) {
            await window.press(DOWN);
          }

          await window.shows('pressure-file5.ts');
          await window.resize({ rows: 24 });
          await until(
            'zero room suppresses completion',
            () => latest?.window.completionHidden === true,
          );
          expect(window.frame()).not.toContain('pressure-file');
          await window.press('\t');
          expect(current().draft).toBe(draft);
          expect(current().cursor).toEqual(cursor);
          expect(latest?.window.finder.highlighted).toBe(5);
          expect(borders(window)).toEqual(opened);
          expect(permanent(window)).toEqual(pinned);
          await window.resize({ rows: 25 });
          await window.shows('pressure-file5.ts');
          await window.press('\t');
          await until(
            'visible highlight accepted',
            () => current().draft === `${draft}pressure-file5.ts `,
          );
        }
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

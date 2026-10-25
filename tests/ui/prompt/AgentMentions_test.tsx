/** Agent completion is a prompt list; sending it leaves routing to the agent. */
import { describe, expect, test } from 'bun:test';
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import { serveChord } from '../../../src/server/server.ts';
import type { Caller } from '../../../src/server/tools.ts';
import type { Turn } from '../../../src/session/session.ts';
import type { WindowedState } from '../../../src/ui/app/state.ts';
import { matchFiles } from '../../../src/ui/prompt/mentions.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  ESC,
  promptRow,
  ready,
  send,
  TAB,
  UP,
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

describe('CHD-519 U3 tester: live roster and completion key ownership', () => {
  async function withRoster(
    body: (window: Window, caller: Caller) => Promise<void>,
    options: NonNullable<Parameters<typeof withWindow>[1]> = {},
  ) {
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Caller | undefined;

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          assert(main);
          await body(window, main);
        },
        { ...options, server, runtimes: ['fake'] },
      );
    } finally {
      await server.close();
    }
  }

  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`opening and closing recipients updates an already-open list at ${columns}x${rows}`, () =>
      withRoster(
        async (window, caller) => {
          await window.type('@@');
          await window.shows('No agents to mention');
          await caller.window.open(caller.key, {
            agent: 'fake',
            name: 'worker',
            prompt: 'text',
          });
          await until('first open recipient offered', () =>
            listed(window, 'worker'),
          );
          await caller.window.open(caller.key, {
            agent: 'fake',
            name: 'worker two',
            prompt: 'text',
          });
          await until('second open recipient offered', () =>
            listed(window, 'worker two'),
          );
          await window.press(DOWN);
          await window.press(UP);
          await caller.window.close(caller, 'worker');
          await until(
            'closed recipient removed from completion',
            () => !listed(window, 'worker') && listed(window, 'worker two'),
          );
          await window.press(TAB);
          expect(promptRow(window)).toContain('@@"worker two" ');
          expect(promptRow(window)).not.toContain('@@worker ');
          expect(listed(window, 'worker two')).toBe(false);
        },
        { columns, rows },
      ));
  }

  test('a late match for a closed recipient cannot satisfy its awaited Tab or a replacement roster', async () => {
    const releases: ((names: readonly string[]) => void)[] = [];

    await withRoster(
      async (window, caller) => {
        await caller.window.open(caller.key, {
          agent: 'fake',
          name: 'parser',
          prompt: 'text',
        });
        await window.type('@@par');
        await until('first agent match held', () => releases.length === 1);
        await window.press(TAB);
        await caller.window.close(caller, 'parser');
        await window.shows('No agents to mention');
        releases[0]!(['parser']);
        await window.press('');
        expect(promptRow(window)).toContain('@@par');
        expect(promptRow(window)).not.toContain('@@parser ');
        await caller.window.open(caller.key, {
          agent: 'fake',
          name: 'par-next',
          prompt: 'text',
        });
        await until(
          'replacement roster match held',
          () => releases.length === 2,
        );
        releases[1]!(['par-next']);
        await until('current roster result displayed', () =>
          listed(window, 'par-next'),
        );
        expect(promptRow(window)).toContain('@@par');
        await window.press(TAB);
        expect(promptRow(window)).toContain('@@par-next ');
      },
      {
        columns: 80,
        rows: 24,
        match: (names, query) =>
          query === 'par' && names.length > 0
            ? new Promise<readonly string[]>((resolve) =>
                releases.push(resolve),
              )
            : matchFiles(names, query),
      },
    );
  });

  test('rebound navigation preserves quoted acceptance and text-only submission to main at 80x24', () =>
    withRoster(
      async (window, caller) => {
        await caller.window.open(caller.key, {
          agent: 'fake',
          name: 'parser',
          prompt: 'text',
        });
        await caller.window.open(caller.key, {
          agent: 'fake',
          name: 'bugfix 2',
          prompt: 'text',
        });

        const session = window.session();

        assert(session);

        const prompt = session.prompt.bind(session);
        const sent: { text: string; turn: Turn }[] = [];

        session.prompt = (text, ...args) => {
          const turn = prompt(text, ...args);

          sent.push({ text, turn });

          return turn;
        };

        await window.type('@@');
        await until(
          'both key-test recipients offered',
          () => listed(window, 'parser') && listed(window, 'bugfix 2'),
        );

        for (const key of ['\x0e', '\x10', '\x0e']) {
          await window.press(key);
          expect(promptRow(window), window.frame()).toContain('@@');
        }

        await window.press(TAB);
        expect(promptRow(window), window.frame()).toContain('@@"bugfix 2" ');
        expect(sent).toHaveLength(0);
        await window.press('\r');
        await until(
          'literal agent mention submitted to main',
          () => sent.length === 1,
        );
        expect(sent[0]!.text.trim()).toBe('@@"bugfix 2"');
        expect(await sent[0]!.turn.sent).toEqual([]);
        expect((await sent[0]!.turn.result).status).toBe('completed');
        await window.type('@@zzz');
        await window.shows('No matching agents');
        await window.press(TAB);
        expect(promptRow(window)).toContain('@@zzz');
        expect(sent).toHaveLength(1);
        await window.press(ESC);
        await until(
          'dismissal closes empty feedback',
          () => !window.frame().includes('No matching agents'),
        );
        expect(promptRow(window)).toContain('@@zzz');
        await window.press('\r');
        await until(
          'dismissed literal query submitted',
          () => sent.length === 2,
        );
        expect(sent[1]!.text).toBe('@@zzz');
        expect(await sent[1]!.turn.sent).toEqual([]);
      },
      {
        columns: 80,
        rows: 24,
        keybindings: JSON.stringify({
          bindings: [
            {
              context: 'Autocomplete',
              bindings: {
                'ctrl+n': 'autocomplete:next',
                'ctrl+p': 'autocomplete:previous',
              },
            },
          ],
        }),
      },
    ));
});

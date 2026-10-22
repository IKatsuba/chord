/**
 * Requests queued, interrupted or left open at a turn's end, a member's
 * row, and a request hidden under the background view (CHD-158, CHD-462,
 * CHD-464).
 */
import { describe, expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { useState } from 'react';
import { draw } from '../harness.tsx';
import {
  type RequestScroller,
  PermissionPrompt,
} from '../../../src/ui/dialogs/Permission.tsx';
import assert from 'node:assert/strict';
import { serveChord } from '../../../src/server/server.ts';
import {
  ESC,
  leader,
  promptRow,
  send,
  until,
  withWindow,
} from '../app/render.tsx';

describe('CHD-158 tester: queued requests in the window', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const mode of ['form', 'url'] as const) {
      test(`${mode}: a queued prompt stays held until the attended request is cancelled at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            const session = window.session()!;
            const answer = session.elicitations.handler(
              mode === 'form'
                ? {
                    sessionId: session.id,
                    mode: 'form',
                    message: 'Choose a target',
                    requestedSchema: { type: 'object', properties: {} },
                  }
                : {
                    sessionId: session.id,
                    mode: 'url',
                    message: 'Approve a target',
                    url: 'https://example.com/approve',
                    elicitationId: 'queued-link',
                  },
              new AbortController().signal,
            );

            await window.shows('ctrl+x a to answer');
            await window.type('text');
            await window.press('\r');
            await window.shows('› after your answer: text');
            expect(window.frame()).toContain('between turns');
            await leader(window, 'a');
            await window.press(ESC);
            expect(await answer).toStrictEqual({ action: 'cancel' });
            await window.shows('Hello, world.');
            expect(window.frame()).not.toContain('after your answer');
            expect(window.frame()).not.toContain('ctrl+x a to answer');
          },
          { columns, rows },
        ));
    }

    test(`an incoming agent message and the person’s prompt retain their order after answering at ${columns} columns`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Parameters<typeof admit>[0] | undefined;
      let child: Parameters<typeof admit>[0] | undefined;

      server.admit = (caller) => {
        if (caller.agent === undefined) {
          main = caller;
        } else {
          child = caller;
        }

        return admit(caller);
      };

      try {
        await withWindow(
          async (window) => {
            assert(main);
            await main.window.open(main.key, {
              agent: 'fake',
              name: 'sender',
              prompt: 'text',
            });
            assert(child);
            await send(window, 'mainbetween');
            await window.shows('main asks · between turns');
            expect(
              child.window.message(child, 'Check the queued report.', () => {}),
            ).toMatchObject({ delivered: 'queued' });
            await window.shows('← from @sender · fake · after your answer:');
            await window.type('text');
            await window.press('\r');
            await window.shows('› after your answer: text');
            expect(window.frame()).toContain('main asks · between turns');
            await leader(window, 'a');
            await window.press('1');
            await window.shows('Received the message from sender · fake.');
            await window.shows('Hello, world.');

            const frame = window.frame();

            expect(frame).not.toContain('after your answer');
            expect(frame.indexOf('Permission: allow.')).toBeLessThan(
              frame.indexOf('Received the message from sender'),
            );
            expect(
              frame.indexOf('Received the message from sender'),
            ).toBeLessThan(frame.indexOf('› text'));
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });

    test(`a task’s between-turn permission holds the queued prompt at ${columns} columns`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            await send(window, 'taskbetween');
            await window.shows(
              'Agent(Fix the tokenizer) · fake asks · between turns',
            );
            await window.type('text');
            await window.press('\r');
            await window.shows('› after your answer: text');
            expect(window.frame()).toContain('ctrl+x a to answer');
            await leader(window, 'a');
            await window.press('1');
            await window.shows('Hello, world.');
            expect(window.frame()).not.toContain('› after your answer: text');
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('CHD-158 tester: interrupting a mixed held queue', () => {
  test('Esc restores the typed prompt but keeps the agent message marked after your answer', async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;
    let child: Parameters<typeof admit>[0] | undefined;

    server.admit = (caller) => {
      if (caller.agent === undefined) {
        main = caller;
      } else {
        child = caller;
      }

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          assert(main);
          await main.window.open(main.key, {
            agent: 'fake',
            name: 'sender',
            prompt: 'text',
          });
          assert(child);
          await send(window, 'mainbetween');
          await window.shows('main asks · between turns');
          await window.type('My queued prompt.');
          await window.press('\r');
          await window.shows('› after your answer: My queued prompt.');
          child.window.message(child, 'Agent message stays.', () => {});

          await window.shows('← from @sender · fake · after your answer:');
          await window.press(ESC);
          await until(
            'Esc restores the typed prompt',
            () => promptRow(window)?.includes('My queued prompt.') ?? false,
          );
          expect(window.frame()).toContain('main asks · between turns');
          expect(window.frame()).toContain(
            '← from @sender · fake · after your answer:',
          );
        },
        { server, runtimes: ['fake'], columns: 120, rows: 40 },
      );
    } finally {
      await server.close();
    }
  });
});

describe("a permission left open at its turn's end (CHD-158 C4, the owner's Q44)", () => {
  test('stays answerable between turns, the queue behind it, through what follows', () =>
    withWindow(async (window) => {
      await send(window, 'leftask');
      // In its turn it has the keys.
      await window.shows('❯ 1. Allow');
      await window.shows('I asked; the turn ends with it open.');
      // Its turn over, it waits between turns, without the keys.
      await window.shows('main asks · between turns');
      await window.shows('ctrl+x a to answer');
      expect(window.frame()).not.toContain('❯ 1. Allow');
      // The call that asked still says it waits, as the box does.
      expect(window.frame()).toMatch(
        /Write\(notes\/left\.md\)\n\s+⎿ {2}Waiting…/,
      );

      await window.type('text');
      await window.press('\r');
      await window.shows('› after your answer: text');
      expect(window.frame()).toContain('main asks · between turns');

      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('1');
      await window.shows('Permission: allow.');
      await window.shows('Hello, world.');
      expect(window.frame()).not.toContain('between turns');
    }));
});

test("a member's permission row names its team, in a turn and between turns (CHD-389 U3, the owner's Q45)", async () => {
  for (const between of [false, true]) {
    const drawn = await draw(
      <PermissionPrompt
        wait={{
          id: 'p',
          title: 'Write tests/parse/tokenize_test.ts',
          options: [],
        }}
        child={{ name: 'tester', colour: undefined, team: 'bugfix' }}
        between={between}
        width={76}
        active={false}
        onChoose={() => {}}
      />,
      { columns: 80, rows: 24 },
    );
    const shown = stripAnsi(drawn.frame());

    await drawn.unmount();
    expect(shown).toContain(
      between ? 'tester · bugfix asks · between turns' : 'tester · bugfix asks',
    );
  }
});

describe('CHD-158 C4 tester: promoted permission keys and withdrawal', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a typed digit remains a draft across two promoted waits and withdrawing the second at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'leftask');
          await window.shows('main asks · between turns');

          const session = window.session();

          assert(session);

          const stop = new AbortController();
          const answer = session.permissions.handler(
            {
              sessionId: session.id,
              toolCall: {
                toolCallId: 'queued-write',
                title: 'Write queued.md',
              },
              options: [
                { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
              ],
            },
            stop.signal,
          );

          try {
            await window.type('2');
            expect(promptRow(window)).toContain('› 2');
            expect(window.frame()).not.toContain('❯ 1. Allow');
            await leader(window, 'a');
            await window.shows('❯ 1. Allow');
            await window.press(ESC);
            await window.shows('Write queued.md');
            await window.shows('ctrl+x a to answer');
            expect(window.frame()).not.toContain('❯ 1. Allow');
            stop.abort();
            expect(await answer).toMatchObject({
              outcome: { outcome: 'cancelled' },
            });
            await until(
              'the withdrawn permission box to leave',
              () => !window.frame().includes('Write queued.md'),
            );
            await window.shows('› 2');
            await window.shows('Permission: deny.');
          } finally {
            stop.abort();
            await answer;
          }
        },
        { columns, rows },
      ));
  }
});

describe('CHD-389 U3 tester: permission row identity and wrapping', () => {
  const name =
    'release validation member checking tokenizer boundaries and source locations';
  const team =
    'the second independent release validation run across all terminal sizes';

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const between of [false, true]) {
      test(`a long member and team stay whole with choices visible at ${columns} columns, between=${between}`, async () => {
        const drawn = await draw(
          <PermissionPrompt
            wait={{
              id: 'p',
              title: 'Write report.md',
              options: [
                { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
              ],
            }}
            child={{ name, team, colour: '#c49cff' }}
            between={between}
            held={between}
            width={columns - 4}
            active={false}
            onChoose={() => {}}
          />,
          { columns, rows },
        );

        try {
          const frame = stripAnsi(drawn.frame());
          const plain = frame.replace(/[│╭╮╰╯─]/g, ' ').replace(/\s+/g, ' ');

          expect(plain).toContain(
            `${name} · ${team} asks${between ? ' · between turns' : ''}`,
          );
          expect(frame).toContain('1. Allow');
          expect(frame).toContain(
            between ? 'ctrl+x a to answer' : 'Esc to reject',
          );
          expect(
            frame.split('\n').every((row) => row.length <= columns),
          ).toBeTrue();
        } finally {
          await drawn.unmount();
        }
      });
    }
  }

  test('member name is bold in its colour, team and between suffix dim, asks plain', async () => {
    const level = chalk.level;

    chalk.level = 3;

    try {
      const drawn = await draw(
        <PermissionPrompt
          wait={{ id: 'p', title: 'Write report.md', options: [] }}
          child={{ name: 'tester', team: 'bugfix', colour: '#c49cff' }}
          between
          width={116}
          active={false}
          onChoose={() => {}}
        />,
        { columns: 120, rows: 40 },
      );

      try {
        const frame = drawn.frame();

        expect(frame).toContain('\x1b[1m\x1b[38;2;196;156;255mtester\x1b[0m');
        expect(frame).toContain('\x1b[2m · bugfix\x1b[0m asks');
        expect(frame).toContain('\x1b[2m · between turns\x1b[0m');
      } finally {
        await drawn.unmount();
      }
    } finally {
      chalk.level = level;
    }
  });

  for (const kind of ['main', 'child', 'task', 'unknown'] as const) {
    test(`${kind} retains its permission naming rule`, async () => {
      const drawn = await draw(
        <PermissionPrompt
          wait={{
            id: 'p',
            title: 'Write report.md',
            options: [],
            ...(kind === 'unknown' ? { subagentId: 'unknown' } : {}),
          }}
          {...(kind === 'child' || kind === 'task' || kind === 'unknown'
            ? { child: { name: 'docs', colour: undefined } }
            : {})}
          {...(kind === 'task'
            ? {
                asker: [
                  {
                    id: 'task',
                    title: 'Fix the tokenizer',
                    state: 'running',
                    entries: [],
                    plan: [],
                    task: { name: 'Fix the tokenizer', runtime: 'fake' },
                  },
                ],
              }
            : {})}
          between={kind === 'unknown'}
          width={76}
          active={false}
          onChoose={() => {}}
        />,
        { columns: 80, rows: 24 },
      );

      try {
        const frame = stripAnsi(drawn.frame());

        if (kind === 'main') {
          expect(frame).not.toContain(' asks');
        } else {
          expect(frame).toContain(
            kind === 'child'
              ? 'docs asks'
              : kind === 'task'
                ? 'Agent(Fix the tokenizer) · fake asks'
                : 'a subagent of docs asks · between turns',
          );
        }
      } finally {
        await drawn.unmount();
      }
    });
  }
});

test('a tall permission held between turns names no scroll key until it has the keys (CHD-158 §8)', () =>
  withWindow(
    async (window) => {
      await send(window, 'bigaskleft');
      await window.shows('main asks · between turns');
      await window.shows('lines below ─');
      // No key scrolls it while the keys are the prompt's.
      expect(window.frame()).not.toContain('to scroll');
      expect(window.frame()).toContain('ctrl+x a to answer');

      await leader(window, 'a');
      await window.shows('pagedown to scroll');
      await window.shows('❯ 1. Yes');
    },
    { columns: 80, rows: 24 },
  ));

test('hidden under the background view, a permission keeps its highlighted choice, and is drawn as it was when shown again (CHD-462)', async () => {
  const show: { set?: (hidden: boolean) => void } = {};

  function Hidden() {
    const [hidden, setHidden] = useState(false);

    show.set = setHidden;

    return (
      <PermissionPrompt
        wait={{
          id: 'p',
          title: 'Write notes.txt',
          options: [
            { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
            { optionId: 'always', name: 'Always allow', kind: 'allow_always' },
            { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
          ],
        }}
        width={76}
        active={!hidden}
        hidden={hidden}
        onChoose={() => {}}
      />
    );
  }

  const drawn = await draw(<Hidden />, { columns: 80, rows: 24 });
  const settle = () => new Promise((resolve) => setTimeout(resolve, 50));

  try {
    await drawn.write('\x1b[B');
    await drawn.write('\x1b[B');
    await settle();
    expect(stripAnsi(drawn.frame())).toContain('❯ 3. Deny');

    show.set?.(true);
    await settle();
    expect(stripAnsi(drawn.frame())).not.toContain('Deny');

    show.set?.(false);
    await settle();
    expect(stripAnsi(drawn.frame())).toContain('❯ 3. Deny');
  } finally {
    await drawn.unmount();
  }
});

describe('CHD-462 B1 tester: hidden permission scroll state', () => {
  for (const columns of [80, 120]) {
    test(`scroll position survives hiding and showing at ${columns} columns`, async () => {
      const control: { set?: (hidden: boolean) => void } = {};
      const scroller: { current: RequestScroller | undefined } = {
        current: undefined,
      };
      const wait = {
        id: 'kept-scroll',
        title: 'Review the release notes',
        rawInput: {
          notes: Array.from({ length: 60 }, (_, n) => `Release note ${n + 1}`),
        },
        options: [
          { optionId: 'allow', name: 'Allow', kind: 'allow_once' as const },
        ],
      };

      function Hidden() {
        const [hidden, setHidden] = useState(false);

        control.set = setHidden;

        return (
          <box height={18}>
            <PermissionPrompt
              wait={wait}
              width={columns - 4}
              active={!hidden}
              hidden={hidden}
              onChoose={() => {}}
              scroller={scroller}
            />
          </box>
        );
      }

      const drawn = await draw(<Hidden />, { columns, rows: 24 });

      try {
        await until('scrollable request', () =>
          drawn.frame().includes('lines below'),
        );
        scroller.current?.('page_down');
        await until('scrolled request', () =>
          drawn.frame().includes('lines above'),
        );

        const before = drawn.frame();

        control.set?.(true);
        await until(
          'request hidden',
          () => !drawn.frame().includes('Review the release notes'),
        );
        control.set?.(false);
        await until('scroll restored', () => drawn.frame() === before);
      } finally {
        await drawn.unmount();
      }
    });
  }
});

describe('CHD-464 tester: a zero-row body recovers its space', () => {
  for (const columns of [80, 120]) {
    test(`the count clears after growing and comes back after shrinking at ${columns} columns`, async () => {
      const drawn = await draw(
        <box flexDirection='column' flexGrow={1}>
          <box flexGrow={1} flexBasis={0} />
          <PermissionPrompt
            wait={{
              id: 'p',
              title: [
                'write',
                ...Array.from({ length: 6 }, (_, n) => `row ${n}`),
              ].join('\n'),
              options: [
                { optionId: 'a', name: 'Allow', kind: 'allow_once' },
                { optionId: 'r', name: 'Deny', kind: 'reject_once' },
              ],
            }}
            width={columns - 4}
            active
            onChoose={() => {}}
          />
        </box>,
        { columns, rows: 10 },
      );

      try {
        const frame = () => stripAnsi(drawn.frame());

        await until('all six body rows counted', () =>
          frame().includes('↓ 6 lines below'),
        );
        await drawn.resize({ rows: 40 });
        await until(
          'body has its rows back',
          () => frame().includes('row 5') && !frame().includes('lines below'),
        );
        expect(frame()).toMatch(/│ Esc to reject +│ *\n╰─+╯/);
        await drawn.resize({ rows: 10 });
        await until('count returns at zero rows', () =>
          frame().includes('↓ 6 lines below'),
        );
        expect(frame()).not.toContain('row 0');
        expect(frame()).toMatch(/│ Esc to reject +│ *\n╰─+╯/);
      } finally {
        await drawn.unmount();
      }
    });
  }
});

describe('CHD-464 tester: request body waits for permission to give way', () => {
  test('only an enabled givesWay lets the body lose its rows', async () => {
    for (const givesWay of [false, true]) {
      const drawn = await draw(
        <box height={10} flexDirection='column'>
          <PermissionPrompt
            wait={{
              id: 'p',
              title: 'write\nfirst body row\nlast body row',
              options: [
                { optionId: 'a', name: 'Allow', kind: 'allow_once' },
                { optionId: 'r', name: 'Deny', kind: 'reject_once' },
              ],
            }}
            width={76}
            active
            givesWay={givesWay}
            onChoose={() => {}}
          />
        </box>,
        { columns: 80, rows: 24 },
      );

      try {
        const frame = () => stripAnsi(drawn.frame());

        if (givesWay) {
          await until('both body rows are counted out of view', () =>
            frame().includes('↓ 2 lines below'),
          );
          expect(frame()).not.toContain('last body row');
        } else {
          await until('body retains its rows', () =>
            frame().includes('last body row'),
          );
          expect(frame()).not.toContain('lines below');
        }
      } finally {
        await drawn.unmount();
      }
    }
  });
});

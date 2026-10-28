/**
 * /fork in the window: a top-level agent beside main, of no one, that
 * starts from the conversation so far (CHD-101).
 */
import { describe, expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  ready,
  send,
  until,
  UP,
  withWindow,
  type Window,
} from './render.tsx';

const FORKS = fakeAgentCommand(undefined, '--fork');

/** Back on main, its box without a name. */
async function pickMain(window: Window) {
  await window.press(DOWN);
  await until('main picked in the list', async () => {
    if (window.frame().includes('  ❯ main ')) {
      return true;
    }

    await window.press(UP);

    return false;
  });

  await window.press('\r');
  await until('main in view', () => !/╭─ \S/.test(window.frame()));
}

describe('/fork opens a fork beside main (CHD-101)', () => {
  test('it is picked at once, listed after main as a fork, and main says where it went', () =>
    withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows('This reply came in chunks.');
        await until(
          'the turn to end',
          () => !window.frame().includes('Working'),
        );
        await window.type('/fork');
        await window.shows('Fork the conversation into a new agent');
        await window.press('\r');
        await window.shows('╭─ fork ');
        await window.shows('forked from main');
        await window.shows('    fork  fork · fake');
        await pickMain(window);
        await window.shows('⎿  Forked into fork');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));

  test('a second is fork 2, a named one keeps its name, and a fork forks too', () =>
    withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/fork');
        await window.shows('╭─ fork ');
        await send(window, '/fork parser');
        await window.shows('╭─ parser ');
        await window.shows('forked from fork');
        await pickMain(window);
        await send(window, '/fork');
        await window.shows('╭─ fork 2 ');
        await window.shows('forked from main');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));

  test("main's /clear leaves the forks open, and /clear on a fork is refused", () =>
    withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows('This reply came in chunks.');
        await until(
          'the turn to end',
          () => !window.frame().includes('Working'),
        );
        await send(window, '/fork');
        await window.shows('╭─ fork ');
        await send(window, '/clear');
        await window.shows(
          'A fork cannot be cleared yet · close it with x and /fork again',
        );
        await pickMain(window);
        await send(window, '/clear');
        await until(
          "main's transcript cleared",
          () => !window.frame().includes('This reply came in chunks.'),
        );

        expect(window.frame()).toContain('    fork  fork · fake');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));

  test('a fork that opens an agent is told it works only from main, as a failed call', async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/fork');
          await window.shows('╭─ fork ');
          await send(window, 'agentnames');
          await window.shows('Quoted agent names refused.');

          expect(window.frame()).toContain(
            'This tool works only from main and its agents, not from a fork.',
          );
          // Nothing was opened: the list is main and the fork alone.
          expect(
            window
              .frame()
              .split('\n')
              .filter((row) => /^ {4}\S/.test(row)),
          ).toHaveLength(2);
        },
        { agentCommand: FORKS, server, columns: 120, rows: 40 },
      );
    } finally {
      await server.close();
    }
  });

  test('x closes a fork, and the list goes with it', () =>
    withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/fork');
        await window.shows('╭─ fork ');
        await window.press(DOWN);
        await window.shows('  ❯ fork ');
        await window.press('x');
        await until(
          'the fork closed',
          () => !window.frame().includes('fork · fake'),
        );
        await until('main in view', () => !/╭─ \S/.test(window.frame()));

        // It has no parent: main is told nothing.
        expect(window.frame()).not.toContain('The person closed');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));

  for (const [why, line, agentCommand] of [
    [
      'an agent that does not fork',
      'This agent does not fork sessions',
      fakeAgentCommand(),
    ],
    [
      'a fork the agent refuses',
      'Could not fork:',
      ['env', 'CHORD_FAKE_REFUSE_FORK=1', ...FORKS],
    ],
  ] as const) {
    test(`${why} is refused under the command, nothing opened`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/fork');
          await window.shows(line);

          expect(window.frame()).not.toContain('fork · fake');
          expect(window.frame()).not.toContain('╭─ fork');
        },
        { agentCommand: [...agentCommand], columns: 120, rows: 40 },
      ));
  }

  test('while main works, or with an ordinary child picked, it is refused', () =>
    withWindow(
      async (window) => {
        // Held until a steer or the cancel, however slow the machine.
        await send(window, 'texttillsteeredheld');
        await window.shows('This reply came in chunks.');
        await send(window, '/fork');
        await window.shows('main is working · /fork once its turn ends');
        await window.press('\u001b');
        await until(
          'the turn to end',
          () => !window.frame().includes('esc to interrupt'),
        );
        await send(window, '/new');
        await window.shows('╭─ fake ');
        await send(window, '/fork');
        await window.shows('/fork forks main or a fork');
        expect(window.frame()).not.toContain('fork · fake');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));
});

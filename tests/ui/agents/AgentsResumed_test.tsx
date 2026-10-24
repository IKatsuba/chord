/**
 * The agents list over a session opened again: main's row says what its
 * agent does now, not what the record's past says of the agents before it
 * (CHD-510).
 */
import { expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import { ready, send, until, type Window } from '../app/render.tsx';
import { withAgents } from './agents_window.tsx';

/** The list's row for `name`, as the screen shows it. */
function rowOf(window: Window, name: string): string | undefined {
  return stripAnsi(window.frame())
    .split('\n')
    .find((line) => new RegExp(`^ {2}[ ❯] ${name}  `).test(line));
}

test("main resumed and answering is not 'exited' once a child shows the list", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'text');
    await window.shows('This reply came in chunks.');
    await send(window, '/clear');
    await ready(window);
    await send(window, '/resume');
    await window.shows('Resume a session');
    await window.press('\r');
    await window.shows('resumed · ');
    await ready(window);
    await send(window, '/new');
    await until('the list', () => rowOf(window, 'main') !== undefined);
    expect(rowOf(window, 'main')).not.toContain('exited');
  }));

test("main resumed whose agent then exits is 'exited', with no connection after it", () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'text');
    await window.shows('This reply came in chunks.');
    await send(window, '/clear');
    await ready(window);
    await send(window, '/resume');
    await window.shows('Resume a session');
    await window.press('\r');
    await window.shows('resumed · ');
    await ready(window);
    // Its agent goes on its own, after it came up.
    await send(window, 'crash');
    await until('the exit said', () =>
      stripAnsi(window.frame()).includes('exited'),
    );
    await send(window, '/new');
    await until('the list', () => rowOf(window, 'main') !== undefined);
    expect(rowOf(window, 'main')).toContain('✗ exited');
  }));

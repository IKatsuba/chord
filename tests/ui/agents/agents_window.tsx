/**
 * The window the long-lived agents' tests run in, on the fake agent and
 * chord's own server, and the steps they share: `Agents_test.tsx` and the
 * files split from it (CHD-501).
 */
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { CHILD_MESSAGES } from '../../fixtures/fake_agent/scenarios/agents.ts';
import { ready, send, until, type Window, withWindow } from '../app/render.tsx';

/** How many times `text` is on screen. */
export function count(window: Window, text: string): number {
  return window.frame().split(text).length - 1;
}

/**
 * Runs `body` in a window with chord's server, the fake its one runtime,
 * started with `flags`.
 */
export async function withAgents(
  body: (window: Window) => Promise<void>,
  ...flags: string[]
) {
  const server = serveChord();

  try {
    await withWindow(body, {
      ...(flags.length === 0
        ? {}
        : { agentCommand: fakeAgentCommand(undefined, ...flags) }),
      server,
      runtimes: ['fake'],
      rows: 80,
      columns: 120,
    });
  } finally {
    await server.close();
  }
}

/**
 * The hint for parser's task asking, as CHD-431 names it: by the task's own
 * name, or by whose task it is where that does not fit.
 */
export const PARSER_TASK =
  /● (Agent\(Fix the tokenizer\) · fake|parser's task) needs your permission/;

export async function parserTaskAsks(window: Window): Promise<void> {
  await until("parser's task asks", () => PARSER_TASK.test(window.frame()));
}

/** `agents`, until both of parser's messages have come back. */
export async function opened(window: Window): Promise<void> {
  await ready(window);
  await send(window, 'agents');
  await window.shows('Open(parser) · fake · fake-small');
  await window.shows('Waiting on parser.');
  await window.shows(CHILD_MESSAGES[1]);
}

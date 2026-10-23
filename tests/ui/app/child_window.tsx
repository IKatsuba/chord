/**
 * Tester steps that keep per-agent guarantees after tabs go: a fake child
 * beside main, selected by the agents list without discarding either draft
 * or taking a form's keys (CHD-493 U2).
 */
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  UP,
  left,
  promptRow,
  send,
  until,
  type Window,
  withWindow,
} from './render.tsx';

type Options = NonNullable<Parameters<typeof withWindow>[1]>;

/** A window with a local server; every runtime still runs the fake agent. */
export async function withChild(
  body: (window: Window) => Promise<void>,
  options: Options = {},
) {
  const server = options.server ?? serveChord();
  const command = fakeAgentCommand(undefined, '--child-runtime', 'fake');

  try {
    await withWindow(body, {
      agentCommand: command,
      startupOf: () => ({ agentCommand: command }),
      ...options,
      server,
      runtimes: [...new Set(['fake', 'codex', ...(options.runtimes ?? [])])],
    });
  } finally {
    if (options.server === undefined) {
      await server.close();
    }
  }
}

/** Main asks the fake scenario to open its one child, named other. */
export async function openOther(window: Window) {
  const count = window.pids.length;

  await send(window, 'agentother');
  await until('other has opened', () => window.pids.length > count);
  await until('other is in the agents list', () =>
    /^ {4}other\s/m.test(window.frame()),
  );
}

/**
 * Empty prompts use the list's keyboard route. A draft or a widget keeps
 * its state while the existing pointer route selects the other agent.
 */
export async function pickAgent(window: Window, name: 'main' | 'other') {
  const rows = () => window.frame().split('\n');
  const target = () =>
    rows().findIndex((row) =>
      new RegExp(`^(?: {4}| {2}❯ )${name}\\s`).test(row),
    );

  if (/^│ ›\s*│$/.test(promptRow(window) ?? '')) {
    await window.press(DOWN);
    await until(`the list picks ${name}`, async () => {
      const drawn = rows();
      const picked = drawn.findIndex((row) => /^ {2}❯ /.test(row));
      const wanted = target();

      if (picked === wanted && wanted !== -1) {
        return true;
      }

      await window.press(picked < wanted ? DOWN : UP);

      return false;
    });
  } else {
    const y = target();

    if (y === -1) {
      throw new Error(`${name} is not in the agents list:\n${window.frame()}`);
    }

    const x = rows()[y]!.indexOf(name);

    await window.press(left(x, y, 'down'));
    await window.press(left(x, y, 'up'));
  }

  await window.press('\r');
}

/**
 * Tester steps that keep per-agent guarantees after tabs go: a fake child
 * beside main, selected through the agents list with drafts set aside,
 * or through attention while a box keeps the keys (CHD-493).
 */
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  CTRL_X,
  DOWN,
  UP,
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
 * A draft uses ↓ to set it aside, then ↓ to reach the list (U10).
 * A box without a prompt keeps the attention route, as an explicit
 * attention request does, preserving its current values and focus.
 */
export async function pickAgent(
  window: Window,
  name: 'main' | 'other',
  attention = false,
) {
  const rows = () => window.frame().split('\n');
  const target = () =>
    rows().findIndex((row) =>
      new RegExp(`^(?: {4}| {2}❯ )${name}\\s`).test(row),
    );

  if (!attention && promptRow(window) !== undefined) {
    await until('the agents list has the keys', async () => {
      if (rows().some((row) => /^ {2}❯ /.test(row))) {
        return true;
      }

      await window.press(DOWN);

      return rows().some((row) => /^ {2}❯ /.test(row));
    });

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
    const picked = () => {
      const frame = window.frame();
      const other =
        frame.includes('╭─ other ') ||
        /^│ other asks(?: for input| you \d+ questions)/m.test(frame);

      return name === 'other' ? other : !other;
    };

    await until(`attention reaches ${name}`, async () => {
      if (picked()) {
        return true;
      }

      // The finder can cover the leader hint; assert the selected agent.
      await window.press(CTRL_X);
      await window.press('a');

      return picked();
    });

    return;
  }

  await window.press('\r');
}

/** The status hint sits above any agents, rather than on the last row. */
export async function readyAgent(window: Window) {
  await until('the shown agent is ready for a prompt', () =>
    window
      .frame()
      .split('\n')
      .some(
        (line) => line.includes('? for shortcuts') && !line.includes('/help'),
      ),
  );
}

/**
 * Tester steps that keep per-agent guarantees after tabs go: a fake child
 * beside main, selected by the agents list on the routes existing keys reach, preserving drafts
 * and forms when attention can reach the other agent (CHD-493 U2).
 */
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  UP,
  leader,
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
 * Empty prompts use the list. With a draft or widget active, only the
 * existing attention action can reach an agent; its news or request must
 * still be waiting (Q183). No pointer selection is invented.
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
    const picked = () =>
      name === 'other'
        ? window.frame().includes('╭─ other ')
        : !window.frame().includes('╭─ other ');

    await until(`attention reaches ${name}`, async () => {
      if (picked()) {
        return true;
      }

      await leader(window, 'a');

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

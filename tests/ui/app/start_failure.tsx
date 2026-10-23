/**
 * A start that fails, as the window shows it: a fake agent opened by
 * `/new codex` with flags that make it fail, beside a main session that
 * started, as the start-failure tests read it (CHD-435, CHD-454).
 */
import { openSession } from '../../../src/session/session.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { ready, send, until, withWindow } from './render.tsx';

/**
 * The window's frame, `columns` wide, once `/new codex` failed to start:
 * its agent is the fake started with `flags`, through the session layer as
 * chord opens one, beside a main session that started.
 */
export function failedFrame(columns: number, ...flags: string[]) {
  return failedFrameShowing(columns, 'where it offers one.', ...flags);
}

/** As `failedFrame`, once the failure shows `last`, its rows run together. */
export async function failedFrameShowing(
  columns: number,
  last: string,
  ...flags: string[]
) {
  let frame = '';

  await withWindow(
    async (window) => {
      await ready(window);
      await send(window, '/new codex');
      await until(`"${last}" after the failure`, () =>
        window.frame().replace(/\s+/g, ' ').includes(last),
      );

      frame = window.frame();
    },
    {
      columns,
      rows: 30,
      runtimes: ['fake', 'codex'],
      openWith: (options) =>
        openSession(
          options.agent === 'codex'
            ? {
                ...options,
                agentCommand: fakeAgentCommand(undefined, ...flags),
              }
            : options,
        ),
    },
  );

  return frame;
}

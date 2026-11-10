import { describe, expect, test } from 'bun:test';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { CredentialNotice } from '../../../src/session/credentials.ts';
import { openSession } from '../../../src/session/session.ts';
import { frontState, type WindowedState } from '../../../src/ui/app/state.ts';
import { CTRL_O, ready, send, until, withWindow } from './render.tsx';

describe('riff credential status notices in the window', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const [scenario, words] of [
      [
        'credentialsunsaved',
        'ChatGPT sign-in refreshed but not saved; will retry.',
      ],
      ['credentialssaved', 'ChatGPT sign-in saved.'],
      [
        'credentialssignedout',
        'ChatGPT sign-in removed. This session is signed out.',
      ],
      [
        'credentialsaccountchanged',
        'ChatGPT account changed. This session is signed out.',
      ],
    ]) {
      test(`${scenario} at ${columns}x${rows} preserves draft and transcript`, () =>
        withWindow(
          async (window) => {
            await ready(window);
            await send(window, scenario ?? '');
            await window.shows('Credential fixture ready.');
            await window.type('draft stays');
            await mkdir(join(window.dir, '.fake-gate'), { recursive: true });
            await writeFile(join(window.dir, '.fake-gate', 'release'), '');
            await window.shows(words ?? '');

            const frame = window.frame();

            expect(frame).toContain('Credential fixture ready.');
            expect(frame).toContain('draft stays');
            expect(frame.indexOf(words ?? '')).toBeGreaterThan(
              frame.indexOf('draft stays'),
            );
          },
          { agent: 'riff', columns, rows },
        ));
    }
  }
});

describe('CHD-606 tester: credential notice authority', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a non-riff agent cannot set a credential notice at ${columns}x${rows}`, async () => {
      let state: WindowedState | undefined;

      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'credentialsaccountchanged');
          await window.shows('Credential fixture ready.');
          await mkdir(join(window.dir, '.fake-gate'), { recursive: true });
          await writeFile(join(window.dir, '.fake-gate', 'release'), '');
          await until(
            'the non-riff turn ended after sending its notification',
            () =>
              state !== undefined &&
              frontState(state).transcript.turn.status === 'idle',
          );

          expect(state?.window.sessionsNote).toBeUndefined();
          expect(window.frame()).not.toContain('account changed');
          expect(window.frame()).toContain('Credential fixture ready.');
        },
        {
          agent: 'fake',
          columns,
          rows,
          onState: (all) => {
            state = all;
          },
        },
      );
    });

    test(`a cleared session cannot overwrite its replacement's notice or draft at ${columns}x${rows}`, async () => {
      const callbacks: ((notice: CredentialNotice) => void)[] = [];
      let state: WindowedState | undefined;

      await withWindow(
        async (window) => {
          await ready(window);
          await until(
            'first credential subscriber',
            () => callbacks.length === 1,
          );
          await send(window, '/clear');
          await until(
            'replacement credential subscriber',
            () => callbacks.length === 2,
          );
          await ready(window);
          await window.type('replacement draft');
          callbacks[1]?.({ provider: 'grok', state: 'saved' });
          await window.shows('Grok sign-in saved.');
          callbacks[0]?.({ provider: 'codex', state: 'account_changed' });
          await window.press(CTRL_O);

          expect(state?.window.sessionsNote).toBe('Grok sign-in saved.');
          expect(window.frame()).toContain('replacement draft');
          expect(window.frame()).not.toContain('ChatGPT account changed');
        },
        {
          agent: 'riff',
          columns,
          rows,
          onState: (all) => {
            state = all;
          },
          openWith: async (options) => {
            const session = await openSession(options);
            const subscribe = session.subscribeCredentials?.bind(session);

            return {
              ...session,
              subscribeCredentials: (listener) => {
                callbacks.push(listener);

                return subscribe?.(listener) ?? (() => {});
              },
            };
          },
        },
      );
    });
  }
});

describe('riff no-store startup in the window', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`typed C1 cause at ${columns}x${rows}, with its child cleaned up`, () =>
      withWindow(
        async (window) => {
          await until('C1 failure', () =>
            window
              .frame()
              .replace(/\s+/g, ' ')
              .includes('Start one and try again.'),
          );

          const frame = window
            .frame()
            .replace(/-\n\s*/g, '-')
            .replace(/\s+/g, ' ');

          expect(frame).toContain(
            "riff did not start: it refused session/new: chord keeps your sign-in in the system's credential store, and none answered: no Secret Service (gnome-keyring or KeePassXC). Start one and try again.",
          );
          expect(frame).not.toContain('before answering initialize');
          expect(frame).not.toContain('end of its stderr');
        },
        {
          agent: 'riff',
          whileStarting: true,
          agentCommand: [
            process.execPath,
            fileURLToPath(
              new URL('../../fixtures/riff/qa_agent.ts', import.meta.url),
            ),
            'no-store',
          ],
          columns,
          rows,
        },
      ));
  }

  test(
    'a slow QA store shows the unchanged timeout cause and cleans up its child',
    () =>
      withWindow(
        async (window) => {
          await until(
            'store timeout',
            () =>
              window
                .frame()
                .replace(/\s+/g, ' ')
                .includes('The Secret Service did not answer in 20 s.'),
            30_000,
          );

          const frame = window.frame().replace(/\s+/g, ' ');

          expect(frame).toContain(
            'riff did not start: it refused session/new: The Secret Service did not answer in 20 s.',
          );
          expect(frame).not.toContain('none answered');
        },
        {
          agent: 'riff',
          whileStarting: true,
          columns: 80,
          rows: 24,
          agentCommand: [
            process.execPath,
            fileURLToPath(
              new URL('../../fixtures/riff/qa_agent.ts', import.meta.url),
            ),
            'timeout',
          ],
        },
      ),
    40_000,
  );
});

describe('riff L2 refusal in the window', () => {
  for (const state of ['removed', 'account-changed']) {
    test(`${state} keeps the submitted row and previous reply`, () =>
      withWindow(
        async (window) => {
          await window.shows('gpt-6.1-sol');
          await send(window, 'hello');
          await window.shows('Hello from a fixture plan.');
          await send(window, 'again');
          await window.shows('Sign in to a plan for riff.');

          const frame = window.frame();

          expect(frame).toContain('Hello from a fixture plan.');
          expect(frame).toContain('again');
          expect(frame).not.toContain('Working');
        },
        {
          agent: 'riff',
          columns: 80,
          rows: 24,
          agentCommand: [
            process.execPath,
            fileURLToPath(
              new URL('../../fixtures/riff/qa_agent.ts', import.meta.url),
            ),
            state,
          ],
        },
      ));
  }
});

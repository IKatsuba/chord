import { describe, expect, test } from 'bun:test';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ready, send, until, withWindow } from './render.tsx';

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

import { describe, expect, test } from 'bun:test';
import {
  memorySecrets,
  SecretStoreUnavailable,
} from '../../../src/platform/secrets.ts';
import { SignInNeeded } from '../../../src/session/sign_in.ts';
import { openSession } from '../../../src/session/session.ts';
import {
  fixtureSignIn,
  fixtureSignOut,
} from '../../../src/riff/sign_in_fixture.ts';
import { ESC, ready, send, withWindow } from '../app/render.tsx';
import { planCredential } from '../../../src/riff/qa_provider.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';

describe('riff sign-in in the window', () => {
  test('G retries the new credential after two failed saves instead of selecting the old account', async () => {
    const backing = memorySecrets({
      codex: JSON.stringify({
        ...planCredential('codex'),
        accountId: 'old-account',
      }),
    });
    let writes = 0;
    const store = {
      ...backing,
      set: (provider: 'codex' | 'grok', value: string) =>
        ++writes <= 2
          ? Promise.reject(
              new Error('Fixture credential store could not save.'),
            )
          : backing.set(provider, value),
    };

    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/login');
        await window.press('1');
        await window.press('2');
        await window.shows('Try the store again');
        expect(JSON.parse((await backing.get('codex')) ?? '{}').accountId).toBe(
          'old-account',
        );
        await window.press('1');
        await window.shows('Try the store again');
        expect(writes).toBe(2);
        expect(JSON.parse((await backing.get('codex')) ?? '{}').accountId).toBe(
          'old-account',
        );
        await window.press('1');
        await window.shows('Signed in to ChatGPT');
        expect(JSON.parse((await backing.get('codex')) ?? '{}').accountId).toBe(
          'fixture-account',
        );
      },
      {
        agent: 'riff',
        columns: 80,
        rows: 24,
        riffAccess: {
          store,
          fetch: fixtureSignOut(store),
          run: fixtureSignIn('success'),
        },
        openWith: async (options) => ({
          ...(await openSession(options)),
          riffProvider: 'codex',
        }),
      },
    );
  });

  test('cancelling an active login keeps its session; switching preserves the transcript', async () => {
    const store = memorySecrets({
      codex: JSON.stringify(planCredential('codex')),
    });
    let provider: 'codex' | 'grok' = 'codex';

    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, 'hello');
        await send(window, '/login');
        await window.shows('ChatGPT · a ChatGPT plan ✔');
        await window.type('blocked typing');
        expect(window.frame()).not.toContain('blocked typing');
        await window.press(ESC);
        expect(window.frame()).not.toContain('Not signed in.');
        await send(window, '/login');
        await window.press('2');
        await window.press('2');
        await window.shows('Signed in to Grok');
        await window.shows('riff · Grok');
        expect(window.frame()).toContain('New riff session · Grok');
        expect(window.frame()).toContain('hello');
      },
      {
        agent: 'riff',
        columns: 120,
        rows: 40,
        riffAccess: {
          store,
          fetch: fixtureSignOut(store),
          run: fixtureSignIn('success'),
          changed: (next) => {
            if (next !== undefined) {
              provider = next;
            }
          },
        },
        openWith: async (options) => ({
          ...(await openSession(options)),
          riffProvider: provider,
        }),
      },
    );
  });

  test('login on another runtime opens an idle riff child', async () => {
    const store = memorySecrets();

    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/login');
        await window.shows('Sign in to riff');
        expect(window.frame()).toContain('not signed in');
        await window.press(ESC);
        await window.shows('Not signed in. /login');
      },
      {
        agent: 'fake',
        columns: 120,
        rows: 40,
        runtimes: ['fake', 'riff'],
        startupOf: () => ({ agentCommand: fakeAgentCommand() }),
        riffAccess: {
          store,
          fetch: fixtureSignOut(store),
          run: fixtureSignIn('waiting'),
        },
        openWith: (options) =>
          options.agent === 'riff'
            ? Promise.reject(
                new SignInNeeded({
                  message:
                    'Sign in to a plan for riff; run chord riff to sign in.',
                  ways: [],
                }),
              )
            : openSession(options),
      },
    );
  });

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`cancel, sign in by code, and sign out at ${columns}x${rows}`, async () => {
      const store = memorySecrets();
      let provider: 'codex' | 'grok' = 'codex';

      await withWindow(
        async (window) => {
          await window.shows('Sign in to riff');
          await window.shows('riff · not signed in');
          expect(window.frame()).not.toContain('chord does not sign agents in');
          await window.press(ESC);
          await window.shows('Not signed in. /login');
          await window.type('hello');
          await window.press('\r');
          await window.shows('riff is not signed in: /login');
          await window.press('\x15');
          await send(window, '/login');
          await window.shows('Sign in to riff');
          await window.press('1');
          await window.shows('Sign in to ChatGPT');
          await window.press('2');
          await window.shows('WXYZ-1234');
          await window.shows('Signed in to ChatGPT');
          await window.shows('riff · ChatGPT');
          await send(window, '/logout');
          await window.shows('Sign out of ChatGPT?');
          await window.shows("OpenAI's tokens are not revoked");
          await window.press('1');
          await window.shows('Signed out of ChatGPT.');
          await window.shows('riff · not signed in');
          expect(await store.get('codex')).toBeNull();
        },
        {
          agent: 'riff',
          columns,
          rows,
          whileStarting: true,
          riffAccess: {
            store,
            fetch: fixtureSignOut(store),
            run: fixtureSignIn('success'),
            changed: (next) => {
              if (next !== undefined) {
                provider = next;
              }
            },
          },
          openWith: async (options) => {
            if ((await store.get(provider)) === null) {
              throw new SignInNeeded({
                message:
                  'Sign in to a plan for riff; run chord riff to sign in.',
                ways: [],
              });
            }

            return { ...(await openSession(options)), riffProvider: provider };
          },
        },
      );
    });

    test(`G names the store and retry remains on the same box at ${columns}x${rows}`, async () => {
      const store = memorySecrets();
      const failure = new SecretStoreUnavailable('Secret Service');

      await withWindow(
        async (window) => {
          await window.shows('Try the store again');
          await window.shows('no Secret Service');
          expect(window.frame()).not.toContain('riff did not start');
          await window.press('1');
          await window.shows('Try the store again');
          expect(window.frame().split('no Secret Service').length - 1).toBe(1);
          await window.press(ESC);
          await window.shows('Not signed in. /login');
        },
        {
          agent: 'riff',
          columns,
          rows,
          whileStarting: true,
          riffAccess: {
            store: { ...store, get: () => Promise.reject(failure) },
            fetch: () => {
              throw new Error('must not fetch');
            },
          },
          openWith: () =>
            Promise.reject(
              new SignInNeeded({
                message: failure.message,
                ways: [],
                store: {
                  state: 'unavailable',
                  name: failure.store,
                  message: failure.message,
                },
              }),
            ),
        },
      );
    });
  }
});

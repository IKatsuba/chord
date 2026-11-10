import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import type { Session, Turn } from '../../../src/session/session.ts';
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
import { CTRL_D, ESC, ready, send, until, withWindow } from '../app/render.tsx';
import { credentialSave } from '../../../src/riff/sign_in_run.ts';
import { serveChord } from '../../../src/server/server.ts';
import type { WindowedState } from '../../../src/ui/app/state.ts';
import type { Caller } from '../../../src/server/tools.ts';
import { planCredential } from '../../../src/riff/qa_provider.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import type { CredentialNotice } from '../../../src/session/credentials.ts';

describe('tester: riff window lifecycle boundaries', () => {
  test.each(['close', 'clear'] as const)(
    '%s of a signing-in child preserves its sibling session and live agent',
    async (action) => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      const opened: Session[] = [];
      const gate = Promise.withResolvers<void>();
      const finished = Promise.withResolvers<void>();
      const store = memorySecrets();
      let main: Caller | undefined;
      let signal: AbortSignal | undefined;

      server.admit = (caller) => {
        if (caller.role === 'person') {
          main = caller;
        }

        return admit(caller);
      };

      try {
        await withWindow(
          async (window) => {
            await ready(window);
            await send(window, '/new fake');
            await window.shows('╭─ fake ');
            await until('sibling connected', () => opened.length === 2);

            const sibling = opened[1];

            assert(sibling !== undefined);

            const id = sibling.id;

            await send(window, '/new riff');
            await window.shows('Sign in to riff');
            await window.press('1');
            await window.press('2');
            await until('OAuth attempt entered', () => signal !== undefined);
            assert(main !== undefined);

            if (action === 'close') {
              expect(main.window.close(main, 'riff')).not.toHaveProperty(
                'error',
              );
            } else {
              await main.window.clear(main, 'riff');
            }

            expect(signal?.aborted).toBe(true);
            gate.resolve();
            await finished.promise;
            expect(opened).toHaveLength(2);
            expect(opened[1]).toBe(sibling);
            expect(sibling.id).toBe(id);
            expect(sibling.agentPids.size).toBeGreaterThan(0);
            expect((await sibling.prompt('hello').result).status).toBe(
              'completed',
            );
            expect(opened[0]?.agentPids.size).toBeGreaterThan(0);
            expect(await store.get('codex')).toBeNull();
            expect(window.frame()).not.toContain('Signed in to ChatGPT');
          },
          {
            agent: 'fake',
            columns: 120,
            rows: 40,
            server,
            runtimes: ['fake', 'riff'],
            startupOf: () => ({ agentCommand: fakeAgentCommand() }),
            riffAccess: {
              store,
              fetch: fixtureSignOut(store),
              run: async (options) => {
                signal = options.signal;

                try {
                  await gate.promise;

                  const save = credentialSave(options, planCredential('codex'));

                  await save.retry(options.attempt, options.signal);
                  options.emit(options.attempt, {
                    kind: 'success',
                    provider: 'codex',
                    way: 'code',
                    store: store.name,
                  });
                } finally {
                  finished.resolve();
                }
              },
            },
            openWith: async (options) => {
              if (options.agent === 'riff') {
                throw new SignInNeeded({
                  message: 'fixture sign-in required',
                  ways: [],
                });
              }

              const session = await openSession(options);

              opened.push(session);

              return session;
            },
          },
        );
      } finally {
        gate.resolve();
        await server.close();
      }
    },
  );

  test('logout cancels real running turns in riff and its child before ending the session', async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    const turns: Turn[] = [];
    const store = memorySecrets({
      codex: JSON.stringify(planCredential('codex')),
    });
    let main: Caller | undefined;

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'slow');
          await window.shows('esc to interrupt');
          assert(main !== undefined);
          expect(
            await main.window.open(
              main.key,
              {
                agent: 'fake',
                name: 'worker',
                prompt: 'slow',
              },
              main,
            ),
          ).not.toHaveProperty('error');
          await until('both real turns are running', () => turns.length === 2);
          await send(window, '/logout');
          await window.shows('Sign out of ChatGPT?');
          await window.press('1');
          await window.shows('Signed out of ChatGPT.');
          expect(
            (await Promise.all(turns.map((turn) => turn.result))).map(
              (result) => result.status,
            ),
          ).toEqual(['cancelled', 'cancelled']);
          expect(await store.get('codex')).toBeNull();
        },
        {
          agent: 'riff',
          columns: 120,
          rows: 40,
          server,
          runtimes: ['riff', 'fake'],
          startupOf: () => ({ agentCommand: fakeAgentCommand() }),
          riffAccess: { store, fetch: fixtureSignOut(store) },
          openWith: async (options) => {
            const session = await openSession(options);

            return {
              ...session,
              ...(options.agent === 'riff'
                ? { riffProvider: 'codex' as const }
                : {}),
              prompt: (...args) => {
                const turn = session.prompt(...args);

                turns.push(turn);

                return turn;
              },
            };
          },
        },
      );
    } finally {
      await server.close();
    }
  });

  test('quit aborts a delayed sign-in and its late success cannot save or reopen', async () => {
    const store = memorySecrets();
    const gate = Promise.withResolvers<void>();
    const finished = Promise.withResolvers<void>();
    let signal: AbortSignal | undefined;
    let opens = 0;

    try {
      await withWindow(
        async (window) => {
          await window.shows('Sign in to riff');
          await window.press('1');
          await window.press('2');
          await until('the attempt started', () => signal !== undefined);
          await window.press(CTRL_D);
          await until('quit aborts OAuth', () => signal?.aborted === true);
          gate.resolve();
          await finished.promise;
          expect(opens).toBe(1);
          expect(await store.get('codex')).toBeNull();
        },
        {
          agent: 'riff',
          columns: 80,
          rows: 24,
          whileStarting: true,
          riffAccess: {
            store,
            fetch: fixtureSignOut(store),
            run: async (options) => {
              signal = options.signal;

              try {
                await gate.promise;

                const save = credentialSave(options, planCredential('codex'));

                await save.retry(options.attempt, options.signal);
                options.emit(options.attempt, {
                  kind: 'success',
                  provider: 'codex',
                  way: 'code',
                  store: store.name,
                });
              } finally {
                finished.resolve();
              }
            },
          },
          openWith: () => {
            opens++;

            return Promise.reject(
              new SignInNeeded({
                message: 'fixture sign-in required',
                ways: [],
              }),
            );
          },
        },
      );
    } finally {
      gate.resolve();
    }
  });
});

describe('riff sign-in in the window', () => {
  test('G can retry the new account while browser cleanup still holds the driver', async () => {
    const gate = Promise.withResolvers<void>();
    const backing = memorySecrets({
      codex: JSON.stringify({
        ...planCredential('codex'),
        accountId: 'old-account',
      }),
    });
    let writes = 0;
    let opens = 0;
    const store = {
      ...backing,
      set: (provider: 'codex' | 'grok', value: string) =>
        ++writes === 1
          ? Promise.reject(new Error('fixture save failed'))
          : backing.set(provider, value),
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/login');
          await window.press('1');
          await window.press('1');
          await window.shows('Try the store again');
          await window.press('1');
          await window.shows('Signed in to ChatGPT');
          expect(
            JSON.parse((await backing.get('codex')) ?? '{}').accountId,
          ).toBe('fixture-account');
          expect(opens).toBe(2);
        },
        {
          agent: 'riff',
          columns: 120,
          rows: 40,
          riffAccess: {
            store,
            fetch: fixtureSignOut(store),
            run: async (options) => {
              const save = credentialSave(options, planCredential('codex'));

              await save.retry(options.attempt, options.signal);
              await gate.promise;

              return save;
            },
          },
          openWith: async (options) => {
            opens++;

            return { ...(await openSession(options)), riffProvider: 'codex' };
          },
        },
      );
    } finally {
      gate.resolve();
    }
  });

  test('closing a signing-in child cancels its generation and keeps its sibling', async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Caller | undefined;

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    const gate = Promise.withResolvers<void>();
    const store = memorySecrets();
    let signal: AbortSignal | undefined;
    let all: WindowedState | undefined;
    let opens = 0;

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/new fake');
          await window.shows('╭─ fake ');
          await send(window, '/new riff');
          await window.shows('Sign in to riff');
          await window.press('1');
          await window.press('2');
          await until('the sign-in started', () => signal !== undefined);
          expect(main).toBeDefined();

          const removed = all!.front;

          expect(main!.window.close(main!, 'riff')).not.toHaveProperty('error');
          expect(signal?.aborted).toBe(true);
          gate.resolve();
          await until(
            'closed child leaves the window',
            () =>
              all!.front !== removed && all!.sessions[removed] === undefined,
          );
          await window.press(ESC);
          await send(window, 'hello');
          expect(opens).toBe(3);
          expect(await store.get('codex')).toBeNull();
          expect(window.frame()).not.toContain('Signed in to ChatGPT');
        },
        {
          agent: 'fake',
          columns: 120,
          rows: 40,
          server,
          runtimes: ['fake', 'riff'],
          onState: (state) => {
            all = state;
          },
          startupOf: () => ({ agentCommand: fakeAgentCommand() }),
          riffAccess: {
            store,
            fetch: fixtureSignOut(store),
            run: async (options) => {
              signal = options.signal;

              await gate.promise;

              const save = credentialSave(options, planCredential('codex'));

              await save.retry(options.attempt, options.signal);
              options.emit(options.attempt, {
                kind: 'success',
                provider: 'codex',
                way: 'code',
                store: store.name,
              });
            },
          },
          openWith: async (options) => {
            opens++;

            if (options.agent === 'riff') {
              throw new SignInNeeded({
                message: 'fixture sign-in required',
                ways: [],
              });
            }

            return await openSession(options);
          },
        },
      );
    } finally {
      gate.resolve();
      await server.close();
    }
  });

  test('logout with both credentials ends the session without opening the retained plan', async () => {
    const store = memorySecrets({
      codex: JSON.stringify(planCredential('codex')),
      grok: JSON.stringify(planCredential('grok')),
    });
    let opens = 0;
    let prompts = 0;

    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/logout');
        await window.press('1');
        await window.shows('Signed out of Grok, and xAI revoked');
        await window.shows('riff · not signed in');
        await window.type('hello');
        await window.press('\r');
        await window.shows('riff is not signed in: /login');
        expect(opens).toBe(1);
        expect(prompts).toBe(0);
        expect(await store.get('grok')).toBeNull();
        expect(await store.get('codex')).not.toBeNull();
        await window.press('\x15');
        await send(window, '/login');
        await window.press('1');
        await window.press('2');
        await window.shows('Signed in to ChatGPT');
        await until(
          'explicit sign-in starts the idle conversation',
          () => opens === 2,
        );
      },
      {
        agent: 'riff',
        columns: 120,
        rows: 40,
        riffAccess: {
          store,
          fetch: fixtureSignOut(store),
          run: fixtureSignIn('success'),
        },
        openWith: async (options) => {
          opens++;

          const session = await openSession(options);

          return {
            ...session,
            riffProvider: opens === 1 ? 'grok' : 'codex',
            prompt: (...args) => {
              prompts++;

              return session.prompt(...args);
            },
          };
        },
      },
    );
  });

  test('an unrelated backend startup failure closes the provisional store-read box', async () => {
    const store = memorySecrets();

    await withWindow(
      async (window) => {
        await window.shows('Fixture backend unavailable.');
        expect(window.frame()).not.toContain('Reading the sign-in');
        expect(window.frame()).not.toContain('Sign in to riff');
      },
      {
        agent: 'riff',
        columns: 80,
        rows: 24,
        splash: true,
        whileStarting: true,
        riffAccess: {
          store,
          fetch: () => {
            throw new Error('must not fetch');
          },
        },
        openWith: () =>
          Promise.reject(new Error('Fixture backend unavailable.')),
      },
    );
  });

  test('an initial slow store read gives way from the splash to its named working line', async () => {
    const gate = Promise.withResolvers<void>();
    const store = memorySecrets();

    try {
      await withWindow(
        async (window) => {
          await window.shows('Reading the sign-in from the Secret Service');
          expect(window.frame()).not.toContain('Starting riff');
          gate.resolve();
          await window.shows('Try the store again');
        },
        {
          agent: 'riff',
          columns: 80,
          rows: 24,
          splash: true,
          whileStarting: true,
          riffAccess: {
            store: { ...store, name: 'Secret Service' },
            fetch: () => {
              throw new Error('must not fetch');
            },
          },
          openWith: async () => {
            await gate.promise;

            throw new SignInNeeded({
              message: 'fixture store timeout',
              ways: [],
              store: {
                name: 'Secret Service',
                state: 'timeout',
                message: 'The Secret Service did not answer in 20 s.',
              },
            });
          },
        },
      );
    } finally {
      gate.resolve();
    }
  });

  test.each(['signed_out', 'account_changed'] as const)(
    'credential %s removes stale effort and keeps its notice after Esc',
    async (reason) => {
      const store = memorySecrets();
      const listeners = new Set<(notice: CredentialNotice) => void>();

      await withWindow(
        async (window) => {
          await ready(window);
          await window.shows('medium effort');
          await send(window, 'hello');
          await window.shows('riff is signed out of ChatGPT');
          expect(window.frame()).not.toContain('effort');
          await window.shows(
            reason === 'signed_out'
              ? 'ChatGPT sign-in removed.'
              : 'ChatGPT account changed.',
          );
          await window.press(ESC);
          expect(window.frame()).not.toContain('effort');
        },
        {
          agent: 'riff',
          columns: 80,
          rows: 24,
          riffAccess: {
            store,
            fetch: fixtureSignOut(store),
            run: fixtureSignIn('waiting'),
          },
          openWith: async (options) => {
            const session = await openSession(options);

            return {
              ...session,
              riffProvider: 'codex',
              subscribeCredentials: (listener) => {
                listeners.add(listener);

                return () => {
                  listeners.delete(listener);
                };
              },
              prompt: () => {
                for (const listener of listeners) {
                  listener({ provider: 'codex', state: reason });
                }

                return {
                  id: crypto.randomUUID(),
                  sent: Promise.resolve([]),
                  result: Promise.resolve({
                    status: 'failed',
                    error: { code: '-32000', message: 'fixture auth required' },
                  }),
                  cancel: () => Promise.resolve(),
                };
              },
            };
          },
        },
      );
    },
  );

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
        await window.shows('waiting for sign-in');
        expect(window.frame()).not.toContain('failed to start');
        await window.press(ESC);
        await window.shows('Not signed in. /login');
        await window.shows('signed out');
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

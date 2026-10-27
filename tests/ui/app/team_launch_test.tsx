import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { serveChord } from '../../../src/server/server.ts';
import type { Caller } from '../../../src/server/tools.ts';
import { openSession } from '../../../src/session/session.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { ESC, ready, send, until, withWindow, type Window } from './render.tsx';

const team = `---
description: Launch authority fixture
lead:
  agent: fake
members:
  - name: reviewer
    role: Review
    agent: fake
    instructions: Review only.
---
Preserve the saved job and permissions.
`;

async function withLaunch(
  body: (window: Window, callers: Caller[]) => Promise<void>,
  openWith: typeof openSession = openSession,
  definition = team,
) {
  const server = serveChord();
  const admit = server.admit.bind(server);
  const callers: Caller[] = [];

  server.admit = (caller) => {
    if (caller.role === 'person') {
      callers.push(caller);
    }

    return admit(caller);
  };

  try {
    await withWindow(
      async (window) => {
        await ready(window);
        await body(window, callers);
      },
      {
        server,
        agentCommand: fakeAgentCommand(),
        startupOf: () => ({ agentCommand: fakeAgentCommand() }),
        runtimes: ['fake'],
        teams: { fixture: definition },
        openWith,
      },
    );
  } finally {
    await server.close();
  }
}

function person(callers: Caller[]) {
  const caller = callers.at(-1);

  assert(caller !== undefined);

  return caller;
}

describe('team launch generation boundary', () => {
  test('cancelled saved-effort startup returns the allocated closing attempt after its await', async () => {
    const gate = Promise.withResolvers<void>();
    const request = new AbortController();
    const prompts: string[] = [];
    let opens = 0;
    let held = false;
    let closed = false;

    try {
      await withLaunch(
        async (_window, callers) => {
          const caller = person(callers);
          let answered = false;
          const pending = caller.window
            .runTeam(
              { ...caller, signal: request.signal },
              { team: 'fixture', job: 'Never deliver this effort job.' },
            )
            .then((answer) => {
              answered = true;

              return answer;
            });

          try {
            await until('saved-effort lead held before startup', () => held);
            expect(answered).toBe(false);

            const runs = (await caller.window.teams(caller)).runs;
            const allocated = caller.window
              .sessions()
              .flatMap((session) => session.children)
              .find((child) => child.name === 'fixture')?.id;

            expect(runs).toHaveLength(1);
            assert(allocated !== undefined);
            request.abort();
            gate.resolve();

            const answer = await pending;

            assert('error' in answer);
            expect(answer.error).toBe(
              `Team launch ${allocated} was cancelled before its first job; the attempted lead is closing.`,
            );
            expect(answer).not.toHaveProperty('id');
            expect(prompts).toEqual([]);
            await until('cancelled saved-effort lead exited', () => closed);
            expect((await caller.window.teams(caller)).runs).toEqual([]);
          } finally {
            gate.resolve();
            await pending;
          }
        },
        async (options) => {
          const child = opens++ > 0;
          const session = await openSession(options);

          if (child) {
            const prompt = session.prompt.bind(session);

            session.prompt = (text, ...rest) => {
              prompts.push(text);

              return prompt(text, ...rest);
            };

            void session.exited.then(() => {
              closed = true;
            });

            held = true;

            await gate.promise;
          }

          return session;
        },
        team.replace(
          'lead:\n  agent: fake\n',
          'lead:\n  agent: fake\n  effort: high\n',
        ),
      );
    } finally {
      gate.resolve();
    }
  });

  test('synchronous cancellation during open reports the allocated attempt truthfully', async () => {
    const request = new AbortController();
    let opens = 0;
    const prompts: string[] = [];

    await withLaunch(
      async (_window, callers) => {
        const caller = person(callers);
        const result = await caller.window.runTeam(
          { ...caller, signal: request.signal },
          { team: 'fixture', job: 'Do not deliver.' },
        );

        assert('error' in result);
        expect(result.error).toMatch(
          /^Team launch [a-f0-9]{8} was cancelled before its first job; the attempted lead is closing\.$/,
        );
        expect(result.error).not.toContain('no run started');
        expect(opens).toBe(2);
        expect(prompts).toEqual([]);
        expect((await caller.window.teams(caller)).runs).toEqual([]);
      },
      async (options) => {
        const child = opens++ > 0;

        if (child) {
          request.abort();
        }

        const session = await openSession(options);

        if (child) {
          const prompt = session.prompt.bind(session);

          session.prompt = (text, ...rest) => {
            prompts.push(text);

            return prompt(text, ...rest);
          };
        }

        return session;
      },
    );
  });

  test('selection is explicitly refused until selected startup integration is enabled', () =>
    withLaunch(async (window, callers) => {
      const caller = person(callers);
      const result = await caller.window.runTeam(caller, {
        team: 'fixture',
        job: 'Job.',
        selection: { reason: 'Preserve every role.' },
      });

      expect(result).toEqual({
        error: 'Selected team launches are not available yet. No run started.',
      });
      expect(window.pids).toHaveLength(1);
      expect((await caller.window.teams(caller)).runs).toEqual([]);
    }));

  for (const cancel of ['request', 'interrupt', 'clear'] as const) {
    test(`${cancel} while preflight waits cannot start a late run`, () =>
      withLaunch(async (window, callers) => {
        if (cancel === 'interrupt') {
          await send(window, 'costwait');
          await window.shows('Working until stopped.');
        }

        const caller = person(callers);
        const offer = caller.window.offer;
        const gate = Promise.withResolvers<undefined>();
        const request = new AbortController();
        let entered = false;

        caller.window.offer = () => {
          entered = true;

          return gate.promise;
        };

        const pending = caller.window.runTeam(
          { ...caller, signal: request.signal },
          { team: 'fixture', job: 'Never send this job.' },
        );

        try {
          await until('preflight capability read', () => entered);

          if (cancel === 'request') {
            request.abort();
          } else if (cancel === 'interrupt') {
            await window.press(ESC);
          } else {
            await send(window, '/clear');
            await until(
              'replacement caller admission',
              () => callers.length === 2,
            );
          }

          gate.resolve(undefined);

          expect(await pending).toEqual({
            error: 'This launch was cancelled; no run started.',
          });
          expect(
            (await person(callers).window.teams(person(callers))).runs,
          ).toEqual([]);

          if (cancel === 'clear') {
            await until(
              'replacement process opened',
              () => window.pids.length === 2,
            );
          }

          expect(window.pids.length).toBe(cancel === 'clear' ? 2 : 1);
        } finally {
          gate.resolve(undefined);

          caller.window.offer = offer;

          await pending;
        }

        if (cancel === 'interrupt') {
          expect(caller.launch?.valid()).toBe(true);
          expect(caller.launch?.signal().aborted).toBe(false);
          expect(
            await caller.window.runTeam(caller, {
              team: 'fixture',
              job: 'A later valid turn may launch.',
            }),
          ).toHaveProperty('id');
        }
      }));
  }

  test('old admission cannot borrow replacement authority or write its late call there', () =>
    withLaunch(async (window, callers) => {
      const old = person(callers);

      await send(window, '/clear');
      await until('new admission', () => callers.length === 2);
      await ready(window);
      expect(old.launch?.valid()).toBe(false);
      expect(person(callers).launch?.valid()).toBe(true);
      expect(person(callers).launch?.decisionRead).toBeUndefined();
      expect(
        await old.window.runTeam(old, {
          team: 'fixture',
          job: 'Obsolete job.',
        }),
      ).toEqual({ error: 'This launch was cancelled; no run started.' });

      old.window.served(old, {
        tool: 'run_team',
        input: { team: 'fixture', job: 'Obsolete job marker.' },
        answer: {
          id: 'obsolete',
          name: 'obsolete-marker',
          agent: 'fake',
          team: 'fixture',
        },
      });

      await window.type('replacement draft');
      await window.shows('replacement draft');

      expect(window.mounted('Obsolete job marker.')).toBe(false);
      expect(window.pids).toHaveLength(2);
    }));

  test('cancellation after the lead opens but before startup sends no first job', async () => {
    const gate = Promise.withResolvers<void>();
    const prompts: string[] = [];
    let opens = 0;
    let held = false;
    let closed = false;

    try {
      await withLaunch(
        async (_window, callers) => {
          try {
            const caller = person(callers);
            const request = new AbortController();
            const result = await caller.window.runTeam(
              { ...caller, signal: request.signal },
              { team: 'fixture', job: 'Never deliver this first job.' },
            );

            expect(result).toHaveProperty('id');
            await until('held lead initialization', () => held);

            request.abort();
            gate.resolve();

            await until('cancelled lead exited', () => closed);
            expect(prompts).toEqual([]);
            expect((await caller.window.teams(caller)).runs).toEqual([]);
          } finally {
            gate.resolve();
          }
        },
        async (options) => {
          const index = opens++;
          const session = await openSession(options);

          if (index > 0) {
            const prompt = session.prompt.bind(session);

            session.prompt = (text, ...rest) => {
              prompts.push(text);

              return prompt(text, ...rest);
            };

            void session.exited.then(() => {
              closed = true;
            });

            held = true;

            await gate.promise;
          }

          return session;
        },
      );
    } finally {
      gate.resolve();
    }
  });
});

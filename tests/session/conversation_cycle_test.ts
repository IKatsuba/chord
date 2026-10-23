/**
 * An agent's own cycle after its turn, its markers and Esc in it (CHD-426),
 * and what a session keeps of its first prompt, title and cost.
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { type SessionUpdate } from '@agentclientprotocol/sdk';
import { shellContext, withContext } from '../../src/session/context.ts';
import { cycleMark } from '../../src/session/cycles.ts';
import { FileRecording } from '../../src/session/record.ts';
import {
  openSessionLabel,
  readRecords,
  type Resume,
  sessionLabel,
} from '../../src/session/sessions.ts';
import {
  Conversation,
  type ConversationEvent,
  type Recording,
} from '../../src/session/conversation.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { initialAppState, reduceApp } from '../../src/ui/app/state.ts';
import { sessionFigure } from '../../src/ui/transcript/spend.ts';
import { turnCost } from '../../src/session/prices.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { Turn } from '../fixtures/fake_agent/turn.ts';
import { SHELL } from '../fixtures/fake_agent/scenarios/shell.ts';
import { LONG_SESSION_TITLE } from '../fixtures/fake_agent/scenarios/text.ts';
import { PERMISSIONS } from '../fixtures/fake_agent/scenarios/permissions.ts';
import {
  until,
  went,
  onFake,
  saidIn,
  MAIN,
  steerOrder,
} from './conversation_fake.ts';

describe("an agent's own cycle after its turn (CHD-426, the owner's Q49)", () => {
  /** The events from the first `cycle_started` on, by type and turn. */
  const cycleOf = (events: readonly ConversationEvent[]) => {
    const at = events.findIndex((event) => event.type === 'cycle_started');

    return at < 0 ? [] : events.slice(at);
  };

  test("Claude's: its work after the turn has gone quiet is a cycle of its own, ended by the autonomous usage", () =>
    onFake(['--adapter', 'claude'], async (conversation, events) => {
      conversation.send('claudecycle');
      await until(() => events.some((event) => event.type === 'result'));

      const turn = events.find((event) => event.type === 'prompt')!;

      await until(() => cycleOf(events).some((e) => e.type === 'result'));

      const cycle = cycleOf(events);
      const started = cycle[0]!;

      assert(started.type === 'cycle_started');
      expect(started.turnId).not.toBe(turn.turnId);
      // Its updates fold under its own turn, and its result ends it.
      expect(
        cycle
          .filter((event) => event.type === 'update' || event.type === 'result')
          .every(
            (event) => 'turnId' in event && event.turnId === started.turnId,
          ),
      ).toBeTruthy();
      expect(saidIn(cycle)).toBe(
        'The background build ended; reading its log. The build passed.',
      );
      expect(cycle.at(-1)).toStrictEqual({
        type: 'result',
        turnId: started.turnId,
        result: { status: 'completed', stopReason: 'end_turn' },
      });
    }));

  test("Claude's with no usage to end it stays working: no result comes", () =>
    onFake(['--adapter', 'claude'], async (conversation, events) => {
      conversation.send('claudecyclebare');
      await until(() => saidIn(events).includes('The build passed.'));
      await new Promise((resolve) => setTimeout(resolve, 500));

      const cycle = cycleOf(events);

      expect(cycle[0]?.type).toBe('cycle_started');
      expect(cycle.some((event) => event.type === 'result')).toBeFalsy();
    }));

  test("an agent that is not Claude's has no unmarked cycle: its work after the turn folds under that turn, as before", () =>
    onFake([], async (conversation, events) => {
      conversation.send('claudecycle');
      await until(() => saidIn(events).includes('The build passed.'));
      await new Promise((resolve) => setTimeout(resolve, 500));

      const turn = events.find((event) => event.type === 'prompt')!;

      expect(cycleOf(events)).toStrictEqual([]);
      // From the prompt on: the session's own updates as it opens, its
      // commands, may come before it.
      expect(
        events
          .slice(events.indexOf(turn))
          .filter((event) => event.type === 'update')
          .every((event) => event.turnId === turn.turnId),
      ).toBeTruthy();
    }));

  test("codebuddy's: its marker starts a cycle and session_end ends it", () =>
    onFake([], async (conversation, events) => {
      conversation.send('codebuddycycle');
      await until(() => cycleOf(events).some((e) => e.type === 'result'));

      const cycle = cycleOf(events);
      const started = cycle[0]!;

      assert(started.type === 'cycle_started');
      expect(saidIn(cycle)).toBe(
        'The background task drained; all checks are green.',
      );
      expect(cycle.at(-1)).toStrictEqual({
        type: 'result',
        turnId: started.turnId,
        result: { status: 'completed', stopReason: 'end_turn' },
      });
    }));

  test('a prompt sent while a cycle runs goes at once and takes it over (the owner’s Q47)', () =>
    onFake(['--adapter', 'claude'], async (conversation, events) => {
      conversation.send('claudecyclebare');
      await until(() => cycleOf(events).length > 0);
      conversation.send('text');
      await until(() => saidIn(events).includes('Hello, world.'));

      const prompts = events.filter((event) => event.type === 'prompt');

      expect(prompts.map((event) => event.text)).toStrictEqual([
        'claudecyclebare',
        'text',
      ]);
      expect(events.some((event) => event.type === 'queued')).toBeFalsy();
    }));
});

describe('CHD-426 U1 tester: cycle markers and pending requests', () => {
  test('the cycle can end with a permission still held, and answering it does not start another cycle', async () => {
    let source: Session | undefined;

    await onFake(
      ['--adapter', 'claude'],
      async (conversation, events) => {
        assert(source);

        const owner = source;
        let response: Promise<unknown> | undefined;
        const stop = owner.subscribe((update) => {
          if (
            response === undefined &&
            update.sessionUpdate === 'agent_message_chunk' &&
            update.content.type === 'text' &&
            update.content.text.includes('The background build ended;')
          ) {
            response = owner.permissions.handler(
              {
                sessionId: owner.id,
                toolCall: {
                  toolCallId: 'cycle-permission',
                  title: 'Keep the log',
                },
                options: [
                  { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
                ],
              },
              new AbortController().signal,
            );
          }
        });

        try {
          conversation.send('claudecycle');
          await until(() =>
            events.some((event) => event.type === 'cycle_started'),
          );

          const cycle = events.find((event) => event.type === 'cycle_started');

          assert(cycle?.type === 'cycle_started');
          await until(() =>
            events.some(
              (event) =>
                event.type === 'result' && event.turnId === cycle.turnId,
            ),
          );

          const asked = events.find(
            (event) => event.type === 'permission_requested',
          );

          assert(asked?.type === 'permission_requested');
          expect(asked.between).toBe(true);
          expect(
            events.some((event) => event.type === 'permission_settled'),
          ).toBe(false);
          conversation.choose(asked.permission.id, 'allow');
          expect(await response).toMatchObject({
            outcome: { outcome: 'selected', optionId: 'allow' },
          });
          await until(() =>
            events.some((event) => event.type === 'permission_settled'),
          );
          expect(
            events.filter((event) => event.type === 'cycle_started'),
          ).toHaveLength(1);
          expect(
            events.filter((event) => event.type === 'result'),
          ).toHaveLength(2);
        } finally {
          stop();
        }
      },
      (session) => (source = session),
    );
  });

  test('form and link requested during a cycle remain held after its end and gate the next prompt together', async () => {
    let source: Session | undefined;

    await onFake(
      ['--adapter', 'claude'],
      async (conversation, events) => {
        assert(source);

        const owner = source;
        const responses: Promise<unknown>[] = [];
        const stop = owner.subscribe((update) => {
          if (
            responses.length === 0 &&
            update.sessionUpdate === 'agent_message_chunk' &&
            update.content.type === 'text' &&
            update.content.text.includes('The background build ended;')
          ) {
            responses.push(
              owner.elicitations.handler(
                {
                  sessionId: owner.id,
                  mode: 'form',
                  message: 'Cycle form',
                  requestedSchema: { type: 'object', properties: {} },
                },
                new AbortController().signal,
              ),
            );
            responses.push(
              owner.elicitations.handler(
                {
                  sessionId: owner.id,
                  mode: 'url',
                  message: 'Cycle link',
                  url: 'https://example.com/cycle',
                  elicitationId: 'cycle-link',
                },
                new AbortController().signal,
              ),
            );
          }
        });

        try {
          conversation.send('claudecycle');
          await until(
            () =>
              events.filter((event) => event.type === 'result').length === 2,
          );

          const asked = events.filter(
            (event) => event.type === 'elicitation_requested',
          );

          expect(asked).toHaveLength(2);
          expect(asked.every((event) => event.elicitation.between)).toBe(true);
          conversation.send('text');
          expect(
            events.filter((event) => event.type === 'prompt'),
          ).toHaveLength(1);
          expect(
            events.filter((event) => event.type === 'queued').at(-1),
          ).toMatchObject({ afterAnswer: true });
          conversation.answer(asked[0]!.elicitation.id, { action: 'cancel' });
          expect(await responses[0]).toMatchObject({ action: 'cancel' });
          expect(
            events.filter((event) => event.type === 'prompt'),
          ).toHaveLength(1);
          conversation.answer(asked[1]!.elicitation.id, { action: 'cancel' });
          expect(await responses[1]).toMatchObject({ action: 'cancel' });
          await until(() => saidIn(events).includes('Hello, world.'));
          expect(
            events
              .filter((event) => event.type === 'prompt')
              .map((event) => event.text),
          ).toEqual(['claudecycle', 'text']);
        } finally {
          stop();
        }
      },
      (session) => (source = session),
    );
  });

  test('a late autonomous end marker cannot finish the prompt that took over the cycle', () =>
    onFake(['--adapter', 'claude'], async (conversation, events) => {
      conversation.send('claudecycle');
      await until(() => events.some((event) => event.type === 'cycle_started'));

      const cycle = events.find((event) => event.type === 'cycle_started');

      assert(cycle?.type === 'cycle_started');
      conversation.send('slow');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' && cycleMark(event.update) === 'end',
        ),
      );

      const own = events.filter((event) => event.type === 'prompt').at(-1);

      assert(own?.type === 'prompt');
      expect(own.text).toBe('slow');
      expect(
        events.some(
          (event) => event.type === 'result' && event.turnId === own.turnId,
        ),
      ).toBe(false);
      expect(
        events.some(
          (event) => event.type === 'result' && event.turnId === cycle.turnId,
        ),
      ).toBe(false);
      expect(events.some((event) => event.type === 'queued')).toBe(false);
      await until(() =>
        events.some(
          (event) => event.type === 'result' && event.turnId === own.turnId,
        ),
      );
      expect(
        events.filter((event) => event.type === 'cycle_started'),
      ).toHaveLength(1);
    }));
});

describe("Esc in an agent's own cycle (CHD-426 U2)", () => {
  test('sends session/cancel for it, and the cycle ends as a cancelled turn does', () =>
    onFake(
      ['--adapter', 'claude', '--say-cancels'],
      async (conversation, events) => {
        conversation.send('claudecyclebare');
        await until(() => saidIn(events).includes('The build passed.'));

        const started = events.find((event) => event.type === 'cycle_started');

        assert(started?.type === 'cycle_started');
        conversation.interrupt();

        const after = events.slice(events.indexOf(started));

        expect(
          after.filter(
            (event) => event.type === 'cancel' || event.type === 'result',
          ),
        ).toStrictEqual([
          { type: 'cancel', turnId: started.turnId, at: expect.any(Number) },
          {
            type: 'result',
            turnId: started.turnId,
            result: { status: 'cancelled', stopReason: 'cancelled' },
          },
        ]);

        // The agent was told, with no turn of chord's running, and says so
        // before anything follows, which could otherwise meet the cancel
        // first, as any prompt after a cancel can (Q42).
        await until(() =>
          saidIn(events).includes('Cancel heard with no turn.'),
        );
        conversation.send('cancels');
        await until(() => saidIn(events).includes('Cancels with no turn:'));
        expect(saidIn(events)).toContain('Cancels with no turn: 1.');
      },
    ));

  test('with no cycle and no turn, Esc tells the agent nothing', () =>
    onFake(['--adapter', 'claude'], async (conversation, events) => {
      conversation.interrupt();
      conversation.send('cancels');
      await until(() => saidIn(events).includes('Cancels with no turn:'));
      expect(saidIn(events)).toContain('Cancels with no turn: 0.');
    }));
});

describe('CHD-426 U2 tester: cancellation at real cycle markers', () => {
  for (const scenario of ['claudecycle', 'codebuddycycle']) {
    test(`${scenario}: duplicate interrupt sends one cancel and its late end cannot complete the cancelled cycle`, async () => {
      let source: Session | undefined;

      await onFake(
        ['--adapter', 'claude', '--say-cancels'],
        async (conversation, events) => {
          assert(source);

          let interrupted = false;
          const stop = source.subscribe((update) => {
            const starts =
              cycleMark(update) === 'start' ||
              (update.sessionUpdate === 'agent_message_chunk' &&
                update.content.type === 'text' &&
                update.content.text.includes('The background build ended;'));

            if (!interrupted && starts) {
              interrupted = true;

              conversation.interrupt();
              conversation.interrupt();
            }
          });

          try {
            conversation.send(scenario);
            await until(() =>
              saidIn(events).includes('Cancel heard with no turn.'),
            );
            await until(() =>
              events.some(
                (event) =>
                  event.type === 'update' && cycleMark(event.update) === 'end',
              ),
            );

            const cycle = events.find(
              (event) => event.type === 'cycle_started',
            );

            assert(cycle?.type === 'cycle_started');
            expect(
              events.filter((event) => event.type === 'cancel'),
            ).toHaveLength(1);
            expect(
              events.filter(
                (event) =>
                  event.type === 'result' && event.turnId === cycle.turnId,
              ),
            ).toEqual([
              {
                type: 'result',
                turnId: cycle.turnId,
                result: { status: 'cancelled', stopReason: 'cancelled' },
              },
            ]);
            expect(
              events.filter((event) => event.type === 'cycle_started'),
            ).toHaveLength(1);
            conversation.send('cancels');
            await until(() =>
              saidIn(events).includes('Cancels with no turn: 1.'),
            );
          } finally {
            stop();
          }
        },
        (session) => (source = session),
      );
    });
  }
});

describe('CHD-467 tester: causal fake gates and cancellation', () => {
  class ObservedTurn extends Turn {
    readonly counts: number[] = [];
    readonly waiting: boolean[] = [];

    override get told(): number {
      const count = super.told;

      this.counts.push(count);

      return count;
    }

    override get steered(): boolean {
      const waiting = super.steered;

      this.waiting.push(waiting);

      return waiting;
    }
  }

  function fixture() {
    const updates: SessionUpdate[] = [];
    const stop = new AbortController();
    const client = {
      notify: (_method: string, params: { update: SessionUpdate }) => {
        updates.push(params.update);

        return Promise.resolve();
      },
      request: () =>
        Promise.resolve({
          outcome: { outcome: 'selected', optionId: 'allow' },
        }),
    } as unknown as ConstructorParameters<typeof Turn>[0];
    const turn = new ObservedTurn(client, crypto.randomUUID(), stop.signal);
    const text = () =>
      updates
        .flatMap((update) =>
          update.sessionUpdate === 'agent_message_chunk' &&
          update.content.type === 'text'
            ? [update.content.text]
            : [],
        )
        .join('');

    return { turn, stop, updates, text };
  }

  test('bashtwo rechecks zero and one arrivals without ending, then ends on the second', async () => {
    const f = fixture();
    let ended = false;
    const running = SHELL.bashtwo(f.turn).then((reason) => {
      ended = true;

      return reason;
    });

    running.catch(() => {});

    try {
      await until(
        () => f.turn.counts.filter((count) => count === 0).length >= 2,
      );
      expect(ended).toBe(false);
      expect(f.text()).not.toContain('Two files changed.');
      f.turn.steer('<message from="main">First.</message>');
      await until(
        () => f.turn.counts.filter((count) => count === 1).length >= 2,
      );
      expect(ended).toBe(false);
      expect(f.text()).not.toContain('Two files changed.');
      f.turn.steer('<message from="main">Second.</message>');
      expect(await running).toBe('end_turn');
      expect(f.text()).toContain('Two files changed.');
      expect(f.text().split('Read the message from main.')).toHaveLength(3);
    } finally {
      f.stop.abort();
      await running.catch(() => {});
    }
  });

  test('permissionsteer rechecks no arrival after allow and only then reads the first message', async () => {
    const f = fixture();
    const running = PERMISSIONS.permissionsteer(f.turn);

    running.catch(() => {});

    try {
      await until(
        () => f.turn.waiting.filter((waiting) => !waiting).length >= 2,
      );
      expect(f.text()).not.toContain('Permission: allow.');
      f.turn.steer('<message from="main">First.</message>');
      expect(await running).toBe('end_turn');
      expect(f.text()).toContain('Read the message from main.');
      expect(f.text()).toContain('Permission: allow.');
    } finally {
      f.stop.abort();
      await running.catch(() => {});
    }
  });

  for (const count of [0, 1]) {
    test(`aborting bashtwo while it has ${count} messages stops its waiter without final output`, async () => {
      const f = fixture();
      const running = SHELL.bashtwo(f.turn);

      running.catch(() => {});

      try {
        await until(() => f.turn.counts.includes(0));

        if (count === 1) {
          f.turn.steer('First.');
        }

        await until(
          () => f.turn.counts.filter((seen) => seen === count).length >= 2,
        );
        f.stop.abort(new Error('fixture cancelled'));
        await expect(running).rejects.toThrow('fixture cancelled');
        expect(f.text()).not.toContain('Two files changed.');
      } finally {
        f.stop.abort();
        await running.catch(() => {});
      }
    });
  }

  test('aborting an allowed permissionsteer before its message stops the waiter', async () => {
    const f = fixture();
    const running = PERMISSIONS.permissionsteer(f.turn);

    running.catch(() => {});

    try {
      await until(
        () => f.turn.waiting.filter((waiting) => !waiting).length >= 2,
      );
      f.stop.abort(new Error('fixture cancelled'));
      await expect(running).rejects.toThrow('fixture cancelled');
      expect(f.text()).not.toContain('Permission: allow.');
    } finally {
      f.stop.abort();
      await running.catch(() => {});
    }
  });

  test('ordinary bash needs no arrival and keeps its existing final reply', async () => {
    const f = fixture();

    try {
      expect(await SHELL.bash(f.turn)).toBe('end_turn');
      expect(f.text()).toBe('Two files changed.');
    } finally {
      f.stop.abort();
    }
  });

  for (const kind of [
    'bashtwo-zero',
    'bashtwo-one',
    'permissionsteer',
  ] as const) {
    for (const action of ['interrupt', 'close'] as const) {
      test(`${action} releases the real fake agent waiting at ${kind}`, async () => {
        let owner: Session | undefined;

        await onFake(
          ['--steering', 'claude'],
          async (conversation, events) => {
            conversation.send(
              kind.startsWith('bashtwo') ? 'bashtwo' : 'permissionsteer',
            );

            if (kind === 'permissionsteer') {
              await until(() =>
                events.some((event) => event.type === 'permission_requested'),
              );

              const asked = events.find(
                (event) => event.type === 'permission_requested',
              );

              assert(asked?.type === 'permission_requested');
              conversation.choose(asked.permission.id, 'allow');
            }

            await until(() => steerOrder(events).includes('call ended'));

            if (kind === 'bashtwo-one') {
              conversation.tell(MAIN, 'Only one.');
              await until(() =>
                events.some(
                  (event) =>
                    event.type === 'prompt' && event.into !== undefined,
                ),
              );
            }

            expect(events.some((event) => event.type === 'result')).toBe(false);
            assert(owner);

            const pids = [...owner.agentPids];

            expect(pids.length).toBeGreaterThan(0);

            if (action === 'interrupt') {
              conversation.interrupt();
              await until(() =>
                events.some(
                  (event) =>
                    event.type === 'result' &&
                    event.result.status === 'cancelled',
                ),
              );
            }

            await conversation.close();
            await owner.exited;
            expect(owner.agentPids.size).toBe(0);
            expect(saidIn(events)).not.toContain(
              kind === 'permissionsteer'
                ? 'Permission: allow.'
                : 'Two files changed.',
            );

            for (const pid of pids) {
              expect(() => process.kill(pid, 0)).toThrow();
            }
          },
          (session) => {
            owner = session;

            return session;
          },
        );
      });
    }
  }
});

test("a session's first prompt is kept whole, shell output ahead of it too, and named as /resume names it, live and resumed (CHD-491)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const stateDir = join(dir, 'state');
  // A first prompt that is only a command's output, as bash mode sends it.
  const shellOnly = withContext(
    shellContext([
      { command: 'ls', stdout: 'a\n', stderr: '', running: false, code: 0 },
    ]),
    '',
  );
  const opened = async (resume?: Resume) => {
    const events: ConversationEvent[] = [];
    const recording = new FileRecording(stateDir, () => {});

    const conversation = new Conversation(
      () =>
        openSession({
          agent: 'fake',
          cwd: dir,
          agentCommand: fakeAgentCommand(),
          ...(resume === undefined ? {} : { resume }),
        }),
      (event) => events.push(event),
      Date.now,
      {},
      recording,
    );

    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));

    return { conversation, events, recording };
  };

  try {
    const live = await opened();

    expect(live.conversation.firstPrompt).toStrictEqual(undefined);
    live.conversation.send('', shellOnly);
    await until(() => live.events.some((event) => event.type === 'result'));
    expect(openSessionLabel(live.conversation.firstPrompt)).toStrictEqual(
      '!ls',
    );
    live.conversation.send('text');
    await until(
      () => live.events.filter((event) => event.type === 'result').length === 2,
    );
    // A later prompt leaves the name as it was.
    expect(openSessionLabel(live.conversation.firstPrompt)).toStrictEqual(
      '!ls',
    );
    await live.conversation.close();
    await live.recording.flushed();

    const [record] = await readRecords(stateDir);

    assert(record);
    expect(sessionLabel(record)).toStrictEqual('!ls');

    const resumed = await opened({
      sessionId: record.sessionId,
      cwd: dir,
      record: record.path,
    });

    try {
      expect(openSessionLabel(resumed.conversation.firstPrompt)).toStrictEqual(
        '!ls',
      );
    } finally {
      await resumed.conversation.close();
    }
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("the agent's own title for its session is kept as it comes and changes, none while it gives none, and comes back on resume (CHD-491)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const stateDir = join(dir, 'state');
  const opened = async (resume?: Resume) => {
    const events: ConversationEvent[] = [];
    const recording = new FileRecording(stateDir, () => {});

    const conversation = new Conversation(
      () =>
        openSession({
          agent: 'fake',
          cwd: dir,
          agentCommand: fakeAgentCommand(),
          ...(resume === undefined ? {} : { resume }),
        }),
      (event) => events.push(event),
      Date.now,
      {},
      recording,
    );

    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));

    return { conversation, events, recording };
  };

  const results = (events: readonly ConversationEvent[]) =>
    events.filter((event) => event.type === 'result').length;

  try {
    const live = await opened();

    live.conversation.send('text');
    await until(() => results(live.events) === 1);
    expect(live.conversation.title).toStrictEqual(undefined);

    // Named, then named again: the last name holds.
    live.conversation.send('retitled');
    await until(() => results(live.events) === 2);
    expect(live.conversation.title).toStrictEqual('Fix the parser');

    live.conversation.send('titled');
    await until(() => results(live.events) === 3);
    expect(live.conversation.title).toStrictEqual('Fix the tokenizer');
    await live.conversation.close();
    await live.recording.flushed();

    const [record] = await readRecords(stateDir);

    assert(record);

    const resumed = await opened({
      sessionId: record.sessionId,
      cwd: dir,
      record: record.path,
    });

    try {
      expect(resumed.conversation.title).toStrictEqual('Fix the tokenizer');
    } finally {
      await resumed.conversation.close();
    }
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('a title the agent gives at its start, before any prompt, and one longer than any row are kept as given (CHD-445)', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(undefined, '--title', 'Started named'),
      }),
    (event) => events.push(event),
  );

  try {
    conversation.start();
    await until(() => conversation.title === 'Started named');
    conversation.send('titledlong');
    await until(() => events.some((event) => event.type === 'result'));
    expect(conversation.title).toStrictEqual(LONG_SESSION_TITLE);
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
});

describe('CHD-491 U2 tester: title ownership, reset and recorded state', () => {
  for (const cleared of [false, true]) {
    test(`resume preserves the ${cleared ? 'null-cleared fallback' : 'last usable own title'} despite nested and blank updates`, async () => {
      const dir = await mkdtemp(join(tmpdir(), 'chord-title-'));
      const stateDir = join(dir, 'state');
      let publish: Parameters<Session['subscribe']>[0] | undefined;
      const opened = async (resume?: Resume) => {
        const events: ConversationEvent[] = [];
        const recording = new FileRecording(stateDir, () => {});

        const conversation = new Conversation(
          async () => {
            const session = await openSession({
              agent: 'fake',
              cwd: dir,
              agentCommand: fakeAgentCommand(undefined, '--resume-only'),
              ...(resume === undefined ? {} : { resume }),
            });
            const subscribe = session.subscribe.bind(session);

            session.subscribe = (listener) => {
              publish = listener;

              return subscribe(listener);
            };

            return session;
          },
          (event) => events.push(event),
          Date.now,
          {},
          recording,
        );

        try {
          conversation.start();
          await until(() => events.some((event) => event.type === 'connected'));

          return { conversation, events, recording };
        } catch (error) {
          await conversation.close();
          await recording.flushed();

          throw error;
        }
      };

      let live: Awaited<ReturnType<typeof opened>> | undefined;
      let resumed: Awaited<ReturnType<typeof opened>> | undefined;

      try {
        live = await opened();

        live.conversation.send('First fallback');
        await until(() =>
          live!.events.some((event) => event.type === 'result'),
        );
        assert(publish);
        publish({ sessionUpdate: 'session_info_update', title: 'Own title' });
        publish({ sessionUpdate: 'session_info_update' });
        publish({ sessionUpdate: 'session_info_update', title: '' });
        publish({ sessionUpdate: 'session_info_update', title: ' \t\n ' });
        publish(
          { sessionUpdate: 'session_info_update', title: 'Nested title' },
          'outer',
        );
        expect(live.conversation.title).toBe('Own title');

        if (cleared) {
          publish({ sessionUpdate: 'session_info_update', title: null });
        }

        expect(live.conversation.title).toBe(cleared ? undefined : 'Own title');
        await live.conversation.close();
        await live.recording.flushed();

        const [record] = await readRecords(stateDir);

        assert(record);

        resumed = await opened({
          sessionId: record.sessionId,
          cwd: dir,
          record: record.path,
        });

        expect(resumed.conversation.title).toBe(
          cleared ? undefined : 'Own title',
        );
        expect(openSessionLabel(resumed.conversation.firstPrompt)).toBe(
          'First fallback',
        );
        resumed.conversation.send('Another prompt');
        await until(() =>
          resumed!.events.some((event) => event.type === 'result'),
        );
        expect(resumed.conversation.title).toBe(
          cleared ? undefined : 'Own title',
        );
      } finally {
        await resumed?.conversation.close();
        await resumed?.recording.flushed();
        await live?.conversation.close();
        await live?.recording.flushed();
        await rm(dir, { recursive: true });
      }
    });
  }
});

test("recorded settles only once the first prompt's line is flushed, and at once for a session opened again (CHD-492)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  // A record whose writes hang until the test lets them land.
  const flushing = Promise.withResolvers<void>();
  const recording: Recording = {
    opened: () => {},
    sent: () => {},
    heard: () => {},
    flushed: () => flushing.promise,
  };
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(),
      }),
    (event) => events.push(event),
    Date.now,
    {},
    recording,
  );
  let settled = false;

  void conversation.recorded().then(() => {
    settled = true;
  });

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));
    conversation.send('text');
    await until(() => events.some((event) => event.type === 'result'));
    await went();
    // Sent and answered, but its line not yet kept.
    expect(settled).toStrictEqual(false);
    flushing.resolve();
    await until(() => settled);
  } finally {
    // A failure above leaves the write held, which the close would wait on.
    flushing.resolve();
    await conversation.close();
  }

  // Opened again with no record and nothing replayed, it is resumable now.
  const resumed = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(undefined, '--resume-only', '--no-load'),
        resume: { sessionId: crypto.randomUUID(), cwd: dir },
      }),
    () => {},
    Date.now,
    {},
    recording,
  );
  let again = false;

  void resumed.recorded().then(() => {
    again = true;
  });

  try {
    resumed.start();
    await until(() => again);
  } finally {
    await resumed.close();
    await rm(dir, { recursive: true });
  }
});

test('on dirac with no cost of its own, an answer priced and then one on a model with no price, each with a costless usage update: the second is not counted, by its model (CHD-472)', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'dirac',
        cwd: dir,
        agentCommand: fakeAgentCommand(
          undefined,
          '--session-usage',
          '--tokens-only',
          '--no-cost',
          '--unpriced-model',
        ),
      }),
    (event) => events.push(event),
  );
  const usages = () => events.filter((event) => event.type === 'usage').length;

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));
    conversation.send('text');
    await until(() => usages() === 1);
    conversation.setModel('fake-unpriced');
    await until(() =>
      events.some(
        (event) =>
          event.type === 'model' && event.models?.current === 'fake-unpriced',
      ),
    );
    conversation.send('text');
    await until(() => usages() === 2);

    const figure = sessionFigure(
      events.reduce(reduceApp, initialAppState).spent,
    );

    expect(figure).toMatchObject({
      cost: {
        amount: expect.closeTo(
          turnCost('gpt-5.3-codex', {
            inputTokens: 1000,
            outputTokens: 200,
            cachedReadTokens: 800,
            totalTokens: 2000,
          })!,
          12,
        ),
      },
      estimated: 'all',
      uncounted: 1,
      totals: { unpriced: ['fake-unpriced'] },
    });
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
});

test('a permission asked in a turn says when it came, as one between turns does, which a subagent asking counts from (CHD-487)', () =>
  onFake([], async (conversation, events) => {
    const before = Date.now();

    conversation.send('permission');
    await until(() =>
      events.some((event) => event.type === 'permission_requested'),
    );

    const asked = events.find((event) => event.type === 'permission_requested');

    assert(asked?.type === 'permission_requested');
    expect(asked.at).toBeGreaterThanOrEqual(before);
    expect(asked.at).toBeLessThanOrEqual(Date.now());
    expect(asked).not.toHaveProperty('between');
    conversation.interrupt();
  }));

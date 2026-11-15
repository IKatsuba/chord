import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  Conversation,
  type ConversationEvent,
  type Starting,
} from '../../src/session/conversation.ts';
import { initialValuesOf } from '../../src/session/initial_options.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { heldSession, isAlive, until } from './conversation_fake.ts';

function fixture() {
  const exits: (() => void)[] = [];
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () => {
      const exit = Promise.withResolvers<void>();
      const { session } = heldSession();

      exits.push(() => exit.resolve());

      return Promise.resolve({
        ...session,
        id: `launch-${exits.length}`,
        exited: exit.promise,
        close: () => {
          exit.resolve();

          return Promise.resolve();
        },
      } as Session);
    },
    (event) => events.push(event),
  );

  return { conversation, events, exits };
}

describe('pending launch authority', () => {
  test('interrupt revokes captured authority even while idle and allows a later turn', async () => {
    const { conversation, events } = fixture();

    try {
      conversation.start();
      await until(() => events.some((event) => event.type === 'connected'));

      const previous = conversation.launchSignal;

      conversation.interrupt();

      expect(previous.aborted).toBe(true);
      expect(conversation.launchSignal).not.toBe(previous);
      expect(conversation.launchSignal.aborted).toBe(false);
    } finally {
      await conversation.close();
    }
  });

  test('clear revokes old authority synchronously and old exit cannot revoke the replacement', async () => {
    const { conversation, events } = fixture();

    try {
      conversation.start();
      await until(() => events.some((event) => event.type === 'connected'));

      const previous = conversation.launchSignal;
      const closed = conversation.clear();

      expect(previous.aborted).toBe(true);
      expect(conversation.launchSignal).not.toBe(previous);
      await closed;
      await until(
        () => events.filter((event) => event.type === 'connected').length === 2,
      );
      expect(conversation.launchSignal.aborted).toBe(false);
    } finally {
      await conversation.close();
    }
  });

  test('disconnect revokes authority and clear creates a new generation', async () => {
    const { conversation, events, exits } = fixture();

    try {
      conversation.start();
      await until(() => events.some((event) => event.type === 'connected'));

      const previous = conversation.launchSignal;

      exits[0]!();
      await until(() => events.some((event) => event.type === 'disconnected'));
      expect(previous.aborted).toBe(true);
      expect(conversation.launchSignal.aborted).toBe(true);
      await conversation.clear();
      await until(
        () => events.filter((event) => event.type === 'connected').length === 2,
      );
      expect(conversation.launchSignal.aborted).toBe(false);
    } finally {
      await conversation.close();
    }
  });

  test('close revokes synchronously and never restores authority', async () => {
    const { conversation, events } = fixture();

    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));

    const previous = conversation.launchSignal;
    const closed = conversation.close();

    expect(previous.aborted).toBe(true);
    conversation.interrupt();
    await closed;
    expect(conversation.launchSignal.aborted).toBe(true);
  });
});

describe('tester: repeated launch authority revocation', () => {
  test('successive idle interrupts revoke every earlier signal without replacing the live session', async () => {
    const { conversation, events } = fixture();

    try {
      conversation.start();
      await until(() => events.some((event) => event.type === 'connected'));

      const session = conversation.session;
      const first = conversation.launchSignal;

      conversation.interrupt();

      const second = conversation.launchSignal;

      conversation.interrupt();

      expect(first.aborted).toBe(true);
      expect(second.aborted).toBe(true);
      expect(conversation.launchSignal.aborted).toBe(false);
      expect(conversation.session).toBe(session);
      expect(events.filter((event) => event.type === 'connected')).toHaveLength(
        1,
      );
    } finally {
      await conversation.close();
    }
  });
});

describe('CHD-629 tester: starting chain process boundaries', () => {
  async function startingFake(
    flags: readonly string[],
    body: (seen: {
      conversation: Conversation;
      events: ConversationEvent[];
      asks: string[];
      session: Session;
    }) => Promise<void>,
  ) {
    const dir = await mkdtemp(join(tmpdir(), 'chord-starting-boundary-'));
    const events: ConversationEvent[] = [];
    const asks: string[] = [];
    let opened: Session | undefined;
    const conversation = new Conversation(
      async (signal, values) => {
        const session = await openSession({
          agent: 'fake',
          cwd: dir,
          agentCommand: fakeAgentCommand(undefined, ...flags),
          signal,
          initial: initialValuesOf(values),
        });

        opened = session;

        return {
          ...session,
          setModel: (id) => {
            asks.push(`model ${id}`);

            return session.setModel(id);
          },
          setMode: (id) => {
            asks.push(`mode ${id}`);

            return session.setMode(id);
          },
        };
      },
      (event) => events.push(event),
      Date.now,
      {
        model: { id: 'fake-small', required: true },
        mode: { id: 'plan', required: true },
      },
    );

    try {
      conversation.start();
      await until(() => opened !== undefined && asks.length > 0);

      if (opened === undefined) {
        throw new Error('the fake session did not open');
      }

      await body({ conversation, events, asks, session: opened });
    } finally {
      const pids = [...(opened?.agentPids ?? [])];

      await conversation.close();

      for (const pid of pids) {
        expect(await isAlive(pid)).toBe(false);
      }

      await rm(dir, { recursive: true });
    }
  }

  test('a hung startup ask does not hold another session', () =>
    startingFake(['--hang', 'config'], async (hung) => {
      await startingFake([], async (healthy) => {
        await until(() =>
          healthy.events.some((event) => event.type === 'connected'),
        );
        healthy.conversation.send('text');
        await until(() =>
          healthy.events.some((event) => event.type === 'result'),
        );

        expect(healthy.asks).toStrictEqual(['model fake-small', 'mode plan']);
        expect(hung.asks).toStrictEqual(['model fake-small']);
        expect(hung.events.some((event) => event.type === 'connected')).toBe(
          false,
        );
      });
    }));

  test('an agent exiting during the first required ask receives no remaining startup changes', () =>
    startingFake(['--hang', 'config'], async ({ events, asks, session }) => {
      await session.close();
      await until(() =>
        events.some(
          (event) =>
            event.type === 'connect_failed' || event.type === 'disconnected',
        ),
      );

      expect(asks).toStrictEqual(['model fake-small']);
      expect(
        events.some(
          (event) => event.type === 'connected' || event.type === 'prompt',
        ),
      ).toBe(false);
    }));
});

describe('the starting values read back as the chain’s first link (CHD-629)', () => {
  /**
   * A conversation on the fake under `flags`, started on `starting`, with
   * every model, effort and mode ask its sessions took, in order, each
   * marked by the session's number when it is not the first's. An ask named
   * `hold` waits for `release` before it reaches the agent; the body then
   * runs once it is held, else once the conversation is up.
   */
  async function startedOn(
    flags: readonly string[],
    starting: Starting,
    body: (seen: {
      conversation: Conversation;
      events: ConversationEvent[];
      asks: string[];
      session: () => Session | undefined;
      release: () => void;
    }) => void | Promise<void>,
    hold?: string,
  ) {
    const dir = await mkdtemp(join(tmpdir(), 'chord-starting-'));
    const events: ConversationEvent[] = [];
    const asks: string[] = [];
    const gate = Promise.withResolvers<void>();
    let opens = 0;
    let current: Session | undefined;
    const conversation: Conversation = new Conversation(
      async (signal, values) => {
        const session = await openSession({
          agent: 'fake',
          cwd: dir,
          agentCommand: fakeAgentCommand(undefined, ...flags),
          signal,
          initial: initialValuesOf(values),
        });
        const mark = ++opens === 1 ? '' : `${opens}: `;
        const asked = async (what: string, ask: () => Promise<void>) => {
          asks.push(`${mark}${what}`);

          if (what === hold) {
            await gate.promise;
          }

          await ask();
          asks.push(`${mark}${what} answered`);
        };

        current = {
          ...session,
          setModel: (id) => asked(`model ${id}`, () => session.setModel(id)),
          setEffort: (id) => asked(`effort ${id}`, () => session.setEffort(id)),
          setMode: (id) => asked(`mode ${id}`, () => session.setMode(id)),
        };

        return current;
      },
      (event) => events.push(event),
      Date.now,
      starting,
    );

    try {
      conversation.start();
      await until(() =>
        hold === undefined
          ? events.some(
              (event) =>
                event.type === 'connected' || event.type === 'connect_failed',
            )
          : asks.includes(hold),
      );
      await body({
        conversation,
        events,
        asks,
        session: () => current,
        release: () => gate.resolve(),
      });
    } finally {
      gate.resolve();
      await conversation.close();
      await rm(dir, { recursive: true });
    }
  }

  const ON = {
    model: { id: 'fake-small', from: 'set by --model' },
    effort: { id: 'high', from: 'set in settings' },
    mode: { id: 'plan', from: 'set by --permission-mode' },
  };

  const failed = (events: readonly ConversationEvent[]) =>
    events.filter(
      (event) => event.type === 'failed' || event.type === 'connect_failed',
    );

  const on = (session: Session | undefined) => ({
    model: session?.models()?.current,
    effort: session?.efforts()?.current,
    mode: session?.modes()?.current,
  });

  /** The asks sent, their answers left out. */
  const sent = (asks: readonly string[]) =>
    asks.filter((ask) => !ask.endsWith(' answered'));

  const ASKED = { model: 'fake-small', effort: 'high', mode: 'plan' };

  test('values the agent took at session/new cost nothing: no ask, no line', () =>
    startedOn(
      ['--adapter', 'claude', '--options', 'apply'],
      ON,
      ({ events, asks, session }) => {
        expect(on(session())).toStrictEqual(ASKED);
        expect(sent(asks)).toStrictEqual([]);
        expect(failed(events)).toStrictEqual([]);
      },
    ));

  for (const flags of [
    ['--options', 'ignore'],
    ['--options', 'apply', '--config-ids', 'renamed'],
  ]) {
    test(`values the agent skipped are asked after it opens, by the ids it reports (${flags.join(' ')})`, () =>
      startedOn(
        ['--adapter', 'claude', ...flags],
        ON,
        ({ events, asks, session }) => {
          expect(on(session())).toStrictEqual(ASKED);
          expect(sent(asks)).toStrictEqual([
            'model fake-small',
            'effort high',
            'mode plan',
          ]);
          expect(failed(events)).toStrictEqual([]);
        },
      ));
  }

  const AUTO = {
    model: { id: 'fake-small', from: 'set by --model' },
    mode: { id: 'auto', from: 'set by --permission-mode' },
  };

  test('an optional value the agent turns down is asked twice at most, and the session goes on in what the agent chose, with no line of chord’s', () =>
    startedOn(
      ['--adapter', 'claude', '--options', 'apply', '--auto-fallback'],
      AUTO,
      ({ events, asks, session }) => {
        expect(sent(asks)).toStrictEqual(['mode auto']);
        expect(session()?.modes()?.current).toBe('acceptEdits');
        expect(failed(events)).toStrictEqual([]);
      },
    ));

  test('a required value the agent turns down fails the start: the agent is in what it chose', () =>
    startedOn(
      ['--adapter', 'claude', '--options', 'apply', '--auto-fallback'],
      { ...AUTO, mode: { ...AUTO.mode, required: true } },
      ({ events }) => {
        expect(JSON.stringify(failed(events))).toContain(
          'Could not start in auto mode, set by --permission-mode: the agent is in acceptEdits',
        );
      },
    ));

  test('a model that moves a mode which matched at first is followed by the mode asked again', () =>
    startedOn(
      ['--adapter', 'claude', '--options', 'ignore', '--auto-fallback'],
      AUTO,
      ({ events, asks, session }) => {
        expect(sent(asks)).toStrictEqual(['model fake-small', 'mode auto']);
        expect(session()?.modes()?.current).toBe('acceptEdits');
        expect(failed(events)).toStrictEqual([]);
      },
    ));

  test('a mode asked while the start runs waits behind it, and goes once the start’s is answered', () =>
    startedOn(
      [],
      { mode: { id: 'acceptEdits', from: 'set in settings' } },
      async ({ conversation, events, asks, session, release }) => {
        const asked = conversation.setMode('plan');

        // The start's ask is held at the agent's door: the person's waits.
        await Promise.resolve();
        expect(asks).toStrictEqual(['mode acceptEdits']);

        release();
        await asked;

        expect(asks).toStrictEqual([
          'mode acceptEdits',
          'mode acceptEdits answered',
          'mode plan',
          'mode plan answered',
        ]);
        expect(session()?.modes()?.current).toBe('plan');
        expect(failed(events)).toStrictEqual([]);
      },
      'mode acceptEdits',
    ));

  test('a clear while a starting ask is out leaves the rest of that start unasked on the retired session', () =>
    startedOn(
      [],
      {
        model: { id: 'fake-small', from: 'set by --model' },
        mode: { id: 'plan', from: 'set in settings' },
      },
      async ({ conversation, events, asks, release }) => {
        const cleared = conversation.clear();

        release();
        await cleared;
        await until(
          () => events.filter((event) => event.type === 'connected').length > 0,
        );
        await until(() => asks.includes('2: mode plan answered'));

        // Its model ask may answer or fail as its agent goes; nothing follows it.
        expect(
          asks.filter(
            (ask) => !ask.startsWith('2: ') && !ask.startsWith('model '),
          ),
        ).toStrictEqual([]);
      },
      'model fake-small',
    ));
});

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
import { heldSession, until } from './conversation_fake.ts';

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

describe('the starting values read back as the chain’s first link (CHD-629)', () => {
  /**
   * A conversation on the fake under `flags`, started on `starting`, with
   * every model, effort and mode ask its session took, in order.
   */
  async function startedOn(
    flags: readonly string[],
    starting: Starting,
    body: (
      conversation: Conversation,
      events: ConversationEvent[],
      asks: string[],
      session: () => Session | undefined,
      answered: string[],
    ) => void | Promise<void>,
    opened: (conversation: Conversation) => void = () => {},
  ) {
    const dir = await mkdtemp(join(tmpdir(), 'chord-starting-'));
    const events: ConversationEvent[] = [];
    const asks: string[] = [];
    /** Each mode asked and answered, in the order it happened. */
    const answered: string[] = [];
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

        current = {
          ...session,
          setModel: (id) => (asks.push(`model ${id}`), session.setModel(id)),
          setEffort: (id) => (asks.push(`effort ${id}`), session.setEffort(id)),
          setMode: async (id) => {
            asks.push(`mode ${id}`);
            answered.push(`ask ${id}`);
            await session.setMode(id);
            answered.push(`answer ${id}`);
          },
        };

        // Once the conversation holds the session, its start just begun.
        setTimeout(() => opened(conversation));

        return current;
      },
      (event) => events.push(event),
      Date.now,
      starting,
    );

    try {
      conversation.start();
      await until(() =>
        events.some(
          (event) =>
            event.type === 'connected' || event.type === 'connect_failed',
        ),
      );
      await body(conversation, events, asks, () => current, answered);
    } finally {
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

  const ASKED = { model: 'fake-small', effort: 'high', mode: 'plan' };

  test('values the agent took at session/new cost nothing: no ask, no line', () =>
    startedOn(
      ['--adapter', 'claude', '--options', 'apply'],
      ON,
      (_, events, asks, session) => {
        expect(on(session())).toStrictEqual(ASKED);
        expect(asks).toStrictEqual([]);
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
        (_, events, asks, session) => {
          expect(on(session())).toStrictEqual(ASKED);
          expect(asks).toStrictEqual([
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
      (_, events, asks, session) => {
        expect(asks).toStrictEqual(['mode auto']);
        expect(session()?.modes()?.current).toBe('acceptEdits');
        expect(failed(events)).toStrictEqual([]);
      },
    ));

  test('a required value the agent turns down fails the start: the agent is in what it chose', () =>
    startedOn(
      ['--adapter', 'claude', '--options', 'apply', '--auto-fallback'],
      { ...AUTO, mode: { ...AUTO.mode, required: true } },
      (_, events) => {
        expect(JSON.stringify(failed(events))).toContain(
          'Could not start in auto mode, set by --permission-mode: the agent is in acceptEdits',
        );
      },
    ));

  test('a model that moves a mode which matched at first is followed by the mode asked again', () =>
    startedOn(
      ['--adapter', 'claude', '--options', 'ignore', '--auto-fallback'],
      AUTO,
      (_, events, asks, session) => {
        expect(asks).toStrictEqual(['model fake-small', 'mode auto']);
        expect(session()?.modes()?.current).toBe('acceptEdits');
        expect(failed(events)).toStrictEqual([]);
      },
    ));

  test('a mode asked while the start runs waits behind it', () =>
    startedOn(
      ['--config-delay', '200'],
      { mode: { id: 'acceptEdits', from: 'set in settings' } },
      async (_, events, asks, session, answered) => {
        await until(() => answered.length === 4);

        // The person's mode is asked only once the start's was answered.
        expect(answered).toStrictEqual([
          'ask acceptEdits',
          'answer acceptEdits',
          'ask plan',
          'answer plan',
        ]);
        expect(session()?.modes()?.current).toBe('plan');
        expect(failed(events)).toStrictEqual([]);
      },
      (conversation) => void conversation.setMode('plan').catch(() => {}),
    ));
});

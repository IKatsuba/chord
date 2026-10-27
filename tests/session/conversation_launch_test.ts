import { describe, expect, test } from 'bun:test';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import type { Session } from '../../src/session/session.ts';
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

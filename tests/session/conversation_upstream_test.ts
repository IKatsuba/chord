/**
 * What `chord acp` asks of a conversation beyond what the window does: a turn
 * the caller names, links as given, one prompt taken back, a set that answers.
 */
import { describe, expect, test } from 'bun:test';
import { RequestError } from '@agentclientprotocol/sdk/unstable';
import { pathToFileURL } from 'node:url';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import type { Session } from '../../src/session/session.ts';
import {
  ended,
  heldSession,
  onFake,
  promptsIn,
  saidIn,
  until,
} from './conversation_fake.ts';

const asked = (events: readonly ConversationEvent[]) =>
  events.some((event) => event.type === 'permission_requested');

const withdrawn = (events: readonly ConversationEvent[]) =>
  events.flatMap((event) =>
    event.type === 'queue_withdrawn' ? [event.turnIds] : [],
  );

const resultOf = (events: readonly ConversationEvent[], turnId: string) =>
  events.find((event) => event.type === 'result' && event.turnId === turnId);

describe('a turn the caller names', () => {
  test('the prompt carries it before send returns', () =>
    onFake([], async (conversation, events) => {
      expect(conversation.send('text', 'text', [], [], { turnId: 'a' })).toBe(
        true,
      );
      expect(events).toContainEqual(
        expect.objectContaining({ type: 'prompt', turnId: 'a' }),
      );

      await ended(events, 1);
    }));

  test('a queued one is reported under it, and plays under it', () =>
    onFake([], async (conversation, events) => {
      conversation.send('permission', 'permission', [], [], { turnId: 'a' });
      conversation.send('text', 'text', [], [], { turnId: 'b' });

      expect(events).toContainEqual(
        expect.objectContaining({ type: 'queued', turnId: 'b' }),
      );

      await until(() => asked(events));

      conversation.cancelPrompt('a');

      await until(() => resultOf(events, 'b') !== undefined);

      expect(events).toContainEqual(
        expect.objectContaining({ type: 'prompt', turnId: 'b' }),
      );
    }));

  test('send still mints one when none is given', () =>
    onFake([], async (conversation, events) => {
      conversation.send('text');

      expect(promptsIn(events)).toHaveLength(1);

      await ended(events, 1);
    }));
});

describe('links as given', () => {
  test('reach the agent, and what a prompt reports went', async () => {
    const uri = pathToFileURL('/somewhere/a.ts').href;
    const link = { type: 'resource_link', name: 'a.ts', uri } as const;
    let sent: Promise<unknown> | undefined;

    await onFake(
      [],
      async (conversation, events) => {
        conversation.send('text', 'text', [], [], { links: [link] });

        await ended(events, 1);

        expect(await sent).toEqual([link]);
        expect(saidIn(events)).toContain(`Received a link: a.ts, ${uri}`);
      },
      (session) => {
        const prompt = session.prompt.bind(session);

        session.prompt = (...args) => {
          const turn = prompt(...args);

          sent = turn.sent;

          return turn;
        };

        return session;
      },
    );
  });
});

describe('queue_withdrawn.turnIds', () => {
  test('an interrupt names each prompt it takes back, and no message', () =>
    onFake([], async (conversation, events) => {
      conversation.send('permission', 'permission', [], [], { turnId: 'a' });

      await until(() => asked(events));

      conversation.send('one', 'one', [], [], { turnId: 'b' });
      conversation.send('two', 'two', [], [], { turnId: 'c' });
      conversation.deliver({ name: 'lead', reachable: true }, 'text');
      conversation.interrupt();

      expect(withdrawn(events)).toEqual([['b', 'c']]);

      await until(() => promptsIn(events).length === 2);
      await ended(events, 2);
    }));
});

describe('cancelPrompt', () => {
  test('a queued prompt alone: it never reaches the agent, the rest run', () =>
    onFake([], async (conversation, events) => {
      conversation.send('permission', 'permission', [], [], { turnId: 'a' });

      await until(() => asked(events));

      conversation.send('one', 'one', [], [], { turnId: 'b' });
      conversation.send('text', 'text', [], [], { turnId: 'c' });
      conversation.cancelPrompt('b');

      expect(withdrawn(events)).toEqual([['b']]);
      expect(resultOf(events, 'a')).toBeUndefined();

      conversation.cancelPrompt('a');

      await until(() => resultOf(events, 'c') !== undefined);

      expect(promptsIn(events).map(([text]) => text)).toEqual([
        'permission',
        'text',
      ]);
    }));

  test('the running prompt: it ends cancelled, and the queue runs next', () =>
    onFake([], async (conversation, events) => {
      conversation.send('permission', 'permission', [], [], { turnId: 'a' });

      await until(() => asked(events));

      conversation.send('text', 'text', [], [], { turnId: 'b' });
      conversation.cancelPrompt('a');

      expect(withdrawn(events)).toEqual([]);
      expect(events).toContainEqual(
        expect.objectContaining({ type: 'cancel', turnId: 'a' }),
      );

      await until(() => resultOf(events, 'b') !== undefined);

      expect(resultOf(events, 'a')).toEqual(
        expect.objectContaining({
          result: expect.objectContaining({ status: 'cancelled' }),
        }),
      );
      expect(events).toContainEqual(
        expect.objectContaining({
          type: 'permission_settled',
          answer: { type: 'withdrawn' },
        }),
      );
    }));

  test('a turn over, or one it never heard of, changes nothing', () =>
    onFake([], async (conversation, events) => {
      conversation.send('text', 'text', [], [], { turnId: 'a' });

      await ended(events, 1);

      const before = events.length;

      conversation.cancelPrompt('a');
      conversation.cancelPrompt('nobody');

      expect(events).toHaveLength(before);
    }));
});

describe('a set that answers', () => {
  const refused = new RequestError(-32602, 'Invalid params: no');

  async function up(overrides: Partial<Session>) {
    const { session } = heldSession();
    const events: ConversationEvent[] = [];
    const conversation = new Conversation(
      () => Promise.resolve({ ...session, ...overrides } as Session),
      (event) => events.push(event),
    );

    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));

    return { conversation, events };
  }

  test('a refused mode rejects, with the events it always had', async () => {
    const { conversation, events } = await up({
      setMode: () => Promise.reject(refused),
    });

    await expect(conversation.setMode('plan')).rejects.toBe(refused);

    expect(events).toContainEqual({ type: 'mode_asked', id: 'plan' });
    expect(events).toContainEqual({ type: 'mode_answered', id: 'plan' });
    expect(events).toContainEqual(
      expect.objectContaining({
        type: 'failed',
        message: 'Could not switch to plan mode: Invalid params: no',
      }),
    );

    await conversation.close();
  });

  test('a refused model rejects, with the event it always had', async () => {
    const { conversation, events } = await up({
      setModel: () => Promise.reject(refused),
    });

    await expect(conversation.setModel('big')).rejects.toBe(refused);

    expect(events).toContainEqual(
      expect.objectContaining({
        type: 'failed',
        message: 'Could not switch to big: Invalid params: no',
      }),
    );

    await conversation.close();
  });

  test('a refused option rejects, with the note it always had', async () => {
    const { conversation, events } = await up({
      setOption: () => Promise.reject(refused),
    });

    await expect(conversation.setOption('effort', 'high')).rejects.toBe(
      refused,
    );

    expect(events).toContainEqual(
      expect.objectContaining({
        type: 'noted',
        failed: true,
        text: 'Could not set Effort to High: Invalid params: no',
      }),
    );

    await conversation.close();
  });

  test('an answered set resolves, after what it reports', async () => {
    const { conversation, events } = await up({
      setMode: () => Promise.resolve(),
      setModel: () => Promise.resolve(),
    });

    await conversation.setMode('plan');
    await conversation.setModel('big');
    await conversation.setOption('effort', 'high');

    expect(events).toContainEqual({ type: 'mode_answered', id: 'plan' });
    expect(events).toContainEqual(
      expect.objectContaining({ type: 'noted', failed: false }),
    );

    await conversation.close();
  });

  test('a refusal does not stop the queue behind it', async () => {
    let asks = 0;
    const { conversation } = await up({
      setMode: () => {
        asks += 1;

        return asks === 1 ? Promise.reject(refused) : Promise.resolve();
      },
    });
    const first = conversation.setMode('plan');
    const second = conversation.setMode('default');

    await expect(first).rejects.toBe(refused);
    await second;

    expect(asks).toBe(2);

    await conversation.close();
  });

  test('before the session is up, each rejects, and may be ignored', async () => {
    const conversation = new Conversation(
      () => new Promise<Session>(() => {}),
      () => {},
    );

    await expect(conversation.setMode('plan')).rejects.toThrow('not up');
    await expect(conversation.setModel('big')).rejects.toThrow('not up');
    await expect(conversation.setOption('a', 'b')).rejects.toThrow('not up');

    void conversation.setMode('plan');
  });

  test('a refusal nobody awaits is no unhandled rejection', async () => {
    const unhandled: unknown[] = [];
    const heard = (reason: unknown) => unhandled.push(reason);

    process.on('unhandledRejection', heard);

    try {
      const { conversation } = await up({
        setMode: () => Promise.reject(refused),
      });

      void conversation.setMode('plan');

      await conversation.setOption('effort', 'low');
      await new Promise((resolve) => setTimeout(resolve, 0));
      await conversation.close();

      expect(unhandled).toEqual([]);
    } finally {
      process.off('unhandledRejection', heard);
    }
  });
});

describe('CHD-574 tester: cancellation keeps other work independent', () => {
  test('repeated queued cancellation withdraws once and leaves the next prompt', () =>
    onFake([], async (conversation, events) => {
      conversation.send('permission', 'permission', [], [], { turnId: 'a' });

      await until(() => asked(events));

      conversation.send('never sent', 'never sent', [], [], { turnId: 'b' });
      conversation.send('text', 'text', [], [], { turnId: 'c' });
      conversation.cancelPrompt('b');
      conversation.cancelPrompt('b');
      conversation.cancelPrompt('unknown');

      expect(withdrawn(events)).toEqual([['b']]);
      expect(resultOf(events, 'a')).toBeUndefined();

      conversation.cancelPrompt('a');

      await until(() => resultOf(events, 'c') !== undefined);

      expect(promptsIn(events).map(([text]) => text)).toEqual([
        'permission',
        'text',
      ]);
      expect(resultOf(events, 'b')).toBeUndefined();
    }));

  test('two sessions using the same turn id cancel and finish independently', () =>
    onFake([], async (first, firstEvents) => {
      await onFake([], async (second, secondEvents) => {
        first.send('permission', 'permission', [], [], { turnId: 'same' });
        second.send('permission', 'permission', [], [], { turnId: 'same' });

        await until(() => asked(firstEvents) && asked(secondEvents));

        first.cancelPrompt('same');

        await until(() => resultOf(firstEvents, 'same') !== undefined);

        expect(resultOf(secondEvents, 'same')).toBeUndefined();
        expect(
          secondEvents.some((event) => event.type === 'permission_settled'),
        ).toBe(false);

        second.cancelPrompt('same');

        await until(() => resultOf(secondEvents, 'same') !== undefined);

        for (const events of [firstEvents, secondEvents]) {
          expect(events.filter((event) => event.type === 'result')).toEqual([
            expect.objectContaining({
              turnId: 'same',
              result: expect.objectContaining({ status: 'cancelled' }),
            }),
          ]);
        }
      });
    }));
});

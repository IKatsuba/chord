import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  NO_TURNS,
  reduceTurns,
  sessionStateOf,
  type TurnInput,
} from '../src/acp/upstream_turns.ts';
import {
  ended,
  onFake,
  promptsIn,
  saidIn,
  until,
} from './session/conversation_fake.ts';

describe('CHD-575 U1 tester: named queue ownership', () => {
  test('a refused middle entry returns between the older and newer entries exactly once', async () => {
    const release = Promise.withResolvers<void>();
    let finished = false;

    try {
      await onFake(
        ['--steering', 'claude'],
        async (conversation, events) => {
          try {
            conversation.send('text');
            await until(() => finished);
            conversation.send('Older.', undefined, [], [], { turnId: 'older' });
            conversation.send('Mine.', undefined, [], [], { turnId: 'mine' });
            conversation.send('Newer.', undefined, [], [], { turnId: 'newer' });
            expect(conversation.steerQueued('mine')).toBe('sent');
            await until(() =>
              events.some(
                (event) =>
                  event.type === 'queued' &&
                  event.turnId === 'mine' &&
                  event.refused,
              ),
            );
            release.resolve();
            await ended(events, 4);
            expect(promptsIn(events)).toEqual([
              ['text', undefined],
              ['Older.', undefined],
              ['Mine.', undefined],
              ['Newer.', undefined],
            ]);
            expect(conversation.steerQueued('mine')).toBe('none');
          } finally {
            release.resolve();
          }
        },
        (session) => {
          const prompt = session.prompt.bind(session);
          let first = true;

          session.prompt = (...args) => {
            const turn = prompt(...args);

            if (!first) {
              return turn;
            }

            first = false;

            return {
              ...turn,
              result: turn.result.then(async (result) => {
                finished = true;

                await release.promise;

                return result;
              }),
            };
          };

          return session;
        },
      );
    } finally {
      release.resolve();
    }
  });

  test('a held named entry and an unknown target never select the older personal entry', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      conversation.send('permissionsteer');
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );
      conversation.send('Older.', undefined, [], [], { turnId: 'older' });
      conversation.send('Mine.', undefined, [], [], { turnId: 'mine' });
      expect(conversation.steerQueued('mine')).toBe('sent');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'queued' &&
            event.turnId === 'mine' &&
            event.afterAnswer,
        ),
      );

      const before = events.length;

      expect(conversation.steerQueued('mine')).toBe('none');
      expect(conversation.steerQueued('unknown')).toBe('none');
      expect(events).toHaveLength(before);

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      conversation.choose(asked.permission.id, 'allow');
      await ended(events, 2);
      expect(promptsIn(events).map(([text]) => text)).toEqual([
        'permissionsteer',
        'Mine.',
        'Older.',
      ]);
    }));

  test('matching turn ids in simultaneous sessions steer only their own session', () =>
    onFake(['--steering', 'claude'], async (first, firstEvents) => {
      await onFake(['--steering', 'claude'], async (second, secondEvents) => {
        first.send('slow');
        second.send('slow');
        await until(
          () =>
            saidIn(firstEvents).startsWith('Working') &&
            saidIn(secondEvents).startsWith('Working'),
        );
        first.send('First only.', undefined, [], [], { turnId: 'same' });
        second.send('Second only.', undefined, [], [], { turnId: 'same' });
        expect(first.steerQueued('same')).toBe('sent');
        await until(() => promptsIn(firstEvents).length === 2);
        expect(promptsIn(secondEvents)).toEqual([['slow', undefined]]);
        expect(second.steerQueued('same')).toBe('sent');
        await until(() => promptsIn(secondEvents).length === 2);
        expect(promptsIn(firstEvents).map(([text]) => text)).toEqual([
          'slow',
          'First only.',
        ]);
        expect(promptsIn(secondEvents).map(([text]) => text)).toEqual([
          'slow',
          'Second only.',
        ]);
        first.interrupt();
        second.interrupt();
        await ended(firstEvents, 1);
        await ended(secondEvents, 1);
      });
    }));
});

describe('CHD-575 U2 tester: independent steered turn lifetimes', () => {
  test('consuming one steered id leaves another queued id client-owned without echo', () => {
    const first = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'first' });
    const both = reduceTurns(first.turns, {
      type: 'steered',
      turnId: 'second',
    });
    const played = reduceTurns(both.turns, {
      type: 'prompt',
      turnId: 'first',
      text: 'First words.',
      into: 'running',
    });

    expect(played.sends).toEqual([]);
    expect(played.turns.steered).toEqual(new Set(['second']));
    expect(both.turns.steered).toEqual(new Set(['first', 'second']));

    const next = reduceTurns(played.turns, {
      type: 'prompt',
      turnId: 'second',
      text: 'Second words.',
    });

    expect(next.sends).toEqual([]);
    expect(next.turns.steered).toBeUndefined();
    expect(sessionStateOf(next.turns, false)).toEqual({
      state: 'running',
      origin: 'client',
    });
  });

  test('disconnect preserves a queued steered id until it plays without echo', () => {
    const marked = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'mine' });
    const gone = reduceTurns(marked.turns, { type: 'disconnected' });

    expect(gone.sends).toEqual([]);
    expect(sessionStateOf(gone.turns, true)).toEqual({
      state: 'requires_action',
    });

    const played = reduceTurns(gone.turns, {
      type: 'prompt',
      turnId: 'mine',
      text: 'Queued words.',
    });

    expect(played.sends).toEqual([]);
    expect(sessionStateOf(played.turns, true)).toEqual({
      state: 'requires_action',
      origin: 'client',
    });
    expect(played.turns.steered).toBeUndefined();
  });

  test('a late result of a steered turn preserves a newer agent-originated turn', () => {
    const marked = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'old' });
    const running = reduceTurns(marked.turns, {
      type: 'cycle_started',
      turnId: 'new',
    });
    const late = reduceTurns(running.turns, {
      type: 'result',
      turnId: 'old',
      result: { status: 'cancelled', stopReason: 'cancelled' },
    });

    expect(late.sends).toEqual([]);
    expect(late.turns.steered).toBeUndefined();
    expect(late.turns.running).toEqual({ turnId: 'new', origin: 'agent' });
    expect(sessionStateOf(late.turns, false)).toEqual({
      state: 'running',
      origin: 'agent',
    });
  });

  test.each(['unbind', 'result', 'queue_withdrawn'] as const)(
    '%s removes only the named steered id and leaves other sessions untouched',
    (kind) => {
      const marked = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'a' });
      const both = reduceTurns(marked.turns, {
        type: 'steered',
        turnId: 'b',
      });
      const input: TurnInput =
        kind === 'queue_withdrawn'
          ? { type: kind, turnIds: ['a'] }
          : kind === 'result'
            ? {
                type: kind,
                turnId: 'a',
                result: { status: 'completed', stopReason: 'end_turn' },
              }
            : { type: kind, turnId: 'a' };
      const cleaned = reduceTurns(both.turns, input);

      expect(cleaned.sends).toEqual([]);
      expect(cleaned.turns.steered).toEqual(new Set(['b']));
      expect(marked.turns.steered).toEqual(new Set(['a']));
      expect(NO_TURNS.steered).toBeUndefined();
    },
  );

  test('closing clears pending steers without adding request answers', () => {
    const marked = reduceTurns(NO_TURNS, { type: 'steered', turnId: 'mine' });
    const bound = reduceTurns(marked.turns, {
      type: 'bind',
      requestId: 'request',
      turnId: 'ordinary',
    });
    const closed = reduceTurns(bound.turns, { type: 'closing' });

    expect(closed.turns).toEqual(NO_TURNS);
    expect(closed.sends).toEqual([{ type: 'cancelled', requestId: 'request' }]);
    expect(marked.turns.steered).toEqual(new Set(['mine']));
  });
});

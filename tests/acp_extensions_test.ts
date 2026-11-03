import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
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

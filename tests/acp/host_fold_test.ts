import { describe, expect, test } from 'bun:test';
import { foldEvent, NO_FOLD } from '../../src/acp/host_fold.ts';
import { busyOf } from '../../src/session/busy.ts';
import type { ConversationEvent } from '../../src/session/conversation.ts';

const prompt: ConversationEvent = {
  type: 'prompt',
  turnId: 't1',
  text: 'hello',
  at: 1,
};

describe('a session folded for the host', () => {
  test('nothing heard yet is idle, so a drop interrupts nothing', () => {
    expect(busyOf(NO_FOLD)).toBeUndefined();
  });

  test('its turn is seen as soon as its event is heard', () => {
    expect(busyOf(foldEvent(undefined, prompt))).toEqual({ kind: 'working' });
  });

  test('an event that is no action of the reducer leaves it as it is', () => {
    const fold = foldEvent(undefined, prompt);

    expect(foldEvent(fold, { type: 'connected', sessionId: 's' })).toBe(fold);
    expect(foldEvent(fold, { type: 'closing' })).toBe(fold);
  });

  test('a clear starts it again', () => {
    expect(foldEvent(foldEvent(undefined, prompt), { type: 'cleared' })).toBe(
      NO_FOLD,
    );
  });

  test('a left_open past is there for the host to read', () => {
    const agents = [{ name: 'parser', runtime: 'fake' }];
    const { transcript } = foldEvent(undefined, {
      type: 'left_open',
      turnId: 'history-left',
      agents,
    });

    expect(transcript.entries).toEqual([
      expect.objectContaining({ kind: 'left_open', agents }),
    ]);
  });
});

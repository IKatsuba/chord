import { expect, test } from 'bun:test';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { cycleMark } from '../../src/session/cycles.ts';

const usage = (meta?: Record<string, unknown>) =>
  ({
    sessionUpdate: 'usage_update',
    used: 1,
    size: 2,
    ...(meta === undefined ? {} : { _meta: meta }),
  }) as SessionUpdate;

test("Claude's cycle ends on a usage update of an autonomous origin, and no other", () => {
  for (const kind of [
    'task-notification',
    'peer',
    'coordinator',
    'observer',
    'observer-activity',
  ]) {
    expect(cycleMark(usage({ '_claude/origin': { kind } }))).toBe('end');
  }

  // The person's own turn, a continuation of it, and what Claude Code
  // could not attribute all take the person's lane, as the adapter does.
  for (const kind of [
    'human',
    'channel',
    'auto-continuation',
    'unclassified',
  ]) {
    expect(cycleMark(usage({ '_claude/origin': { kind } }))).toBe(undefined);
  }

  expect(cycleMark(usage())).toBe(undefined);
  expect(cycleMark(usage({ '_claude/origin': 'task-notification' }))).toBe(
    undefined,
  );
});

test("codebuddy's unasked turn starts on its marker and ends on session_end", () => {
  expect(
    cycleMark({
      sessionUpdate: 'session_info_update',
      _meta: {
        'codebuddy.ai/unsolicitedTurn': {
          requestId: 'r',
          reason: 'background_drain',
        },
      },
    } as SessionUpdate),
  ).toBe('start');
  expect(
    cycleMark({ sessionUpdate: 'session_info_update' } as SessionUpdate),
  ).toBe(undefined);
  expect(
    cycleMark({ sessionUpdate: 'session_end' } as unknown as SessionUpdate),
  ).toBe('end');
  expect(
    cycleMark({
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: 'hi' },
    }),
  ).toBe(undefined);
});

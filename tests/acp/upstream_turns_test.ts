import { describe, expect, test } from 'bun:test';
import type { JsonRpcId } from '@agentclientprotocol/sdk/unstable';
import {
  NO_TURNS,
  reduceTurns,
  turnOf,
  type TurnInput,
  type Turns,
  type TurnSend,
} from '../../src/acp/upstream_turns.ts';
import type { TurnResult } from '../../src/session/transcript/types.ts';

const DONE: TurnResult = { status: 'completed', stopReason: 'end_turn' };
const FAILED: TurnResult = { status: 'failed', error: { message: 'gone' } };
const LEAD = { name: 'lead', reachable: true } as const;

/** Plays inputs from nothing; what was sent, and where it left the table. */
function play(...inputs: readonly TurnInput[]): {
  turns: Turns;
  sends: TurnSend[];
} {
  let turns = NO_TURNS;
  const sends: TurnSend[] = [];

  for (const input of inputs) {
    const step = reduceTurns(turns, input);

    turns = step.turns;

    sends.push(...step.sends);
  }

  return { turns, sends };
}

const bind = (requestId: JsonRpcId, turnId: string): TurnInput => ({
  type: 'bind',
  requestId,
  turnId,
});
const prompt = (turnId: string, text = turnId): TurnInput => ({
  type: 'prompt',
  turnId,
  text,
});
const message = (turnId: string, text = turnId): TurnInput => ({
  type: 'prompt',
  turnId,
  text,
  from: LEAD,
});
const result = (turnId: string, ended: TurnResult = DONE): TurnInput => ({
  type: 'result',
  turnId,
  result: ended,
});
const answer = (requestId: JsonRpcId, ended: TurnResult = DONE): TurnSend => ({
  type: 'answer',
  requestId,
  result: ended,
});

describe('the table, row by row', () => {
  test("a bound prompt runs as the client's and says nothing", () => {
    const { turns, sends } = play(bind(1, 'a'), prompt('a'));

    expect(turns.running).toEqual({ turnId: 'a', origin: 'client' });
    expect(sends).toEqual([]);
  });

  test('an unbound prompt runs as a message, and the client is told', () => {
    const { turns, sends } = play(message('m', 'report'));

    expect(turns.running).toEqual({ turnId: 'm', origin: 'message' });
    expect(sends).toEqual([{ type: 'message', text: 'report', from: LEAD }]);
  });

  test('a steered message changes nothing and gets no result', () => {
    const { turns, sends } = play(bind(1, 'a'), prompt('a'), {
      type: 'prompt',
      turnId: 's',
      text: 'also',
      from: LEAD,
      into: 'a',
    });

    expect(turns.running).toEqual({ turnId: 'a', origin: 'client' });
    expect(sends).toEqual([{ type: 'message', text: 'also', from: LEAD }]);
  });

  test('a prompt while a cycle runs replaces it', () => {
    const { turns } = play(
      { type: 'cycle_started', turnId: 'c' },
      bind(1, 'a'),
      prompt('a'),
    );

    expect(turns.running).toEqual({ turnId: 'a', origin: 'client' });
  });

  test('a message while a cycle runs replaces it too, and is told', () => {
    const { turns, sends } = play(
      { type: 'cycle_started', turnId: 'c' },
      message('m', 'hi'),
    );

    expect(turns.running).toEqual({ turnId: 'm', origin: 'message' });
    expect(sends).toEqual([{ type: 'message', text: 'hi', from: LEAD }]);
  });

  test('a bound result answers once, with what it ended with', () => {
    const { turns, sends } = play(bind(1, 'a'), prompt('a'), result('a'));

    expect(turns.running).toBeUndefined();
    expect(turnOf(turns, 1)).toBeUndefined();
    expect(sends).toEqual([answer(1)]);
  });

  test("a failed result is that prompt's error", () => {
    const { sends } = play(bind(1, 'a'), prompt('a'), result('a', FAILED));

    expect(sends).toEqual([answer(1, FAILED)]);
  });

  test('an unbound result answers nothing', () => {
    const { turns, sends } = play(message('m'), result('m'));

    expect(turns.running).toBeUndefined();
    expect(sends.filter((send) => send.type === 'answer')).toEqual([]);
  });

  test('a result of another turn leaves the running one', () => {
    const { turns } = play(bind(1, 'a'), prompt('a'), result('old'));

    expect(turns.running).toEqual({ turnId: 'a', origin: 'client' });
  });

  test('queue_withdrawn answers each bound cancelled, and skips the rest', () => {
    const { turns, sends } = play(bind(1, 'a'), bind(2, 'b'), {
      type: 'queue_withdrawn',
      turnIds: ['a', 'b', 'stranger'],
    });

    expect(sends).toEqual([
      { type: 'cancelled', requestId: 1 },
      { type: 'cancelled', requestId: 2 },
    ]);
    expect(turns.bound.size).toBe(0);
  });

  test("queue_withdrawn with no ids, as the window's, answers nothing", () => {
    const { turns, sends } = play(bind(1, 'a'), { type: 'queue_withdrawn' });

    expect(sends).toEqual([]);
    expect(turnOf(turns, 1)).toBe('a');
  });

  test("a cycle runs as the agent's", () => {
    expect(play({ type: 'cycle_started', turnId: 'c' }).turns.running).toEqual({
      turnId: 'c',
      origin: 'agent',
    });
  });

  test("a turn the agent took for a steer runs as its, until the message's prompt", () => {
    const started = play({ type: 'self_started', turnId: 'own' });

    expect(started.turns.running).toEqual({ turnId: 'own', origin: 'agent' });
    expect(reduceTurns(started.turns, message('m')).turns.running).toEqual({
      turnId: 'm',
      origin: 'message',
    });
  });

  test('disconnected: the running bound stays for its result, queued answer gone', () => {
    const { turns, sends } = play(bind(1, 'a'), prompt('a'), bind(2, 'b'), {
      type: 'disconnected',
    });

    expect(turns.running).toBeUndefined();
    expect(turnOf(turns, 1)).toBe('a');
    expect(sends).toEqual([
      { type: 'session_gone', requestId: 2, turnId: 'b' },
    ]);
    expect(reduceTurns(turns, result('a', FAILED)).sends).toEqual([
      answer(1, FAILED),
    ]);
  });

  test('a second disconnect does not take the running one for queued', () => {
    const { turns, sends } = play(
      bind(1, 'a'),
      prompt('a'),
      { type: 'disconnected' },
      { type: 'disconnected' },
    );

    expect(sends).toEqual([]);
    expect(turnOf(turns, 1)).toBe('a');
  });

  test('closing answers every binding cancelled and empties the table', () => {
    const { turns, sends } = play(bind(1, 'a'), prompt('a'), bind(2, 'b'), {
      type: 'closing',
    });

    expect(sends).toEqual([
      { type: 'cancelled', requestId: 1 },
      { type: 'cancelled', requestId: 2 },
    ]);
    expect(turns).toEqual(NO_TURNS);
  });

  test('unbind: a send refused leaves nothing to answer', () => {
    const { turns, sends } = play(bind(1, 'a'), {
      type: 'unbind',
      turnId: 'a',
    });

    expect(turnOf(turns, 1)).toBeUndefined();
    expect(sends).toEqual([]);
  });
});

describe('interleavings', () => {
  test("a monitor's turn with A and B queued, A cancelled: each answers its own", () => {
    const { sends, turns } = play(
      message('monitor', 'event'),
      bind('A', 'a'),
      bind('B', 'b'),
      { type: 'queue_withdrawn', turnIds: ['a'] },
      result('monitor'),
      prompt('b'),
      result('b'),
    );

    expect(sends).toEqual([
      { type: 'message', text: 'event', from: LEAD },
      { type: 'cancelled', requestId: 'A' },
      answer('B'),
    ]);
    expect(turns.bound.size).toBe(0);
  });

  test("A and B queued behind a monitor, the monitor's result answers neither", () => {
    const { turns, sends } = play(
      message('monitor'),
      bind('A', 'a'),
      bind('B', 'b'),
      result('monitor'),
    );

    expect(sends.filter((send) => send.type === 'answer')).toEqual([]);
    expect(turnOf(turns, 'A')).toBe('a');
    expect(turnOf(turns, 'B')).toBe('b');
  });

  test('prompts bound out of order answer by their turn, not by arrival', () => {
    const { sends } = play(
      bind('first', 'a'),
      bind('second', 'b'),
      prompt('b'),
      result('b'),
      prompt('a'),
      result('a'),
    );

    expect(sends).toEqual([answer('second'), answer('first')]);
  });

  test('a cycle ends with its own result, with a prompt queued behind it', () => {
    const { turns, sends } = play(
      { type: 'cycle_started', turnId: 'c' },
      bind(1, 'a'),
      result('c'),
    );

    expect(sends).toEqual([]);
    expect(turns.running).toBeUndefined();
    expect(turnOf(turns, 1)).toBe('a');
  });

  test("a steered message in a client's turn leaves its answer alone", () => {
    const { sends } = play(
      bind(1, 'a'),
      prompt('a'),
      { type: 'prompt', turnId: 's', text: 'also', from: LEAD, into: 'a' },
      result('a'),
    );

    expect(sends).toEqual([
      { type: 'message', text: 'also', from: LEAD },
      answer(1),
    ]);
  });

  test('a session/cancel: queued withdrawn, the running answered on its result', () => {
    const { sends } = play(
      bind(1, 'a'),
      prompt('a'),
      bind(2, 'b'),
      { type: 'queue_withdrawn', turnIds: ['b'] },
      result('a', { status: 'cancelled', stopReason: 'cancelled' }),
    );

    expect(sends).toEqual([
      { type: 'cancelled', requestId: 2 },
      answer(1, { status: 'cancelled', stopReason: 'cancelled' }),
    ]);
  });

  test('an answered request is out of the table: a late cancel finds no turn', () => {
    const { turns } = play(bind(1, 'a'), prompt('a'), result('a'));

    expect(turnOf(turns, 1)).toBeUndefined();
  });

  test('closing after a result does not answer twice', () => {
    const { sends } = play(bind(1, 'a'), prompt('a'), result('a'), {
      type: 'closing',
    });

    expect(sends).toEqual([answer(1)]);
  });

  test('a result after closing answers nothing more', () => {
    const { sends } = play(
      bind(1, 'a'),
      prompt('a'),
      { type: 'closing' },
      result('a'),
    );

    expect(sends).toEqual([{ type: 'cancelled', requestId: 1 }]);
  });

  test('a result after a withdrawal answers nothing more', () => {
    const { sends } = play(
      bind(1, 'a'),
      { type: 'queue_withdrawn', turnIds: ['a'] },
      result('a'),
    );

    expect(sends).toEqual([{ type: 'cancelled', requestId: 1 }]);
  });

  test('the same request id over string and number stays apart', () => {
    const { turns } = play(bind(1, 'a'), bind('1', 'b'));

    expect(turnOf(turns, 1)).toBe('a');
    expect(turnOf(turns, '1')).toBe('b');
  });
});

describe('CHD-574 tester: late results and independent tables', () => {
  test('a lost turn answers without clearing a newer running turn', () => {
    const { turns, sends } = play(
      bind('old request', 'old'),
      prompt('old'),
      { type: 'disconnected' },
      bind('new request', 'new'),
      prompt('new'),
      result('old', FAILED),
      result('old', FAILED),
    );

    expect(sends).toEqual([answer('old request', FAILED)]);
    expect(turns.running).toEqual({ turnId: 'new', origin: 'client' });
    expect(turnOf(turns, 'new request')).toBe('new');
    expect(reduceTurns(turns, result('new')).sends).toEqual([
      answer('new request'),
    ]);
  });

  test('closing one table never removes equal ids in another session', () => {
    const first = play(bind(1, 'same'), prompt('same')).turns;
    const second = play(bind(1, 'same'), prompt('same')).turns;

    expect(reduceTurns(first, { type: 'closing' }).sends).toEqual([
      { type: 'cancelled', requestId: 1 },
    ]);
    expect(turnOf(second, 1)).toBe('same');
    expect(reduceTurns(second, result('same')).sends).toEqual([answer(1)]);
    expect(NO_TURNS.bound.size).toBe(0);
  });
});

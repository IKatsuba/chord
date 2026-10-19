import { expect, test } from 'bun:test';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { FILLED } from '../../src/session/enrich.ts';
import { turnCost } from '../../src/session/prices.ts';
import {
  costOfTurn,
  costReading,
  type CostReading,
  lastReading,
  type OpeningCosts,
  TurnCosts,
} from '../../src/session/turn_costs.ts';

const usd = (amount: number, estimated = false): CostReading => ({
  amount,
  currency: 'USD',
  estimated,
});

const opening = (more: Partial<OpeningCosts> = {}): OpeningCosts => ({
  counts: undefined,
  resumed: false,
  ...more,
});

const TOKENS = { inputTokens: 1000, outputTokens: 200 };

test("a usage_update's cost is read with whether chord filled it in, and a session's last such is its cost so far", () => {
  const agent: SessionUpdate = {
    sessionUpdate: 'usage_update',
    used: 1,
    size: 2,
    cost: { amount: 0.5, currency: 'USD' },
  };
  const chord: SessionUpdate = {
    ...agent,
    cost: { amount: 0.25, currency: 'USD' },
    _meta: { [FILLED]: ['cost'] },
  };

  expect(costReading(agent)).toStrictEqual(usd(0.5));
  expect(costReading(chord)).toStrictEqual(usd(0.25, true));
  expect(costReading({ sessionUpdate: 'usage_update', used: 1, size: 2 })).toBe(
    undefined,
  );
  expect(
    lastReading([
      agent,
      { sessionUpdate: 'usage_update', used: 3, size: 4 },
      {
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text: 'x' },
      },
    ]),
  ).toStrictEqual(usd(0.5));
  expect(lastReading([])).toBe(undefined);
});

test('a cost that does not read as one, as an agent or a record may bend it, is none', () => {
  const bent = (cost: unknown): SessionUpdate =>
    ({
      sessionUpdate: 'usage_update',
      used: 1,
      size: 2,
      cost,
    }) as SessionUpdate;

  expect(
    [
      { amount: -1, currency: 'USD' },
      { amount: Number.NaN, currency: 'USD' },
      { amount: Number.POSITIVE_INFINITY, currency: 'USD' },
      { amount: 1, currency: '' },
      { amount: '1', currency: 'USD' },
      null,
    ].map((cost) => costReading(bent(cost))),
  ).toStrictEqual([
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
  ]);
});

test("within an opening a turn's cost is what the session's cost moved by in it, chord's estimate marked", () => {
  const cost = (seen: CostReading, before: CostReading) =>
    costOfTurn(opening({ seen }), before, TOKENS, 'm');

  expect(cost(usd(0.0375), usd(0.025))).toStrictEqual({
    cost: { amount: expect.closeTo(0.0125, 9), currency: 'USD' },
  });
  expect(cost(usd(0.3, true), usd(0.1, true))).toStrictEqual({
    cost: { amount: expect.closeTo(0.2, 9), currency: 'USD' },
    estimated: true,
  });
  // Another currency is not taken from.
  expect(
    costOfTurn(
      opening({ seen: { amount: 3, currency: 'EUR', estimated: false } }),
      usd(1),
      TOKENS,
      'm',
    ),
  ).toStrictEqual({});
});

test('a turn the cost did not move in has none', () => {
  const seen = usd(0.5);

  expect(costOfTurn(opening({ seen }), seen, TOKENS, 'm')).toStrictEqual({});
  expect(costOfTurn(opening(), undefined, TOKENS, 'm')).toStrictEqual({});
  // One that came in the turn and did not move says the turn cost nothing.
  expect(
    costOfTurn(opening({ seen: usd(0.5) }), seen, TOKENS, 'm'),
  ).toStrictEqual({ cost: { amount: 0, currency: 'USD' } });
});

test("a cost sent as the session opened is the opening's start, not a turn's", () => {
  const atLoad = usd(0.4);

  expect(
    costOfTurn(
      opening({ resumed: true, seen: usd(0.45) }),
      atLoad,
      TOKENS,
      'm',
    ),
  ).toStrictEqual({
    cost: { amount: expect.closeTo(0.05, 9), currency: 'USD' },
  });
});

test("an opening's first cost is the turn's for a new session and for an agent that counts from each opening", () => {
  const seen = usd(0.0125);

  expect(costOfTurn(opening({ seen }), undefined, TOKENS, 'm')).toStrictEqual({
    cost: { amount: 0.0125, currency: 'USD' },
  });
  expect(
    costOfTurn(
      opening({ counts: 'opening', resumed: true, past: usd(0.4), seen }),
      undefined,
      TOKENS,
      'm',
    ),
  ).toStrictEqual({ cost: { amount: 0.0125, currency: 'USD' } });
});

test("after a resume, an agent that counts from the session's start has its first cost less the record's", () => {
  expect(
    costOfTurn(
      opening({
        counts: 'session',
        resumed: true,
        past: usd(0.025),
        seen: usd(0.0375),
      }),
      undefined,
      TOKENS,
      'm',
    ),
  ).toStrictEqual({
    cost: { amount: expect.closeTo(0.0125, 9), currency: 'USD' },
  });
  // A record with no cost of the agent's had it at nothing.
  expect(
    costOfTurn(
      opening({ counts: 'session', resumed: true, seen: usd(0.0375) }),
      undefined,
      TOKENS,
      'm',
    ),
  ).toStrictEqual({ cost: { amount: 0.0375, currency: 'USD' } });
});

test("chord's estimate after a resume goes on from the record's, so the first turn's is what it added", () => {
  expect(
    costOfTurn(
      opening({ resumed: true, past: usd(0.1, true), seen: usd(0.13, true) }),
      undefined,
      TOKENS,
      'm',
    ),
  ).toStrictEqual({
    cost: { amount: expect.closeTo(0.03, 9), currency: 'USD' },
    estimated: true,
  });
});

test("after a resume, an agent whose counting is not known has its first turn priced from its tokens, and with none it is not counted (the owner's Q61)", () => {
  const unknown = opening({ resumed: true, past: usd(0.2), seen: usd(0.25) });
  const model = 'gpt-5.3-codex';
  const priced = turnCost(model, TOKENS);

  expect(priced).toBeNumber();
  expect(costOfTurn(unknown, undefined, TOKENS, model)).toStrictEqual({
    cost: { amount: priced!, currency: 'USD' },
    estimated: true,
  });
  expect(costOfTurn(unknown, undefined, undefined, model)).toStrictEqual({
    uncounted: true,
  });
  // A model chord has no price for cannot price it either.
  expect(costOfTurn(unknown, undefined, TOKENS, 'fake-large')).toStrictEqual({
    uncounted: true,
  });
  // From the second turn on, the difference holds.
  expect(costOfTurn(unknown, usd(0.2), TOKENS, model)).toStrictEqual({
    cost: { amount: expect.closeTo(0.05, 9), currency: 'USD' },
  });
});

const update = (amount?: number): SessionUpdate => ({
  sessionUpdate: 'usage_update',
  used: 1,
  size: 2,
  ...(amount === undefined ? {} : { cost: { amount, currency: 'USD' } }),
});

test("a turn's figures as it ends: its tokens, its own cost and the model it ended on", () => {
  const costs = new TurnCosts('opening', false, []);

  costs.began('t1');
  expect(costs.heard('t1', update(0.01))).toBe(undefined);
  expect(costs.ended('t1', { totalTokens: 5 }, 'm')).toStrictEqual({
    turnId: 't1',
    usage: { totalTokens: 5 },
    model: 'm',
    cost: { amount: 0.01, currency: 'USD' },
  });
  // A turn whose prompt never went has its tokens alone.
  expect(costs.ended('t0', { totalTokens: 1 }, 'm')).toStrictEqual({
    turnId: 't0',
    usage: { totalTokens: 1 },
  });
});

test("a cost that comes after its turn's end is still that turn's, said again; after the next began, the next's", () => {
  const costs = new TurnCosts('opening', false, []);

  costs.began('t1');
  expect(costs.ended('t1', { totalTokens: 5 }, 'm')).toStrictEqual({
    turnId: 't1',
    usage: { totalTokens: 5 },
    model: 'm',
  });
  expect(costs.heard('t1', update(0.01))).toStrictEqual({
    turnId: 't1',
    usage: { totalTokens: 5 },
    model: 'm',
    cost: { amount: 0.01, currency: 'USD' },
  });
  // The same again moves nothing, so says nothing.
  expect(costs.heard('t1', update(0.01))).toBe(undefined);

  // A cancelled turn whose cost comes once the next has begun: the next's.
  costs.began('t2');
  expect(costs.ended('t2', undefined, 'm')).toBe(undefined);
  costs.began('t3');
  expect(costs.heard('t3', update(0.03))).toBe(undefined);
  expect(costs.ended('t3', { totalTokens: 7 }, 'm')).toMatchObject({
    turnId: 't3',
    cost: { amount: expect.closeTo(0.02, 9), currency: 'USD' },
  });
});

test("an agent's own cycle is a turn of its own, by what its usage moved the cost by; one whose usage says no cost has none", () => {
  const costs = new TurnCosts('opening', false, []);

  costs.began('t1');
  costs.heard('t1', update(0.01));
  costs.ended('t1', { totalTokens: 5 }, 'm');
  costs.began('c1');
  costs.heard('c1', update(0.015));
  expect(costs.ended('c1', undefined, 'm')).toStrictEqual({
    turnId: 'c1',
    usage: {},
    model: 'm',
    cost: { amount: expect.closeTo(0.005, 9), currency: 'USD' },
  });
  costs.began('c2');
  costs.heard('c2', update());
  expect(costs.ended('c2', undefined, 'm')).toBe(undefined);
});

test("an opening resumed from a record counts from the record's last cost, as its agent counts", () => {
  const past = [update(0.025)];
  const first = (costs: TurnCosts) => {
    costs.began('t');
    costs.heard('t', update(0.0375));

    return costs.ended('t', { totalTokens: 5 }, 'fake-large');
  };

  expect(first(new TurnCosts('session', true, past))).toMatchObject({
    cost: { amount: expect.closeTo(0.0125, 9) },
  });
  expect(first(new TurnCosts('opening', true, past))).toMatchObject({
    cost: { amount: 0.0375 },
  });
  expect(first(new TurnCosts(undefined, true, past))).toMatchObject({
    uncounted: true,
  });
});

import { expect, test } from 'bun:test';
import { RequestError } from '@agentclientprotocol/sdk';
import {
  agentMessageOf,
  askStarting,
  type StartingAsk,
} from '../../src/session/starting.ts';

/** A mode ask against an agent that lists `ids` and answers with `answer`. */
function mode(
  ids: string[] | undefined,
  answer: () => Promise<void> = () => Promise.resolve(),
): StartingAsk & { asked: number } {
  const ask = {
    value: { id: 'plan', from: 'set by --permission-mode' },
    what: 'in plan mode',
    kind: 'modes',
    listedOnly: true,
    asked: 0,
    offered: () => Promise.resolve(ids?.map((id) => ({ id }))),
    ask: () => {
      ask.asked++;

      return answer();
    },
  };

  return ask;
}

const refuse = () =>
  Promise.reject(new RequestError(-32602, 'Invalid params: not now'));

test("a refusal's details, where an agent puts its reason, come before its message", () => {
  expect(
    agentMessageOf(
      new RequestError(-32603, 'Internal error', {
        details: ' Not in plan. ',
      }),
    ),
  ).toStrictEqual('Not in plan.');
  expect(agentMessageOf(new RequestError(-32603, 'Busy'))).toStrictEqual(
    'Busy',
  );
});

test('a starting value the agent lists and takes says nothing', async () => {
  const ask = mode(['default', 'plan']);

  expect(await askStarting(ask)).toStrictEqual(undefined);
  expect(ask.asked).toStrictEqual(1);
});

test('a starting value the agent does not list is not asked for', async () => {
  const ask = mode(['default', 'acceptEdits']);

  expect(await askStarting(ask)).toStrictEqual(
    'start in plan mode, set by --permission-mode: the agent offers default, acceptEdits',
  );
  expect(ask.asked).toStrictEqual(0);
});

test("a listed value the agent refuses is said in the agent's words", async () => {
  expect(await askStarting(mode(['plan'], refuse))).toStrictEqual(
    'start in plan mode, set by --permission-mode: Invalid params: not now',
  );
});

test('a mode from an agent that lists none is not asked for, and says it lists none', async () => {
  for (const ids of [undefined, []]) {
    const ask = mode(ids);

    expect(await askStarting(ask)).toStrictEqual(
      'start in plan mode, set by --permission-mode: the agent offers no modes',
    );
    expect(ask.asked).toStrictEqual(0);
  }
});

test("a model from an agent that lists none is asked all the same, its refusal in the agent's words", async () => {
  for (const ids of [undefined, []]) {
    const model = mode(ids);

    expect(await askStarting({ ...model, listedOnly: false })).toStrictEqual(
      undefined,
    );
    expect(model.asked).toStrictEqual(1);
    expect(
      await askStarting({ ...mode(ids, refuse), listedOnly: false }),
    ).toStrictEqual(
      'start in plan mode, set by --permission-mode: Invalid params: not now',
    );
  }
});

test('a value set nowhere in particular says no where', async () => {
  expect(
    await askStarting({ ...mode(['default']), value: { id: 'plan' } }),
  ).toStrictEqual('start in plan mode: the agent offers default');
});

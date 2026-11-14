/**
 * A `chord acp` client's initial `configOptions` read back after the session
 * opens (CHD-629, the owner's Q4 b), on a session of the test's own whose
 * options depend on its model.
 */
import { expect, test } from 'bun:test';
import type {
  InitialSessionConfigOption,
  SessionConfigOption,
} from '@agentclientprotocol/sdk/unstable';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import type { Session } from '../../src/session/session.ts';
import { heldSession, until } from './conversation_fake.ts';

/**
 * A session on model `a` or `b` whose `extra` option is offered on `b`
 * alone; every entry sent is kept whole, and `refuse` names an option the
 * agent will not set.
 */
function modelled(model: 'a' | 'b', refuse?: string) {
  const state = { model, extra: 'off' };
  const sent: InitialSessionConfigOption[] = [];
  const select = (
    id: string,
    currentValue: string,
    values: readonly string[],
  ): SessionConfigOption => ({
    id,
    name: id,
    type: 'select',
    currentValue,
    options: values.map((value) => ({ value, name: value })),
  });
  const { session } = heldSession();

  return {
    sent,
    session: {
      ...session,
      configOptions: () => [
        select('model', state.model, ['a', 'b']),
        ...(state.model === 'b'
          ? [select('extra', state.extra, ['off', 'on'])]
          : []),
      ],
      setConfigOption: (entry: InitialSessionConfigOption) => {
        sent.push(entry);

        if (entry.configId === refuse) {
          return Promise.reject(new Error('The agent holds it.'));
        }

        if (entry.configId === 'model') {
          state.model = entry.value as 'a' | 'b';
        } else {
          state.extra = String(entry.value);
        }

        return Promise.resolve();
      },
    } as unknown as Session,
  };
}

async function started(
  session: Session,
  entries: readonly InitialSessionConfigOption[],
) {
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () => Promise.resolve(session),
    (event) => events.push(event),
    Date.now,
    { entries },
  );

  conversation.start();
  await until(() =>
    events.some(
      (event) => event.type === 'connected' || event.type === 'connect_failed',
    ),
  );
  await conversation.close();

  return events;
}

const EXTRA: InitialSessionConfigOption = {
  configId: 'extra',
  value: 'on',
  _meta: { 'example.com/opaque': { kept: true } },
};

test('an option a model entry brings in is set at its own turn, the entry as the client sent it, its _meta too', async () => {
  const { session, sent } = modelled('a');

  await started(session, [{ configId: 'model', value: 'b' }, EXTRA]);

  expect(sent).toStrictEqual([{ configId: 'model', value: 'b' }, EXTRA]);
});

test('an option a model entry takes away is dropped at its turn, and one already current costs nothing', async () => {
  const { session, sent } = modelled('b');

  await started(session, [
    { configId: 'model', value: 'b' },
    { configId: 'model', value: 'a' },
    EXTRA,
  ]);

  expect(sent).toStrictEqual([{ configId: 'model', value: 'a' }]);
});

test("a refused entry fails the start, worded as chord's own refused values are", async () => {
  const { session } = modelled('b', 'extra');
  const events = await started(session, [EXTRA]);

  expect(JSON.stringify(events)).toContain(
    'Could not start with extra on, set by the client: The agent holds it.',
  );
});

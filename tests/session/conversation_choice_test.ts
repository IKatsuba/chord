import { describe, expect, test } from 'bun:test';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import type { Session } from '../../src/session/session.ts';
import { heldSession, onFake, until } from './conversation_fake.ts';

/** The rows a choice wrote, by their order in `events`. */
function notes(events: readonly ConversationEvent[]): string[] {
  return events.flatMap((event) =>
    event.type === 'noted' ? [event.text] : [],
  );
}

/** The calls `session` makes for changes, in order, into `calls`. */
function logged(calls: string[]) {
  return (session: Session): Session => {
    const { setModel, setOption, setMode } = session;

    session.setModel = (id) => (calls.push(`model ${id}`), setModel(id));
    session.setOption = (id, value) => (
      calls.push(`${id} ${value}`),
      setOption(id, value)
    );
    session.setMode = (id) => (calls.push(`mode ${id}`), setMode(id));

    return session;
  };
}

const SMALL = { id: 'fake-small', name: 'Fake Small' };
const effort = (value: string, name: string) => ({
  option: 'effort',
  value,
  name,
});
/** The effort each `options` event among `events` reports, in order. */
const effortsSeen = (events: readonly ConversationEvent[]) =>
  events.flatMap((event) =>
    event.type === 'options'
      ? event.options.flatMap((option) =>
          option.id === 'effort' ? [option.current] : [],
        )
      : [],
  );

/** The effort the last `options` event among `events` reports. */
const effortIn = (events: readonly ConversationEvent[]) =>
  events
    .flatMap((event) => (event.type === 'options' ? [event.options] : []))
    .at(-1)
    ?.find((option) => option.id === 'effort')?.current;

describe('a choice in /model (CHD-626)', () => {
  test('the model, then the moved effort carried by its id, one row from pending to outcome', async () => {
    const calls: string[] = [];

    await onFake(
      ['--model-parameters'],
      async (conversation, events) => {
        const made = conversation.makeChoice(
          { model: SMALL, effort: effort('low', 'Low') },
          'model',
        );

        expect(notes(events)).toEqual(['Switching to Fake Small…']);
        await made;
        expect(calls).toEqual(['model fake-small', 'effort low']);
        expect(notes(events)).toEqual([
          'Switching to Fake Small…',
          'Switched to Fake Small · Low effort',
        ]);

        const rows = events.flatMap((event) =>
          event.type === 'noted' ? [event.turnId] : [],
        );

        expect(new Set(rows).size).toBe(1);
      },
      logged(calls),
    );
  });

  test('a value the new model does not offer is not asked for; the model stays', async () => {
    const calls: string[] = [];

    await onFake(
      ['--model-parameters'],
      async (conversation, events) => {
        await conversation.makeChoice(
          { model: SMALL, effort: effort('max', 'Max') },
          'model',
        );
        expect(calls).toEqual(['model fake-small']);
        expect(notes(events).at(-1)).toBe(
          'Switched to Fake Small; it offers no Max effort, it is on Medium.',
        );
      },
      logged(calls),
    );
  });

  test('an effort asked after a model choice does not overtake it', async () => {
    const calls: string[] = [];

    await onFake(
      ['--model-parameters', '--config-delay', '50'],
      async (conversation) => {
        const model = conversation.makeChoice({ model: SMALL }, 'model');
        const option = conversation.setOption('effort', 'low');

        await Promise.all([model, option]);
        expect(calls).toEqual(['model fake-small', 'effort low']);
      },
      logged(calls),
    );
  });

  test('the model refused: stop with its reason, no effort sent', async () => {
    const calls: string[] = [];

    await onFake(
      ['--model-parameters'],
      async (conversation, events) => {
        await conversation.makeChoice(
          {
            model: { id: 'fake-gone', name: 'Fake Gone' },
            effort: effort('low', 'Low'),
          },
          'model',
        );
        expect(calls).toEqual(['model fake-gone']);
        expect(notes(events).at(-1)).toBe(
          'Could not switch to Fake Gone: Invalid params: model cannot be fake-gone',
        );
      },
      logged(calls),
    );
  });

  for (const [when, effortAfter] of [
    ['before', 'medium'],
    ['after', 'low'],
  ] as const) {
    test(`a set resent ${when} the answer is folded in arrival order`, async () => {
      await onFake(
        ['--model-parameters', '--resend-config', when],
        async (conversation, events) => {
          await conversation.makeChoice({ model: SMALL }, 'model');
          // Both sets were seen; the one that came last holds.
          await until(
            () =>
              effortsSeen(events).includes('low') &&
              effortIn(events) === effortAfter,
          );
          expect(notes(events).at(-1)).toBe('Switched to Fake Small');
        },
      );
    });
  }

  test('a hung effort holds the chain with its row pending; /clear starts a new one', async () => {
    const calls: string[] = [];

    await onFake(
      ['--model-parameters', '--hang', 'effort'],
      async (conversation, events) => {
        const hung = conversation.makeChoice(
          { effort: effort('high', 'High') },
          'effort',
        );
        let moved = false;

        void conversation.setMode('plan').then(() => (moved = true));
        await until(() => calls.includes('effort high'));
        expect(notes(events)).toEqual(['Setting Effort to High…']);
        expect(moved).toBe(false);
        expect(calls).not.toContain('mode plan');

        void hung.catch(() => {});

        await conversation.clear();
        await until(
          () => events.filter((event) => event.type === 'connected').length > 1,
        );
        await conversation.setMode('plan');
        expect(calls.filter((call) => call === 'mode plan')).toEqual([
          'mode plan',
        ]);
      },
      logged(calls),
    );
  });

  test('/clear mid-choice: the old session neither sends the effort nor writes the outcome', async () => {
    const calls: string[] = [];

    await onFake(
      ['--model-parameters', '--config-delay', '200'],
      async (conversation, events) => {
        const made = conversation.makeChoice(
          { model: SMALL, effort: effort('low', 'Low') },
          'model',
        );

        await until(() => calls.includes('model fake-small'));
        await conversation.clear();
        await made;
        expect(calls).toEqual(['model fake-small']);
        expect(notes(events)).toEqual(['Switching to Fake Small…']);
      },
      logged(calls),
    );
  });
});

test('legacy session/set_model answers with no options: the effort step skips with its note', async () => {
  const events: ConversationEvent[] = [];
  const { session } = heldSession();
  const asked: string[] = [];
  const legacy = Object.assign(session, {
    models: () => ({
      available: [
        { id: 'large', name: 'Large' },
        { id: 'small', name: 'Small' },
      ],
      current: 'large',
    }),
    configOptions: () => [],
    setModel: (id: string) => (asked.push(id), Promise.resolve()),
  });
  const conversation = new Conversation(
    () => Promise.resolve(legacy),
    (event) => events.push(event),
  );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));
  await conversation.makeChoice(
    { model: { id: 'small', name: 'Small' }, effort: effort('high', 'High') },
    'model',
  );
  expect(asked).toEqual(['small']);
  expect(notes(events).at(-1)).toBe(
    'Switched to Small; it offers no High effort.',
  );
  await conversation.close();
});

/**
 * Requests that wait on the person between turns, and the prompts, messages
 * and tasks queued behind them (CHD-158).
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import type { PendingElicitation } from '../../src/session/elicitations.ts';
import { type Session } from '../../src/session/session.ts';
import { TaskAgent } from '../../src/session/tasks.ts';
import { initialAppState, reduceApp } from '../../src/ui/app/state.ts';
import {
  until,
  parentUp,
  adoptTask,
  onFake,
  saidIn,
  MAIN,
  steeringStub,
} from './conversation_fake.ts';

describe('CHD-158 tester: requests outside a turn', () => {
  test('before the first prompt, permissions, forms and links wait independently until answered or withdrawn', async () => {
    let owner: Session | undefined;

    await onFake(
      [],
      async (conversation, events) => {
        assert(owner);

        const abort = new AbortController();
        const permission = owner.permissions.handler(
          {
            sessionId: owner.id,
            toolCall: {
              toolCallId: 'startup',
              title: 'Write notes/startup.md',
            },
            options: [{ optionId: 'allow', name: 'Allow', kind: 'allow_once' }],
          },
          abort.signal,
        );
        const form = owner.elicitations.handler(
          {
            sessionId: owner.id,
            mode: 'form',
            message: 'Choose a target',
            requestedSchema: { type: 'object', properties: {} },
          },
          new AbortController().signal,
        );
        const link = owner.elicitations.handler(
          {
            sessionId: owner.id,
            mode: 'url',
            message: 'Approve the target',
            url: 'https://example.com/approve',
            elicitationId: 'startup-link',
          },
          new AbortController().signal,
        );
        const asked = events.find(
          (event) => event.type === 'permission_requested',
        );
        const forms = events.filter(
          (event) => event.type === 'elicitation_requested',
        );

        assert(asked?.type === 'permission_requested');
        expect(asked).toMatchObject({ turnId: 'session', between: true });
        expect(forms).toHaveLength(2);
        expect(forms.every((event) => event.elicitation.between === true)).toBe(
          true,
        );
        expect(events.some((event) => event.type === 'prompt')).toBe(false);
        abort.abort();
        expect(await permission).toStrictEqual({
          outcome: { outcome: 'cancelled' },
        });
        expect(
          events.filter((event) => event.type === 'permission_settled'),
        ).toMatchObject([
          { id: asked.permission.id, answer: { type: 'withdrawn' } },
        ]);
        conversation.answer(forms[1]!.elicitation.id, { action: 'decline' });
        expect(await link).toStrictEqual({ action: 'decline' });
        conversation.answer(forms[0]!.elicitation.id, {
          action: 'accept',
          content: {},
        });
        expect(await form).toStrictEqual({ action: 'accept', content: {} });
        expect(
          events.filter((event) => event.type === 'elicitation_settled'),
        ).toHaveLength(2);
      },
      (session) => (owner = session),
    );
  });

  test('two real fake-agent sessions keep their between-turn answers separate', () =>
    Promise.all(
      ['allow', 'deny'].map((option) =>
        onFake([], async (conversation, events) => {
          conversation.send('mainbetween');
          await until(() =>
            events.some((event) => event.type === 'permission_requested'),
          );

          const asked = events.find(
            (event) => event.type === 'permission_requested',
          );

          assert(asked?.type === 'permission_requested');
          expect(asked.between).toBe(true);
          conversation.choose(asked.permission.id, option);
          await until(() => saidIn(events).includes(`Permission: ${option}.`));
          expect(
            events.filter((event) => event.type === 'permission_settled'),
          ).toHaveLength(1);
          expect(saidIn(events)).not.toContain(
            `Permission: ${option === 'allow' ? 'deny' : 'allow'}.`,
          );
        }),
      ),
    ));

  for (const stage of ['permission', 'form'] as const) {
    test(`closing an unanswered between-turn ${stage} withdraws it and stops the fake`, async () => {
      let owner: Session | undefined;

      await onFake(
        [],
        async (conversation, events) => {
          conversation.send(
            stage === 'permission' ? 'mainbetween' : 'claudebetween',
          );
          await until(() =>
            events.some((event) => event.type === 'permission_requested'),
          );

          if (stage === 'form') {
            const permission = events.find(
              (event) => event.type === 'permission_requested',
            );

            assert(permission?.type === 'permission_requested');
            conversation.choose(permission.permission.id, 'allow');
            await until(() =>
              events.some((event) => event.type === 'elicitation_requested'),
            );
          }

          await conversation.close();
          assert(owner);
          await owner.exited;
          expect(owner.agentPids.size).toBe(0);
          expect(
            events.filter(
              (event) =>
                event.type ===
                `${stage === 'form' ? 'elicitation' : 'permission'}_settled`,
            ),
          ).toMatchObject([{ answer: { type: 'withdrawn' } }]);
        },
        (session) => (owner = session),
      );
    });
  }

  test('clear removes the old wait and a fresh session can answer a prompt', async () => {
    let original: Session | undefined;

    await onFake(
      [],
      async (conversation, events) => {
        conversation.send('mainbetween');
        await until(() =>
          events.some((event) => event.type === 'permission_requested'),
        );
        conversation.clear();
        await until(
          () =>
            events.filter((event) => event.type === 'connected').length === 2,
        );
        assert(original);
        await original.exited;
        expect(original.agentPids.size).toBe(0);
        expect(events.filter((event) => event.type === 'cleared')).toHaveLength(
          1,
        );
        conversation.send('text');
        await until(() =>
          saidIn(events).includes('Hello, world. This reply came in chunks.'),
        );
        expect(saidIn(events)).not.toContain('Permission: allow.');
      },
      (session) => {
        original ??= session;

        return session;
      },
    );
  });
});

describe('a prompt or message while a request waits between turns (CHD-158)', () => {
  test('both wait in the queue for the answer, and the request stays on screen while the agent waits', () =>
    onFake([], async (conversation, events) => {
      conversation.send('mainbetween');
      await until(() => events.some((event) => event.type === 'result'));
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );

      expect(conversation.send('text')).toBeTrue();
      expect(conversation.tell(MAIN, 'Then the docs.')).toStrictEqual('queued');

      const queued = events.filter((event) => event.type === 'queued');

      expect(queued).toMatchObject([
        { text: 'text', afterAnswer: true },
        { text: 'Then the docs.', afterAnswer: true },
      ]);

      // Long enough for a turn the queue let go to have started.
      await new Promise((resolve) => setTimeout(resolve, 300));

      const prompts = () =>
        events.filter((event) => event.type === 'prompt').length;

      expect(prompts()).toStrictEqual(1);

      // What the window draws from the events: the request still waits,
      // between turns, on the person.
      const shown = events.reduce(reduceApp, initialAppState);

      expect(shown.transcript.turn).toMatchObject({
        status: 'awaiting_permission',
        between: true,
      });

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      conversation.choose(asked.permission.id, 'allow');
      await until(() => saidIn(events).includes('Permission: allow.'));
      // Then, in the order they came, each as a turn of its own.
      await until(() => prompts() === 3);
      expect(
        events.flatMap((event) =>
          event.type === 'prompt' ? [event.text] : [],
        ),
      ).toStrictEqual(['mainbetween', 'text', 'Then the docs.']);

      // What the work that asked said of the answer came before the held
      // prompt went, so it is never taken for that prompt's reply.
      const said = events.findIndex(
        (event) =>
          event.type === 'update' &&
          event.update.sessionUpdate === 'agent_message_chunk' &&
          event.update.content.type === 'text' &&
          event.update.content.text.includes('Permission: allow.'),
      );
      const went = events.findIndex(
        (event) => event.type === 'prompt' && event.text === 'text',
      );

      expect(said).toBeGreaterThan(-1);
      expect(said).toBeLessThan(went);
    }));
});

test('a second request between turns, answered during the quiet after the first, has its own quiet before the held prompt goes', () =>
  onFake([], async (conversation, events) => {
    conversation.send('mainbetweentwice');
    await until(() => events.some((event) => event.type === 'result'));

    const asked = () =>
      events.flatMap((event) =>
        event.type === 'permission_requested' ? [event.permission.id] : [],
      );

    await until(() => asked().length === 1);
    conversation.send('text');
    conversation.choose(asked()[0]!, 'allow');
    await until(() => asked().length === 2);

    // The prompt queued says again that it waits, now for the second.
    const marks = events.flatMap((event) =>
      event.type === 'queued' && event.text === 'text'
        ? [event.afterAnswer === true]
        : [],
    );

    expect(marks).toStrictEqual([true, false, true]);
    // Answered most of a second on, within the quiet after the first.
    await new Promise((resolve) => setTimeout(resolve, 800));
    conversation.choose(asked()[1]!, 'allow');
    await until(() =>
      events.some((event) => event.type === 'prompt' && event.text === 'text'),
    );

    const said = events.findIndex(
      (event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'agent_message_chunk' &&
        event.update.content.type === 'text' &&
        event.update.content.text.includes('Second: allow.'),
    );
    const went = events.findIndex(
      (event) => event.type === 'prompt' && event.text === 'text',
    );

    expect(said).toBeGreaterThan(-1);
    expect(said).toBeLessThan(went);
  }));

test("a task's request with no turn of the parent's running holds the parent's queue until it is answered", async () => {
  const { parent, events } = await parentUp();
  const { task, asked } = adoptTask(parent, 'task-a');
  const prompts = () =>
    events.flatMap((event) => (event.type === 'prompt' ? [event.text] : []));

  task.heard({ type: 'connected', sessionId: 'a' });
  task.heard({
    type: 'permission_requested',
    turnId: 'child-turn',
    permission: { id: 'request', options: [] },
  });

  expect(parent.send('text')).toStrictEqual(true);
  expect(parent.tell(MAIN, 'Then the docs.')).toStrictEqual('queued');
  expect(
    events.flatMap((event) =>
      event.type === 'queued' ? [[event.text, event.afterAnswer]] : [],
    ),
  ).toStrictEqual([
    ['text', true],
    ['Then the docs.', true],
  ]);

  // Long enough for a turn the queue let go to have started.
  await new Promise((resolve) => setTimeout(resolve, 300));
  expect(prompts()).toStrictEqual([]);

  parent.choose('request', 'allow');
  expect(asked).toContain('choose request allow');
  task.heard({
    type: 'permission_settled',
    turnId: 'child-turn',
    id: 'request',
    answer: { type: 'chosen', optionId: 'allow' },
  });
  await until(() => prompts().length > 0);
  expect(prompts()[0]).toStrictEqual('text');
  await parent.close();
});

test('with two requests between turns, the queue says it waits and holds until the last is answered', async () => {
  const { parent, events } = await parentUp();
  const a = adoptTask(parent, 'task-a');
  const b = adoptTask(parent, 'task-b');
  const prompts = () =>
    events.flatMap((event) => (event.type === 'prompt' ? [event.text] : []));
  const marks = () =>
    events.flatMap((event) =>
      event.type === 'queued' ? [event.afterAnswer === true] : [],
    );
  const settled = (task: TaskAgent, id: string) =>
    task.heard({
      type: 'permission_settled',
      turnId: 'child-turn',
      id,
      answer: { type: 'chosen', optionId: 'allow' },
    });

  for (const [{ task }, id] of [
    [a, 'request-a'],
    [b, 'request-b'],
  ] as const) {
    task.heard({ type: 'connected', sessionId: id });
    task.heard({
      type: 'permission_requested',
      turnId: 'child-turn',
      permission: { id, options: [] },
    });
  }

  parent.send('text');
  settled(a.task, 'request-a');
  await new Promise((resolve) => setTimeout(resolve, 300));

  // One still waits: the prompt still says so, and has not gone.
  expect(marks()).toStrictEqual([true]);
  expect(prompts()).toStrictEqual([]);

  settled(b.task, 'request-b');
  await until(() => prompts().length > 0);
  expect(marks()).toStrictEqual([true, false]);
  expect(prompts()).toStrictEqual(['text']);
  await parent.close();
});

describe('CHD-158 tester: queued work across between-turn requests', () => {
  for (const mode of ['form', 'url'] as const) {
    test(`${mode}: a new request during quiet restarts a full quiet before the queued prompt`, async () => {
      let owner: Session | undefined;
      let sentAt: number | undefined;

      await onFake(
        [],
        async (conversation, events) => {
          assert(owner);

          const first = owner.permissions.handler(
            {
              sessionId: owner.id,
              toolCall: { toolCallId: 'first', title: 'Write first.md' },
              options: [
                { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
              ],
            },
            new AbortController().signal,
          );
          const permission = events.find(
            (event) => event.type === 'permission_requested',
          );

          assert(permission?.type === 'permission_requested');
          conversation.send('text');
          conversation.choose(permission.permission.id, 'allow');
          await first;

          const response = owner.elicitations.handler(
            mode === 'form'
              ? {
                  sessionId: owner.id,
                  mode: 'form',
                  message: 'Second request',
                  requestedSchema: { type: 'object', properties: {} },
                }
              : {
                  sessionId: owner.id,
                  mode: 'url',
                  message: 'Second request',
                  url: 'https://example.com/approve',
                  elicitationId: 'second',
                },
            new AbortController().signal,
          );
          const input = events.find(
            (event) => event.type === 'elicitation_requested',
          );

          assert(input?.type === 'elicitation_requested');
          expect(
            events
              .filter((event) => event.type === 'queued')
              .map((event) => event.afterAnswer === true),
          ).toStrictEqual([true, false, true]);

          const answeredAt = performance.now();

          conversation.answer(input.elicitation.id, { action: 'decline' });
          expect(await response).toStrictEqual({ action: 'decline' });
          await until(() => sentAt !== undefined);
          assert(sentAt !== undefined);
          expect(sentAt - answeredAt).toBeGreaterThanOrEqual(1000);
          await until(() => saidIn(events).includes('Hello, world.'));
        },
        (session) => {
          owner = session;

          const prompt = session.prompt.bind(session);

          session.prompt = (...args) => {
            sentAt = performance.now();

            return prompt(...args);
          };

          return session;
        },
      );
    });
  }

  test('a form and a link keep prompts and messages held until the last wait settles', async () => {
    let owner: Session | undefined;

    await onFake(
      [],
      async (conversation, events) => {
        assert(owner);

        const form = owner.elicitations.handler(
          {
            sessionId: owner.id,
            mode: 'form',
            message: 'Form',
            requestedSchema: { type: 'object', properties: {} },
          },
          new AbortController().signal,
        );
        const abort = new AbortController();
        const link = owner.elicitations.handler(
          {
            sessionId: owner.id,
            mode: 'url',
            message: 'Link',
            url: 'https://example.com/approve',
            elicitationId: 'link',
          },
          abort.signal,
        );
        const input = events.find(
          (event) => event.type === 'elicitation_requested',
        );

        assert(input?.type === 'elicitation_requested');
        conversation.send('text');
        expect(conversation.tell(MAIN, 'Message after the form.')).toBe(
          'queued',
        );
        conversation.answer(input.elicitation.id, { action: 'decline' });
        await form;
        expect(events.filter((event) => event.type === 'prompt')).toHaveLength(
          0,
        );
        expect(
          events
            .filter((event) => event.type === 'queued')
            .every((event) => event.afterAnswer === true),
        ).toBe(true);
        abort.abort();
        expect(await link).toStrictEqual({ action: 'cancel' });
        await until(
          () => events.filter((event) => event.type === 'prompt').length === 2,
        );
        expect(
          events
            .filter((event) => event.type === 'prompt')
            .map((event) => event.text),
        ).toStrictEqual(['text', 'Message after the form.']);
      },
      (session) => (owner = session),
    );
  });

  test('interrupt restores only the person’s prompt while a held message still waits for the link answer', async () => {
    let owner: Session | undefined;

    await onFake(
      [],
      async (conversation, events) => {
        assert(owner);

        const response = owner.elicitations.handler(
          {
            sessionId: owner.id,
            mode: 'url',
            message: 'Approve',
            url: 'https://example.com/approve',
            elicitationId: 'link',
          },
          new AbortController().signal,
        );
        const input = events.find(
          (event) => event.type === 'elicitation_requested',
        );

        assert(input?.type === 'elicitation_requested');
        conversation.send('My queued prompt.');
        conversation.tell(MAIN, 'Message stays.');
        conversation.interrupt();
        expect(events.some((event) => event.type === 'queue_withdrawn')).toBe(
          true,
        );
        expect(events.filter((event) => event.type === 'prompt')).toHaveLength(
          0,
        );
        expect(
          events
            .filter(
              (event) =>
                event.type === 'queued' && event.text === 'Message stays.',
            )
            .at(-1),
        ).toMatchObject({ afterAnswer: true });
        conversation.answer(input.elicitation.id, { action: 'decline' });
        await response;
        await until(() => events.some((event) => event.type === 'prompt'));
        expect(
          events
            .filter((event) => event.type === 'prompt')
            .map((event) => event.text),
        ).toStrictEqual(['Message stays.']);
      },
      (session) => (owner = session),
    );
  });

  for (const end of ['close', 'clear'] as const) {
    test(`${end} during the final quiet never sends the old queued prompt`, async () => {
      let original: Session | undefined;

      await onFake(
        [],
        async (conversation, events) => {
          conversation.send('mainbetween');
          await until(() =>
            events.some((event) => event.type === 'permission_requested'),
          );

          const permission = events.find(
            (event) => event.type === 'permission_requested',
          );

          assert(permission?.type === 'permission_requested');
          conversation.send('Old queued prompt.');
          conversation.choose(permission.permission.id, 'allow');

          if (end === 'close') {
            await conversation.close();
          } else {
            conversation.clear();
            await until(
              () =>
                events.filter((event) => event.type === 'connected').length ===
                2,
            );
            conversation.send('text');
            await until(() => saidIn(events).includes('Hello, world.'));
          }

          assert(original);
          await original.exited;
          expect(original.agentPids.size).toBe(0);
          expect(
            events
              .filter((event) => event.type === 'prompt')
              .map((event) => event.text),
          ).not.toContain('Old queued prompt.');
        },
        (session) => {
          original ??= session;

          return session;
        },
      );
    });
  }
});

test("a task's permission asked during the parent's turn holds the queue once that turn ends, until it is answered (CHD-158 C4)", async () => {
  const stub = await steeringStub();
  const { conversation, events, prompts } = stub;

  conversation.send('go');
  stub.go();
  await stub.settled();

  const { task } = adoptTask(conversation, 'task-a');

  task.heard({ type: 'connected', sessionId: 'a' });
  task.heard({
    type: 'permission_requested',
    turnId: 'child-turn',
    permission: { id: 'request', options: [] },
  });
  stub.end();
  await until(() => events.some((event) => event.type === 'result'));

  expect(conversation.send('text')).toStrictEqual(true);
  expect(conversation.tell(MAIN, 'Then the docs.')).toStrictEqual('queued');

  const held = () =>
    events.flatMap((event) =>
      event.type === 'queued' ? [[event.text, event.afterAnswer === true]] : [],
    );

  expect(held()).toStrictEqual([
    ['text', true],
    ['Then the docs.', true],
  ]);
  // Long enough for a turn the queue let go to have started.
  await new Promise((resolve) => setTimeout(resolve, 300));
  expect(prompts).toHaveLength(1);

  conversation.choose('request', 'allow');
  task.heard({
    type: 'permission_settled',
    turnId: 'child-turn',
    id: 'request',
    answer: { type: 'chosen', optionId: 'allow' },
  });
  await until(() => prompts.length >= 2);
  expect(prompts[1]).toContain('text');
  await conversation.close();
});

describe('CHD-158 C4 tester: work queued before the parent result', () => {
  for (const release of ['answer', 'withdraw', 'clear', 'close'] as const) {
    test(`${release}: own and task permissions hold already queued work when the fake parent's turn ends`, async () => {
      let owner: Session | undefined;

      await onFake(
        [],
        async (conversation, events) => {
          assert(owner);

          const adopted = adoptTask(conversation, 'task-c4');
          const task = adopted.task;
          let ownId: string | undefined;
          let queuedBeforeResult = false;
          const stop = owner.permissions.subscribe(() => {
            const request = events.find(
              (event) =>
                event.type === 'permission_requested' &&
                event.permission.subagentId === undefined,
            );

            assert(request?.type === 'permission_requested');

            ownId = request.permission.id;

            task.heard({ type: 'connected', sessionId: 'task-session' });
            task.heard({
              type: 'permission_requested',
              turnId: 'task-turn',
              permission: { id: 'task-request', options: [] },
            });
            conversation.send('text');
            conversation.tell(MAIN, 'After the answer.');

            queuedBeforeResult = !events.some(
              (event) => event.type === 'result',
            );
          });

          try {
            conversation.send('leftask');
            await until(() => events.some((event) => event.type === 'result'));
            expect(queuedBeforeResult).toBeTrue();
            expect(
              events.filter((event) => event.type === 'prompt'),
            ).toHaveLength(1);
            expect(
              events.filter((event) => event.type === 'queued').slice(-2),
            ).toMatchObject([
              { text: 'text', afterAnswer: true },
              { text: 'After the answer.', afterAnswer: true },
            ]);
            assert(ownId);

            if (release === 'clear' || release === 'close') {
              if (release === 'clear') {
                conversation.clear();
                await until(() =>
                  events.some((event) => event.type === 'cleared'),
                );
                await until(
                  () =>
                    events.filter((event) => event.type === 'connected')
                      .length === 2,
                );
                conversation.send('tools');
                await until(
                  () =>
                    events.filter((event) => event.type === 'result').length ===
                    2,
                );
              } else {
                await conversation.close();
              }

              expect(adopted.asked).toContain('close');
              expect(
                events
                  .filter((event) => event.type === 'prompt')
                  .map((event) => event.text),
              ).toStrictEqual(
                release === 'clear' ? ['leftask', 'tools'] : ['leftask'],
              );
            } else {
              conversation.choose(ownId, 'allow');
              await until(() => saidIn(events).includes('Permission: allow.'));
              expect(
                events.filter((event) => event.type === 'prompt'),
              ).toHaveLength(1);
              expect(
                events.filter((event) => event.type === 'queued').at(-1),
              ).toMatchObject({ afterAnswer: true });

              if (release === 'answer') {
                conversation.choose('task-request', 'allow');
              }

              task.heard({
                type: 'permission_settled',
                turnId: 'task-turn',
                id: 'task-request',
                answer:
                  release === 'answer'
                    ? { type: 'chosen', optionId: 'allow' }
                    : { type: 'withdrawn' },
              });
              await until(
                () =>
                  events.filter((event) => event.type === 'prompt').length >= 3,
              );

              const sent = events
                .filter((event) => event.type === 'prompt')
                .map((event) => event.text);

              expect(sent).toStrictEqual([
                'leftask',
                'text',
                'After the answer.',
              ]);
            }
          } finally {
            stop();
          }
        },
        (session) => {
          owner = session;

          return session;
        },
      );
    });
  }
});

describe('CHD-158 C5 tester: closing carried inputs in concurrent sessions', () => {
  test('clear and close withdraw each session own form and link without releasing queued text', async () => {
    const bothHeld = Promise.withResolvers<void>();
    let arrived = 0;

    await Promise.all(
      ['clear', 'close'].map((release) => {
        let source: Session | undefined;

        return onFake(
          [],
          async (conversation, events) => {
            assert(source);

            const owner = source;
            let form: PendingElicitation | undefined;
            let link: Promise<unknown> | undefined;
            const stop = owner.elicitations.subscribe((pending) => {
              if (form !== undefined) {
                return;
              }

              form = pending;
              link = owner.elicitations.handler(
                {
                  sessionId: owner.id,
                  mode: 'url',
                  message: release,
                  url: 'https://example.com/release',
                  elicitationId: release,
                },
                new AbortController().signal,
              );
            });

            try {
              conversation.send('leftform');
              await until(() =>
                events.some((event) => event.type === 'result'),
              );
              assert(form);
              expect(form.signal.aborted).toBe(false);
              conversation.send('tools');
              expect(
                events.filter((event) => event.type === 'prompt'),
              ).toHaveLength(1);
              expect(
                events.filter((event) => event.type === 'queued').at(-1),
              ).toMatchObject({ afterAnswer: true });
              arrived++;

              if (arrived === 2) {
                bothHeld.resolve();
              }

              await bothHeld.promise;

              if (release === 'clear') {
                conversation.clear();
                await until(() =>
                  events.some((event) => event.type === 'cleared'),
                );
                await until(
                  () =>
                    events.filter((event) => event.type === 'connected')
                      .length === 2,
                );
              } else {
                await conversation.close();
              }

              expect(form.signal.aborted).toBe(true);
              expect(await link).toMatchObject({ action: 'cancel' });
              expect(
                events
                  .filter((event) => event.type === 'prompt')
                  .map((event) => event.text),
              ).toEqual(['leftform']);
              await owner.exited;
              expect(owner.agentPids.size).toBe(0);
            } finally {
              stop();
            }
          },
          (session) => (source = session),
        );
      }),
    );
  });
});

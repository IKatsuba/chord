/**
 * Messages steered into a turn on Codex's and Claude's adapters, a steer
 * that misses its turn, and a cut-off call told to the agent (CHD-417,
 * CHD-452).
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { setImmediate as settleQueued } from 'node:timers/promises';
import { type SessionUpdate } from '@agentclientprotocol/sdk';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import {
  type Session,
  type SteerOutcome,
} from '../../src/session/session.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type TranscriptAction,
  type TurnResult,
} from '../../src/session/transcript/types.ts';
import { cutNote } from '../../src/session/cut_off.ts';
import {
  CUT_MESSAGE,
  CUT_OPEN,
} from '../fixtures/fake_agent/scenarios/chord_tools.ts';
import {
  heldSession,
  until,
  went,
  isAlive,
  onFake,
  saidIn,
  MAIN,
  steerOrder,
  callOpen,
  promptsIn,
  steeringStub,
  ended,
} from './conversation_fake.ts';

test("on Codex's adapter, whose steer cuts nothing, a message told while the turn's call is open goes into it at once", () =>
  onFake(['--steering', 'codex'], async (conversation, events) => {
    conversation.send('bash');
    await callOpen(events);
    conversation.tell(MAIN, 'Then the docs.');
    await until(() => events.some((event) => event.type === 'result'));

    expect(steerOrder(events)).toStrictEqual([
      'into: Then the docs.',
      'call ended',
      'ended',
    ]);
  }));

test("a steer that meets the turn's end on Claude's adapter is refused, and goes as the next turn", () =>
  onFake(
    ['--steering', 'claude', '--steer-late'],
    async (conversation, events) => {
      conversation.send('text');
      await went();

      let queued = 0;

      expect(
        conversation.tell(MAIN, 'Stop.', () => (queued += 1)),
      ).toStrictEqual('sent');
      await until(
        () => events.filter((event) => event.type === 'result').length === 2,
      );

      expect(promptsIn(events)).toStrictEqual([
        ['text', undefined],
        ['Stop.', undefined],
      ]);
      // It waited after all, which the sender's row is told.
      expect(queued).toStrictEqual(1);
    },
  ));

test("a turn Codex's adapter starts with a steer that missed the turn is cancelled at once, and the message goes as chord's next turn, alone", async () => {
  let cancels = 0;

  await onFake(
    ['--steering', 'codex', '--steer-late'],
    async (conversation, events) => {
      conversation.send('text');
      await went();

      let queued = 0;

      // A scenario's name, so the agent's own turn with it works on long
      // after the cancel, were there none.
      expect(
        conversation.tell(MAIN, 'slow', () => (queued += 1)),
      ).toStrictEqual('sent');
      // The turn ends with the steer still out; the person's prompt, sent
      // now, waits for it, as Codex's adapter is starting a turn of its own.
      await until(() => events.some((event) => event.type === 'result'));
      conversation.send('hi');

      expect(events.at(-1)).toMatchObject({ type: 'queued', text: 'hi' });
      await until(
        () =>
          promptsIn(events).length === 3 && saidIn(events).includes('Working'),
      );

      expect(cancels).toStrictEqual(1);
      expect(queued).toStrictEqual(1);
      expect(promptsIn(events)).toStrictEqual([
        ['text', undefined],
        ['hi', undefined],
        ['slow', undefined],
      ]);
      expect(
        events.some(
          (event) => event.type === 'queued' && event.text === 'slow',
        ),
      ).toBeTruthy();

      // Were the agent's own turn left to run, its thousand steps would
      // outlast chord's wait for quiet, and chord's next prompt would start
      // alongside it.
      expect(saidIn(events)).not.toContain('Started alongside');
      conversation.interrupt();
    },
    (session) => {
      const cancel = session.cancel.bind(session);

      return Object.assign(session, {
        cancel: () => {
          cancels += 1;

          return cancel();
        },
      });
    },
  );
});

test("what a turn Codex's adapter started on its own sends is that turn's, closed by chord's line, never the reply before it", () =>
  onFake(
    ['--steering', 'codex', '--steer-late'],
    async (conversation, events) => {
      conversation.send('text');
      await went();
      conversation.tell(MAIN, 'Then the docs.');
      await until(
        () => events.filter((event) => event.type === 'result').length === 2,
      );

      const line = events.find((event) => event.type === 'self_started');

      assert(line?.type === 'self_started');
      expect(line.from).toStrictEqual(MAIN);

      const first = events.find((event) => event.type === 'prompt');

      assert(first?.type === 'prompt');

      const next = events.findLast((event) => event.type === 'prompt');

      assert(next?.type === 'prompt');

      // Whatever the agent's own turn said before the cancel landed is its
      // own, and chord's next turn says it got the message: never the turn
      // of chord's that ended before them.
      const said = events.flatMap((event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'agent_message_chunk' &&
        event.update.content.type === 'text' &&
        event.update.content.text.startsWith('Received the message')
          ? [event.turnId]
          : [],
      );

      expect(said).toContain(next.turnId);
      expect(
        said.every((turnId) => [line.turnId, next.turnId].includes(turnId)),
      ).toBeTruthy();
      expect(said).not.toContain(first.turnId);
      // Before the message went as chord's next turn.
      expect(events.indexOf(line)).toBeLessThan(events.indexOf(next));
    },
  ));

test("a second message told while the first steer is out never goes into the turn Codex's adapter started with the first, which chord cancels", () =>
  onFake(
    ['--steering', 'codex', '--steer-late'],
    async (conversation, events) => {
      conversation.send('text');
      await went();
      conversation.tell(MAIN, 'Run the tests.');
      conversation.tell(MAIN, 'Stop.');
      await until(
        () => events.filter((event) => event.type === 'result').length === 3,
      );

      expect(promptsIn(events)).toStrictEqual([
        ['text', undefined],
        ['Run the tests.', undefined],
        ['Stop.', undefined],
      ]);
      expect(saidIn(events)).not.toContain('Read the message from main.');
    },
  ));

test("what the agent's own turn says on its way to the cancel is folded under that turn, above chord's line, not the reply before it", async () => {
  const { session } = heldSession();
  const { promise: steered, resolve: steer } =
    Promise.withResolvers<'startedNewTurn'>();
  const { promise: ended, resolve: end } = Promise.withResolvers<TurnResult>();
  const listeners: ((update: SessionUpdate) => void)[] = [];
  const said = (text: string) => {
    for (const listener of listeners) {
      listener({
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text },
      });
    }
  };

  let prompts = 0;
  const steering = Object.assign(session, {
    subscribe: (listener: (update: SessionUpdate) => void) => {
      listeners.push(listener);

      return () => {};
    },
    steers: () => true,
    steer: () => steered,
    prompt: () => {
      prompts += 1;

      return {
        id: String(prompts),
        sent: Promise.resolve([]),
        result:
          prompts === 1
            ? ended
            : Promise.resolve({ status: 'completed', stopReason: 'end_turn' }),
      };
    },
    // Its own turn's chunk arrives as the cancel goes out.
    cancel: () => {
      said('Received the message.');

      return Promise.resolve();
    },
  });
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () => Promise.resolve(steering),
    (event) => events.push(event),
  );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));
  conversation.send('go');
  await went();
  said('I will run the tests.');
  conversation.tell(MAIN, 'Stop.');
  end({ status: 'completed', stopReason: 'end_turn' });
  await until(() => events.some((event) => event.type === 'result'));
  steer('startedNewTurn');
  await until(() => prompts === 2);

  const entries = events
    .filter((event): event is TranscriptAction =>
      ['prompt', 'update', 'result', 'self_started'].includes(event.type),
    )
    .reduce(reduceTranscript, emptyTranscript)
    .entries.map((entry) => [
      entry.kind,
      'text' in entry ? entry.text : 'alone' in entry ? entry.alone : undefined,
    ]);

  expect(entries).toStrictEqual([
    ['user', 'go'],
    ['assistant', 'I will run the tests.'],
    ['assistant', 'Received the message.'],
    ['self_started', false],
    ['message', 'Stop.'],
  ]);
  await conversation.close();
});

test('a steer the agent refuses, as when the turn ended on the way, goes as the next turn', async () => {
  const { session } = heldSession();
  const { promise: answered, resolve: answer } =
    Promise.withResolvers<TurnResult>();
  const prompts: string[] = [];
  const steering = Object.assign(session, {
    steers: () => true,
    steer: () => Promise.resolve('refused' as const),
    prompt: (text: string) => {
      prompts.push(text);

      return {
        id: text,
        sent: Promise.resolve([]),
        result:
          prompts.length === 1
            ? answered
            : Promise.resolve({ status: 'completed', stopReason: 'end_turn' }),
        cancel: () => Promise.resolve(),
      };
    },
  });
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () => Promise.resolve(steering),
    (event) => events.push(event),
  );

  conversation.start();
  await until(() => events.some((event) => event.type === 'connected'));
  conversation.send('slow');
  await went();

  expect(conversation.tell(MAIN, 'Stop.')).toStrictEqual('sent');
  await until(() => events.some((event) => event.type === 'queued'));
  answer({ status: 'completed', stopReason: 'end_turn' });
  await until(() => prompts.length === 2);

  expect(prompts[1]).toContain('Stop.');
  expect(
    !events.some((event) => event.type === 'prompt' && event.into),
  ).toBeTruthy();
  await conversation.close();
});

/** The turn id of the first prompt among `events`. */
function firstTurn(events: readonly ConversationEvent[]): string | undefined {
  return events.find((event) => event.type === 'prompt')?.turnId;
}

for (const wait of ['permission', 'form'] as const) {
  test(`a message behind the steer ahead waits on a ${wait} asked meanwhile, and goes into the turn once it is answered`, async () => {
    const stub = await steeringStub();
    const { conversation, events, steers } = stub;

    conversation.send('go');
    stub.go();
    await stub.settled();
    stub.ask('first');
    conversation.tell(MAIN, 'Run the tests.');
    conversation.tell(MAIN, 'Then the docs.');
    conversation.choose('first', 'allow');
    await until(() => steers.length === 1);

    if (wait === 'permission') {
      stub.ask('second');
    } else {
      stub.form('second');
    }

    steers[0]!.answer('injected');
    await stub.settled();

    // The second waits for the answer, marked so, as one told now would.
    expect(steers).toHaveLength(1);
    expect(promptsIn(events)).toStrictEqual([
      ['go', undefined],
      ['Run the tests.', firstTurn(events)],
    ]);
    expect(events.at(-1)).toMatchObject({
      type: 'queued',
      text: 'Then the docs.',
      afterAnswer: true,
    });

    if (wait === 'permission') {
      conversation.choose('second', 'allow');
    } else {
      conversation.answer('second', { action: 'decline' });
    }

    await until(() => steers.length === 2);
    steers[1]!.answer('injected');
    await until(() => promptsIn(events).length === 3);

    expect(steers[1]!.text).toContain('Then the docs.');
    expect(promptsIn(events).at(-1)).toStrictEqual([
      'Then the docs.',
      firstTurn(events),
    ]);
    stub.end();
    await conversation.close();
  });
}

test("a message waiting on a question asked while the steer ahead was out waits on for the answer when the turn ends first, then goes as the next turn (the owner's Q44)", async () => {
  const stub = await steeringStub();
  const { conversation, events, steers, prompts } = stub;

  conversation.send('go');
  stub.go();
  await stub.settled();
  conversation.tell(MAIN, 'Run the tests.');
  conversation.tell(MAIN, 'Then the docs.');
  await until(() => steers.length === 1);
  stub.ask('first');
  steers[0]!.answer('injected');
  await stub.settled();
  stub.end();
  // The question outlives the turn, between turns, and the message waits
  // for its answer rather than start a turn that would hide it.
  await until(() => events.some((event) => event.type === 'result'));
  await new Promise((resolve) => setTimeout(resolve, 300));
  expect(prompts).toHaveLength(1);
  conversation.choose('first', 'allow');
  await until(() => prompts.length === 2);

  expect(steers).toHaveLength(1);
  expect(prompts[1]).toContain('Then the docs.');
  expect(promptsIn(events)).toStrictEqual([
    ['go', undefined],
    ['Run the tests.', firstTurn(events)],
    ['Then the docs.', undefined],
  ]);
  await conversation.close();
});

test('a message told while the prompt waits to go, as one with mentions does, is queued behind the turn and never steered', async () => {
  const stub = await steeringStub();
  const { conversation, events, steers, prompts } = stub;

  conversation.send('go');

  expect(conversation.tell(MAIN, 'Stop.')).toStrictEqual('queued');
  stub.go();
  await stub.settled();
  stub.say('Done.');
  stub.end();
  await until(() => prompts.length === 2);

  expect(steers).toHaveLength(0);
  expect(promptsIn(events)).toStrictEqual([
    ['go', undefined],
    ['Stop.', undefined],
  ]);
  // The reply is the turn's that asked for it, with no turn of the agent's
  // own to fold it under.
  expect(
    events.find(
      (event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'agent_message_chunk',
    ),
  ).toMatchObject({ turnId: firstTurn(events) });
  expect(!events.some((event) => event.type === 'self_started')).toBeTruthy();
  await conversation.close();
});

/**
 * A session on the fake that names chord's server `chord`, as the window
 * gives it one, and keeps every prompt it sends the agent in `sent`.
 */
function noting(sent: string[]) {
  return (session: Session): Session => {
    const prompt = session.prompt.bind(session);

    return Object.assign(session, {
      chordServer: {
        type: 'http' as const,
        name: 'chord',
        url: 'http://127.0.0.1:1/mcp',
        headers: [],
      },
      prompt: ((text, ...rest) => {
        sent.push(text);

        return prompt(text, ...rest);
      }) as Session['prompt'],
    });
  };
}

test("chord's calls the agent cut off before they reached chord are told to it ahead of its next turn, once, a line each", async () => {
  const sent: string[] = [];

  await onFake(
    ['--steering', 'claude'],
    async (conversation, events) => {
      conversation.send('cutcalls');
      await ended(events, 1);
      conversation.send('text');
      await ended(events, 2);
      conversation.send('text');
      await ended(events, 3);

      expect(sent[1]).toStrictEqual(
        `<message from="chord">\n${cutNote([
          { tool: 'send_message', input: { to: 'main', text: CUT_MESSAGE } },
          { tool: 'open_agent', input: CUT_OPEN },
        ])}\n</message>\n\ntext`,
      );
      expect(sent[2]).toStrictEqual('text');
      expect(saidIn(events)).toContain(
        "Received chord's note: Your send_message to @main",
      );
      // The person's prompt is drawn as they typed it.
      expect(
        events.flatMap((event) =>
          event.type === 'prompt' ? [event.text] : [],
        ),
      ).toStrictEqual(['cutcalls', 'text', 'text']);
    },
    noting(sent),
  );
});

// What chord does today, not what it should (CHD-450, the owner's to
// decide): 0.93's report for a call Claude dropped for a steer carries no
// `nonExecutionKind`, so chord does not read the calls as cut off.
for (const [scenario, status] of [
  ['cutcallsunfinished', 'failed'],
  ['cutcallsunfinishedv2', 'cancelled'],
] as const) {
  test(`chord's calls claude-agent-acp 0.93 ends ${status} as never run, with no structured kind, are not told to the agent (CHD-450)`, async () => {
    const sent: string[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        conversation.send(scenario);
        await ended(events, 1);
        conversation.send('text');
        await ended(events, 2);

        const ends = events.flatMap((event) =>
          event.type === 'update' &&
          event.update.sessionUpdate === 'tool_call_update' &&
          event.update.status !== undefined
            ? [event.update]
            : [],
        );

        // No `claudeCode` in `_meta`: what is there is chord's own.
        expect(
          ends.map((end) => [
            end.status,
            (end._meta as Record<string, unknown> | undefined)?.['claudeCode'],
          ]),
        ).toStrictEqual([
          [status, undefined],
          [status, undefined],
        ]);
        expect(sent).toStrictEqual([scenario, 'text']);
        expect(saidIn(events)).not.toContain("Received chord's note");
      },
      noting(sent),
    );
  });
}

test('a cut call chord served after all reached it, and the note names only the calls that did not', async () => {
  const sent: string[] = [];
  const input = { to: 'main', text: CUT_MESSAGE };

  await onFake(
    ['--steering', 'claude'],
    async (conversation, events) => {
      conversation.send('cutcalls');
      // The send_message\'s arguments came: chord serves it as the batch waits.
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call_update' &&
            JSON.stringify(event.update.rawInput) === JSON.stringify(input),
        ),
      );
      conversation.served({
        tool: 'send_message',
        input,
        answer: { delivered: 'sent', to: 'main' },
      });
      await ended(events, 1);
      conversation.send('text');
      await ended(events, 2);

      expect(sent[1]).toStrictEqual(
        `<message from="chord">\n${cutNote([
          { tool: 'open_agent', input: CUT_OPEN },
        ])}\n</message>\n\ntext`,
      );
    },
    noting(sent),
  );
});

test('cut calls are told once each, in the order they were made, whatever order they failed in', async () => {
  const sent: string[] = [];

  await onFake(
    ['--steering', 'claude'],
    async (conversation, events) => {
      conversation.send('cutcallsback');
      await ended(events, 1);
      conversation.send('text');
      await ended(events, 2);

      expect(sent[1]).toStrictEqual(
        `<message from="chord">\n${cutNote([
          { tool: 'send_message', input: { to: 'main', text: CUT_MESSAGE } },
          { tool: 'open_agent', input: CUT_OPEN },
          { tool: 'list_sessions', input: {} },
        ])}\n</message>\n\ntext`,
      );
    },
    noting(sent),
  );
});

test('a cut call is told though chord served another tool with the same arguments', async () => {
  const sent: string[] = [];

  await onFake(
    ['--steering', 'claude'],
    async (conversation, events) => {
      conversation.send('cutcallsback');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.title === 'mcp__chord__list_sessions',
        ),
      );
      // list_agents({}) served: the cut list_sessions({}) is not it.
      conversation.served({ tool: 'list_agents', input: {}, answer: {} });
      await ended(events, 1);
      conversation.send('text');
      await ended(events, 2);

      expect(sent[1]).toContain(
        'Your list_sessions call was cut off before it reached chord',
      );
    },
    noting(sent),
  );
});

test('a note a prompt never took stays with its session, never the one clear starts after it', async () => {
  const opened: {
    prompts: string[];
    update: (update: SessionUpdate) => void;
    turns: {
      went: (links: readonly never[] | undefined) => void;
      end: () => void;
    }[];
  }[] = [];
  const open = () => {
    const { session } = heldSession();
    const own: (typeof opened)[number] = {
      prompts: [],
      update: () => {},
      turns: [],
    };

    opened.push(own);

    return Promise.resolve(
      Object.assign(session, {
        chordServer: {
          type: 'http' as const,
          name: 'chord',
          url: 'http://127.0.0.1:1/mcp',
          headers: [],
        },
        steers: () => false,
        cutsCallsOnSteer: () => true,
        subscribe: (listener: (update: SessionUpdate) => void) => {
          own.update = listener;

          return () => {};
        },
        prompt: (text: string) => {
          const sent = Promise.withResolvers<readonly never[] | undefined>();
          const result = Promise.withResolvers<TurnResult>();

          own.prompts.push(text);
          own.turns.push({
            went: sent.resolve,
            end: () =>
              result.resolve({ status: 'completed', stopReason: 'end_turn' }),
          });

          return {
            id: text,
            sent: sent.promise,
            result: result.promise,
            cancel: () => Promise.resolve(),
          };
        },
      }),
    );
  };

  const events: ConversationEvent[] = [];
  const conversation = new Conversation(open, (event) => events.push(event));
  const connected = (count: number) =>
    until(
      () =>
        events.filter((event) => event.type === 'connected').length === count,
    );

  conversation.start();
  await connected(1);

  const [first] = opened;

  conversation.send('first');
  await until(() => first!.turns.length === 1);
  first!.turns[0]!.went([]);
  await went();
  first!.update({
    sessionUpdate: 'tool_call',
    toolCallId: 'cut',
    title: 'mcp__chord__send_message',
    status: 'pending',
    rawInput: { to: 'main', text: 'Hi' },
  });
  first!.update({
    sessionUpdate: 'tool_call_update',
    toolCallId: 'cut',
    status: 'failed',
    _meta: { claudeCode: { nonExecutionKind: 'interrupted' } },
  });
  first!.turns[0]!.end();
  await ended(events, 1);

  // The next prompt takes the note but has not gone when clear starts anew.
  conversation.send('second');
  await until(() => first!.turns.length === 2);
  expect(first!.prompts[1]).toContain('Your send_message to @main');
  conversation.clear();
  await connected(2);
  first!.turns[1]!.went(undefined);
  first!.turns[1]!.end();
  await new Promise((resolve) => setTimeout(resolve, 10));

  conversation.send('third');
  await until(() => opened[1]!.prompts.length === 1);
  expect(opened[1]!.prompts).toStrictEqual(['third']);
});

test('a turn of a session /clear let go ends without touching the new session: a question the new one asks stays (CHD-373 S3c)', async () => {
  const opened: {
    prompts: string[];
    update: (update: SessionUpdate) => void;
    turns: {
      went: (links: readonly never[] | undefined) => void;
      end: () => void;
    }[];
  }[] = [];
  const open = () => {
    const { session } = heldSession();
    const own: (typeof opened)[number] = {
      prompts: [],
      update: () => {},
      turns: [],
    };

    opened.push(own);

    return Promise.resolve(
      Object.assign(session, {
        chordServer: {
          type: 'http' as const,
          name: 'chord',
          url: 'http://127.0.0.1:1/mcp',
          headers: [],
        },
        steers: () => false,
        cutsCallsOnSteer: () => true,
        subscribe: (listener: (update: SessionUpdate) => void) => {
          own.update = listener;

          return () => {};
        },
        prompt: (text: string) => {
          const sent = Promise.withResolvers<readonly never[] | undefined>();
          const result = Promise.withResolvers<TurnResult>();

          own.prompts.push(text);
          own.turns.push({
            went: sent.resolve,
            end: () =>
              result.resolve({ status: 'completed', stopReason: 'end_turn' }),
          });

          return {
            id: text,
            sent: sent.promise,
            result: result.promise,
            cancel: () => Promise.resolve(),
          };
        },
      }),
    );
  };

  const events: ConversationEvent[] = [];
  const conversation = new Conversation(open, (event) => events.push(event));
  const connected = (count: number) =>
    until(
      () =>
        events.filter((event) => event.type === 'connected').length === count,
    );
  const wait = {
    options: [
      { optionId: 'yes', name: 'Yes', kind: 'allow_once' as const },
      { optionId: 'no', name: 'No', kind: 'reject_once' as const },
    ],
    save: { question: 'Save team bugfix?', files: {}, escape: 'no' },
  };

  conversation.start();
  await connected(1);
  conversation.send('first');
  await until(() => opened[0]!.turns.length === 1);
  opened[0]!.turns[0]!.went([]);
  await went();

  // Let go while its turn runs; the new session's turn asks a question.
  void conversation.clear();
  await connected(2);
  conversation.send('second');
  await until(() => opened[1]?.turns.length === 1);
  opened[1]!.turns[0]!.went([]);
  await went();

  const asking = conversation.ask(wait, new AbortController().signal);

  await until(() =>
    events.some((event) => event.type === 'permission_requested'),
  );

  // Only now does the old turn answer its cancel.
  opened[0]!.turns[0]!.end();

  const settled = await Promise.race([
    asking.then(() => 'settled'),
    new Promise((resolve) => setTimeout(() => resolve('waiting'), 50)),
  ]);

  expect(settled).toBe('waiting');
  opened[1]!.turns[0]!.end();
  await conversation.close();
});

test("a session /clear lets go while its turn's end waits out the quiet ends as its own: its cost said apart, nothing of the new session's touched (CHD-373 S3c)", async () => {
  const opened: {
    prompts: string[];
    update: (update: SessionUpdate) => void;
    turns: {
      went: (links: readonly never[] | undefined) => void;
      end: () => void;
    }[];
  }[] = [];
  const open = () => {
    const { session } = heldSession();
    const own: (typeof opened)[number] = {
      prompts: [],
      update: () => {},
      turns: [],
    };

    opened.push(own);

    return Promise.resolve(
      Object.assign(session, {
        chordServer: {
          type: 'http' as const,
          name: 'chord',
          url: 'http://127.0.0.1:1/mcp',
          headers: [],
        },
        steers: () => false,
        cutsCallsOnSteer: () => true,
        subscribe: (listener: (update: SessionUpdate) => void) => {
          own.update = listener;

          return () => {};
        },
        prompt: (text: string) => {
          const sent = Promise.withResolvers<readonly never[] | undefined>();
          const result = Promise.withResolvers<TurnResult>();

          own.prompts.push(text);
          own.turns.push({
            went: sent.resolve,
            end: () =>
              result.resolve({ status: 'completed', stopReason: 'end_turn' }),
          });

          return {
            id: text,
            sent: sent.promise,
            result: result.promise,
            cancel: () => Promise.resolve(),
          };
        },
      }),
    );
  };

  const events: ConversationEvent[] = [];
  const conversation = new Conversation(open, (event) => events.push(event));
  const connected = (count: number) =>
    until(
      () =>
        events.filter((event) => event.type === 'connected').length === count,
    );

  conversation.start();
  await connected(1);
  conversation.send('first');
  await until(() => opened[0]!.turns.length === 1);
  opened[0]!.turns[0]!.went([]);
  await went();
  opened[0]!.update({
    sessionUpdate: 'usage_update',
    used: 1,
    size: 2,
    cost: { amount: 0.01, currency: 'USD' },
  });
  // Queued behind it, so its end waits out the quiet before it finishes.
  conversation.send('second');
  opened[0]!.turns[0]!.end();
  await new Promise((resolve) => setTimeout(resolve, 20));

  const started = performance.now();

  await conversation.clear();

  // Let go well within the settle limit, so its end was heard.
  expect(performance.now() - started).toBeLessThan(3000);
  expect(
    events.filter((event) => event.type === 'retired_usage'),
  ).toMatchObject([{ cost: { amount: 0.01, currency: 'USD' } }]);
  expect(events.some((event) => event.type === 'usage')).toBeFalsy();
  // The queued prompt went with the session it was queued in.
  expect(opened[1]?.prompts ?? []).toStrictEqual([]);
  await conversation.close();
});

describe('CHD-417 tester: held steer lifecycle', () => {
  test('serialized messages keep separate snapshots when the second call opens between them', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      const has = (id: string) =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.toolCallId === id,
        );

      conversation.send('overlaptwo');
      await until(() => has('overlap-a'));
      conversation.tell(MAIN, 'First.');
      await until(() => has('overlap-b'));
      conversation.tell(MAIN, 'Second.');
      await until(() => events.some((event) => event.type === 'result'));

      const order = events.flatMap((event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'tool_call_update' &&
        event.update.status === 'completed'
          ? [event.update.toolCallId]
          : event.type === 'prompt' && event.into !== undefined
            ? [event.text]
            : [],
      );

      expect(order).toStrictEqual([
        'overlap-a',
        'First.',
        'overlap-b',
        'Second.',
      ]);
      expect(
        promptsIn(events)
          .slice(1)
          .map(([, into]) => into),
      ).toStrictEqual([firstTurn(events), firstTurn(events)]);
    }));

  test('a failed snapshotted call releases its message before a later call ends', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      conversation.send('overlapfail');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.toolCallId === 'overlapfail-a',
        ),
      );
      conversation.tell(MAIN, 'After the failed call.');
      await until(() => events.some((event) => event.type === 'result'));

      const order = events.flatMap((event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'tool_call_update'
          ? [`${event.update.toolCallId}: ${event.update.status}`]
          : event.type === 'prompt' && event.into !== undefined
            ? [event.text]
            : [],
      );

      expect(order).toStrictEqual([
        'overlapfail-a: failed',
        'After the failed call.',
        'overlapfail-b: completed',
      ]);
    }));

  for (const answer of ['allow', 'deny']) {
    test(`a permission ${answer} releases the message only after the other top-level call ends`, () =>
      onFake(['--steering', 'claude'], async (conversation, events) => {
        conversation.send('overlapask');
        await until(() =>
          events.some((event) => event.type === 'permission_requested'),
        );

        const asked = events.find(
          (event) => event.type === 'permission_requested',
        );

        assert(asked?.type === 'permission_requested');
        assert(asked.permission.toolCallId !== undefined);
        expect(conversation.tell(MAIN, 'After both calls.')).toBe('queued');
        conversation.choose(asked.permission.id, answer);
        await until(() =>
          events.some(
            (event) =>
              event.type === 'prompt' && event.text === 'After both calls.',
          ),
        );

        const sent = events.findIndex(
          (event) =>
            event.type === 'prompt' && event.text === 'After both calls.',
        );
        const ended = (id: string, status: string) =>
          events.findIndex(
            (event) =>
              event.type === 'update' &&
              event.update.sessionUpdate === 'tool_call_update' &&
              event.update.toolCallId === id &&
              event.update.status === status,
          );
        const write = ended(
          asked.permission.toolCallId,
          answer === 'allow' ? 'completed' : 'failed',
        );
        const other = ended('overlapask-a', 'completed');

        expect(write >= 0).toBe(true);
        expect(other > write).toBe(true);
        expect(sent > other).toBe(true);
      }));
  }

  test('an open subagent-only call never holds a steer into its parent', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      conversation.send('subagentcall');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.subagentId !== undefined &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.status === 'in_progress',
        ),
      );
      conversation.tell(MAIN, 'For the parent.');
      await until(() => events.some((event) => event.type === 'result'));

      const order = events.flatMap((event) =>
        event.type === 'update' &&
        event.subagentId !== undefined &&
        event.update.sessionUpdate === 'tool_call_update' &&
        event.update.status === 'completed'
          ? ['child ended']
          : event.type === 'prompt' && event.into !== undefined
            ? [event.text]
            : [],
      );

      expect(order).toStrictEqual(['For the parent.', 'child ended']);
    }));

  for (const action of ['clear', 'close'] as const) {
    test(`${action} discards a held steer without delivering it to the old or new session`, async () => {
      const steered: string[] = [];
      const pids: number[] = [];

      await onFake(
        ['--steering', 'claude'],
        async (conversation, events) => {
          conversation.send('bash');
          await callOpen(events);
          conversation.tell(MAIN, 'Must be discarded.');
          expect(steered).toStrictEqual([]);

          if (action === 'clear') {
            conversation.clear();
            await until(
              () =>
                events.filter((event) => event.type === 'connected').length ===
                2,
            );
            conversation.send('slow');
            await until(() => saidIn(events).includes('Working'));
            conversation.tell(MAIN, 'New session only.');
            await until(() => steered.length === 1);
            await until(() =>
              saidIn(events).includes('Read the message from main.'),
            );
            expect(steered[0]).toContain('New session only.');
            conversation.interrupt();
          } else {
            await conversation.close();
          }

          expect(steered.join('\n')).not.toContain('Must be discarded.');
          expect(promptsIn(events).map(([text]) => text)).not.toContain(
            'Must be discarded.',
          );
        },
        (session) => {
          pids.push(...session.agentPids);

          const steer = session.steer.bind(session);

          session.steer = (text) => {
            steered.push(text);

            return steer(text);
          };

          return session;
        },
      );

      expect(pids.length > 0).toBeTruthy();

      for (const pid of pids) {
        expect(await isAlive(pid), `fake agent ${pid} survived ${action}`).toBe(
          false,
        );
      }
    });
  }
});

describe('CHD-417 tester: cut-call note delivery', () => {
  test('a queued teammate turn takes the ordered note once without drawing a chord message row', async () => {
    const sent: string[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        conversation.send('cutcallsback');
        await until(() =>
          events.some(
            (event) =>
              event.type === 'update' &&
              event.update.sessionUpdate === 'tool_call',
          ),
        );
        expect(conversation.deliver(MAIN, 'Continue the review.')).toBe(
          'queued',
        );
        await ended(events, 2);
        conversation.send('text');
        await ended(events, 3);

        expect(sent[1]).toContain('<message from="chord">');
        expect(sent[1]!.indexOf('Your send_message')).toBeLessThan(
          sent[1]!.indexOf('Your open_agent'),
        );
        expect(sent[1]!.indexOf('Your open_agent')).toBeLessThan(
          sent[1]!.indexOf('Your list_sessions'),
        );
        expect(sent[1]).toEndWith(
          '<message from="main">\nContinue the review.\n</message>',
        );
        expect(sent[2]).toBe('text');
        expect(
          events.some(
            (event) => event.type === 'prompt' && event.from?.name === 'chord',
          ),
        ).toBe(false);
      },
      noting(sent),
    );
  });

  test('a prompt cancelled before it goes restores the note for this session only, once', async () => {
    const attempted: string[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        conversation.send('cutcalls');
        await ended(events, 1);
        conversation.send('cancel-before-send');
        await ended(events, 2);
        conversation.send('text');
        await ended(events, 3);
        conversation.send('text');
        await ended(events, 4);

        expect(attempted[1]).toContain('Your send_message to @main');
        expect(attempted[2]).toContain('Your send_message to @main');
        expect(attempted[2]!.match(/Your send_message/g)).toHaveLength(1);
        expect(attempted[3]).toBe('text');
      },
      (session) => {
        const observed = noting(attempted)(session);
        const prompt = observed.prompt.bind(observed);

        observed.prompt = (text, ...rest) => {
          if (text.endsWith('cancel-before-send')) {
            attempted.push(text);

            return {
              id: 'unsent',
              sent: Promise.resolve(undefined),
              result: Promise.resolve({
                status: 'cancelled',
                stopReason: 'cancelled',
              }),
              cancel: () => Promise.resolve(),
            };
          }

          return prompt(text, ...rest);
        };

        return observed;
      },
    );
  });

  test('replayed cut-call updates still mark their rows but schedule no new note', async () => {
    let history: TranscriptAction[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        conversation.send('cutcalls');
        await ended(events, 1);

        history = [
          { type: 'prompt', turnId: 'history-1', text: 'cutcalls', at: 0 },
          ...events.flatMap((event): TranscriptAction[] =>
            event.type === 'update'
              ? [{ type: 'update', turnId: 'history-1', update: event.update }]
              : [],
          ),
        ];
      },
      noting([]),
    );

    const sent: string[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        const replayed = history.reduce(reduceTranscript, emptyTranscript);

        expect(
          replayed.entries.filter(
            (entry) => entry.kind === 'tool' && entry.call.cut,
          ),
        ).toHaveLength(2);
        conversation.send('text');
        await ended(events, 1);
        expect(sent).toStrictEqual(['text']);
      },
      (session) =>
        Object.assign(noting(sent)(session), { history: () => history }),
    );
  });

  test('an interrupted call on a different server schedules no chord retry note', async () => {
    const sent: string[] = [];

    await onFake(
      ['--steering', 'claude'],
      async (conversation, events) => {
        conversation.send('cutcalls');
        await ended(events, 1);
        conversation.send('text');
        await ended(events, 2);
        expect(sent[1]).toBe('text');
      },
      (session) =>
        Object.assign(noting(sent)(session), {
          chordServer: {
            type: 'http' as const,
            name: 'chord-2',
            url: 'http://127.0.0.1:1/mcp',
            headers: [],
          },
        }),
    );
  });
});

describe('CHD-423 tester: mixed queue holds', () => {
  const refuseSteering = ['--steering', 'claude', '--steer-late'];

  test('answer-to-call reason replacement preserves the earlier call-held message and delivery order', () =>
    onFake(refuseSteering, async (conversation, events) => {
      conversation.send('overlapask');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call' &&
            event.update.toolCallId === 'overlapask-a',
        ),
      );
      conversation.tell(MAIN, 'First, while the call runs.');
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );
      conversation.tell(MAIN, 'Second, while the answer waits.');

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      conversation.choose(asked.permission.id, 'allow');
      await until(
        () =>
          events.filter(
            (event) => event.type === 'prompt' && event.from?.name === 'main',
          ).length === 2,
      );

      const queued = events.flatMap((event) =>
        event.type === 'queued' ? [event] : [],
      );

      const first = queued.filter((event) => event.text.startsWith('First,'));
      const second = queued.filter((event) => event.text.startsWith('Second,'));
      const reasons = (rows: typeof queued) =>
        rows.map((event) => [event.afterCalls, event.afterAnswer]);

      // The question takes priority for both messages, then the still-open
      // call does again, without changing either row's identity (CHD-378).
      expect(reasons(first).slice(0, 3)).toStrictEqual([
        [true, undefined],
        [undefined, true],
        [true, undefined],
      ]);
      expect(reasons(second).slice(0, 2)).toStrictEqual([
        [undefined, true],
        [true, undefined],
      ]);
      expect(new Set(first.map((event) => event.turnId)).size).toBe(1);
      expect(new Set(second.map((event) => event.turnId)).size).toBe(1);
      expect(
        promptsIn(events)
          .slice(1)
          .map(([text]) => text),
      ).toStrictEqual([
        'First, while the call runs.',
        'Second, while the answer waits.',
      ]);
    }));

  test('an adapter refusal starts the held message as the next turn with the same row identity', () =>
    onFake(
      ['--steering', 'claude', '--steer-late'],
      async (conversation, events) => {
        conversation.send('bash');
        await callOpen(events);
        conversation.tell(MAIN, 'After refusal.');
        await ended(events, 2);

        const queued = events.flatMap((event) =>
          event.type === 'queued' ? [event] : [],
        );

        expect(queued.filter((event) => event.afterCalls)).toHaveLength(1);

        const taken = events.find(
          (event) => event.type === 'prompt' && event.text === 'After refusal.',
        );

        assert(taken?.type === 'prompt');
        expect(taken.turnId).toBe(queued[0]!.turnId);
        expect(taken.into).toBeUndefined();
        expect(new Set(queued.map((event) => event.turnId)).size).toBe(1);
        expect(promptsIn(events)).toStrictEqual([
          ['bash', undefined],
          ['After refusal.', undefined],
        ]);
      },
    ));
});

describe('CHD-452 tester: two-steer gate boundaries', () => {
  function callEnded(events: readonly ConversationEvent[]) {
    return until(() =>
      events.some(
        (event) =>
          event.type === 'update' &&
          event.update.sessionUpdate === 'tool_call_update' &&
          event.update.status === 'completed',
      ),
    );
  }

  test('a first steer read before the call ends still counts when the second arrives later', () =>
    onFake(['--steering', 'codex'], async (conversation, events) => {
      conversation.send('callchildtwo');
      await until(() =>
        events.some(
          (event) =>
            event.type === 'update' &&
            event.update.sessionUpdate === 'tool_call',
        ),
      );
      conversation.tell(MAIN, 'First, during the call.');
      await callEnded(events);

      expect(saidIn(events)).toBe('Read the message from main.\n\n');
      expect(events.some((event) => event.type === 'result')).toBe(false);

      conversation.tell(MAIN, 'Second, after the call.');
      await ended(events, 1);

      expect(saidIn(events)).toBe(
        'Read the message from main.\n\n' +
          'Read the message from main.\n\nThe tests pass.',
      );
      expect(promptsIn(events).map(([text]) => text)).toStrictEqual([
        'callchildtwo',
        'First, during the call.',
        'Second, after the call.',
      ]);
    }));

  for (const end of ['cancel', 'close'] as const) {
    test(`${end} releases a turn waiting for its missing second steer`, async () => {
      let owner: Session | undefined;

      await onFake(
        ['--steering', 'claude'],
        async (conversation, events) => {
          conversation.send('callchildtwo');
          await until(() =>
            events.some(
              (event) =>
                event.type === 'update' &&
                event.update.sessionUpdate === 'tool_call',
            ),
          );
          conversation.tell(MAIN, 'Only the first.');
          await callEnded(events);
          await until(() =>
            events.some(
              (event) =>
                event.type === 'prompt' &&
                event.into !== undefined &&
                event.text === 'Only the first.',
            ),
          );

          expect(events.some((event) => event.type === 'result')).toBe(false);

          if (end === 'cancel') {
            conversation.interrupt();
            await ended(events, 1);

            const result = events.find((event) => event.type === 'result');

            assert(result?.type === 'result');
            expect(result.result.status).toBe('cancelled');
            conversation.send('callchild');
            await ended(events, 2);
            expect(saidIn(events)).toEndWith('The tests pass.');
          } else {
            assert(owner);

            const started = Date.now();

            await conversation.close();
            expect(Date.now() - started).toBeLessThan(1500);
            expect(owner.agentPids.size).toBe(0);
            await owner.exited;
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

describe('a request with no turn running (CHD-158)', () => {
  test("the session's own agent asking after its answer waits on the person, and hears the answer", () =>
    onFake([], async (conversation, events) => {
      conversation.send('mainbetween');
      await until(() => events.some((event) => event.type === 'result'));
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      expect(asked.between).toBeTrue();
      expect(asked.at).toBeNumber();
      expect(asked.permission.title).toStrictEqual('Write notes/report.md');
      conversation.choose(asked.permission.id, 'allow');
      await until(() => saidIn(events).includes('Permission: allow.'));
      expect(
        events.some((event) => event.type === 'permission_settled'),
      ).toBeTrue();
    }));

  test('a subagent that outlived its turn asks a permission and a form, and hears both answers', () =>
    onFake([], async (conversation, events) => {
      conversation.send('claudebetween');
      await until(() => events.some((event) => event.type === 'result'));
      await until(() =>
        events.some((event) => event.type === 'permission_requested'),
      );

      const asked = events.find(
        (event) => event.type === 'permission_requested',
      );

      assert(asked?.type === 'permission_requested');
      expect(asked.between).toBeTrue();
      expect(asked.permission.subagentId).toBeString();
      conversation.choose(asked.permission.id, 'allow');
      await until(() =>
        events.some((event) => event.type === 'elicitation_requested'),
      );

      const form = events.find(
        (event) => event.type === 'elicitation_requested',
      );

      assert(form?.type === 'elicitation_requested');
      expect(form.elicitation.between).toBeTrue();
      // Asked by the subagent, which the box names.
      expect(form.elicitation.asker).toStrictEqual(asked.permission.subagentId);
      conversation.answer(form.elicitation.id, { action: 'decline' });
      await until(() =>
        saidIn(events).includes('Write allowed; form decline.'),
      );
    }));
});

describe("the person's prompt steered into the running turn (CHD-378)", () => {
  for (const adapter of ['claude', 'codex']) {
    test(`on ${adapter}'s adapter it goes into the turn at once, drawn there as the person's and never queued`, () =>
      onFake(['--steering', adapter], async (conversation, events) => {
        conversation.send('slow');
        await until(() => saidIn(events).startsWith('Working'));

        expect(conversation.steerIn('Then the docs.')).toStrictEqual('sent');
        await until(() =>
          saidIn(events).includes('Read the message from nobody.'),
        );

        const into = events.findLast((event) => event.type === 'prompt');

        assert(into?.type === 'prompt');
        expect(promptsIn(events)).toStrictEqual([
          ['slow', undefined],
          ['Then the docs.', firstTurn(events)],
        ]);
        expect(into.from).toBeUndefined();
        expect(!events.some((event) => event.type === 'queued')).toBeTruthy();
        conversation.interrupt();
        await until(() => events.some((event) => event.type === 'result'));
      }));
  }

  test('on an agent that takes no steering nothing is sent or queued, and the shell output held for the next prompt stays', async () => {
    const sent: string[] = [];

    await onFake(
      [],
      async (conversation, events) => {
        conversation.send('slow');
        await until(() => saidIn(events).startsWith('Working'));
        conversation.aside(MAIN, 'parser exited.');

        expect(conversation.steerIn('Then the docs.')).toStrictEqual(
          'unsteerable',
        );
        expect(promptsIn(events)).toStrictEqual([['slow', undefined]]);
        expect(!events.some((event) => event.type === 'queued')).toBeTruthy();
        conversation.interrupt();
        await until(() => events.some((event) => event.type === 'result'));
        conversation.send('text');
        await until(() => sent.length === 2);

        expect(sent[1]).toContain('parser exited.');
      },
      (session) => {
        const prompt = session.prompt.bind(session);

        return Object.assign(session, {
          prompt: ((text, ...rest) => {
            sent.push(text);

            return prompt(text, ...rest);
          }) as Session['prompt'],
        });
      },
    );
  });

  test("one that meets the turn's end on Claude's adapter is refused, and goes as the next turn", () =>
    onFake(
      ['--steering', 'claude', '--steer-late'],
      async (conversation, events) => {
        conversation.send('text');
        await went();

        expect(conversation.steerIn('Stop.')).toStrictEqual('sent');
        await ended(events, 2);

        expect(promptsIn(events)).toStrictEqual([
          ['text', undefined],
          ['Stop.', undefined],
        ]);
      },
    ));

  test("a turn Codex's adapter starts with one that missed the turn is cancelled, and the prompt goes as chord's next turn", async () => {
    let cancels = 0;

    await onFake(
      ['--steering', 'codex', '--steer-late'],
      async (conversation, events) => {
        conversation.send('text');
        await went();

        expect(conversation.steerIn('slow')).toStrictEqual('sent');
        await until(
          () =>
            promptsIn(events).length === 2 &&
            saidIn(events).includes('Working'),
        );

        expect(cancels).toStrictEqual(1);
        expect(promptsIn(events)).toStrictEqual([
          ['text', undefined],
          ['slow', undefined],
        ]);
        // Closed by chord's line, which names no sender for the person.
        expect(
          events.find((event) => event.type === 'self_started'),
        ).not.toHaveProperty('from');
        expect(
          events.some((event) => event.type === 'self_started'),
        ).toBeTruthy();
        expect(saidIn(events)).not.toContain('Started alongside');
        conversation.interrupt();
      },
      (session) => {
        const cancel = session.cancel.bind(session);

        return Object.assign(session, {
          cancel: () => {
            cancels += 1;

            return cancel();
          },
        });
      },
    );
  });

  test("while the turn waits on the person's answer it is held, marked so, and goes into the turn once they answer", async () => {
    const stub = await steeringStub();
    const { conversation, events, steers } = stub;

    conversation.send('go');
    stub.go();
    await stub.settled();
    stub.ask('first');

    expect(conversation.steerIn('Run the tests.')).toStrictEqual('queued');
    expect(events.at(-1)).toMatchObject({
      type: 'queued',
      text: 'Run the tests.',
      afterAnswer: true,
    });
    await stub.settled();
    expect(steers).toHaveLength(0);
    conversation.choose('first', 'allow');
    await until(() => steers.length === 1);
    steers[0]!.answer('injected');
    await until(() => promptsIn(events).length === 2);

    expect(promptsIn(events).at(-1)).toStrictEqual([
      'Run the tests.',
      firstTurn(events),
    ]);
    stub.end();
    await conversation.close();
  });

  test('several go one at a time in the order pressed, each with what is held ahead of it, and the prompts queued with Enter stay queued', async () => {
    const stub = await steeringStub();
    const { conversation, events, steers, prompts } = stub;

    conversation.send('go');
    stub.go();
    await stub.settled();

    expect(conversation.send('Queued with Enter.')).toStrictEqual(true);
    conversation.aside(MAIN, 'parser exited.');
    conversation.steerIn('Run the tests.');
    conversation.steerIn('Then the docs.');
    await until(() => steers.length === 1);
    await stub.settled();

    // The second waits for the first's answer.
    expect(steers).toHaveLength(1);
    expect(steers[0]!.text).toContain('parser exited.');
    expect(steers[0]!.text).toEndWith('Run the tests.');
    steers[0]!.answer('injected');
    await until(() => steers.length === 2);

    expect(steers[1]!.text).toStrictEqual('Then the docs.');
    steers[1]!.answer('injected');
    await until(() => promptsIn(events).length === 3);
    expect(prompts).toHaveLength(1);
    stub.end();
    await until(() => prompts.length === 2);

    expect(promptsIn(events)).toStrictEqual([
      ['go', undefined],
      ['Run the tests.', firstTurn(events)],
      ['Then the docs.', firstTurn(events)],
      ['Queued with Enter.', undefined],
    ]);
    await conversation.close();
  });

  test('with no turn running it goes as the next turn, as Enter sends it', async () => {
    const stub = await steeringStub();
    const { conversation, events, steers, prompts } = stub;

    expect(conversation.steerIn('go')).toStrictEqual('sent');
    await until(() => prompts.length === 1);

    expect(steers).toHaveLength(0);
    expect(promptsIn(events)).toStrictEqual([['go', undefined]]);
    stub.go();
    stub.end();
    await conversation.close();
  });
});

test("Esc takes the person's steer held behind Claude's open calls back with the queue, never to be sent, while another agent's held message still goes (CHD-378)", () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    conversation.send('bashcut');
    await callOpen(events);

    expect(conversation.steerIn('Skip the slow tests')).toStrictEqual('sent');
    conversation.tell(MAIN, 'Then the docs.');
    await until(
      () => events.filter((event) => event.type === 'queued').length === 2,
    );
    expect(events.at(-2)).toMatchObject({
      type: 'queued',
      text: 'Skip the slow tests',
      afterCalls: true,
    });
    conversation.interrupt();

    expect(events).toContainEqual({ type: 'queue_withdrawn' });
    await until(() => promptsIn(events).length === 2);
    await ended(events, 2);

    expect(promptsIn(events)).toStrictEqual([
      ['bashcut', undefined],
      ['Then the docs.', undefined],
    ]);
  }));

describe("the person's steer the agent has not answered yet (CHD-378)", () => {
  /** What the queue was told of `text`, each time: its reason, if any. */
  const told = (events: readonly ConversationEvent[], text: string) =>
    events.flatMap((event) =>
      event.type === 'queued' && event.text === text
        ? [
            event.steering
              ? 'steering'
              : event.afterCalls
                ? 'calls'
                : event.afterAnswer
                  ? 'answer'
                  : 'plain',
          ]
        : [],
    );

  test('unanswered for a while it shows in the queue, and refused once the turn ends it goes as the next turn, the row with it', () =>
    onFake(
      ['--steering', 'claude', '--steer-late'],
      async (conversation, events) => {
        conversation.send('slow');
        await until(() => saidIn(events).startsWith('Working'));

        expect(conversation.steerIn('Then the docs.')).toStrictEqual('sent');
        await until(() => told(events, 'Then the docs.').length === 1);
        conversation.interrupt();
        await ended(events, 2);

        // Nothing waits ahead of it, so it starts at once, under its row's id.
        expect(told(events, 'Then the docs.')).toStrictEqual(['steering']);
        expect(
          events.findLast((event) => event.type === 'prompt')?.turnId,
        ).toStrictEqual(
          events.find((event) => event.type === 'queued')?.turnId,
        );
        expect(promptsIn(events)).toStrictEqual([
          ['slow', undefined],
          ['Then the docs.', undefined],
        ]);
      },
    ));

  test('held for the running calls, it says it is out with the agent as soon as it goes', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      conversation.send('bashone');
      await callOpen(events);
      conversation.steerIn('Skip the slow tests');
      await until(() =>
        promptsIn(events).some(([text]) => text === 'Skip the slow tests'),
      );

      expect(told(events, 'Skip the slow tests')).toStrictEqual([
        'calls',
        'steering',
      ]);
      conversation.interrupt();
    }));
});

test("the person's unanswered steer of a session /clear let go never shows in the new session's queue (CHD-378)", async () => {
  const opened: { went: () => void }[] = [];
  let steered = 0;
  const open = () => {
    const { session } = heldSession();
    const { promise: sent, resolve: go } =
      Promise.withResolvers<readonly never[]>();

    opened.push({ went: () => go([]) });

    return Promise.resolve(
      Object.assign(session, {
        steers: () => true,
        // Never answered: the agent sits on it.
        steer: () => {
          steered += 1;

          return new Promise<never>(() => {});
        },
        prompt: (text: string) => ({
          id: text,
          sent,
          result: new Promise<never>(() => {}),
          cancel: () => Promise.resolve(),
        }),
      }),
    );
  };

  const events: ConversationEvent[] = [];
  const conversation = new Conversation(open, (event) => events.push(event));
  const connected = (count: number) =>
    until(
      () =>
        events.filter((event) => event.type === 'connected').length === count,
    );

  conversation.start();
  await connected(1);
  conversation.send('go');
  opened[0]!.went();
  await went();

  expect(conversation.steerIn('Use the parser')).toStrictEqual('sent');
  await until(() => steered === 1);
  void conversation.clear();
  await connected(2);

  const reopened = events.length;

  // Past the wait after which an unanswered steer shows.
  await new Promise((resolve) => setTimeout(resolve, 700));

  expect(
    events
      .slice(reopened)
      .some((event) => event.type === 'queued' && event.steering),
  ).toBeFalsy();
  await conversation.close();
});

describe('a steer held for the running calls while a question opens and is answered (CHD-378)', () => {
  /** Each reason the queue was told for `text`, in order. */
  const reasons = (events: readonly ConversationEvent[], text: string) =>
    events.flatMap((event) =>
      event.type === 'queued' && event.text === text
        ? [
            event.steering
              ? 'steering'
              : event.afterAnswer
                ? 'answer'
                : event.afterCalls
                  ? 'calls'
                  : 'plain',
          ]
        : [],
    );

  for (const whose of ['the person', 'another agent'] as const) {
    test(`${whose}'s says it waits for the answer while the question is open, then for the calls again, and goes in once they end`, () =>
      onFake(['--steering', 'claude'], async (conversation, events) => {
        const text = 'Also write the docs';

        conversation.send('overlapasksteer');
        await until(() =>
          events.some(
            (event) =>
              event.type === 'update' &&
              event.update.sessionUpdate === 'tool_call' &&
              event.update.toolCallId === 'overlapask-a',
          ),
        );

        if (whose === 'the person') {
          conversation.steerIn(text);
        } else {
          conversation.tell(MAIN, text);
        }

        await until(() =>
          events.some((event) => event.type === 'permission_requested'),
        );
        await until(() => reasons(events, text).includes('answer'));

        const asked = events.find(
          (event) => event.type === 'permission_requested',
        );

        assert(asked?.type === 'permission_requested');
        conversation.choose(asked.permission.id, 'allow');
        await until(() =>
          promptsIn(events).some(([said, into]) => said === text && into),
        );

        expect(reasons(events, text)).toStrictEqual([
          'calls',
          'answer',
          'calls',
          ...(whose === 'the person' ? ['steering'] : []),
        ]);
        await ended(events, 1);
      }));
  }
});

describe("the person's draft with an image or a mention steered whole, as a new turn would send it (CHD-378, the owner's Q215, Q216)", () => {
  /** A session on the fake whose directory holds `a.ts`, to mention. */
  const withFile = (session: Session): Session => {
    writeFileSync(join(session.cwd, 'a.ts'), '');

    return session;
  };

  for (const adapter of ['claude', 'codex']) {
    test(`on ${adapter}'s adapter the image and the file's link go into the running turn with the text`, () =>
      onFake(
        ['--steering', adapter],
        async (conversation, events) => {
          conversation.send('slow');
          await until(() => saidIn(events).startsWith('Working'));

          expect(
            conversation.steerIn(
              'See @a.ts and [Image #1]',
              undefined,
              [{ mediaType: 'image/png', data: 'aGVsbG8=' }],
              ['a.ts'],
            ),
          ).toStrictEqual('sent');
          await until(() =>
            saidIn(events).includes('Read the message from nobody.'),
          );

          expect(saidIn(events)).toContain(
            'Received an image: image/png, 5 bytes',
          );
          expect(saidIn(events)).toContain('Received a link: a.ts, file://');
          expect(promptsIn(events).at(-1)).toStrictEqual([
            'See @a.ts and [Image #1]',
            firstTurn(events),
          ]);
          conversation.interrupt();
          await until(() => events.some((event) => event.type === 'result'));
        },
        withFile,
      ));
  }

  test('refused once the turn has ended, it goes as the next turn with its image and link still', () =>
    onFake(
      ['--steering', 'claude', '--steer-late'],
      async (conversation, events) => {
        conversation.send('text');
        await went();
        conversation.steerIn(
          'See @a.ts and [Image #1]',
          undefined,
          [{ mediaType: 'image/png', data: 'aGVsbG8=' }],
          ['a.ts'],
        );
        await ended(events, 2);

        expect(promptsIn(events).at(-1)).toStrictEqual([
          'See @a.ts and [Image #1]',
          undefined,
        ]);
        expect(saidIn(events)).toContain(
          'Received an image: image/png, 5 bytes',
        );
        expect(saidIn(events)).toContain('Received a link: a.ts, file://');
      },
      withFile,
    ));
});

test("the fake's texttillsteeredheld reads a steer, then holds its turn with nothing more said until it is cancelled (CHD-526)", () =>
  onFake(['--steering', 'claude'], async (conversation, events) => {
    conversation.send('texttillsteeredheld');
    await until(() => saidIn(events).endsWith('came in chunks.'));
    conversation.tell(MAIN, 'Then the docs.');
    await until(() => saidIn(events).includes('Read the message from main.'));

    const said = saidIn(events);

    expect(!events.some((event) => event.type === 'result')).toBeTruthy();
    conversation.interrupt();
    await until(() => events.some((event) => event.type === 'result'));

    expect(events.find((event) => event.type === 'result')).toMatchObject({
      result: { status: 'cancelled' },
    });
    expect(saidIn(events)).toStrictEqual(said);
  }));

describe("the person's oldest queued message sent into the running turn (CHD-535)", () => {
  /** The `queued` events of message `text`, in order. */
  const rows = (events: readonly ConversationEvent[], text: string) =>
    events.filter((event) => event.type === 'queued' && event.text === text);

  for (const adapter of ['claude', 'codex']) {
    test(`on ${adapter}'s adapter the oldest goes in, the next only on the next press, each once`, () =>
      onFake(['--steering', adapter], async (conversation, events) => {
        conversation.send('slow');
        await until(() => saidIn(events).startsWith('Working'));
        conversation.send('Then the docs.');
        conversation.send('And the tests.');

        expect(conversation.steerQueued()).toStrictEqual('sent');
        await until(() => promptsIn(events).length === 2);

        expect(promptsIn(events)).toStrictEqual([
          ['slow', undefined],
          ['Then the docs.', firstTurn(events)],
        ]);
        expect(conversation.steerQueued()).toStrictEqual('sent');
        await until(() => promptsIn(events).length === 3);

        expect(promptsIn(events).at(-1)).toStrictEqual([
          'And the tests.',
          firstTurn(events),
        ]);
        expect(conversation.steerQueued()).toStrictEqual('none');
        conversation.interrupt();
        await ended(events, 1);
        expect(promptsIn(events)).toHaveLength(3);
      }));
  }

  test('nothing goes with no turn running, an empty queue, or only messages not the person’s', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      expect(conversation.steerQueued()).toStrictEqual('none');
      conversation.send('slow');
      await until(() => saidIn(events).startsWith('Working'));

      expect(conversation.steerQueued()).toStrictEqual('none');
      conversation.deliver(MAIN, 'From main.');

      expect(conversation.steerQueued()).toStrictEqual('none');
      expect(promptsIn(events)).toStrictEqual([['slow', undefined]]);
      conversation.interrupt();
      await ended(events, 1);
    }));

  test('on an agent that takes no steering it stays queued, nothing sent', () =>
    onFake([], async (conversation, events) => {
      conversation.send('slow');
      await until(() => saidIn(events).startsWith('Working'));
      conversation.send('Then the docs.');

      expect(conversation.steerQueued()).toStrictEqual('unsteerable');
      expect(rows(events, 'Then the docs.')).toHaveLength(1);
      expect(promptsIn(events)).toStrictEqual([['slow', undefined]]);
      conversation.interrupt();
      await ended(events, 1);
    }));

  test('refused while the turn runs, it and the one sent behind it go back to the top in their order, marked, and go first, once each', async () => {
    const stub = await steeringStub();
    const { conversation, events, steers, prompts } = stub;

    conversation.send('go');
    stub.go();
    await stub.settled();
    conversation.send('First.');
    conversation.send('Second.');
    conversation.send('Third.');

    expect(conversation.steerQueued()).toStrictEqual('sent');
    expect(conversation.steerQueued()).toStrictEqual('sent');
    await until(() => steers.length === 1);
    steers[0]!.answer('refused');
    await until(() => rows(events, 'Second.').length === 2);

    // The turn refused one: the second is not sent into it either.
    expect(steers).toHaveLength(1);
    expect(rows(events, 'First.').at(-1)).toMatchObject({ refused: true });
    expect(rows(events, 'Second.').at(-1)).toMatchObject({ refused: true });
    stub.end();
    await until(() => prompts.length === 4);

    expect(prompts).toStrictEqual(['go', 'First.', 'Second.', 'Third.']);
    expect(promptsIn(events).map(([text, into]) => [text, into])).toStrictEqual(
      [
        ['go', undefined],
        ['First.', undefined],
        ['Second.', undefined],
        ['Third.', undefined],
      ],
    );
    await conversation.close();
  });

  test("refused, it goes back where its row is: behind another agent's message queued before it, ahead of the rest", async () => {
    const stub = await steeringStub();
    const { conversation, events, steers, prompts } = stub;

    conversation.send('go');
    stub.go();
    await stub.settled();
    conversation.deliver(MAIN, 'From main.');
    conversation.send('Mine.');
    conversation.send('After.');
    conversation.steerQueued();
    await until(() => steers.length === 1);
    steers[0]!.answer('refused');
    await until(() => rows(events, 'Mine.').length === 2);
    stub.end();
    await until(() => prompts.length === 4);

    expect(promptsIn(events).map(([text]) => text)).toStrictEqual([
      'go',
      'From main.',
      'Mine.',
      'After.',
    ]);
    await conversation.close();
  });

  test('put back in one turn and refused again in the next, they keep the order they were queued in', async () => {
    const stub = await steeringStub(true);
    const { conversation, events, steers, prompts } = stub;

    conversation.send('go');
    stub.go();
    await stub.settled();
    conversation.send('A.');
    conversation.send('B.');
    conversation.send('C.');
    conversation.steerQueued();
    conversation.steerQueued();
    conversation.steerQueued();
    await until(() => steers.length === 1);
    steers[0]!.answer('refused');
    await until(() => rows(events, 'C.').length === 2);
    stub.end();
    await until(() => prompts.length === 2);
    await until(() => promptsIn(events).length === 2);

    // A runs as its own turn; B is sent into it, refused, and goes back.
    expect(conversation.steerQueued()).toStrictEqual('sent');
    await until(() => steers.length === 2);

    expect(steers[1]!.text).toStrictEqual('B.');
    steers[1]!.answer('refused');
    await until(() => rows(events, 'B.').length === 3);
    stub.end();
    await until(() => prompts.length === 3);
    stub.end();
    await until(() => prompts.length === 4);
    stub.end();

    expect(prompts).toStrictEqual(['go', 'A.', 'B.', 'C.']);
    await conversation.close();
  });

  for (const outcome of ['injected', 'refused'] as const) {
    test(`out when the turn ends, the end does not send it; ${outcome} late, it is ${outcome === 'injected' ? 'drawn in that turn' : 'the next turn, ahead of the rest'}, once`, async () => {
      const stub = await steeringStub();
      const { conversation, events, steers, prompts } = stub;

      conversation.send('go');
      stub.go();
      await stub.settled();
      conversation.send('Out.');
      conversation.send('Behind.');
      conversation.steerQueued();
      await until(() => steers.length === 1);
      stub.end();
      await ended(events, 1);
      await stub.settled();

      expect(prompts).toStrictEqual(['go']);
      steers[0]!.answer(outcome);
      await until(() => prompts.length === (outcome === 'injected' ? 2 : 3));

      expect(prompts).toStrictEqual(
        outcome === 'injected' ? ['go', 'Behind.'] : ['go', 'Out.', 'Behind.'],
      );
      expect(promptsIn(events)).toStrictEqual(
        outcome === 'injected'
          ? [
              ['go', undefined],
              ['Out.', firstTurn(events)],
              ['Behind.', undefined],
            ]
          : [
              ['go', undefined],
              ['Out.', undefined],
              ['Behind.', undefined],
            ],
      );
      // A late refusal is the next turn, which says so; no note.
      expect(
        rows(events, 'Out.').some((event) => 'refused' in event),
      ).toBeFalse();
      await conversation.close();
    });
  }

  test("its image and file link go with it into the turn on Codex's adapter", () =>
    onFake(
      ['--steering', 'codex'],
      async (conversation, events) => {
        conversation.send('slow');
        await until(() => saidIn(events).startsWith('Working'));
        conversation.send(
          'See @a.ts and [Image #1]',
          undefined,
          [{ mediaType: 'image/png', data: 'aGVsbG8=' }],
          ['a.ts'],
        );

        expect(conversation.steerQueued()).toStrictEqual('sent');
        await until(() =>
          saidIn(events).includes('Read the message from nobody.'),
        );

        expect(saidIn(events)).toContain(
          'Received an image: image/png, 5 bytes',
        );
        expect(saidIn(events)).toContain('Received a link: a.ts, file://');
        expect(promptsIn(events).at(-1)).toStrictEqual([
          'See @a.ts and [Image #1]',
          firstTurn(events),
        ]);
        conversation.interrupt();
        await ended(events, 1);
      },
      (session) => {
        writeFileSync(join(session.cwd, 'a.ts'), '');

        return session;
      },
    ));
});

describe('CHD-535 U1 tester: queued steering boundaries', () => {
  const queueRows = (events: readonly ConversationEvent[], text: string) =>
    events.flatMap((event) =>
      event.type === 'queued' && event.text === text ? [event] : [],
    );

  const sentRows = (events: readonly ConversationEvent[], text: string) =>
    events.flatMap((event) =>
      event.type === 'prompt' && event.text === text ? [event] : [],
    );

  for (const adapter of ['claude', 'codex']) {
    test(`${adapter} refusal or own-turn fallback keeps the original row, image and link exactly once`, async () => {
      const release = Promise.withResolvers<void>();
      let firstFinished = false;
      const outcomes: SteerOutcome[] = [];
      const promptInputs: Parameters<Session['prompt']>[] = [];
      const steerInputs: Parameters<Session['steer']>[] = [];
      const text = 'Queued [Image #1] @a.ts';

      try {
        await onFake(
          ['--steering', adapter],
          async (conversation, events) => {
            try {
              conversation.send('text');
              await until(() => firstFinished);
              expect(events.some((event) => event.type === 'result')).toBe(
                false,
              );
              conversation.send(
                text,
                undefined,
                [{ mediaType: 'image/png', data: 'aGVsbG8=' }],
                ['a.ts'],
              );
              conversation.send('After the attachment.');

              const original = queueRows(events, text)[0];

              assert(original !== undefined);
              expect(conversation.steerQueued()).toBe('sent');
              await until(() => outcomes.length === 1);
              expect(outcomes).toEqual([
                adapter === 'codex' ? 'startedNewTurn' : 'refused',
              ]);
              await until(() => queueRows(events, text).length >= 2);
              release.resolve();
              await ended(events, 3);

              const delivered = events.find(
                (event) => event.type === 'prompt' && event.text === text,
              );

              assert(delivered?.type === 'prompt');
              expect(delivered.turnId).toBe(original.turnId);
              expect(delivered.into).toBeUndefined();
              expect(steerInputs[0]?.slice(0, 3)).toEqual([
                text,
                [{ mediaType: 'image/png', data: 'aGVsbG8=' }],
                ['a.ts'],
              ]);

              const fallback = promptInputs.filter(([prompt]) =>
                prompt.includes(text),
              );

              expect(fallback).toHaveLength(1);
              expect(fallback[0]?.slice(1, 3)).toEqual([
                [{ mediaType: 'image/png', data: 'aGVsbG8=' }],
                ['a.ts'],
              ]);
              expect(promptsIn(events).map(([prompt]) => prompt)).toEqual([
                'text',
                text,
                'After the attachment.',
              ]);
              expect(
                new Set(queueRows(events, text).map((row) => row.turnId)),
              ).toEqual(new Set([original.turnId]));

              const reply = saidIn(
                events.filter(
                  (event) =>
                    event.type === 'update' &&
                    event.turnId === delivered.turnId,
                ),
              );

              expect(reply).toContain('Received an image: image/png, 5 bytes');
              expect(reply).toContain('Received a link: a.ts, file://');
              expect(
                events.filter((event) => event.type === 'self_started'),
              ).toHaveLength(adapter === 'codex' ? 1 : 0);
            } finally {
              release.resolve();
            }
          },
          (session) => {
            writeFileSync(join(session.cwd, 'a.ts'), '');

            const prompt = session.prompt.bind(session);
            const steer = session.steer.bind(session);
            let first = true;

            session.prompt = (...args) => {
              promptInputs.push(args);

              const turn = prompt(...args);

              if (!first) {
                return turn;
              }

              first = false;

              return {
                ...turn,
                result: turn.result.then(async (result) => {
                  firstFinished = true;

                  await release.promise;

                  return result;
                }),
              };
            };

            session.steer = async (...args) => {
              steerInputs.push(args);

              const outcome = await steer(...args);

              outcomes.push(outcome);

              return outcome;
            };

            return session;
          },
        );
      } finally {
        release.resolve();
      }
    });
  }

  test('two fake sessions keep accepted queue IDs and an interrupt independent', () =>
    onFake(['--steering', 'claude'], (first, firstEvents) =>
      onFake(['--steering', 'codex'], async (second, secondEvents) => {
        first.send('slow');
        second.send('slow');
        await until(() =>
          [firstEvents, secondEvents].every((events) =>
            saidIn(events).startsWith('Working'),
          ),
        );
        first.send('Only first queued.');
        first.send('Only first still waiting.');
        second.send('Only second queued.');

        const firstRow = queueRows(firstEvents, 'Only first queued.')[0];
        const secondRow = queueRows(secondEvents, 'Only second queued.')[0];

        assert(firstRow !== undefined && secondRow !== undefined);
        expect(first.steerQueued()).toBe('sent');
        expect(second.steerQueued()).toBe('sent');
        await until(() =>
          [firstEvents, secondEvents].every(
            (events) => promptsIn(events).length === 2,
          ),
        );
        first.interrupt();
        await ended(firstEvents, 1);
        expect(promptsIn(firstEvents).map(([text]) => text)).toEqual([
          'slow',
          'Only first queued.',
        ]);
        expect(promptsIn(secondEvents).map(([text]) => text)).toEqual([
          'slow',
          'Only second queued.',
        ]);
        expect(sentRows(firstEvents, 'Only first queued.')[0]?.turnId).toBe(
          firstRow.turnId,
        );
        expect(sentRows(secondEvents, 'Only second queued.')[0]?.turnId).toBe(
          secondRow.turnId,
        );
        expect(
          secondEvents.some((event) => event.type === 'queue_withdrawn'),
        ).toBe(false);
        expect(secondEvents.some((event) => event.type === 'result')).toBe(
          false,
        );
        second.interrupt();
        await ended(secondEvents, 1);
      }),
    ));

  test('Esc withdraws queued rows held behind calls but preserves the agent message between them', () =>
    onFake(['--steering', 'claude'], async (conversation, events) => {
      conversation.send('bashcut');
      await callOpen(events);
      conversation.send('First held row.');
      conversation.deliver(MAIN, 'Agent row.');
      conversation.send('Second held row.');

      const first = queueRows(events, 'First held row.')[0];
      const second = queueRows(events, 'Second held row.')[0];

      assert(first !== undefined && second !== undefined);
      expect(conversation.steerQueued()).toBe('sent');
      expect(conversation.steerQueued()).toBe('sent');
      await until(() =>
        ['First held row.', 'Second held row.'].every((text) =>
          queueRows(events, text).some((row) => row.afterCalls),
        ),
      );
      expect(
        new Set(queueRows(events, 'First held row.').map((row) => row.turnId)),
      ).toEqual(new Set([first.turnId]));
      expect(
        new Set(queueRows(events, 'Second held row.').map((row) => row.turnId)),
      ).toEqual(new Set([second.turnId]));
      conversation.interrupt();
      await ended(events, 2);
      expect(promptsIn(events).map(([text]) => text)).toEqual([
        'bashcut',
        'Agent row.',
      ]);
      expect(
        events.filter((event) => event.type === 'queue_withdrawn'),
      ).toHaveLength(1);
    }));

  test('late acceptance after clear cannot add the old row to the replacement session', async () => {
    const late = Promise.withResolvers<SteerOutcome>();
    const pids: number[] = [];
    let steers = 0;
    let opened = 0;

    try {
      await onFake(
        ['--steering', 'claude'],
        async (conversation, events) => {
          conversation.send('slow');
          await until(() => saidIn(events).startsWith('Working'));
          conversation.send('Old queued row.');
          expect(conversation.steerQueued()).toBe('sent');
          await until(() => steers === 1);
          conversation.clear();
          await until(
            () =>
              events.filter((event) => event.type === 'connected').length === 2,
          );

          const afterClear = events.length;

          late.resolve('injected');
          await settleQueued();
          expect(
            events
              .slice(afterClear)
              .some(
                (event) =>
                  (event.type === 'prompt' || event.type === 'queued') &&
                  event.text === 'Old queued row.',
              ),
          ).toBe(false);
          conversation.send('text');
          await until(() =>
            events.some(
              (event) =>
                event.type === 'result' &&
                event.turnId === sentRows(events, 'text').at(-1)?.turnId,
            ),
          );
          expect(promptsIn(events).map(([text]) => text)).toEqual([
            'slow',
            'text',
          ]);
        },
        (session) => {
          pids.push(...session.agentPids);

          if (++opened === 1) {
            session.steer = () => {
              steers++;

              return late.promise;
            };
          }

          return session;
        },
      );
    } finally {
      late.resolve('refused');
    }

    for (const pid of pids) {
      expect(await isAlive(pid)).toBe(false);
    }
  });

  test('a wedged fake turn keeps a refused queued row until Esc and closes every agent process', async () => {
    const pids: number[] = [];
    let sent = false;

    await onFake(
      ['--steering', 'claude', '--hang', 'turn'],
      async (conversation, events) => {
        conversation.send('text');
        await until(() => sent);
        conversation.send('After the wedged turn.');
        expect(conversation.steerQueued()).toBe('sent');
        await until(() =>
          queueRows(events, 'After the wedged turn.').some(
            (row) => row.refused,
          ),
        );
        expect(promptsIn(events).map(([text]) => text)).toEqual(['text']);
        conversation.interrupt();
        expect(events).toContainEqual({ type: 'queue_withdrawn' });
      },
      (session) => {
        pids.push(...session.agentPids);

        const prompt = session.prompt.bind(session);

        session.prompt = (...args) => {
          const turn = prompt(...args);

          return {
            ...turn,
            sent: turn.sent.then((links) => {
              sent = true;

              return links;
            }),
          };
        };

        return session;
      },
    );
    expect(pids.length).toBeGreaterThan(0);

    for (const pid of pids) {
      expect(await isAlive(pid)).toBe(false);
    }
  });
});

/**
 * The steps the conversation's tests share on the fake agent:
 * `conversation_test.ts` and the files split from it (CHD-501).
 */
import { execFile } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { type McpServer, type SessionUpdate } from '@agentclientprotocol/sdk';
import type { AgentOption } from '../../src/session/config.ts';
import {
  Conversation,
  type ConversationEvent,
} from '../../src/session/conversation.ts';
import type { PendingElicitation } from '../../src/session/elicitations.ts';
import type { PendingPermission } from '../../src/session/permissions.ts';
import {
  openSession,
  type Session,
  type SteerOutcome,
} from '../../src/session/session.ts';
import { TaskAgent, type TaskSession } from '../../src/session/tasks.ts';
import { type TurnResult } from '../../src/session/transcript/types.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';

/**
 * A session with one option, `effort`, held in memory, that answers a change
 * as the agent would, with the option as it now stands.
 */
export function heldSession() {
  const state = { current: 'medium' };
  const snapshot = (): AgentOption[] => [
    {
      id: 'effort',
      name: 'Effort',
      current: state.current,
      values: ['low', 'medium', 'high'].map((value) => ({
        value,
        name: value.charAt(0).toUpperCase() + value.slice(1),
      })),
    },
  ];
  const session = {
    id: 'held',
    heldBack: [],
    permissions: { subscribe: () => () => {} },
    elicitations: { subscribe: () => () => {} },
    plans: { subscribe: () => () => {} },
    subscribe: () => () => {},
    history: () => [],
    // Its agent never goes on its own.
    exited: new Promise<void>(() => {}),
    takesImages: () => false,
    modes: () => undefined,
    commands: () => [],
    models: () => undefined,
    options: snapshot,
    setOption: (_id: string, value: string) => {
      state.current = value;

      return Promise.resolve();
    },
    close: () => Promise.resolve(),
  } as unknown as Session;

  return { session, state };
}

/**
 * Until `check` holds, looked at on every turn of the event loop; it gives
 * up after `timeout` ms on the monotonic clock, naming the check, so a wait
 * that never ends fails rather than hanging the file (CHD-501).
 */
export async function until(
  check: () => boolean,
  timeout = 10_000,
): Promise<void> {
  const deadline = performance.now() + timeout;

  while (!check()) {
    if (performance.now() > deadline) {
      throw new Error(`timed out waiting for ${String(check)}`);
    }

    await new Promise((resolve) => setTimeout(resolve, 0));
  }
}

/**
 * Lets a prompt just sent go to the agent: until it has, its turn takes no
 * message.
 */
export function went(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

export function isAlive(pid: number): Promise<boolean> {
  return new Promise((resolve) => {
    execFile('ps', ['-p', String(pid)], (error) => resolve(error === null));
  });
}

/** A parent up on a held session, with the events it reports. */
export async function parentUp() {
  const { session } = heldSession();
  const events: ConversationEvent[] = [];
  const parent = new Conversation(
    () => Promise.resolve(session),
    (event) => events.push(event),
    () => 7,
  );

  parent.start();
  await until(() => events.some((event) => event.type === 'connected'));

  return { parent, events };
}

/** Task `id` adopted by `parent`, on a session that keeps what it was asked. */
export function adoptTask(parent: Conversation, id: string) {
  const asked: string[] = [];
  const session: TaskSession = {
    start: () => {},
    send: (text) => asked.push(`send ${text}`) > 0,
    interrupt: () => asked.push('interrupt'),
    choose: (request, option) => asked.push(`choose ${request} ${option}`),
    reject: (request) => asked.push(`reject ${request}`),
    answer: (request) => asked.push(`answer ${request}`),
    close: () => {
      asked.push('close');

      return Promise.resolve();
    },
  };
  const task = new TaskAgent(
    { id, name: id, runtime: 'fake', prompt: 'job' },
    parent.taskParent(id),
    () => 7,
  );

  parent.adopt(task, session);

  return { task, asked };
}

export async function onFake(
  flags: string[],
  body: (
    conversation: Conversation,
    events: ConversationEvent[],
  ) => Promise<void>,
  watch: (session: Session) => Session = (session) => session,
  mcpServers: readonly McpServer[] = [],
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-conversation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    async () =>
      watch(
        await openSession({
          agent: 'fake',
          cwd: dir,
          agentCommand: fakeAgentCommand(undefined, ...flags),
          mcpServers,
        }),
      ),
    (event) => events.push(event),
  );

  try {
    conversation.start();
    await until(() => events.some((event) => event.type === 'connected'));
    await body(conversation, events);
  } finally {
    await conversation.close();
    await rm(dir, { recursive: true });
  }
}

/** The text of every agent message chunk among `events`, joined. */
export function saidIn(events: readonly ConversationEvent[]): string {
  return events
    .map((event) =>
      event.type === 'update' &&
      event.update.sessionUpdate === 'agent_message_chunk' &&
      event.update.content.type === 'text'
        ? event.update.content.text
        : '',
    )
    .join('');
}

export const MAIN = { name: 'main', reachable: true } as const;

/**
 * The order of a call's end, the messages that went into the turn and the
 * turn's end among `events`.
 */
export function steerOrder(events: readonly ConversationEvent[]): string[] {
  return events.flatMap((event) =>
    event.type === 'update' &&
    event.update.sessionUpdate === 'tool_call_update' &&
    event.update.status === 'completed'
      ? ['call ended']
      : event.type === 'prompt' && event.into !== undefined
        ? [`into: ${event.text}`]
        : event.type === 'result'
          ? ['ended']
          : [],
  );
}

/** Until the turn on the fake has its call open. */
export async function callOpen(
  events: readonly ConversationEvent[],
): Promise<void> {
  await until(() =>
    events.some(
      (event) =>
        event.type === 'update' &&
        event.update.sessionUpdate === 'tool_call_update' &&
        event.update.status === 'in_progress',
    ),
  );
}

/** Each prompt's text among `events`, with the turn it went into. */
export function promptsIn(
  events: readonly ConversationEvent[],
): [string, string | undefined][] {
  return events.flatMap((event) =>
    event.type === 'prompt' ? [[event.text, event.into]] : [],
  );
}

/**
 * A session that steers, whose first turn runs until `end`, with every
 * steer's answer and its prompt's going out in the test's hands, and its
 * permissions and forms asked from the test.
 */
export async function steeringStub() {
  const { session } = heldSession();
  const { promise: ended, resolve: end } = Promise.withResolvers<TurnResult>();
  const { promise: went, resolve: go } =
    Promise.withResolvers<readonly never[]>();
  const permissions: ((request: PendingPermission) => void)[] = [];
  const elicitations: ((request: PendingElicitation) => void)[] = [];
  const updates: ((update: SessionUpdate) => void)[] = [];
  const steers: {
    readonly text: string;
    readonly answer: (outcome: SteerOutcome) => void;
  }[] = [];
  const prompts: string[] = [];
  const steering = Object.assign(session, {
    permissions: {
      subscribe: (listener: (request: PendingPermission) => void) => {
        permissions.push(listener);

        return () => {};
      },
    },
    elicitations: {
      subscribe: (listener: (request: PendingElicitation) => void) => {
        elicitations.push(listener);

        return () => {};
      },
    },
    plans: { subscribe: () => () => {} },
    subscribe: (listener: (update: SessionUpdate) => void) => {
      updates.push(listener);

      return () => {};
    },
    steers: () => true,
    steer: (text: string) => {
      const { promise, resolve } = Promise.withResolvers<SteerOutcome>();

      steers.push({ text, answer: resolve });

      return promise;
    },
    cancel: () => Promise.resolve(),
    prompt: (text: string) => {
      prompts.push(text);

      return {
        id: text,
        sent: prompts.length === 1 ? went : Promise.resolve([]),
        result:
          prompts.length === 1
            ? ended
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

  const ask = (id: string) => {
    for (const listener of permissions) {
      listener({
        id,
        sessionId: 'held',
        toolCall: { toolCallId: id, title: 'Write notes.txt' },
        options: [{ optionId: 'allow', name: 'Allow', kind: 'allow_once' }],
        signal: new AbortController().signal,
        resolve: () => {},
        reject: () => {},
      });
    }
  };

  const form = (id: string) => {
    for (const listener of elicitations) {
      listener({
        id,
        wait: { id } as unknown as PendingElicitation['wait'],
        signal: new AbortController().signal,
        answer: () => {},
      });
    }
  };

  const say = (text: string) => {
    for (const listener of updates) {
      listener({
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text },
      });
    }
  };

  const settled = () => new Promise((resolve) => setTimeout(resolve, 10));

  return {
    conversation,
    events,
    steers,
    prompts,
    go: () => go([]),
    end: () => end({ status: 'completed', stopReason: 'end_turn' }),
    ask,
    form,
    say,
    settled,
  };
}

/** Until `count` turns have ended among `events`. */
export function ended(events: readonly ConversationEvent[], count: number) {
  return until(
    () => events.filter((event) => event.type === 'result').length === count,
  );
}

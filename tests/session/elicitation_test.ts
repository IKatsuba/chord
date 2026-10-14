import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  Conversation,
  type ConversationEvent,
  ranOut,
} from '../../src/session/conversation.ts';
import type {
  ElicitationReply,
  PendingElicitation,
} from '../../src/session/elicitations.ts';
import type { QuestionsAgent } from '../../src/session/questions.ts';
import { openSession, type Session } from '../../src/session/session.ts';
import { reduceTranscript } from '../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type ElicitationWait,
  type Entry,
  type TranscriptAction,
} from '../../src/session/transcript/types.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';
import { FORM_SCHEMA, LINK_URL } from '../fixtures/forms.ts';
import { run, said as saidIn } from '../fixtures/recorder.ts';
import {
  CLAUDE_QUESTION,
  CLAUDE_QUESTIONS,
  CODEX_QUESTIONS,
  DIMCODE_QUESTIONS,
  DROID_QUESTIONS,
  OPENCODE_QUESTIONS,
  type QuestionForm,
} from '../fixtures/questions.ts';

async function withSession(body: (session: Session) => Promise<void>) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-elicitation-'));
  const session = await openSession({
    agent: 'fake',
    cwd: dir,
    agentCommand: fakeAgentCommand(),
  });

  try {
    await body(session);
  } finally {
    await session.close();
    await rm(dir, { recursive: true });
  }
}

/**
 * Plays `scenario`, answering its request with `answer` a moment after it
 * arrives, as a key press would; returns the request and what the agent said.
 */
async function answered(
  session: Session,
  scenario: string,
  answer: ElicitationReply,
): Promise<{ request: PendingElicitation; said: string }> {
  let request: PendingElicitation | undefined;

  const unsubscribe = session.elicitations.subscribe((pending) => {
    request = pending;

    setTimeout(() => pending.answer(answer), 10);
  });

  const said = saidIn(
    (await run(session, scenario).finally(unsubscribe)).updates,
  ).join('');

  assert(request);

  return { request, said };
}

test('a form request reaches the interface with its schema', () =>
  withSession(async (session) => {
    const { request } = await answered(session, 'form', { action: 'cancel' });

    expect(request.wait.mode).toStrictEqual('form');
    expect(request.wait.message).toStrictEqual('Set up the deploy target');
    assert(request.wait.mode === 'form');
    expect(request.wait.schema).toStrictEqual(FORM_SCHEMA);
  }));

test('an accepted form reaches the agent with its content', () =>
  withSession(async (session) => {
    const content = { name: 'web-app', replicas: 3, region: 'us' };
    const { said } = await answered(session, 'form', {
      action: 'accept',
      content,
    });

    expect(said).toStrictEqual(
      `Elicitation answer: accept  \n${JSON.stringify(content)}`,
    );
  }));

test('a declined or cancelled form reaches the agent as such', () =>
  withSession(async (session) => {
    for (const action of ['decline', 'cancel'] as const) {
      const { said } = await answered(session, 'form', { action });

      expect(said).toStrictEqual(`Elicitation answer: ${action}`);
    }
  }));

test('a link request carries the link, and nothing opens it', () =>
  withSession(async (session) => {
    const { request, said } = await answered(session, 'link', {
      action: 'decline',
    });

    assert(request.wait.mode === 'url');
    expect(request.wait.url).toStrictEqual(LINK_URL);
    expect(request.wait.message).toStrictEqual(
      'Sign in to Example to continue',
    );
    expect(said).toStrictEqual('Elicitation answer: decline');
  }));

test('cancelling the turn aborts its open form', () =>
  withSession(async (session) => {
    const asked = new Promise<PendingElicitation>((resolve) =>
      session.elicitations.subscribe(resolve),
    );
    const turn = session.prompt('form');
    const request = await asked;

    await turn.cancel();
    expect(request.signal.aborted).toBeTruthy();
    expect((await turn.result).status).toStrictEqual('cancelled');
  }));

/**
 * A conversation on the fake agent, its events folded into a transcript as
 * the window folds them; `onAsked` meets each form as the person would.
 */
async function conversing(
  body: (
    conversation: Conversation,
    events: ConversationEvent[],
  ) => Promise<void>,
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-elicitation-'));
  const events: ConversationEvent[] = [];
  const conversation = new Conversation(
    () =>
      openSession({
        agent: 'fake',
        cwd: dir,
        agentCommand: fakeAgentCommand(),
      }),
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

async function until(check: () => boolean): Promise<void> {
  while (!check()) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

const TRANSCRIPT_EVENTS = new Set([
  'prompt',
  'update',
  'elicitation_requested',
  'elicitation_settled',
  'cancel',
  'result',
]);

function entries(events: readonly ConversationEvent[]): readonly Entry[] {
  return events
    .filter((event): event is TranscriptAction =>
      TRANSCRIPT_EVENTS.has(event.type),
    )
    .reduce(reduceTranscript, emptyTranscript).entries;
}

function asked(events: readonly ConversationEvent[]) {
  return events.flatMap((event) =>
    event.type === 'elicitation_requested' ? [event.elicitation] : [],
  );
}

test('an answered form leaves its record, and the agent goes on', () =>
  conversing(async (conversation, events) => {
    conversation.send('form');
    await until(() => asked(events).length > 0);

    const [wait] = asked(events);

    conversation.answer(wait!.id, {
      action: 'accept',
      content: { name: 'web-app' },
    });
    await until(() => events.some((event) => event.type === 'result'));

    const [, record, echo] = entries(events);

    expect(record?.kind === 'elicitation' && record.outcome).toStrictEqual(
      'accepted',
    );
    expect(record?.kind === 'elicitation' && record.content).toStrictEqual({
      name: 'web-app',
    });
    expect(echo?.kind === 'assistant' && echo.text).toStrictEqual(
      'Elicitation answer: accept  \n{"name":"web-app"}',
    );
  }));

test('an interrupt takes the open form with it, recorded as cancelled', () =>
  conversing(async (conversation, events) => {
    conversation.send('form');
    await until(() => asked(events).length > 0);
    conversation.interrupt();
    await until(() => events.some((event) => event.type === 'result'));

    const settled = events.find(
      (event) => event.type === 'elicitation_settled',
    );

    expect(
      settled?.type === 'elicitation_settled' && settled.answer,
    ).toStrictEqual({
      type: 'withdrawn',
    });
    expect(
      entries(events).map((entry) =>
        entry.kind === 'elicitation'
          ? `${entry.kind}:${entry.outcome}`
          : entry.kind,
      ),
    ).toStrictEqual(['user', 'elicitation:cancelled', 'cancelled']);
  }));

test("each adapter's question form reaches the interface with its questions read, and its answer goes back as given", () =>
  withSession(async (session) => {
    for (const [scenario, agent] of [
      ['askclaude', 'claude'],
      ['askclaudeone', 'claude'],
      ['askcodex', 'codex'],
      ['askdroid', 'droid'],
      ['askopencode', 'opencode'],
      ['askdimcode', 'dimcode'],
    ] as const) {
      const content = { picked: 'yes' };
      const { request, said } = await answered(session, scenario, {
        action: 'accept',
        content,
      });

      assert(request.wait.mode === 'form');
      expect(request.wait.questions?.agent).toStrictEqual(agent);
      expect(said).toStrictEqual(
        `Elicitation answer: accept  \n${JSON.stringify(content)}`,
      );
    }
  }));

test("a form with no adapter's marks reaches the interface with no questions", () =>
  withSession(async (session) => {
    const { request } = await answered(session, 'form', { action: 'cancel' });

    assert(request.wait.mode === 'form');
    expect(request.wait.questions).toBeUndefined();
  }));

describe('CHD-1 tester: question request round trips', () => {
  const cases: {
    scenario: string;
    agent: QuestionsAgent;
    form: QuestionForm;
    content: Record<string, string | string[]>;
  }[] = [
    {
      scenario: 'askclaude',
      agent: 'claude',
      form: CLAUDE_QUESTIONS,
      content: {
        question_0: 'Python',
        question_0_custom: 'portable',
        question_1: ['Types', 'Tests'],
        question_1_custom: 'lint later',
      },
    },
    {
      scenario: 'askclaudeone',
      agent: 'claude',
      form: CLAUDE_QUESTION,
      content: { question_0: 'Deno', question_0_custom: 'from source' },
    },
    {
      scenario: 'askcodex',
      agent: 'codex',
      form: CODEX_QUESTIONS,
      content: {
        next: 'Review existing work',
        next_note: 'tests first',
        token: 'fake-secret-for-tests',
      },
    },
    {
      scenario: 'askdroid',
      agent: 'droid',
      form: DROID_QUESTIONS,
      content: {
        question_0: 'other',
        question_0_other: 'NFS',
        question_1: ['option_0', 'other'],
        question_1_other: 'HEIC',
        question_2: 'uploads',
      },
    },
    {
      scenario: 'askopencode',
      agent: 'opencode',
      form: OPENCODE_QUESTIONS,
      content: { q0: 'Beside the module', q0_custom: 'with fixtures' },
    },
    {
      scenario: 'askdimcode',
      agent: 'dimcode',
      form: DIMCODE_QUESTIONS,
      content: { __custom_0: 'Preview environment' },
    },
  ];

  const deliveredSchema = (entry: (typeof cases)[number]) => {
    const schema = structuredClone(entry.form.requestedSchema);

    if (entry.agent === 'droid') {
      const formats = schema.properties?.question_1;

      assert(formats !== undefined);
      // The SDK strips this pre-existing keyword after the raw relay kept it.
      // The generic multi-select's checkbox toggles keep its picks unique.
      Reflect.deleteProperty(formats, 'uniqueItems');
    }

    return schema;
  };

  test('six sessions ask concurrently and return their own field ids and content unchanged', async () => {
    await Promise.all(
      cases.map((entry) =>
        withSession(async (session) => {
          const { request, said } = await answered(session, entry.scenario, {
            action: 'accept',
            content: entry.content,
          });

          assert(request.wait.mode === 'form');
          expect(request.wait.schema).toStrictEqual(deliveredSchema(entry));
          expect(request.wait.message).toBe(entry.form.message);
          expect(request.wait.questions?.agent).toBe(entry.agent);
          expect(said).toBe(
            `Elicitation answer: accept  \n${JSON.stringify(entry.content)}`,
          );
        }),
      ),
    );
  });

  for (const entry of cases) {
    test(`${entry.scenario}: cancellation rejects a late answer and the next request is independent`, () =>
      withSession(async (session) => {
        let receive: (pending: PendingElicitation) => void = () => {};

        const pending = new Promise<PendingElicitation>((resolve) => {
          receive = resolve;
        });

        const unsubscribe = session.elicitations.subscribe(receive);
        const first = session.prompt(entry.scenario);
        const request = await pending;

        unsubscribe();
        await first.cancel();
        expect(request.signal.aborted).toBe(true);
        expect((await first.result).status).toBe('cancelled');
        request.answer({ action: 'accept', content: { stale: 'late answer' } });

        const next = await answered(session, entry.scenario, {
          action: 'accept',
          content: entry.content,
        });

        expect(next.request.id).not.toBe(request.id);
        assert(next.request.wait.mode === 'form');
        expect(next.request.wait.schema).toStrictEqual(deliveredSchema(entry));
        expect(next.request.wait.questions?.agent).toBe(entry.agent);
        expect(next.said).toBe(
          `Elicitation answer: accept  \n${JSON.stringify(entry.content)}`,
        );
        expect(next.said).not.toContain('late answer');
      }));
  }
});

test("a form is read as timed out only once the agent's whole wait has passed", () => {
  const wait = (expiresInMs?: number): ElicitationWait => ({
    id: 'e',
    mode: 'form',
    message: 'Questions',
    schema: { type: 'object', properties: {} },
    ...(expiresInMs === undefined
      ? {}
      : { questions: { agent: 'codex', questions: [], expiresInMs } }),
  });

  expect(ranOut(wait(300_000), 299_100)).toStrictEqual(false);
  expect(ranOut(wait(300_000), 300_000)).toStrictEqual(true);
  expect(ranOut(wait(300_000), 301_000)).toStrictEqual(true);
  // A wait shorter than a second: withdrawn before it ends is a cancel.
  expect(ranOut(wait(300), 10)).toStrictEqual(false);
  expect(ranOut(wait(300), 300)).toStrictEqual(true);
  expect(ranOut(wait(), 1_000_000)).toStrictEqual(false);
});

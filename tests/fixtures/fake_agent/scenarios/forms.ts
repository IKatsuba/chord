/** Elicitations: a form to fill in and a link to open. */
import * as acp from '@agentclientprotocol/sdk';
import { FORM_SCHEMA, LINK_URL } from '../../forms.ts';
import {
  CLAUDE_QUESTION,
  CLAUDE_QUESTIONS,
  CODEX_QUESTIONS,
  DIMCODE_QUESTIONS,
  DROID_QUESTIONS,
  OPENCODE_QUESTIONS,
  type QuestionForm,
} from '../../questions.ts';
import { STEP_MS } from '../options.ts';
import { pause, type Play, type Turn } from '../turn.ts';
import { GATE_RELEASE, gateOpened } from './agents.ts';

/**
 * Asks the client for input and says what came back: the action, and an
 * accepted form's content as one line of JSON.
 */
async function elicit(
  turn: Turn,
  request: acp.CreateElicitationRequest,
): Promise<acp.StopReason> {
  const answer = await turn.client.request('elicitation/create', request);

  // The client answers `cancel` for a turn being cancelled; the turn ends so.
  if (turn.signal.aborted) {
    return 'cancelled';
  }

  // A link accepted is done once the person has been there, which only the
  // agent learns; it says so, as ACP's `elicitation/complete`.
  if (request.mode === 'url' && answer.action === 'accept') {
    await turn.client.notify('elicitation/complete', {
      elicitationId: request.elicitationId,
    });
  }

  // A hard break, so the content starts a line of its own.
  const content =
    answer.action === 'accept' && answer.content
      ? `  \n${JSON.stringify(answer.content)}`
      : '';

  await turn.say(`Elicitation answer: ${answer.action}${content}`);

  return 'end_turn';
}

/** Asks an adapter's question form, as that adapter sends it. */
function ask(form: QuestionForm): Play {
  return async (turn) =>
    await elicit(turn, { ...form, sessionId: turn.sessionId });
}

/** Each of claude's questions by its field, with its text. */
function claudeQuestions(form: QuestionForm): [string, string][] {
  const properties = Object.entries(form.requestedSchema.properties ?? {});

  return properties
    .filter(([key]) => /^question_\d+$/.test(key))
    .map(([key, property]) => [
      key,
      (property as { description?: string }).description ?? form.message,
    ]);
}

/**
 * Asks claude's questions as claude-agent-acp 0.93.0 does: AskUserQuestion's
 * tool call first, titled `Asking for your input`, or by the question when
 * there is one, its questions as its content; then the form, under that call;
 * then the call's result, the tool's text for what was answered, or its
 * failure when the person cancelled; then what came back, as `elicit` says.
 */
function askClaude(form: QuestionForm): Play {
  return async (turn) => {
    const toolCallId = turn.callId('ask');
    const questions = claudeQuestions(form);
    const [lone] = questions;

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      title:
        questions.length === 1 && lone !== undefined
          ? lone[1]
          : 'Asking for your input',
      kind: 'other',
      status: 'pending',
      rawInput: {
        questions: questions.map(([, text]) => ({ question: text })),
      },
      content: questions.map(([, text]) => ({
        type: 'content',
        content: { type: 'text', text },
      })),
    });

    const answer = await turn.client.request('elicitation/create', {
      ...form,
      sessionId: turn.sessionId,
      toolCallId,
    });

    if (turn.signal.aborted) {
      return 'cancelled';
    }

    const content = new Map<string, unknown>(
      Object.entries(answer.action === 'accept' ? (answer.content ?? {}) : {}),
    );
    const answered = questions.flatMap(([key, text]) => {
      const value = content.get(key);

      return value === undefined
        ? []
        : [
            `"${text}"="${Array.isArray(value) ? value.join(', ') : String(value)}"`,
          ];
    });

    const result =
      answer.action === 'cancel'
        ? 'Tool use aborted'
        : `User has answered your questions: ${answered.join(', ')}. You can now continue with the user's answers in mind.`;

    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      status: answer.action === 'cancel' ? 'failed' : 'completed',
      content: [{ type: 'content', content: { type: 'text', text: result } }],
    });

    const echoed =
      answer.action === 'accept' && answer.content
        ? `  \n${JSON.stringify(answer.content)}`
        : '';

    await turn.say(`Elicitation answer: ${answer.action}${echoed}`);

    return 'end_turn';
  };
}

/**
 * `leftform`'s play: the form asked, then the turn ended with it open,
 * after a while, or with `gated` once the test opens the gate.
 */
async function leftForm(turn: Turn, gated: boolean): Promise<acp.StopReason> {
  const { client, sessionId } = turn;

  void (async () => {
    try {
      const answer = await client.request('elicitation/create', {
        sessionId,
        mode: 'form',
        message: 'Set up the deploy target',
        requestedSchema: FORM_SCHEMA,
      });

      await client.notify('session/update', {
        sessionId,
        update: {
          sessionUpdate: 'agent_message_chunk',
          content: {
            type: 'text',
            text: `Elicitation answer: ${answer.action}`,
          },
        },
      });
    } catch {
      // The client went before it was answered.
    }
  })();

  if (gated) {
    await gateOpened(turn, GATE_RELEASE);
  } else {
    await pause(turn.signal, STEP_MS * 100);
  }

  await turn.say('I asked; the turn ends with the form open.');

  return 'end_turn';
}

export const FORMS = {
  // Each adapter's question form, as `tests/fixtures/questions.ts` has it.
  askclaude: askClaude(CLAUDE_QUESTIONS),
  askclaudeone: askClaude(CLAUDE_QUESTION),
  askcodex: ask(CODEX_QUESTIONS),
  askdroid: ask(DROID_QUESTIONS),
  askopencode: ask(OPENCODE_QUESTIONS),
  askdimcode: ask(DIMCODE_QUESTIONS),

  // codex's questions with a wait of 300 ms, which it withdraws once the
  // wait has run out, as codex-acp does, and answers for the person.
  async askcodexwait(turn) {
    const wait = 300;
    const timer = new AbortController();
    // Withdrawn as the wait ends, with no margin, as codex withdraws it.
    const timeout = setTimeout(() => timer.abort(), wait);
    const answer = await turn.client
      .request(
        'elicitation/create',
        {
          ...CODEX_QUESTIONS,
          _meta: { codex: { autoResolutionMs: wait } },
          sessionId: turn.sessionId,
        },
        { cancellationSignal: timer.signal },
      )
      .catch(() => undefined)
      .finally(() => clearTimeout(timeout));

    await turn.say(
      timer.signal.aborted
        ? 'Elicitation answer: timed out'
        : `Elicitation answer: ${answer?.action ?? 'none'}`,
    );

    return 'end_turn';
  },

  // The form asked in its turn, which then ends with it open, as an agent
  // may: the form outlives the turn (the owner's Q53, CHD-158), and its
  // answer is said once it comes.
  leftform: (turn) => leftForm(turn, false),

  // As `leftform`, its turn ending only once the test writes
  // `GATE_RELEASE`, so a test sees the form within its turn however slow
  // it is (CHD-399).
  leftformgated: (turn) => leftForm(turn, true),

  // A form with a field of each kind, then what came back, so a capture
  // shows the round trip.
  async form(turn) {
    return await elicit(turn, {
      sessionId: turn.sessionId,
      mode: 'form',
      message: 'Set up the deploy target',
      requestedSchema: FORM_SCHEMA,
    });
  },

  // A link to open; the client opens nothing without a key press.
  async link(turn) {
    return await elicit(turn, {
      sessionId: turn.sessionId,
      mode: 'url',
      elicitationId: turn.callId('link'),
      message: 'Sign in to Example to continue',
      url: LINK_URL,
    });
  },
} satisfies Record<string, Play>;

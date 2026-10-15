/**
 * Task agents: a session that starts one on the fake runtime through chord's
 * `spawn_task`, and the task's own turn, which messages its parent through
 * `send_message` before its report.
 */
import * as acp from '@agentclientprotocol/sdk';
import { STEP_MS } from '../options.ts';
import { pause, type Play, type Turn } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';

/** A task's pace: 20 steps, a tenth of a second by default. */
const TASK_STEP_MS = STEP_MS * 20;

/** What `task` asks for: the fake runtime, its small model, `taskchild`. */
export const TASK_ARGS = {
  agent: 'fake',
  model: 'fake-small',
  prompt: 'taskchild',
  name: 'Fix the tokenizer',
};

/** What the task says to its parent while it works. */
export const TASK_MESSAGE =
  'Found it: a string at the end of a line lost its closing quote. ' +
  'Fixing src/parse/tokenize.ts now.';

/** The task's report, its last message. */
export const TASK_REPORT =
  'The tokenizer dropped a closing quote when a string ended the line. ' +
  'Fixed in src/parse/tokenize.ts, with two cases added to ' +
  'tests/parse/tokenize_test.ts. deno task test passes.';

/** Why the task fails when the person denies its write. */
export const TASK_FAILURE =
  'The edit to src/parse/tokenize.ts was denied, so the tokenizer is not fixed.';

/** A call of the task's own, done after a step. */
async function work(
  turn: Turn,
  title: string,
  kind: acp.ToolKind,
  output: string,
): Promise<void> {
  const toolCallId = turn.callId(kind);

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    title,
    kind,
    status: 'in_progress',
  });
  await pause(turn.signal, TASK_STEP_MS);
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'completed',
    content: [{ type: 'content', content: { type: 'text', text: output } }],
  });
}

export const TASKS = {
  // Starts `taskchild` as a task agent, says so, and works on a while, so
  // the task's message comes during the turn and waits behind it.
  async task(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await turn.say('I will send a task agent on fake for the fix.');
      await callChord(turn, client, 'spawn_task', TASK_ARGS);
      await turn.say('It is running; I will check its report when it lands.');
      await pause(turn.signal, TASK_STEP_MS * 30);
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // A call of its own titled as claude's question call, never asked, then
  // a task whose job is `askclaude`. Played first in a session, the
  // parent's call and the task's question call share the id `ask-1`, as
  // each session numbers its own calls.
  async taskask(turn) {
    const toolCallId = turn.callId('ask');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      title: 'Asking for your input',
      kind: 'other',
      status: 'completed',
      content: [
        {
          type: 'content',
          content: { type: 'text', text: "The parent's own call." },
        },
      ],
    });

    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'spawn_task', {
        ...TASK_ARGS,
        prompt: 'askclaude',
        name: 'Ask the person',
      });
      await turn.say('It is asking; I will read its report when it lands.');
      await pause(turn.signal, TASK_STEP_MS * 30);
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // chord's tools as calls an agent makes: both lists, the models of the
  // fake runtime, the sessions, and a task on a runtime chord does not know,
  // which chord refuses.
  async chordcalls(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'list_agents', {});
      await callChord(turn, client, 'list_agents', { agent: 'fake' });
      await callChord(turn, client, 'list_sessions', {});
      await callChord(turn, client, 'spawn_task', {
        ...TASK_ARGS,
        agent: 'fakx',
      });
      await turn.say('chord knows no fakx.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // A task's job: two calls, a write it asks the person for, a message to
  // its parent, a test run, then the report. A denied write fails the turn,
  // so the parent gets a failed report.
  async taskchild(turn) {
    const client = await chordClient(turn);

    try {
      await work(
        turn,
        'Search tokenize in src/parse',
        'search',
        'src/parse/tokenize.ts',
      );
      await work(turn, 'Read src/parse/tokenize.ts', 'read', '120 lines');

      const toolCallId = turn.callId('edit');
      const toolCall: acp.ToolCall = {
        toolCallId,
        title: 'Edit src/parse/tokenize.ts',
        kind: 'edit',
        status: 'pending',
        locations: [{ path: 'src/parse/tokenize.ts' }],
      };

      await turn.send({ sessionUpdate: 'tool_call', ...toolCall });

      const answer = await turn.client.request('session/request_permission', {
        sessionId: turn.sessionId,
        toolCall,
        options: [
          { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
          { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
        ],
      });

      if (answer.outcome.outcome === 'cancelled') {
        return 'cancelled';
      }

      const allowed = answer.outcome.optionId === 'allow';

      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId,
        status: allowed ? 'completed' : 'failed',
      });

      if (!allowed) {
        throw new acp.RequestError(-32603, TASK_FAILURE);
      }

      if (client !== undefined) {
        await callChord(turn, client, 'send_message', { text: TASK_MESSAGE });
      }

      await work(turn, '`deno task test`', 'execute', '214 passed, 0 failed');
      await pause(turn.signal, TASK_STEP_MS * 10);
      await turn.say(TASK_REPORT);
    } finally {
      await client?.close();
    }

    return 'end_turn';
  },
} satisfies Record<string, Play>;

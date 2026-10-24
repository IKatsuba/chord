/**
 * Task agents: a session that starts one on the fake runtime through chord's
 * `spawn_task`, and the task's own turn, which messages its parent through
 * `send_message` before its report.
 */
import { once } from 'node:events';
import * as acp from '@agentclientprotocol/sdk';
import { STEP_MS } from '../options.ts';
import { steeredInto } from '../sessions.ts';
import { lifetime, pause, type Play, type Turn } from '../turn.ts';
import { codexCall, callChord, chordClient } from './chord_tools.ts';

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

/** What `tasklong` asks for: a task that works on, asking nothing. */
export const LONG_TASK_ARGS = {
  agent: 'fake',
  prompt: 'taskwait',
  name: 'Watch the build',
};

/**
 * A task name of about 600 characters, which wraps to more lines than the
 * background frame holds at 80x24 (CHD-430).
 */
export const TALL_TASK_NAME =
  'Rewrite the tokenizer as a single pass over the source that reads every token, string and comment once, keeping the line and column of each one so the parser can point at the exact place a mistake starts, with the old lookahead buffer replaced by a small ring of the last three tokens, the escapes inside strings decoded where they are read rather than in a second walk, the numbers parsed with their radix and separators checked as they come, every error message reworded to say what was expected and what was found instead, with the positions kept for the error messages the parser prints, and the old two-pass reader removed together';

/** `taskstays`' play, its task started with `args`. */
async function taskStays(
  turn: Turn,
  args: typeof TASK_ARGS,
): Promise<acp.StopReason> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await turn.say('I will send a task agent on fake for the fix.');
    await callChord(turn, client, 'spawn_task', args);
    await turn.say('It is running; I will check its report when it lands.');
    turn.signal.throwIfAborted();
    await once(turn.signal, 'abort', { signal: lifetime.signal });
    turn.signal.throwIfAborted();
  } finally {
    await client.close();
  }

  return 'end_turn';
}

/**
 * What `tasktitled` asks for: a task whose agent names its own session,
 * which chord shows nowhere, the task known by this name (CHD-445, Q200).
 */
export const TITLED_TASK_ARGS = {
  agent: 'fake',
  prompt: 'titledlong',
  name: 'Name the session',
};

/** Starts a task on `args` and ends the turn, the task working on. */
async function startTask(
  turn: Turn,
  args: typeof TITLED_TASK_ARGS,
): Promise<acp.StopReason> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await callChord(turn, client, 'spawn_task', args);
    await turn.say('Started.');
  } finally {
    await client.close();
  }

  return 'end_turn';
}

/** How long `taskchildhold` stays at work if no cancel comes. */
const HOLD_MS = 10_000;

/** `taskchild`'s play: with `hold`, at work after its message. */
async function taskChild(turn: Turn, hold: boolean): Promise<acp.StopReason> {
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

    if (hold) {
      // At work until the turn is cancelled, or for a while at most.
      await pause(turn.signal, HOLD_MS);
    }

    await work(turn, '`deno task test`', 'execute', '214 passed, 0 failed');
    await pause(turn.signal, TASK_STEP_MS * 10);
    await turn.say(TASK_REPORT);
  } finally {
    await client?.close();
  }

  return 'end_turn';
}

export const TASKS = {
  // As tasklong, under a name taller than the background frame (CHD-430).
  async tasktallname(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'spawn_task', {
        ...LONG_TASK_ARGS,
        name: TALL_TASK_NAME,
      });
      await turn.say('The tokenizer is being rewritten.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // Starts `taskwait` as a task agent and ends its turn at once, so the
  // task works on behind an idle parent, asking the person nothing.
  async tasklong(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'spawn_task', LONG_TASK_ARGS);
      await turn.say('The build is being watched.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // As `tasklong`, its task on `costwait`: it says a cost and works on until
  // it is stopped, to let its parent go with its spend said (CHD-373).
  async taskcost(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'spawn_task', {
        agent: 'fake',
        prompt: 'costwait',
        name: 'Count the cost',
      });
      await turn.say('The cost is being counted.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // Two `taskwait` tasks spawned one after the other, which the transcript
  // draws as one group, `Running 2 agents…`.
  async tasktwo(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'spawn_task', LONG_TASK_ARGS);
      await callChord(turn, client, 'spawn_task', {
        ...LONG_TASK_ARGS,
        name: 'Watch the deploy',
      });
      await turn.say('The build and the deploy are being watched.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // A task's job that takes a minute and asks nothing, until it is stopped.
  async taskwait(turn) {
    await turn.say('Watching the build.');
    await pause(turn.signal, 60_000);

    return turn.signal.aborted ? 'cancelled' : 'end_turn';
  },

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

  // As `task`, its turn running on until it is cancelled, however long
  // the task takes to ask its permission and send its message: no timer
  // ends it, only the cancel, or the client going.
  taskstays: (turn) => taskStays(turn, TASK_ARGS),

  // A task whose agent titles its session (CHD-445, Q200).
  tasktitled: (turn) => startTask(turn, TITLED_TASK_ARGS),

  // As `taskstays`, its task on `taskchildhold`, which stays at work after
  // its message until it is cancelled (CHD-399).
  taskstayshold: (turn) =>
    taskStays(turn, { ...TASK_ARGS, prompt: 'taskchildhold' }),

  // As `task`, its turn running on until a message is steered into it, as
  // the task's is, however long the task takes to ask and send it; for a
  // session started with `--steering` (CHD-470).
  async tasktillsteered(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    // Listening before the task starts, so its message is never missed.
    const waiting = steeredInto(
      turn.sessionId,
      AbortSignal.any([turn.signal, lifetime.signal]),
    );

    try {
      await turn.say('I will send a task agent on fake for the fix.');
      await callChord(turn, client, 'spawn_task', TASK_ARGS);
      await turn.say('It is running; I will check its report when it lands.');
      await waiting.steered;
    } finally {
      waiting.stop();
      await client.close();
    }

    return 'end_turn';
  },

  // Starts `taskchild` as `task` does, then ends its turn at once, so the
  // task asks its write's permission with no turn of its parent's running
  // (CHD-158).
  async taskbetween(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'spawn_task', TASK_ARGS);
      await turn.say('It is running; I will check its report when it lands.');
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

  // As `taskask`, its turn running on until it is cancelled, so the task's
  // questions are asked within it however slow the person's answer is: a
  // turn ended first moves them between turns, out of the keys (CHD-467).
  async taskaskstays(turn) {
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
      turn.signal.throwIfAborted();
      await once(turn.signal, 'abort', { signal: lifetime.signal });
      turn.signal.throwIfAborted();
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

  // codex's models and modes, which chord reads for the directory the
  // asking session works in (CHD-466).
  async codexmodels(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      const answer = await callChord(turn, client, 'list_agents', {
        agent: 'codex',
      });

      await turn.say(`Codex read: ${answer ?? 'failed'}`);
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // The same lists as codex-acp calls them (CHD-377), after a call of
  // another server's with the same arguments as the first, which chord
  // served none of.
  async codexchordcalls(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      const other = turn.callId('list_notes');

      await turn.send({
        sessionUpdate: 'tool_call',
        toolCallId: other,
        status: 'completed',
        ...codexCall('notes', 'list_notes', {}),
        content: [
          { type: 'content', content: { type: 'text', text: 'no notes' } },
        ],
      });
      await callChord(turn, client, 'list_agents', {}, undefined, 'codex');
      await callChord(turn, client, 'list_sessions', {}, undefined, 'codex');
      await turn.say('Listed as Codex.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // A task's job: two calls, a write it asks the person for, a message to
  // its parent, a test run, then the report. A denied write fails the turn,
  // so the parent gets a failed report.
  taskchild: (turn) => taskChild(turn, false),

  // As `taskchild`, at work after its message until it is cancelled, so a
  // test's Esc meets it running however slow the test is (CHD-399).
  taskchildhold: (turn) => taskChild(turn, true),
} satisfies Record<string, Play>;

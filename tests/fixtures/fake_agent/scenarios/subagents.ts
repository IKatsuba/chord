/** Subagents in the draft form Codex's adapter sent before 2.4, and in ACP's own `subagent_update` as Claude's and Codex's 2.4 send it. */
import * as acp from '@agentclientprotocol/sdk/unstable';
import { clientTakesSubagents } from '../client.ts';
import { existsSync } from 'node:fs';
import { appendFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { ADAPTER, STEERING, STEP_MS, STOP_GATE } from '../options.ts';
import { cwds } from '../sessions.ts';
import { GATE, GATE_RELEASE, gateOpened } from './agents.ts';
import { lifetime, pause, type Play, Turn, type Update } from '../turn.ts';

/**
 * How long a subagent takes between steps of its work: 40 steps, a fifth of a
 * second by default, so `subagent` runs for a few seconds and each state can
 * be seen; and how long its last subagent outlives the turn: 400 steps, 2 s.
 */
const SUBAGENT_STEP_MS = STEP_MS * 40;
const SUBAGENT_AFTER_MS = STEP_MS * 400;

/** The subagents a turn has started and not ended, to cancel with it. */
type Children = Map<string, Turn>;

/**
 * How many subagents this process has started: a subagent's session id names
 * it across the whole connection, so it is numbered across every session.
 */
let subagentCount = 0;

/**
 * This process's own mark in its subagents' ids: a fake started on a
 * resumed session counts from zero again, and a new subagent must not take
 * the id of one an earlier process started, as no real adapter's does.
 */
const run = crypto.randomUUID();

/** A new subagent's session id, opaque as an adapter's. */
function subagentId(): string {
  return `agent-${run}-${++subagentCount}`;
}

/**
 * Starts a subagent under `parent`, as Codex's adapter before 2.4 announces one
 * to a client that takes them: a `subagent_spawned` on the parent's session, after which
 * the subagent's work goes out under a session id of its own.
 */
async function spawn(
  parent: Turn,
  open: Children,
  name: string,
  task: string,
): Promise<Turn> {
  const child = new Turn(parent.client, subagentId(), parent.signal);

  await parent.send({
    sessionUpdate: 'subagent_spawned',
    subagentSessionId: child.sessionId,
    name,
    task,
    capabilities: {},
  } as unknown as Update);
  open.set(child.sessionId, parent);

  return child;
}

/**
 * Ends a subagent as the adapters do, with a `subagent_state_update` on its
 * parent's session. Sent at once, as a cancelled turn's are sent after its
 * signal has aborted.
 */
async function finish(
  childId: string,
  open: Children,
  state: 'completed' | 'failed' | 'cancelled',
): Promise<void> {
  const parent = open.get(childId);

  if (parent === undefined) {
    return;
  }

  open.delete(childId);
  await parent.client.notify('session/update', {
    sessionId: parent.sessionId,
    update: {
      sessionUpdate: 'subagent_state_update',
      subagentSessionId: childId,
      state,
    } as unknown as Update,
  });
}

/** A tool call that runs and ends as `status`, with `text` as its output. */
async function call(
  turn: Turn,
  name: string,
  call: Pick<acp.ToolCall, 'title' | 'kind' | 'locations'>,
  status: 'completed' | 'failed' | 'in_progress',
  text?: string,
): Promise<string> {
  const toolCallId = turn.callId(name);

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    ...call,
    status: 'in_progress',
  });

  if (status === 'in_progress') {
    return toolCallId;
  }

  await pause(turn.signal, SUBAGENT_STEP_MS);
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status,
    ...(text === undefined
      ? {}
      : { content: [{ type: 'content', content: { type: 'text', text } }] }),
  });

  return toolCallId;
}

/** The plan the first subagent of `subagent` works through. */
function childPlan(done: number): Update {
  const steps = [
    'Find the transport',
    'Find the listeners',
    'Write the answer',
  ];

  return {
    sessionUpdate: 'plan',
    entries: steps.map((content, index) => ({
      content,
      priority: 'medium',
      status:
        index < done ? 'completed' : index === done ? 'in_progress' : 'pending',
    })),
  };
}

/**
 * The first subagent of `subagent`: a plan, calls, a subagent of its own,
 * and a write it asks permission for, the answer deciding how the call ends.
 */
async function findSessionLayer(child: Turn, open: Children): Promise<void> {
  await child.think('Looking for where updates are routed.');
  await child.send(childPlan(0));
  await call(
    child,
    'search',
    {
      title: 'Search sessionUpdate in src',
      kind: 'search',
    },
    'completed',
    'Found 14 files',
  );
  await call(
    child,
    'read',
    {
      title: 'Read src/acp/connection.ts',
      kind: 'read',
      locations: [{ path: 'src/acp/connection.ts' }],
    },
    'completed',
  );

  const grandchild = await spawn(
    child,
    open,
    'Read the transport tests',
    'Read tests/acp/connection_test.ts and say what the transport ' +
      'promises about sessions it did not open.',
  );

  await call(
    grandchild,
    'read',
    {
      title: 'Read tests/acp/connection_test.ts',
      kind: 'read',
      locations: [{ path: 'tests/acp/connection_test.ts' }],
    },
    'completed',
  );
  await call(
    grandchild,
    'search',
    {
      title: 'Search cancel in tests/acp/connection_test.ts',
      kind: 'search',
    },
    'completed',
    '3 matches',
  );
  await grandchild.say('Nothing it did not open is promised.');
  await finish(grandchild.sessionId, open, 'completed');
  await child.send(childPlan(1));
  await call(
    child,
    'read',
    {
      title: 'Read src/session/session.ts',
      kind: 'read',
      locations: [{ path: 'src/session/session.ts' }],
    },
    'completed',
  );
  await pause(child.signal, SUBAGENT_STEP_MS);

  const write = child.callId('write');
  const toolCall: acp.ToolCall = {
    toolCallId: write,
    title: 'Write notes/routing.md',
    kind: 'edit',
    status: 'pending',
    locations: [{ path: 'notes/routing.md' }],
  };

  await child.send({ sessionUpdate: 'tool_call', ...toolCall });

  const answer = await child.client.request('session/request_permission', {
    sessionId: child.sessionId,
    toolCall,
    options: [
      { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
      { optionId: 'always', name: 'Always allow', kind: 'allow_always' },
      { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
    ],
  });

  // A request withdrawn is the turn being cancelled, whose cancel follows.
  if (answer.outcome.outcome === 'cancelled') {
    await pause(child.signal, SUBAGENT_AFTER_MS * 10);
  }

  const allowed =
    answer.outcome.outcome === 'selected' && answer.outcome.optionId !== 'deny';

  await child.send({
    sessionUpdate: 'tool_call_update',
    toolCallId: write,
    status: allowed ? 'completed' : 'failed',
  });
  await child.send(childPlan(3));
  await child.say(
    'The listeners are kept per sessionId in openAgent; ',
    'an id chord did not open is dropped there.',
  );
  await finish(child.sessionId, open, 'completed');
}

/** The second subagent of `subagent`, whose read fails, and it with it. */
async function findToolDrawing(child: Turn, open: Children): Promise<void> {
  await call(
    child,
    'search',
    {
      title: 'Search function Tool in src/ui',
      kind: 'search',
    },
    'completed',
    'Found 1 file',
  );
  await pause(child.signal, SUBAGENT_STEP_MS);
  await call(
    child,
    'read',
    {
      title: 'Read src/ui/App.tsx',
      kind: 'read',
      locations: [{ path: 'src/ui/App.tsx' }],
    },
    'failed',
    'File is too large to read whole.',
  );
  await child.say('Could not read the component.');
  await finish(child.sessionId, open, 'failed');
}

/** The plan the parent of `subagentstates` works through. */
function parentPlan(done: number): Update {
  const steps = [
    'Plan the change',
    'Read the session layer',
    'Write the design',
  ];

  return {
    sessionUpdate: 'plan',
    entries: steps.map((content, index) => ({
      content,
      priority: 'medium',
      status:
        index < done ? 'completed' : index === done ? 'in_progress' : 'pending',
    })),
  };
}

/**
 * The lone subagent of `subagentstates`: a plan of its own, which never shows
 * above the prompt, then five calls, more than a running block shows, held on
 * the last so the fold can be seen.
 */
async function readSessionLayer(child: Turn, open: Children): Promise<void> {
  await child.send(childPlan(0));

  for (const [name, title, path] of [
    ['search', 'Search sessionUpdate in src', undefined],
    ['read', 'Read src/acp/connection.ts', 'src/acp/connection.ts'],
    ['read', 'Read src/session/session.ts', 'src/session/session.ts'],
    ['read', 'Read src/session/conversation.ts', 'src/session/conversation.ts'],
    ['read', 'Read src/session/enrichers.ts', 'src/session/enrichers.ts'],
  ] as const) {
    await call(
      child,
      name,
      {
        title,
        kind: name,
        ...(path === undefined ? {} : { locations: [{ path }] }),
      },
      'completed',
    );
  }

  await pause(child.signal, SUBAGENT_AFTER_MS);
  await child.say('Routing lives in src/acp/connection.ts.');
  await finish(child.sessionId, open, 'completed');
}

/** One of the pair of `subagentstates`, whose calls all succeed. */
async function readAll(
  child: Turn,
  open: Children,
  paths: readonly string[],
): Promise<void> {
  for (const path of paths) {
    await call(
      child,
      'read',
      { title: `Read ${path}`, kind: 'read', locations: [{ path }] },
      'completed',
    );
  }

  await child.say('Read.');
  await finish(child.sessionId, open, 'completed');
}

/** Claude's subagents still at work, to end with a cancelled turn. */
type Working = Set<string>;

/**
 * Claude's subagents at work, by session id, each with the stop a
 * `session/cancel` on its own id makes: its work stops, and it reports itself
 * idle and cancelled, its parent's turn going on.
 */
export const claudeChildren = new Map<string, () => Promise<void>>();

/** What `--stop-gate` writes each stop to, and waits on to let it go. */
export const STOP_GATE_STOPS = 'stops';
export const STOP_GATE_RELEASE = 'stop-release';

/**
 * With `--stop-gate`, writes the stop of subagent `id` under `parent` to its
 * session's gate, then waits until the test releases it.
 */
async function stopGate(parent: Turn, id: string): Promise<void> {
  if (!STOP_GATE) {
    return;
  }

  const gate = join(cwds.get(parent.sessionId) ?? '.', GATE);

  await mkdir(gate, { recursive: true });
  await appendFile(join(gate, STOP_GATE_STOPS), `${id}\n`);

  while (!existsSync(join(gate, STOP_GATE_RELEASE))) {
    await pause(lifetime.signal, STEP_MS * 2);
  }
}

/** The subagents a stop of their own ended, whose work's abort is no error. */
const stoppedAlone = new Set<string>();

/**
 * Claude's subagents at work now: a stop of an idle one leaves its end as
 * it was, as Claude's adapter does, and one messaged again is at work again.
 */
const atWork = new Set<string>();

/**
 * `work` of `child`'s, which its parent waits on: a stop of the child alone
 * ends it quietly, any other failure is the parent's.
 */
async function alone(child: Turn, work: Promise<void>): Promise<void> {
  try {
    await work;
  } catch (error) {
    if (!stoppedAlone.has(child.sessionId)) {
      throw error;
    }
  }
}

/**
 * What a call in place of which the adapter sends a message said, as its two
 * views: the sender's on the sender's session, then the recipient's on theirs,
 * each naming the other (`linkedSessionMessages` in claude-agent-acp 0.99).
 */
async function linked(
  client: Turn['client'],
  messageId: string,
  sender: string,
  recipient: string,
  text: string,
): Promise<void> {
  const message = {
    sessionUpdate: 'session_message' as const,
    messageId,
    senderSessionId: sender,
    recipientSessionId: recipient,
    content: [{ type: 'text' as const, text }],
  };

  await client.notify('session/update', {
    sessionId: sender,
    update: { ...message, recipientMessageId: messageId },
  });
  await client.notify('session/update', {
    sessionId: recipient,
    update: { ...message, senderMessageId: messageId },
  });
}

/** The tool id each Claude subagent's launch went under, its reply's prefix. */
const launches = new Map<string, string>();

/**
 * A foreground subagent's answer, in its parent's transcript alone: its own
 * has it as an agent message (`launchReply` in claude-agent-acp 0.99).
 */
async function replied(parent: Turn, childId: string, text: string) {
  await parent.client.notify('session/update', {
    sessionId: parent.sessionId,
    update: {
      sessionUpdate: 'session_message',
      messageId: `${launches.get(childId) ?? childId}:reply`,
      senderSessionId: childId,
      recipientSessionId: parent.sessionId,
      content: [{ type: 'text', text }],
    },
  });
}

/**
 * Starts a subagent under `parent` as Claude's adapter announces one from 0.95
 * to a client that takes them: a `subagent_update` titled by its name, else
 * its short task, its role as its description unless that is the title, running
 * and open to a cancel of its own; then its whole task as both views of a
 * `session_message`, in place of the call that started it. `signal` is the
 * parent's unless the subagent outlives its turn.
 */
async function announce(
  parent: Turn,
  working: Working | undefined,
  role: string | undefined,
  title: string,
  task: string,
  signal = parent.signal,
  stopAfterMs = 0,
): Promise<Turn> {
  const own = new AbortController();
  const child = new Turn(
    parent.client,
    subagentId(),
    AbortSignal.any([signal, own.signal]),
  );

  claudeChildren.set(child.sessionId, async () => {
    await stopGate(parent, child.sessionId);
    await pause(lifetime.signal, stopAfterMs);

    if (!atWork.has(child.sessionId)) {
      return;
    }

    stoppedAlone.add(child.sessionId);
    own.abort();
    await report(parent, working, child.sessionId, {
      state: 'idle',
      stopReason: 'cancelled',
    });
  });

  await parent.send({
    sessionUpdate: 'subagent_update',
    sessionId: child.sessionId,
    title,
    // Its role goes only under Claude's name, which is what tells chord a
    // description is one: named otherwise, the fake's would read as its task.
    ...(role === undefined || (ADAPTER !== 'claude' && STEERING !== 'claude')
      ? {}
      : { description: role }),
    capabilities: { cancel: {} },
    state: { state: 'running' },
  });
  working?.add(child.sessionId);
  atWork.add(child.sessionId);

  const launch = parent.callId('agent');

  launches.set(child.sessionId, launch);
  await alone(
    child,
    (async () => {
      await pause(child.signal);
      await linked(
        parent.client,
        launch,
        parent.sessionId,
        child.sessionId,
        task,
      );
    })(),
  );

  return child;
}

/**
 * Reports where a Claude subagent stands, on its parent's session. Sent at
 * once, as a cancelled turn's are sent after its signal has aborted.
 */
async function report(
  parent: Turn,
  working: Working | undefined,
  childId: string,
  state: acp.StateUpdate,
): Promise<void> {
  if (state.state === 'running' || state.state === 'requires_action') {
    atWork.add(childId);
  } else {
    working?.delete(childId);
    atWork.delete(childId);
  }

  await parent.client.notify('session/update', {
    sessionId: parent.sessionId,
    update: { sessionUpdate: 'subagent_update', sessionId: childId, state },
  });
}

/**
 * The explorer of `claudesubagents`: calls, then a write it asks permission
 * for, waiting on the person meanwhile, and done.
 */
async function explore(
  parent: Turn,
  working: Working,
  child: Turn,
): Promise<void> {
  await call(
    child,
    'search',
    { title: 'Search sessionUpdate in src', kind: 'search' },
    'completed',
    'Found 14 files',
  );
  await call(
    child,
    'read',
    {
      title: 'Read src/acp/connection.ts',
      kind: 'read',
      locations: [{ path: 'src/acp/connection.ts' }],
    },
    'completed',
  );

  const write = child.callId('write');
  const toolCall: acp.ToolCall = {
    toolCallId: write,
    title: 'Write notes/routing.md',
    kind: 'edit',
    status: 'pending',
    locations: [{ path: 'notes/routing.md' }],
  };

  await child.send({ sessionUpdate: 'tool_call', ...toolCall });
  await report(parent, working, child.sessionId, { state: 'requires_action' });

  const answer = await child.client.request(
    'session/request_permission',
    {
      sessionId: child.sessionId,
      toolCall,
      options: [
        { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
        { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
      ],
    },
    // Withdrawn when it is stopped alone, as Claude Code withdraws it.
    { cancellationSignal: child.signal },
  );

  // A request withdrawn is the turn being cancelled, whose cancel follows.
  if (answer.outcome.outcome === 'cancelled') {
    await pause(child.signal, SUBAGENT_AFTER_MS * 10);
  }

  await report(parent, working, child.sessionId, { state: 'running' });

  const allowed =
    answer.outcome.outcome === 'selected' && answer.outcome.optionId !== 'deny';

  await child.send({
    sessionUpdate: 'tool_call_update',
    toolCallId: write,
    status: allowed ? 'completed' : 'failed',
  });
  await child.say('Routing lives in src/acp/connection.ts.');
  await report(parent, working, child.sessionId, {
    state: 'idle',
    stopReason: 'end_turn',
  });
}

/** The reviewer of `claudesubagents`, whose work fails. */
async function review(
  parent: Turn,
  working: Working,
  child: Turn,
): Promise<void> {
  await call(
    child,
    'read',
    {
      title: 'Read src/session/transcript/reducer.ts',
      kind: 'read',
      locations: [{ path: 'src/session/transcript/reducer.ts' }],
    },
    'completed',
  );
  await pause(child.signal, SUBAGENT_STEP_MS);
  await report(parent, working, child.sessionId, {
    state: 'idle',
    stopReason: 'error',
    error: { code: -32603, message: 'API Error: 529 Overloaded' },
  });
}

/** The tester of `claudesubagents`, stopped while its command runs. */
async function stopped(
  parent: Turn,
  working: Working,
  child: Turn,
): Promise<void> {
  const test = await call(
    child,
    'bash',
    { title: '`bun test`', kind: 'execute' },
    'in_progress',
  );

  await pause(child.signal, SUBAGENT_STEP_MS * 2);
  await child.send({
    sessionUpdate: 'tool_call_update',
    toolCallId: test,
    status: 'failed',
    content: [
      {
        type: 'content',
        content: {
          type: 'text',
          text: 'The turn was cancelled before this tool call returned a result.',
        },
      },
    ],
  });
  await report(parent, working, child.sessionId, {
    state: 'idle',
    stopReason: 'cancelled',
  });
}

/** The watcher of `claudesubagents`, which the adapter loses sight of. */
async function lost(
  parent: Turn,
  working: Working,
  child: Turn,
): Promise<void> {
  await call(
    child,
    'read',
    {
      title: 'Read package.json',
      kind: 'read',
      locations: [{ path: 'package.json' }],
    },
    'completed',
  );
  await pause(child.signal, SUBAGENT_STEP_MS * 3);
  await report(parent, working, child.sessionId, { state: 'unknown' });
}

/**
 * The background tester of `claudebackground`: a command that runs past its
 * parent's turn, then done.
 */
async function testInBackground(parent: Turn, child: Turn): Promise<void> {
  try {
    const test = await call(
      child,
      'bash',
      { title: '`bun test`', kind: 'execute' },
      'in_progress',
    );

    await pause(child.signal, SUBAGENT_AFTER_MS * 2);
    await child.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: test,
      status: 'completed',
    });
    await child.say('Every test passed.');
    await report(parent, undefined, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
  } catch {
    // The client went before the subagent ended.
  }
}

/**
 * The background tester of `claudebetween`: once its parent's turn has
 * answered, it asks to write its report, then asks a form, with no turn of
 * the client's running, as a Claude subagent that outlived its turn asks
 * (CHD-158); then it says what came back and is done.
 */
async function askAfterTurn(parent: Turn, child: Turn): Promise<void> {
  try {
    await pause(child.signal, SUBAGENT_AFTER_MS);

    const write = child.callId('write');
    const toolCall: acp.ToolCall = {
      toolCallId: write,
      title: 'Write notes/test-report.md',
      kind: 'edit',
      status: 'pending',
      locations: [{ path: 'notes/test-report.md' }],
    };

    await child.send({ sessionUpdate: 'tool_call', ...toolCall });
    await report(parent, undefined, child.sessionId, {
      state: 'requires_action',
    });

    const answer = await child.client.request(
      'session/request_permission',
      {
        sessionId: child.sessionId,
        toolCall,
        options: [
          { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
          { optionId: 'always', name: 'Always allow', kind: 'allow_always' },
          { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
        ],
      },
      { cancellationSignal: child.signal },
    );
    const allowed =
      answer.outcome.outcome === 'selected' &&
      answer.outcome.optionId !== 'deny';

    await child.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: write,
      status: allowed ? 'completed' : 'failed',
    });

    const form = await child.client.request(
      'elicitation/create',
      {
        sessionId: child.sessionId,
        mode: 'form',
        message: 'Which suite should run next?',
        requestedSchema: {
          type: 'object',
          properties: { suite: { type: 'string', title: 'Suite' } },
        },
      },
      { cancellationSignal: child.signal },
    );

    await report(parent, undefined, child.sessionId, { state: 'running' });
    await child.say(
      `Write ${allowed ? 'allowed' : 'denied'}; form ${form.action}.`,
    );
    await report(parent, undefined, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
  } catch {
    // The client went before the subagent ended.
  }
}

/**
 * A Claude subagent in the background beside one the turn waits on: the
 * first goes on past the turn's end, and past a cancel, which stops only the
 * second, then reports done; each stopped alone after `stopAfterMs`.
 */
async function background(
  turn: Turn,
  stopAfterMs = 0,
): Promise<acp.StopReason> {
  if (!clientTakesSubagents) {
    await turn.say('Subagents go only to a client that takes them.');

    return 'end_turn';
  }

  const working: Working = new Set();

  try {
    await turn.say('The tests run in the background while I look.');

    const tests = await announce(
      turn,
      undefined,
      'general-purpose',
      'Run the test suite',
      'Run bun test in the background and report what fails.',
      lifetime.signal,
      stopAfterMs,
    );

    // At once, so a cancel that comes before the next announcement leaves
    // it at work all the same.
    void testInBackground(turn, tests);

    const looker = await announce(
      turn,
      working,
      'Explore',
      'Find the cancel path',
      'Find where chord ends a turn on Esc.',
      turn.signal,
      stopAfterMs,
    );

    await alone(
      looker,
      (async () => {
        await call(
          looker,
          'search',
          { title: 'Search cancelled in src/session', kind: 'search' },
          'completed',
          'Found 3 files',
        );
        await pause(looker.signal, SUBAGENT_AFTER_MS);
        await looker.say(
          'Esc ends the turn in src/session/transcript/turn.ts.',
        );
        await report(turn, working, looker.sessionId, {
          state: 'idle',
          stopReason: 'end_turn',
        });
      })(),
    );
    await turn.say('The tests run on; I will say when they end.');

    return 'end_turn';
  } catch (error) {
    for (const id of [...working].toReversed()) {
      await report(turn, working, id, {
        state: 'idle',
        stopReason: 'cancelled',
      });
    }

    throw error;
  }
}

/** How long `subagentstatesstay`'s pair is at work if no cancel comes. */
const PAIR_HOLD_MS = 10_000;

/**
 * `subagentstates`' play: with `holdPair`, its pair stays at work until the
 * turn is cancelled, so a test's Esc meets it running however slow it is.
 */
async function subagentStates(
  turn: Turn,
  holdPair: boolean,
): Promise<acp.StopReason> {
  if (!clientTakesSubagents) {
    await turn.say('Subagents go only to a client that takes them.');

    return 'end_turn';
  }

  const open: Children = new Map();

  try {
    await turn.send(parentPlan(1));
    await readSessionLayer(
      await spawn(
        turn,
        open,
        'Find the session layer',
        'Find where chord hands each session/update to its listeners.',
      ),
      open,
    );
    await turn.send(parentPlan(2));
    await turn.say('Routing is in src/acp/connection.ts. Now both sides.');

    const explorer = await spawn(
      turn,
      open,
      'explorer',
      'Find where chord routes session/update.',
    );
    const worker = await spawn(
      turn,
      open,
      'worker',
      'Find where tool calls are drawn on screen.',
    );
    const wait = turn.callId('wait');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: wait,
      title: 'Wait explorer, worker',
      kind: 'other',
      status: 'in_progress',
    });

    if (holdPair) {
      // At work until the turn is cancelled, which ends the pair as the
      // catch below does, or for a while at most.
      await pause(turn.signal, PAIR_HOLD_MS);
    }

    await Promise.all([
      readAll(explorer, open, [
        'src/acp/connection.ts',
        'src/session/session.ts',
        'src/session/conversation.ts',
      ]),
      readAll(worker, open, ['src/ui/transcript/tools/Tool.tsx']),
    ]);
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: wait,
      status: 'completed',
    });
    await turn.send(parentPlan(3));
    await turn.say(
      'Both sides found: routing is in src/acp/connection.ts, ',
      'drawing is Tool in src/ui/transcript/tools/Tool.tsx.',
    );

    return 'end_turn';
  } catch (error) {
    for (const child of [...open.keys()].toReversed()) {
      await finish(child, open, 'cancelled');
    }

    throw error;
  }
}

export const SUBAGENTS = {
  // One subagent whose call is the only one open: the parent has none of
  // its own while the subagent's `sleep 2` runs, then it ends.
  async subagentcall(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const open: Children = new Map();

    try {
      const child = await spawn(turn, open, 'sleeper', 'Sleep a while');
      const id = await call(
        child,
        'sleep',
        { title: '`sleep 2`', kind: 'execute' },
        'in_progress',
      );

      await pause(turn.signal, SUBAGENT_STEP_MS);
      await child.send({
        sessionUpdate: 'tool_call_update',
        toolCallId: id,
        status: 'completed',
      });
      await finish(child.sessionId, open, 'completed');
      await turn.say('The sleeper is done.');
    } finally {
      for (const id of [...open.keys()]) {
        await finish(id, open, 'cancelled');
      }
    }

    return 'end_turn';
  },

  // Subagents in the draft form Codex's adapter sends to a client that takes
  // them: two spawned back to back, one with a plan, calls, a subagent of its
  // own and a permission to ask, the other failing; then, alone, a third that
  // outlives the turn. A cancel ends each one still open before the prompt is
  // answered, as the draft form does.
  async subagent(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const open: Children = new Map();

    try {
      await turn.say('I will send two agents, one for each side.');

      const first = await spawn(
        turn,
        open,
        'Find the session layer',
        'Find where chord hands each session/update to its listeners and ' +
          'say which file owns the routing. Report paths and line numbers.',
      );
      const second = await spawn(
        turn,
        open,
        'Find where tool calls are drawn on screen and how they fold',
        'Find the component that draws a tool call and the rule that folds ' +
          'its output.',
      );

      await Promise.all([
        findSessionLayer(first, open),
        findToolDrawing(second, open),
      ]);

      // Said between the spawns, so the last stands alone, not in a group.
      await turn.say('Now the tests, in the background.');

      const last = await spawn(
        turn,
        open,
        'Run the whole test suite',
        'Run bun dev test and report what fails.',
      );

      // A moment before its first call, to see it starting.
      await pause(turn.signal, SUBAGENT_STEP_MS);

      const test = await call(
        last,
        'bash',
        {
          title: 'bun dev test',
          kind: 'execute',
        },
        'in_progress',
      );

      await turn.say('It is running; I will say when it ends.');

      setTimeout(async () => {
        try {
          // Where a test made the session's gate, the subagent works on
          // until GATE_RELEASE is in it, or 10 s, so a test that picks it
          // finds it at work however slow the window is (CHD-501).
          const gate = join(cwds.get(turn.sessionId) ?? '.', GATE);
          const deadline = performance.now() + 10_000;

          while (
            existsSync(gate) &&
            !existsSync(join(gate, GATE_RELEASE)) &&
            performance.now() < deadline
          ) {
            await new Promise((resolve) => setTimeout(resolve, STEP_MS * 2));
          }

          await last.client.notify('session/update', {
            sessionId: last.sessionId,
            update: {
              sessionUpdate: 'tool_call_update',
              toolCallId: test,
              status: 'completed',
            },
          });
          await last.client.notify('session/update', {
            sessionId: last.sessionId,
            update: {
              sessionUpdate: 'agent_message_chunk',
              content: { type: 'text', text: 'Every test passed.' },
            },
          });
          await finish(last.sessionId, open, 'completed');
        } catch {
          // The client went before the subagent ended.
        }
      }, SUBAGENT_AFTER_MS);

      return 'end_turn';
    } catch (error) {
      for (const child of [...open.keys()].toReversed()) {
        await finish(child, open, 'cancelled');
      }

      throw error;
    }
  },

  // The states `subagent` never reaches: the parent's own plan beside a lone
  // subagent whose calls outrun its fold, then a pair the parent waits on
  // with a call of its own, as Codex's adapter does, both finishing.
  subagentstates: (turn) => subagentStates(turn, false),

  // As `subagentstates`, its pair at work until the turn is cancelled
  // (CHD-399).
  subagentstatesstay: (turn) => subagentStates(turn, true),

  // A subagent as ACP's own `subagent_update` says it, as an agent that
  // already speaks it sends one: announced running, then idle once done.
  async subagentupdate(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const child = new Turn(turn.client, subagentId(), turn.signal);

    await turn.send({
      sessionUpdate: 'subagent_update',
      sessionId: child.sessionId,
      title: 'Summarise the README',
      description: 'Read README.md and say in one line what chord is.',
      capabilities: {},
      state: { state: 'running' },
    });
    await call(
      child,
      'read',
      {
        title: 'Read README.md',
        kind: 'read',
        locations: [{ path: 'README.md' }],
      },
      'completed',
      '# chord',
    );
    await child.say('chord is a terminal client for ACP agents.');
    await turn.send({
      sessionUpdate: 'subagent_update',
      sessionId: child.sessionId,
      state: { state: 'idle' },
    });
    await turn.say('It says chord is a terminal client for ACP agents.');

    return 'end_turn';
  },
  // Subagents as Claude's adapter sends them, in ACP's own form: four
  // spawned back to back, each with its whole task, ending each way it
  // reports, the first waiting on the person for a write meanwhile. A cancel
  // ends each still at work idle and `cancelled`, as Claude Code stops them.
  async claudesubagents(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();

    try {
      await turn.say('I will send four agents.');

      const explorer = await announce(
        turn,
        working,
        'Explore',
        'Find the session layer',
        'Find where chord hands each session/update to its listeners and ' +
          'say which file owns the routing.\n\nReport paths and line ' +
          'numbers, and write what you find to notes/routing.md.',
      );
      const reviewer = await announce(
        turn,
        working,
        'general-purpose',
        'Review the transcript reducer',
        'Review src/session/transcript/reducer.ts for updates it drops.',
      );
      const tester = await announce(
        turn,
        working,
        'general-purpose',
        'Run the tests',
        'Run bun test and report what fails.',
      );
      const watcher = await announce(
        turn,
        working,
        undefined,
        'Watch the build',
        'Watch the build and say when it breaks.',
      );

      await Promise.all([
        alone(explorer, explore(turn, working, explorer)),
        alone(reviewer, review(turn, working, reviewer)),
        alone(tester, stopped(turn, working, tester)),
        alone(watcher, lost(turn, working, watcher)),
      ]);
      await turn.say('Each agent has ended.');

      return 'end_turn';
    } catch (error) {
      for (const id of [...working].toReversed()) {
        await report(turn, working, id, {
          state: 'idle',
          stopReason: 'cancelled',
        });
      }

      throw error;
    }
  },

  claudebackground: (turn) => background(turn),

  // A Claude subagent in the background that asks a permission and then a
  // form once the turn has answered, with no turn running (CHD-158).
  async claudebetween(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const tests = await announce(
      turn,
      undefined,
      'general-purpose',
      'Run the whole test suite',
      'Run bun test in the background and write a report of what fails.',
      lifetime.signal,
    );

    void askAfterTurn(turn, tests);
    await turn.say('It is running; I will say when it ends.');

    return 'end_turn';
  },

  // As claudebackground, its subagents taking about 2 s to stop alone, as
  // Claude does, so a stop pending can be seen.
  claudeslowstop: (turn) => background(turn, SUBAGENT_AFTER_MS),

  // A Claude subagent its parent messages again once it is done, as
  // SendMessage does: the message on its session, from the parent, then it
  // runs once more and is done again.
  async claudemessage(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();

    try {
      const explorer = await announce(
        turn,
        working,
        'Explore',
        'Find the session layer',
        'Find where chord hands each session/update to its listeners.\n\n' +
          'Report the file that owns the routing, with line numbers.',
      );

      await alone(
        explorer,
        (async () => {
          await call(
            explorer,
            'read',
            {
              title: 'Read src/acp/connection.ts',
              kind: 'read',
              locations: [{ path: 'src/acp/connection.ts' }],
            },
            'completed',
          );
          await explorer.say('Routing lives in src/acp/connection.ts.');
          await report(turn, working, explorer.sessionId, {
            state: 'idle',
            stopReason: 'end_turn',
          });
          await replied(
            turn,
            explorer.sessionId,
            'Routing lives in src/acp/connection.ts.',
          );
        })(),
      );

      // One stopped alone is not messaged again.
      if (!stoppedAlone.has(explorer.sessionId)) {
        await turn.say('I will ask it for the tests too. ');
        await linked(
          turn.client,
          turn.callId('send'),
          turn.sessionId,
          explorer.sessionId,
          'Now find the tests that cover it.',
        );
        await report(turn, working, explorer.sessionId, { state: 'running' });
        await alone(
          explorer,
          (async () => {
            await call(
              explorer,
              'search',
              { title: 'Search connection in tests/acp', kind: 'search' },
              'completed',
              'Found 2 files',
            );
            await explorer.say('tests/acp/connection_test.ts covers it.');
            await report(turn, working, explorer.sessionId, {
              state: 'idle',
              stopReason: 'end_turn',
            });
          })(),
        );
      }

      await turn.say('Both found.');

      return 'end_turn';
    } catch (error) {
      for (const id of [...working].toReversed()) {
        await report(turn, working, id, {
          state: 'idle',
          stopReason: 'cancelled',
        });
      }

      throw error;
    }
  },

  // A Claude subagent its agent says waits on the person, with no request
  // of its reaching chord, as one refused between turns does; it is held
  // about 2 s, then runs on and is done.
  async claudewaiting(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();

    try {
      const child = await announce(
        turn,
        working,
        'general-purpose',
        'Run the test suite',
        'Run bun test and report what fails.',
      );

      await alone(
        child,
        (async () => {
          await report(turn, working, child.sessionId, {
            state: 'requires_action',
          });
          await pause(child.signal, SUBAGENT_AFTER_MS);
          await report(turn, working, child.sessionId, { state: 'running' });
          await child.say('Every test passed.');
          await report(turn, working, child.sessionId, {
            state: 'idle',
            stopReason: 'end_turn',
          });
        })(),
      );
      await turn.say('The tests passed.');

      return 'end_turn';
    } catch (error) {
      for (const id of [...working].toReversed()) {
        await report(turn, working, id, {
          state: 'idle',
          stopReason: 'cancelled',
        });
      }

      throw error;
    }
  },

  // A Claude subagent that takes its own cancel back, as a later update
  // without it does: held about 2 s with no stop of its own, then done.
  async claudenostop(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const child = await announce(
      turn,
      working,
      'general-purpose',
      'Run the test suite',
      'Run bun test and report what fails.',
    );

    claudeChildren.delete(child.sessionId);
    await turn.send({
      sessionUpdate: 'subagent_update',
      sessionId: child.sessionId,
      capabilities: null,
    });
    await pause(turn.signal, SUBAGENT_AFTER_MS);
    await report(turn, working, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
    await turn.say('The tests passed.');

    return 'end_turn';
  },

  // A launch's prompt over six rows, and a reply over two paragraphs.
  async claudelongprompt(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const child = await announce(
      turn,
      working,
      'Explore',
      'Check the handover',
      Array.from(
        { length: 9 },
        (_, step) =>
          `${step + 1}. Check step ${step + 1} of the handover and report what it finds.`,
      ).join('\n'),
    );

    await child.say('Checked.');
    await report(turn, working, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
    await replied(
      turn,
      child.sessionId,
      'Every step holds.\n\nStep 9 was the slowest to check.',
    );
    await turn.say('The handover holds.');

    return 'end_turn';
  },

  // A launch's prompt with code above its fold and more below it.
  async claudecodeprompt(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const child = await announce(
      turn,
      working,
      'Explore',
      'Check the build',
      [
        'Run this first.\n\n```sh\nbun test\n```',
        ...Array.from({ length: 8 }, (_, step) => `Then step ${step + 1}.`),
      ].join('\n\n'),
    );

    await report(turn, working, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
    await turn.say('The build holds.');

    return 'end_turn';
  },

  // A launch's short prompt with code, that the agent then lengthens under the
  // same id, past the fold, once the test's file says so.
  async claudepromptgrows(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const child = await announce(
      turn,
      working,
      'Explore',
      'Check the build',
      'Run this.\n\n```sh\nbun test\n```',
    );

    await turn.say('Short so far. ');
    await gateOpened(turn, GATE_RELEASE);
    await linked(
      turn.client,
      launches.get(child.sessionId) ?? child.sessionId,
      turn.sessionId,
      child.sessionId,
      [
        'Run this.\n\n```sh\nbun test\n```',
        ...Array.from({ length: 8 }, (_, step) => `Then step ${step + 1}.`),
      ].join('\n\n'),
    );
    await report(turn, working, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
    await turn.say('Long now.');

    return 'end_turn';
  },

  // A launch's prompt that fits six rows wide and not narrow.
  async claudewrapprompt(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const child = await announce(
      turn,
      working,
      'Explore',
      'Check the build',
      `${'Check every step of the handover and report it. '.repeat(3)}\n\n\`\`\`sh\nbun test\n\`\`\``,
    );

    await report(turn, working, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
    await turn.say('Done wrapping.');

    return 'end_turn';
  },

  // A SendMessage to a child still at work: the adapter sees no resume, so the
  // call comes after all, once, with its final status.
  async claudesendrunning(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const child = await announce(
      turn,
      working,
      'Explore',
      'Find the session layer',
      'Find the routing.',
    );

    await call(
      turn,
      'send',
      { title: 'SendMessage', kind: 'other' },
      'completed',
      'Message queued',
    );
    await report(turn, working, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
    await replied(turn, child.sessionId, 'It is the relay.');

    return 'end_turn';
  },

  // A child that hands its report back: both views, with no `:reply`, and on
  // its own session a one-option config update, its model as it runs.
  async claudehandback(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const child = await announce(
      turn,
      working,
      'Explore',
      'explorer',
      'Find the routing and hand it back.',
    );

    await child.send({
      sessionUpdate: 'config_option_update',
      configOptions: [
        {
          id: 'model',
          name: 'Model',
          category: 'model',
          type: 'select',
          currentValue: 'child-model',
          options: [{ value: 'child-model', name: 'Child model' }],
        },
      ],
    });
    await linked(
      turn.client,
      child.callId('handback'),
      child.sessionId,
      turn.sessionId,
      'The relay in connection.ts owns the routing.',
    );
    await report(turn, working, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });

    return 'end_turn';
  },

  // A lone failure that says why, with no answer.
  async claudefailed(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const child = await announce(
      turn,
      working,
      undefined,
      'Run the test suite',
      'Run bun test and report what fails.',
    );

    await report(turn, working, child.sessionId, {
      state: 'idle',
      stopReason: 'error',
      error: { code: -32603, message: 'The build still fails.' },
    });
    await turn.say('It failed.');

    return 'end_turn';
  },

  // A failure that says nothing of why, and a stop: neither answers.
  async claudenoanswer(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const failing = await announce(
      turn,
      working,
      undefined,
      'Run the test suite',
      'Run bun test and report what fails.',
    );

    await report(turn, working, failing.sessionId, {
      state: 'idle',
      stopReason: 'error',
    });

    const told = await announce(
      turn,
      working,
      undefined,
      'Watch the build',
      'Watch the build.',
    );

    await report(turn, working, told.sessionId, {
      state: 'idle',
      stopReason: 'cancelled',
    });
    await turn.say('Neither answered.');

    return 'end_turn';
  },

  // A child that launches one of its own, and has its reply, and then its own
  // answer to its parent.
  async claudenested(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const working: Working = new Set();
    const child = await announce(
      turn,
      working,
      'general-purpose',
      'Review the layer',
      'Review the session layer.',
    );
    const inner = await announce(
      child,
      working,
      'Explore',
      'Find the routing',
      'Find the routing.',
    );

    await inner.say('The relay.');
    await report(child, working, inner.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
    await replied(child, inner.sessionId, 'It is the relay.');
    await child.say('Reviewed.');
    await report(turn, working, child.sessionId, {
      state: 'idle',
      stopReason: 'end_turn',
    });
    await replied(turn, child.sessionId, 'The layer holds.');

    return 'end_turn';
  },

  // Subagents as Codex's adapter sends them from 2.4: an announcement with no
  // state and perhaps no title, then each thing as it changes, alone: the
  // title, the state, whether it can be stopped. One ends done and is renamed
  // after, one fails.
  async codexsubagents(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const told = (sessionId: string, fields: Partial<acp.SubagentUpdate>) =>
      turn.send({ sessionUpdate: 'subagent_update', sessionId, ...fields });
    const worker = new Turn(turn.client, subagentId(), turn.signal);

    await told(worker.sessionId, { capabilities: {} });
    await told(worker.sessionId, { title: 'worker' });
    await worker.send({
      sessionUpdate: 'session_info_update',
      title: 'worker',
    });
    await worker.send({
      sessionUpdate: 'config_option_update',
      configOptions: [],
    });
    await told(worker.sessionId, { state: { state: 'running' } });
    await told(worker.sessionId, { capabilities: { cancel: {} } });
    await call(
      worker,
      'read',
      {
        title: 'Read README.md',
        kind: 'read',
        locations: [{ path: 'README.md' }],
      },
      'completed',
    );
    await worker.say('Read.');
    await told(worker.sessionId, {
      state: { state: 'idle', stopReason: 'end_turn' },
    });
    await told(worker.sessionId, { capabilities: { cancel: null } });
    await told(worker.sessionId, { title: 'worker renamed' });

    const failing = subagentId();

    await told(failing, {
      capabilities: {},
      title: 'failing',
      description: 'Fail at once',
    });
    await told(failing, { state: { state: 'running' } });
    await told(failing, { capabilities: { cancel: {} } });
    await told(failing, {
      state: {
        state: 'idle',
        stopReason: 'error',
        error: { code: -32603, message: 'Subagent work failed' },
      },
    });
    await told(failing, { capabilities: { cancel: null } });
    await turn.say('Both have ended.');

    return 'end_turn';
  },

  // A subagent as Codex's 2.4 sends one, at work until a `session/cancel` on
  // its own id or on the turn, its parent's turn going on after the first.
  async codexsubagentstop(turn) {
    if (!clientTakesSubagents) {
      await turn.say('Subagents go only to a client that takes them.');

      return 'end_turn';
    }

    const id = subagentId();
    const told = (fields: Partial<acp.SubagentUpdate>) =>
      turn.send({ sessionUpdate: 'subagent_update', sessionId: id, ...fields });
    const stopped = Promise.withResolvers<void>();

    // Sent at once, as a cancelled turn's are sent after its signal has aborted.
    const ended = async () => {
      for (const fields of [
        { state: { state: 'idle', stopReason: 'cancelled' } },
        { capabilities: { cancel: null } },
      ]) {
        await turn.client.notify('session/update', {
          sessionId: turn.sessionId,
          update: {
            sessionUpdate: 'subagent_update',
            sessionId: id,
            ...fields,
          },
        });
      }
    };

    // Its own, so a stop leaves no wait behind for the rest of the session.
    const waiting = new AbortController();

    claudeChildren.set(id, () => {
      stopped.resolve();

      return Promise.resolve();
    });

    try {
      await told({ capabilities: {}, title: 'watcher' });
      await told({ state: { state: 'running' } });
      await told({ capabilities: { cancel: {} } });
      await Promise.race([
        stopped.promise,
        pause(AbortSignal.any([turn.signal, waiting.signal]), 60_000),
      ]);
    } catch (error) {
      await ended();

      throw error;
    } finally {
      waiting.abort();
      claudeChildren.delete(id);
    }

    await ended();
    await turn.say('It stopped, and the turn goes on.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;

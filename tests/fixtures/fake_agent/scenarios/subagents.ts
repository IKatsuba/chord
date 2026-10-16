/** Subagents as both adapters send them, and as ACP's own `subagent_update`. */
import * as acp from '@agentclientprotocol/sdk';
import { clientTakesSubagents } from '../client.ts';
import { STEP_MS } from '../options.ts';
import { pause, type Play, Turn, type Update } from '../turn.ts';

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

/** A new subagent's session id. */
function subagentId(): string {
  return `agent-${++subagentCount}`;
}

/**
 * Starts a subagent under `parent`, as both adapters announce one to a client
 * that takes them: a `subagent_spawned` on the parent's session, after which
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

export const SUBAGENTS = {
  // Subagents as Claude's and Codex's adapters send them to a client that
  // takes them: two spawned back to back, one with a plan, calls, a subagent
  // of its own and a permission to ask, the other failing; then, alone, a
  // third that outlives the turn. A cancel ends each one still open, as
  // Claude's adapter does before it answers the prompt.
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
        'Run deno task test and report what fails.',
      );

      // A moment before its first call, to see it starting.
      await pause(turn.signal, SUBAGENT_STEP_MS);

      const test = await call(
        last,
        'bash',
        {
          title: 'deno task test',
          kind: 'execute',
        },
        'in_progress',
      );

      await turn.say('It is running; I will say when it ends.');

      setTimeout(async () => {
        try {
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
  async subagentstates(turn) {
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
  },

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
} satisfies Record<string, Play>;

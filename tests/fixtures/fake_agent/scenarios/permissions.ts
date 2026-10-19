/**
 * Permissions: a write asked for, with three options or with two of one kind,
 * and MCP calls asked for by their name and arguments alone, one of them a
 * file too long for the box.
 */
import * as acp from '@agentclientprotocol/sdk';
import { RELEASE_NOTES } from '../../release_notes.ts';
import { STEP_MS } from '../options.ts';
import { lifetime, pause, type Play, type Turn } from '../turn.ts';

/**
 * Asks for permission to call `server`'s `tool` with `rawInput`, as
 * claude-agent-acp asks for an MCP tool, and says which option came back.
 */
async function askMcp(
  turn: Turn,
  server: string,
  tool: string,
  rawInput: Record<string, unknown>,
): Promise<acp.StopReason> {
  const id = turn.callId(tool);
  const toolCall: acp.ToolCall = {
    toolCallId: id,
    title: `mcp__${server}__${tool}`,
    kind: 'other',
    status: 'pending',
    rawInput,
  };

  await turn.send({ sessionUpdate: 'tool_call', ...toolCall });

  const answer = await turn.client.request('session/request_permission', {
    sessionId: turn.sessionId,
    toolCall,
    options: [
      { optionId: 'allow', name: 'Yes', kind: 'allow_once' },
      {
        optionId: 'always',
        name: `Yes, and don't ask again for ${server} - ${tool} commands`,
        kind: 'allow_always',
      },
      {
        optionId: 'deny',
        name: 'No, and tell Claude what to do differently',
        kind: 'reject_once',
      },
    ],
  });

  if (answer.outcome.outcome === 'cancelled') {
    return 'cancelled';
  }

  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId: id,
    status: answer.outcome.optionId === 'deny' ? 'failed' : 'completed',
  });
  await turn.say(`Permission: ${answer.outcome.optionId}.`);

  return 'end_turn';
}

/**
 * Asks for permission to write a file with `options`, and says which option
 * came back, by its id.
 */
async function askPermission(
  turn: Turn,
  options: acp.PermissionOption[],
  { untilSteered = false }: { readonly untilSteered?: boolean } = {},
): Promise<acp.StopReason> {
  const id = turn.callId('write');
  const toolCall: acp.ToolCall = {
    toolCallId: id,
    title: 'Write notes.txt',
    kind: 'edit',
    status: 'pending',
    locations: [{ path: 'notes.txt' }],
  };

  await turn.send({ sessionUpdate: 'tool_call', ...toolCall });

  // The request carries the diff and the arguments, as Claude Code's adapter
  // asks for a write; with content of its own, its arguments stay unshown.
  const answer = await turn.client.request('session/request_permission', {
    sessionId: turn.sessionId,
    toolCall: {
      ...toolCall,
      content: [{ type: 'diff', path: 'notes.txt', newText: 'notes\n' }],
      rawInput: { file_path: 'notes.txt', content: 'notes\n' },
    },
    options,
  });

  if (answer.outcome.outcome === 'cancelled') {
    return 'cancelled';
  }

  const allowed = answer.outcome.optionId !== 'deny';

  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId: id,
    status: allowed ? 'completed' : 'failed',
  });

  // A model's next step comes only after the tool's result is in: a message
  // held behind the call until it ended is read at that step, not after it.
  while (untilSteered && !turn.steered) {
    await pause(turn.signal);
  }

  await turn.say(`Permission: ${answer.outcome.optionId}.`);

  return 'end_turn';
}

/**
 * The session's own agent asking, with no turn running, to write `file`,
 * and, silent for `saysAfterMs` after the answer, ending the call: how its
 * answer reads.
 */
async function askBetween(
  turn: Turn,
  file: string,
  saysAfterMs = 0,
): Promise<string> {
  const { client, sessionId } = turn;
  const update = (update: acp.SessionUpdate) =>
    client.notify('session/update', { sessionId, update });
  const toolCall: acp.ToolCall = {
    toolCallId: turn.callId('write'),
    title: `Write ${file}`,
    kind: 'edit',
    status: 'pending',
    locations: [{ path: file }],
  };

  await update({ sessionUpdate: 'tool_call', ...toolCall });

  const answer = await client.request(
    'session/request_permission',
    {
      sessionId,
      toolCall,
      options: [
        { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
        { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
      ],
    },
    { cancellationSignal: lifetime.signal },
  );
  const chosen =
    answer.outcome.outcome === 'selected'
      ? answer.outcome.optionId
      : 'cancelled';

  await pause(lifetime.signal, saysAfterMs);
  await update({
    sessionUpdate: 'tool_call_update',
    toolCallId: toolCall.toolCallId,
    status: chosen === 'allow' ? 'completed' : 'failed',
  });

  return chosen;
}

/** Text from the session's own agent with no turn running. */
function sayBetween(turn: Turn, text: string): Promise<void> {
  return turn.client.notify('session/update', {
    sessionId: turn.sessionId,
    update: {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text },
    },
  });
}

export const PERMISSIONS = {
  // A write asked for while another call, `overlapask-a`, stays open: the
  // answer releases what waited on it while `a` still runs, and `a` ends
  // a while after the write.
  async overlapask(turn) {
    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: 'overlapask-a',
      title: '`sleep 2`',
      kind: 'execute',
      status: 'in_progress',
    });
    await pause(turn.signal, STEP_MS * 20);

    const stop = await askPermission(turn, [
      { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
      { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
    ]);

    if (stop === 'cancelled') {
      return stop;
    }

    await pause(turn.signal, STEP_MS * 20);
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: 'overlapask-a',
      status: 'completed',
    });

    return 'end_turn';
  },

  async permission(turn) {
    return await askPermission(turn, [
      { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
      { optionId: 'always', name: 'Always allow', kind: 'allow_always' },
      { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
    ]);
  },

  // As `permission`, its next step after the write waiting for a message
  // steered in, as the model's next step waits for the tool's result.
  async permissionsteer(turn) {
    return await askPermission(
      turn,
      [
        { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
        { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
      ],
      { untilSteered: true },
    );
  },

  // Two options of one kind, as Codex's adapter offers two ways to allow
  // once; only the option's id says which the person picked.
  async twins(turn) {
    return await askPermission(turn, [
      { optionId: 'allow', name: 'Allow once', kind: 'allow_once' },
      {
        optionId: 'allow-here',
        name: 'Allow once in this folder',
        kind: 'allow_once',
      },
      { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
    ]);
  },

  // As claude-agent-acp asks for an MCP tool: the title is the tool's name,
  // the arguments are only in rawInput, and there is no content.
  mcpask: (turn) =>
    askMcp(turn, 'chord', 'monitor', {
      command: 'tail -f dev.log | grep --line-buffered -E "ERROR|WARN"',
      description: 'dev server errors',
      timeout_ms: 600000,
    }),

  // An MCP write whose file runs past any window (CHD-246).
  bigask: (turn) =>
    askMcp(turn, 'files', 'write_file', {
      path: 'docs/release.md',
      content: RELEASE_NOTES,
      mode: 'overwrite',
    }),

  // bigask's write, its turn ending with it still open (CHD-158 §8): a tall
  // request held between turns, whose rows scroll on a short screen; its
  // answer is said once it comes.
  async bigaskleft(turn) {
    const toolCall: acp.ToolCall = {
      toolCallId: turn.callId('write_file'),
      title: 'mcp__files__write_file',
      kind: 'other',
      status: 'pending',
      rawInput: {
        path: 'docs/release.md',
        content: RELEASE_NOTES,
        mode: 'overwrite',
      },
    };

    await turn.send({ sessionUpdate: 'tool_call', ...toolCall });

    void (async () => {
      try {
        const answer = await turn.client.request('session/request_permission', {
          sessionId: turn.sessionId,
          toolCall,
          options: [
            { optionId: 'allow', name: 'Yes', kind: 'allow_once' },
            { optionId: 'deny', name: 'No', kind: 'reject_once' },
          ],
        });
        const chosen =
          answer.outcome.outcome === 'selected'
            ? answer.outcome.optionId
            : 'cancelled';

        await sayBetween(turn, `Permission: ${chosen}.`);
      } catch {
        // The client went before it was answered.
      }
    })();

    await pause(turn.signal, STEP_MS * 100);
    await turn.say('I asked; the turn ends with it open.');

    return 'end_turn';
  },

  // Two such writes asked at once, the second waiting behind the first, told
  // apart by their paths; each says what came back.
  async bigasktwice(turn) {
    const answers = await Promise.all([
      askMcp(turn, 'files', 'write_file', {
        path: 'docs/release.md',
        content: RELEASE_NOTES,
        mode: 'overwrite',
      }),
      askMcp(turn, 'files', 'write_file', {
        path: 'docs/changes.md',
        content: RELEASE_NOTES,
        mode: 'append',
      }),
    ]);

    return answers.includes('cancelled') ? 'cancelled' : 'end_turn';
  },

  // The session's own agent asks once its turn has answered, with no turn
  // running, as an agent's background command's follow-up does (CHD-158),
  // and says what came back.
  async leftask(turn) {
    // Asks in its turn, then ends the turn with the request still open, as
    // an agent may: the request outlives the turn (the owner's Q44,
    // CHD-158), and its answer is said once it comes.
    void (async () => {
      try {
        const chosen = await askBetween(turn, 'notes/left.md');

        await sayBetween(turn, `Permission: ${chosen}.`);
      } catch {
        // The client went before it was answered.
      }
    })();

    await pause(turn.signal, STEP_MS * 100);
    await turn.say('I asked; the turn ends with it open.');

    return 'end_turn';
  },

  async mainbetween(turn) {
    void (async () => {
      try {
        await pause(lifetime.signal, STEP_MS * 100);

        const chosen = await askBetween(turn, 'notes/report.md');

        await sayBetween(turn, `Permission: ${chosen}.`);
      } catch {
        // The client went before it was answered.
      }
    })();

    await turn.say('I will write the report once the build is done.');

    return 'end_turn';
  },

  // As mainbetween, then, once answered, a second request at once, after
  // whose answer it is silent half a second before it says what came back:
  // a follow-up that must not be taken for a held prompt's reply.
  async mainbetweentwice(turn) {
    void (async () => {
      try {
        await pause(lifetime.signal, STEP_MS * 100);
        await askBetween(turn, 'notes/report.md');

        // Within chord's second of quiet at any pace, which is fixed, so the
        // follow-up never meets its end.
        const chosen = await askBetween(
          turn,
          'notes/summary.md',
          Math.min(STEP_MS * 100, 500),
        );

        await sayBetween(turn, `Second: ${chosen}.`);
      } catch {
        // The client went before it was answered.
      }
    })();

    await turn.say('I will write the report once the build is done.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;

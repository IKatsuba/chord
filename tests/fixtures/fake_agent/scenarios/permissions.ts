/**
 * Permissions: a write asked for, with three options or with two of one kind,
 * and MCP calls asked for by their name and arguments alone, one of them a
 * file too long for the box.
 */
import * as acp from '@agentclientprotocol/sdk';
import { RELEASE_NOTES } from '../../release_notes.ts';
import { STEP_MS } from '../options.ts';
import { pause, type Play, type Turn } from '../turn.ts';

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
  await turn.say(`Permission: ${answer.outcome.optionId}.`);

  return 'end_turn';
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
} satisfies Record<string, Play>;

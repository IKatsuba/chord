/**
 * Commands run as Codex's adapter and Claude's run them, with their terminals.
 */
import * as acp from '@agentclientprotocol/sdk';
import { BASH_OUTPUT, CUT_OUTPUT, SHELL_OUTPUT } from '../../terminals.ts';
import { clientTerminalOutput } from '../client.ts';
import { STEP_MS } from '../options.ts';
import { cwds } from '../sessions.ts';
import { pause, type Play, type Turn } from '../turn.ts';

/**
 * How long the `shell` scenario's command takes between pieces of output:
 * 100 steps, half a second by default, so its run is seen for about 2 s; and
 * how long the `bash` scenario's runs before its output comes.
 */
const SHELL_STEP_MS = STEP_MS * 100;

/**
 * A command as Codex's adapter runs one, writing `pieces`: see the `shell`
 * scenario.
 */
async function codexShell(
  turn: Turn,
  pieces: readonly string[],
): Promise<acp.StopReason> {
  const toolCallId = turn.callId('shell');
  const terminalId = `terminal-${toolCallId}`;
  const update = (_meta: Record<string, unknown>, status?: 'failed') =>
    turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      ...(status === undefined ? {} : { status }),
      _meta,
    });

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    title: 'Run deno task test',
    kind: 'execute',
    status: 'in_progress',
    rawInput: { command: ['deno', 'task', 'test'] },
    content: [{ type: 'terminal', terminalId }],
    _meta: {
      terminal_info: {
        terminal_id: terminalId,
        cwd: cwds.get(turn.sessionId) ?? '',
      },
    },
  });

  for (const data of pieces.slice(0, -1)) {
    await pause(turn.signal, SHELL_STEP_MS);
    await update({
      terminal_output_delta: { terminal_id: terminalId, data },
    });
  }

  await pause(turn.signal, SHELL_STEP_MS);
  await update(
    {
      terminal_output_delta: {
        terminal_id: terminalId,
        data: pieces.at(-1),
      },
      terminal_exit: { terminal_id: terminalId, exit_code: 1, signal: null },
    },
    'failed',
  );
  await turn.say('The tests failed.');

  return 'end_turn';
}

export const SHELL = {
  // A command as Codex's adapter runs one, to any client: the terminal named
  // up front, its output in pieces as it comes, and the exit, which fails,
  // with the last of the output.
  shell: (turn) => codexShell(turn, SHELL_OUTPUT),

  shellcut: (turn) => codexShell(turn, CUT_OUTPUT),

  // A command as Claude's adapter runs one: to a client that takes terminal
  // output, the terminal named up front and nothing of it until it is done,
  // then the whole output, as asked for, and the exit; to any other, the
  // output as a block of text when it is done.
  async bash(turn) {
    const toolCallId = turn.callId('bash');
    const terminalId = toolCallId;
    const takes = clientTerminalOutput !== 'none';
    const terminal = [{ type: 'terminal' as const, terminalId }];

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      title: '`git status --short`',
      kind: 'execute',
      status: 'pending',
      rawInput: { command: 'git status --short' },
      content: takes ? terminal : [],
      ...(takes
        ? { _meta: { terminal_info: { terminal_id: terminalId } } }
        : {}),
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      status: 'in_progress',
    });
    // The command takes a moment, so its call is seen working with no output.
    await pause(turn.signal, SHELL_STEP_MS);

    if (!takes) {
      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId,
        status: 'completed',
        content: [
          {
            type: 'content',
            content: {
              type: 'text',
              text: `\`\`\`console\n${BASH_OUTPUT.trimEnd()}\n\`\`\``,
            },
          },
        ],
      });
    } else {
      const output = { terminal_id: terminalId, data: BASH_OUTPUT };

      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId,
        _meta:
          clientTerminalOutput === 'delta'
            ? { terminal_output_delta: output }
            : { terminal_output: output },
      });
      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId,
        status: 'completed',
        content: terminal,
        _meta: {
          terminal_exit: {
            terminal_id: terminalId,
            exit_code: 0,
            signal: null,
          },
        },
      });
    }

    await turn.say('Two files changed.');

    return 'end_turn';
  },

  // A turn Claude's adapter ends with a command still running and a call
  // that never ran: cancelled, each ends `failed` with the line the adapter
  // gives, the command's terminal with no exit code; left alone, the turn
  // ends on its own and the command with the line for no result.
  async bashcut(turn) {
    const command = turn.callId('bash');
    const read = turn.callId('read');
    const takes = clientTerminalOutput !== 'none';
    const terminal = [{ type: 'terminal' as const, terminalId: command }];
    const unfinished = (
      toolCallId: string,
      text: string,
      exits: boolean,
    ): acp.SessionUpdate => ({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      status: 'failed',
      content: [{ type: 'content', content: { type: 'text', text } }],
      ...(exits && takes
        ? {
            _meta: {
              terminal_exit: {
                terminal_id: command,
                exit_code: null,
                signal: null,
              },
            },
          }
        : {}),
    });

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: command,
      title: '`bun test`',
      kind: 'execute',
      status: 'pending',
      rawInput: { command: 'bun test' },
      content: takes ? terminal : [],
      ...(takes ? { _meta: { terminal_info: { terminal_id: command } } } : {}),
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: command,
      status: 'in_progress',
    });
    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: read,
      title: 'Read package.json',
      kind: 'read',
      status: 'pending',
      locations: [{ path: 'package.json' }],
    });

    try {
      // Long enough to press Esc while the command runs.
      await pause(turn.signal, SHELL_STEP_MS * 20);
    } catch (error) {
      for (const update of [
        unfinished(
          command,
          'The turn was cancelled before this tool call returned a result.',
          true,
        ),
        unfinished(read, 'Claude stopped this tool call before it ran.', false),
      ]) {
        await turn.client.notify('session/update', {
          sessionId: turn.sessionId,
          update,
        });
      }

      throw error;
    }

    await turn.send(
      unfinished(
        command,
        'Claude ended the turn without returning a result for this tool.',
        true,
      ),
    );
    await turn.send(
      unfinished(read, 'Claude stopped this tool call before it ran.', false),
    );
    await turn.say('The tests did not report.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;

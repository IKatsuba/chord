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

/**
 * A command's permission asked as `toolCall`, with the options `agent`'s
 * adapter gives: whether it was allowed, or `undefined` when the turn was
 * cancelled while it asked.
 */
async function askToRun(
  turn: Turn,
  toolCall: acp.ToolCall,
  agent: 'Codex' | 'Claude',
): Promise<boolean | undefined> {
  const answer = await turn.client.request('session/request_permission', {
    sessionId: turn.sessionId,
    toolCall,
    options: [
      { optionId: 'allow', name: 'Yes', kind: 'allow_once' },
      {
        optionId: 'always',
        name: "Yes, and don't ask again for this command",
        kind: 'allow_always',
      },
      {
        optionId: 'deny',
        name: `No, and tell ${agent} what to do differently`,
        kind: 'reject_once',
      },
    ],
  });

  return answer.outcome.outcome === 'cancelled'
    ? undefined
    : answer.outcome.optionId !== 'deny';
}

/**
 * A command Codex's adapter has started, `in_progress` with its output
 * coming, that asks for approval part way through and stays `in_progress`
 * while it asks, as codex-acp does (CHD-404).
 */
async function codexAsksMidRun(turn: Turn): Promise<boolean | undefined> {
  const toolCallId = turn.callId('shell');
  const terminalId = `terminal-${toolCallId}`;
  const toolCall: acp.ToolCall = {
    toolCallId,
    title: 'Run ./deploy.sh',
    kind: 'execute',
    status: 'in_progress',
    rawInput: { command: ['./deploy.sh'] },
  };
  const output = (data: string, exit?: number) =>
    turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      ...(exit === undefined
        ? {}
        : { status: exit === 0 ? 'completed' : 'failed' }),
      _meta: {
        terminal_output_delta: { terminal_id: terminalId, data },
        ...(exit === undefined
          ? {}
          : {
              terminal_exit: {
                terminal_id: terminalId,
                exit_code: exit,
                signal: null,
              },
            }),
      },
    });

  await turn.send({
    sessionUpdate: 'tool_call',
    ...toolCall,
    content: [{ type: 'terminal', terminalId }],
    _meta: {
      terminal_info: {
        terminal_id: terminalId,
        cwd: cwds.get(turn.sessionId) ?? '',
      },
    },
  });
  await pause(turn.signal, SHELL_STEP_MS);
  await output('building…\n');
  await pause(turn.signal, SHELL_STEP_MS);
  await output('built in 1.2s\n');

  const allowed = await askToRun(turn, toolCall, 'Codex');

  if (allowed === undefined) {
    return undefined;
  }

  await pause(turn.signal, SHELL_STEP_MS);
  await output(allowed ? 'deployed\n' : 'not deployed\n', allowed ? 0 : 1);

  return allowed;
}

/**
 * A command Claude's adapter asks for first, `pending`, and leaves
 * `pending` once allowed until it completes, as claude-agent-acp does.
 */
async function claudeAsksFirst(turn: Turn): Promise<boolean | undefined> {
  const toolCallId = turn.callId('bash');
  const takes = clientTerminalOutput !== 'none';
  const terminal = [{ type: 'terminal' as const, terminalId: toolCallId }];
  const toolCall: acp.ToolCall = {
    toolCallId,
    title: '`git push`',
    kind: 'execute',
    status: 'pending',
    rawInput: { command: 'git push' },
  };

  await turn.send({
    sessionUpdate: 'tool_call',
    ...toolCall,
    content: takes ? terminal : [],
    ...(takes ? { _meta: { terminal_info: { terminal_id: toolCallId } } } : {}),
  });

  const allowed = await askToRun(turn, toolCall, 'Claude');

  if (allowed === undefined) {
    return undefined;
  }

  if (!allowed) {
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      status: 'failed',
    });

    return false;
  }

  await pause(turn.signal, SHELL_STEP_MS);
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'completed',
    ...(takes
      ? {
          content: terminal,
          _meta: {
            [clientTerminalOutput === 'delta'
              ? 'terminal_output_delta'
              : 'terminal_output']: {
              terminal_id: toolCallId,
              data: 'pushed\n',
            },
            terminal_exit: {
              terminal_id: toolCallId,
              exit_code: 0,
              signal: null,
            },
          },
        }
      : {
          content: [
            {
              type: 'content',
              content: { type: 'text', text: 'pushed' },
            },
          ],
        }),
  });

  return true;
}

export const SHELL = {
  // A command as Codex's adapter runs one, to any client: the terminal named
  // up front, its output in pieces as it comes, and the exit, which fails,
  // with the last of the output.
  shell: (turn) => codexShell(turn, SHELL_OUTPUT),

  shellcut: (turn) => codexShell(turn, CUT_OUTPUT),

  // A permission asked for a command as each adapter asks: Codex's mid-run,
  // the call `in_progress` with output already under it, then Claude's
  // before it runs, the call `pending` throughout.
  async bashask(turn) {
    const codex = await codexAsksMidRun(turn);

    if (codex === undefined) {
      return 'cancelled';
    }

    const claude = await claudeAsksFirst(turn);

    if (claude === undefined) {
      return 'cancelled';
    }

    await turn.say(
      `Codex: ${codex ? 'ran' : 'denied'}; Claude: ${claude ? 'ran' : 'denied'}.`,
    );

    return 'end_turn';
  },

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

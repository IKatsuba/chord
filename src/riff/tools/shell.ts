/** Shell execution through chord's process-group runner, with streamed output. */
import type { ToolCallUpdate } from '@agentclientprotocol/sdk/unstable';
import { z } from '@zod/zod';
import type { FxToolResult } from 'libfx/node';
import { Buffer } from 'node:buffer';
import { runShell } from '../../shell.ts';
import { LIMITS } from './limits.ts';

export const ShellInput = z.object({ command: z.string().min(1) }).strict();

export type ShellInput = z.infer<typeof ShellInput>;

export const SHELL_DESCRIPTION =
  'Run the exact command through the user shell in the session directory. Every ungranted command needs permission. Output streams to the window; the model receives bounded output and the exit code. Cancellation stops the whole process group.';

/** Runs one approved command; the terminal stream is independent of model caps. */
export async function shell(
  directory: string,
  input: ShellInput,
  signal: AbortSignal,
  terminalId: string,
  update: (update: ToolCallUpdate) => void | Promise<void>,
): Promise<FxToolResult> {
  signal.throwIfAborted();

  let pending = Promise.resolve();
  const send = (content: Omit<ToolCallUpdate, 'toolCallId'>) => {
    pending = pending.then(() =>
      update({ toolCallId: terminalId, ...content }),
    );
  };

  send({
    content: [{ type: 'terminal', terminalId }],
    _meta: { terminal_info: { terminal_id: terminalId, cwd: directory } },
  });

  let output = '';
  let bytes = 0;
  let lines = 0;
  let cut = false;
  const run = runShell(input.command, {
    cwd: directory,
    reap: true,
    onOutput: (_stream, text) => {
      send({
        _meta: {
          terminal_output_delta: { terminal_id: terminalId, data: text },
        },
      });

      // Iterate code points so the byte cap never cuts a UTF-8 sequence.
      for (const char of text) {
        const size = Buffer.byteLength(char);

        if (
          cut ||
          bytes + size > LIMITS.shellBytes ||
          lines >= LIMITS.shellLines
        ) {
          cut = true;

          break;
        }

        output += char;
        bytes += size;

        if (char === '\n') {
          lines++;
        }
      }
    },
  });
  const stop = () => run.stop();

  signal.addEventListener('abort', stop, { once: true });

  if (signal.aborted) {
    stop();
  }

  try {
    const end = await run.ended;

    send({
      _meta: {
        terminal_exit: {
          terminal_id: terminalId,
          exit_code: end.code ?? null,
          signal: end.signal ?? null,
        },
      },
    });
    await pending;
    signal.throwIfAborted();

    const status =
      end.error !== undefined
        ? `Shell failed: ${end.error}`
        : end.stopped === true
          ? 'Shell stopped'
          : end.signal !== undefined
            ? `Killed by ${end.signal} (exit code ${end.code ?? 'unknown'})`
            : `Exit code ${end.code ?? 'unknown'}`;

    return {
      type: 'libfx.tool-result',
      text: `${output}${cut ? '\n… output truncated' : ''}\n${status}`,
      images: [],
      isError:
        end.error !== undefined ||
        end.stopped === true ||
        end.signal !== undefined ||
        end.code !== 0,
    };
  } finally {
    signal.removeEventListener('abort', stop);
  }
}

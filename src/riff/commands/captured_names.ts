/**
 * Adapted from vercel-labs/fx v0.0.16,
 * src/core/terminal/shell_snapshot.zig:27,422-432,1070-1082, Apache-2.0.
 * chord captures only alias/function names before each reversible command,
 * through the same non-interactive shell as runShell, instead of replaying an
 * interactive snapshot. Capture failure, unknown shells and timeouts review.
 */
import { basename } from 'node:path';
import process from 'node:process';
import { runDirect } from './direct.ts';

export const CAPTURE_TIMEOUT_MS = 10_000;

const LIST_NAMES = {
  bash: 'builtin compgen -a\nbuiltin compgen -A function\nbuiltin true',
  zsh: 'builtin print -rl -- ${(k)aliases} ${(k)functions}',
};

/** fx matches every word, including arguments and words inside shell quoting. */
export function definesAnyWord(
  command: string,
  names: ReadonlySet<string>,
): boolean {
  return command
    .split(/[ \t\r\n;|&()<>'"`$\\{}!]+/)
    .some((word) => word.length > 0 && names.has(word));
}

/** The capture is fresh, cancellable, bounded and owned by this exact call. */
export async function capturedNamesAllow(
  command: string,
  options: {
    cwd: string;
    signal: AbortSignal;
    environment?: NodeJS.ProcessEnv;
  },
): Promise<boolean> {
  const { signal } = options;

  signal.throwIfAborted();

  const source = options.environment ?? process.env;
  const shell = source['SHELL'] || '/bin/sh';
  const name = basename(shell);

  if (name !== 'bash' && name !== 'zsh') {
    return false;
  }

  const environment: Record<string, string> = {};

  for (const [key, value] of Object.entries(source)) {
    if (value !== undefined) {
      environment[key] = value;
    }
  }

  let output = '';
  const run = runDirect(
    [{ executable: shell, argv: [shell, '-c', LIST_NAMES[name]], environment }],
    {
      cwd: options.cwd,
      onOutput: (stream, text) => {
        if (stream === 'stdout') {
          output += text;
        }
      },
    },
  );
  let timedOut = false;
  const deadline = setTimeout(() => {
    timedOut = true;

    run.stop();
  }, CAPTURE_TIMEOUT_MS);
  const cancel = () => run.stop();

  signal.addEventListener('abort', cancel, { once: true });

  if (signal.aborted) {
    cancel();
  }

  try {
    const end = await run.ended;

    signal.throwIfAborted();

    if (
      timedOut ||
      end.error !== undefined ||
      end.stopped ||
      end.signal !== undefined ||
      end.code !== 0
    ) {
      return false;
    }

    const names = new Set(output.split('\n').filter((word) => word.length > 0));

    return !definesAnyWord(command, names);
  } finally {
    clearTimeout(deadline);
    signal.removeEventListener('abort', cancel);
  }
}

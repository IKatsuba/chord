/**
 * Adapted from vercel-labs/fx v0.0.16,
 * src/core/terminal/shell_snapshot.zig:27,422-432,683-728,1070-1082 and
 * src/core/terminal/shell_resolver.zig:318-388, Apache-2.0.
 * chord captures only alias/function names before each reversible command,
 * through the same non-interactive shell as runShell, instead of replaying an
 * interactive snapshot. chord fixes capture IFS/globbing state, rejects
 * ambiguous names, and reaps startup children. Uncertain captures review.
 */
import { randomBytes } from 'node:crypto';
import { basename } from 'node:path';
import process from 'node:process';
import { runDirect } from './direct.ts';

export const CAPTURE_TIMEOUT_MS = 10_000;
const WORD_DELIMITERS = /[ \t\r\n;|&()<>'"`$\\{}!]+/;

/** fx's NUL-delimited, nonce-framed names section, without env or replay. */
function namesScript(shell: 'bash' | 'zsh', nonce: string): string {
  const names =
    shell === 'bash'
      ? String.raw`\builtin 'printf' '%s\0' $(\builtin 'compgen' -a) $(\builtin 'compgen' -A function)`
      : "\\builtin 'printf' '%s\\0' ${(k)aliases} ${(k)galiases} ${(k)saliases} ${(k)functions}";
  const load =
    shell === 'zsh'
      ? String.raw`\builtin 'zmodload' 'zsh/parameter' 2>/dev/null || \builtin 'exit' 125`
      : '';

  const enable =
    shell === 'bash'
      ? String.raw`\builtin 'enable' 'compgen' || \builtin 'exit' 125`
      : '';

  return String.raw`{
IFS=$' \t\n' || \builtin 'exit' 125
\builtin 'set' '-f' || \builtin 'exit' 125
${enable}
${load}
\builtin 'printf' 'FXSNAP:${nonce}:NAMES\0'
${names}
\builtin 'printf' '\0FXSNAP:${nonce}:END\0'
} 2>/dev/null`;
}

/** Startup chatter before the first nonce marker is ignored, as fx does. */
export function parseCapturedNames(
  output: string,
  nonce: string,
): ReadonlySet<string> | undefined {
  const startMarker = `FXSNAP:${nonce}:NAMES\0`;
  const endMarker = `\0FXSNAP:${nonce}:END\0`;
  const start = output.indexOf(startMarker);

  if (start < 0) {
    return undefined;
  }

  const dataStart = start + startMarker.length;
  const end = output.indexOf(endMarker, dataStart);

  // chord refuses duplicate frames or trailing output instead of guessing.
  if (
    end < 0 ||
    output.indexOf(startMarker, dataStart) >= 0 ||
    end + endMarker.length !== output.length
  ) {
    return undefined;
  }

  const names = output.slice(dataStart, end).split('\0');

  if (
    names.some(
      (name) =>
        name.startsWith('FXSNAP:') ||
        name.includes('\ufffd') ||
        WORD_DELIMITERS.test(name),
    )
  ) {
    return undefined;
  }

  return new Set(names.filter((name) => name.length > 0));
}

/** fx matches every word, including arguments and words inside shell quoting. */
export function definesAnyWord(
  command: string,
  names: ReadonlySet<string>,
): boolean {
  return command
    .split(WORD_DELIMITERS)
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

  const nonce = randomBytes(16).toString('hex');
  let output = '';
  const run = runDirect(
    [
      {
        executable: shell,
        argv: [shell, '-c', namesScript(name, nonce)],
        environment,
      },
    ],
    {
      cwd: options.cwd,
      reap: true,
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

    const names = parseCapturedNames(output, nonce);

    return names !== undefined && !definesAnyWord(command, names);
  } finally {
    clearTimeout(deadline);
    signal.removeEventListener('abort', cancel);
  }
}

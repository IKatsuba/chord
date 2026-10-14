/**
 * A shell command's output as the agent hears it: held from the run and sent
 * ahead of the next prompt, in the tags Claude Code wraps bash mode's output
 * in, so an agent that knows them reads it as it would from Claude Code. A
 * resumed session's prompts are read back the same way.
 */
import stripAnsi from 'strip-ansi';
import type { ShellRun } from './transcript/types.ts';

/**
 * The most of each stream kept, Claude Code's default for bash output: the
 * context should not swallow the agent's window.
 */
export const OUTPUT_LIMIT = 30_000;

/** Said where output was cut at `OUTPUT_LIMIT`. */
export const TRUNCATED = '… output cut';

/**
 * Output as a terminal would leave it on screen: colours and other escapes
 * gone, and of a line a progress bar rewrote with `\r`, only what was written
 * last. Trailing blank lines go too.
 */
export function cleanOutput(text: string): string {
  return stripAnsi(text)
    .replace(/\r\n/g, '\n')
    .split('\n')
    .map((line) => line.slice(line.lastIndexOf('\r') + 1))
    .join('\n')
    .replace(/\s+$/, '');
}

/**
 * How a finished run ended, when that is news: a failing exit code, a stop,
 * or a shell that never started. Undefined while it runs and on success.
 */
export function endNote(run: ShellRun): string | undefined {
  if (run.running) {
    return undefined;
  }

  if (run.error !== undefined) {
    return `Error: ${run.error}`;
  }

  if (run.stopped) {
    return STOPPED;
  }

  return run.code === undefined || run.code === 0
    ? undefined
    : `Exit code ${run.code}`;
}

const STOPPED = 'Stopped by the user';

/** The held runs as the text sent ahead of a prompt; empty when none. */
export function shellContext(runs: readonly ShellRun[]): string {
  return runs
    .map((run) => {
      const note = endNote(run);
      const cut = run.truncated ? `\n${TRUNCATED}` : '';

      return (
        `<bash-input>${run.command}</bash-input>\n` +
        `<bash-stdout>${cleanOutput(run.stdout)}${cut}</bash-stdout>` +
        `<bash-stderr>${cleanOutput(run.stderr)}</bash-stderr>` +
        (note === undefined ? '' : `<bash-status>${note}</bash-status>`)
      );
    })
    .join('\n');
}

/** `prompt` with the held output ahead of it, a blank line between. */
export function withContext(context: string, prompt: string): string {
  return context === '' ? prompt : `${context}\n\n${prompt}`;
}

const RUN =
  /^<bash-input>([\s\S]*?)<\/bash-input>\n<bash-stdout>([\s\S]*?)<\/bash-stdout><bash-stderr>([\s\S]*?)<\/bash-stderr>(?:<bash-status>([\s\S]*?)<\/bash-status>)?\n*/;

/**
 * A sent prompt taken apart again: the runs whose output went ahead of it,
 * and what was typed. A prompt with none is all typed text.
 */
export function splitContext(text: string): {
  readonly runs: readonly ShellRun[];
  readonly text: string;
} {
  const runs: ShellRun[] = [];
  let rest = text;

  for (let match = RUN.exec(rest); match; match = RUN.exec(rest)) {
    const [whole, command = '', stdout = '', stderr = '', note] = match;
    const cut = stdout.endsWith(`\n${TRUNCATED}`);

    runs.push({
      command,
      stdout: cut ? stdout.slice(0, -TRUNCATED.length - 1) : stdout,
      stderr,
      running: false,
      ...ending(note),
      ...(cut ? { truncated: true } : {}),
    });

    rest = rest.slice(whole.length);
  }

  return { runs, text: rest };
}

function ending(
  note: string | undefined,
): Pick<ShellRun, 'code' | 'stopped' | 'error'> {
  if (note === undefined) {
    return { code: 0 };
  }

  if (note === STOPPED) {
    return { stopped: true };
  }

  const code = /^Exit code (-?\d+)$/.exec(note)?.[1];

  return code === undefined
    ? { error: note.replace(/^Error: /, '') }
    : { code: Number(code) };
}

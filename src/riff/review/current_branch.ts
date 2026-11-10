/** Git proves its own current branch; detached/unavailable means no branch evidence. */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execute = promisify(execFile);

export async function currentBranch(
  directory: string,
  signal: AbortSignal,
): Promise<string | undefined> {
  try {
    const { stdout } = await execute(
      'git',
      ['symbolic-ref', '--quiet', '--short', 'HEAD'],
      {
        cwd: directory,
        signal,
        timeout: 1000,
        maxBuffer: 4096,
        encoding: 'utf8',
      },
    );

    return stdout.replace(/\r?\n$/, '') || undefined;
  } catch {
    signal.throwIfAborted();

    return undefined;
  }
}

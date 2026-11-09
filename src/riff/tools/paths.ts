/**
 * Where a tool's path really is (CHD-485, "Tools"): resolved with `realpath`
 * at the effect, not at the ask, so a symlink inside the session's directory
 * that points out of it is outside. A file is opened at its real path and
 * its handle's `dev`/`ino` compared with a `stat` of that path, so a swap in
 * between is refused; a parent directory swapped between the two is not
 * caught, as the design acknowledges.
 */
import { open, realpath, stat, type FileHandle } from 'node:fs/promises';
import { homedir } from 'node:os';
import { isAbsolute, relative, resolve, sep } from 'node:path';

/** Whether `path` is `directory` or under it; both real paths. */
export function isInside(directory: string, path: string): boolean {
  const rel = relative(directory, path);

  return (
    rel === '' ||
    (!rel.startsWith(`..${sep}`) && rel !== '..' && !isAbsolute(rel))
  );
}

/**
 * `path` as the person reads it: relative to the session's directory inside
 * it, `~`-shortened under the home directory, absolute otherwise.
 */
export function shown(directory: string, path: string): string {
  if (isInside(directory, path)) {
    return relative(directory, path) || '.';
  }

  const home = homedir();

  return isInside(home, path) ? `~${sep}${relative(home, path)}` : path;
}

/** The call's path against the session's directory, before any link. */
export function resolveIn(directory: string, path: string): string {
  return resolve(directory, path);
}

/** A file opened at its real path, its handle checked to be that file. */
export interface Opened {
  readonly real: string;
  readonly handle: FileHandle;
  readonly size: number;
}

/**
 * Opens the file at `path`'s real path for reading. Throws, with words for
 * the model, when it is missing, not a file, or not the file the path names
 * by the time it is open. `between` runs after the open and before the
 * check, for tests to swap the file there.
 */
export async function openReal(
  path: string,
  between?: () => Promise<void>,
): Promise<Opened> {
  let real: string;

  try {
    real = await realpath(path);
  } catch (error) {
    throw new Error(`${path}: ${reason(error)}`);
  }

  const handle = await open(real, 'r').catch((error: unknown) => {
    throw new Error(`${real}: ${reason(error)}`);
  });

  try {
    await between?.();

    const [held, named] = await Promise.all([handle.stat(), stat(real)]);

    if (held.dev !== named.dev || held.ino !== named.ino) {
      throw new Error(
        `${real}: the file changed while it was opened; read it again`,
      );
    }

    if (held.isDirectory()) {
      throw new Error(`${real}: is a directory; list it instead`);
    }

    if (!held.isFile()) {
      throw new Error(`${real}: not a regular file`);
    }

    return { real, handle, size: held.size };
  } catch (error) {
    await handle.close();

    throw error;
  }
}

function reason(error: unknown): string {
  const code = (error as { code?: unknown }).code;

  if (code === 'ENOENT') {
    return 'no such file';
  }

  if (code === 'EACCES' || code === 'EPERM') {
    return 'permission denied';
  }

  return error instanceof Error ? error.message : String(error);
}

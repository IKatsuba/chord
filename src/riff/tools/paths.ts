/**
 * Where a tool's path really is (CHD-485, "Tools"): resolved with `realpath`
 * at the effect, not at the ask, so a symlink inside the session's directory
 * that points out of it is outside. A file is opened at its real path and
 * its handle's `dev`/`ino` compared with the path's before and after, so a
 * swap in between is refused; a parent directory swapped between the
 * realpath and the open is not caught, as the design acknowledges.
 */
import { constants, type Stats } from 'node:fs';
import { type FileHandle, lstat, open, realpath } from 'node:fs/promises';
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

/**
 * `path`'s real path, or a refusal naming it as `label` when it has none
 * (missing, not reachable): what a permission is asked on.
 */
export async function realOf(path: string, label: string): Promise<string> {
  try {
    return await realpath(path);
  } catch (error) {
    throw new Error(`${label}: ${reason(error)}`);
  }
}

/** A file opened at its real path, its handle checked to be that file. */
export interface Opened {
  readonly real: string;
  readonly handle: FileHandle;
  readonly size: number;
}

/** How a file is opened, and points where tests swap it to force a check. */
export interface OpenSteps {
  /** The path as the person reads it, for messages; the path when not given. */
  readonly label?: string;
  /**
   * `path` is the real path a permission was asked on: one that resolves
   * elsewhere now is refused, as another file than the one allowed.
   */
  readonly exact?: boolean;
  /** After the file's identity is taken, before it is opened. */
  readonly beforeOpen?: () => Promise<void>;
  /** After it is opened, before the handle is checked. */
  readonly afterOpen?: () => Promise<void>;
}

const CHANGED = 'the file changed while it was opened; read it again';

// No link followed at the last name, and no wait on a FIFO swapped in.
const FLAGS = constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK;

/**
 * Opens the file at `path`'s real path for reading. Its identity is taken
 * before the open, which follows no link at the last name, and the handle
 * must be that file and still the one the path names: a file, a link or a
 * FIFO swapped in at any point is refused. Throws, with words for the
 * model, when it is missing, not a regular file, or not that file.
 */
export async function openReal(
  path: string,
  steps: OpenSteps = {},
): Promise<Opened> {
  let real: string;
  let before: Stats;
  const named = steps.label ?? path;

  try {
    real = await realpath(path);
    before = await lstat(real);
  } catch (error) {
    throw new Error(`${named}: ${reason(error)}`);
  }

  if (steps.exact === true && real !== path) {
    throw new Error(`${named}: ${CHANGED}`);
  }

  if (before.isDirectory()) {
    throw new Error(`${named}: is a directory; list it instead`);
  }

  if (!before.isFile()) {
    throw new Error(`${named}: not a regular file`);
  }

  await steps.beforeOpen?.();

  const handle = await open(real, FLAGS).catch((error: unknown) => {
    const code = (error as { code?: unknown }).code;

    // ELOOP: a link now stands at the last name.
    throw new Error(`${named}: ${code === 'ELOOP' ? CHANGED : reason(error)}`);
  });

  try {
    await steps.afterOpen?.();

    const [held, current] = await Promise.all([handle.stat(), lstat(real)]);
    const same = (other: Stats) =>
      held.dev === other.dev && held.ino === other.ino;

    if (!held.isFile() || !same(before) || !same(current)) {
      throw new Error(`${named}: ${CHANGED}`);
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

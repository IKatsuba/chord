/**
 * Paths as the window draws them (CHD-611, S0). ACP carries absolute paths,
 * and the wire and the records keep them; the window names a file relative
 * to the session's directory, `~`-shortened outside it, whole elsewhere, and
 * a directory `~`-shortened, as the header does. Each base is compared by
 * its real path too, so a directory reached through a link (macOS's `/tmp`)
 * reads as short as the header says it.
 */
import { realpathSync } from 'node:fs';
import { isAbsolute, relative, sep } from 'node:path';

/** The session's directory and the home directory, as given and real. */
export interface PathView {
  readonly cwds: readonly string[];
  readonly homes: readonly string[];
}

/** The view of a session in `cwd`, read once: what links they resolve to. */
export function pathView(
  cwd: string,
  home: string | undefined,
  real: (path: string) => string = realOrSame,
): PathView {
  return {
    cwds: [...new Set([cwd, real(cwd)])],
    homes: home === undefined ? [] : [...new Set([home, real(home)])],
  };
}

function realOrSame(path: string): string {
  try {
    return realpathSync(path);
  } catch {
    return path;
  }
}

/** `path` from `base` when it is `base` or under it. */
function under(base: string, path: string): string | undefined {
  const rel = relative(base, path);

  return rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel)
    ? undefined
    : rel;
}

/** `path` under a home of `view`, as `~/…`, or undefined. */
function fromHome(path: string, view: PathView): string | undefined {
  for (const home of view.homes) {
    const rel = under(home, path);

    if (rel !== undefined) {
      return rel === '' ? '~' : `~${sep}${rel}`;
    }
  }

  return undefined;
}

/**
 * A file as the window names it: from the session's directory, else from
 * `~`, else whole. Without a view, as it came.
 */
export function shownFile(path: string, view: PathView | undefined): string {
  // An agent that sends a path relative, against ACP, chose its form already.
  if (view === undefined || !isAbsolute(path)) {
    return path;
  }

  for (const cwd of view.cwds) {
    const rel = under(cwd, path);

    if (rel !== undefined) {
      return rel === '' ? '.' : rel;
    }
  }

  return fromHome(path, view) ?? path;
}

/** A directory as the header names one: from `~`, else whole. */
export function shownDirectory(
  path: string,
  view: PathView | undefined,
): string {
  return view === undefined || !isAbsolute(path)
    ? path
    : (fromHome(path, view) ?? path);
}

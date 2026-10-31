/**
 * The project's settings file as the `settings` tool reads it: chord's server
 * runs outside any agent's sandbox, and a sandboxed agent can write in its
 * project, so this must not follow a link or read what a swap put in place.
 * One read from one handle, whose bytes then serve the whole answer. A start
 * still follows links, through `loadSettings`.
 */
import { closeSync, constants, fstatSync, openSync, readSync } from 'node:fs';
import { constants as system } from 'node:os';
import { join } from 'node:path';
import { notFound } from './not_found.ts';
import { type OpenAt, openAt as libcOpenAt } from './platform/openat.ts';

/** What the read found: the bytes, nothing there, or what it would not read. */
export type ProjectRead =
  | { readonly kind: 'read'; readonly text: string }
  | { readonly kind: 'absent' }
  | { readonly kind: 'refused'; readonly what: 'directory' | 'file' };

/** What tests put between the steps, to swap a path at an exact point. */
export interface ProjectReadSeam {
  readonly afterDirectory?: () => void;
  readonly afterFile?: () => void;
  readonly afterStat?: () => void;
  /** In place of libc's, none for a libc chord cannot reach. */
  readonly openAt?: OpenAt | undefined;
}

const REFUSED_DIRECTORY: ProjectRead = { kind: 'refused', what: 'directory' };
const REFUSED_FILE: ProjectRead = { kind: 'refused', what: 'file' };
const ABSENT: ProjectRead = { kind: 'absent' };

/**
 * The most a project's settings file may hold, far past any real one: the read
 * is synchronous in the window's own process, and an agent can write in its
 * project, so a huge or sparse file must not freeze the window.
 */
const READ_LIMIT = 1024 * 1024;

/** The file's text, or undefined where it holds more than the limit. */
function boundedText(fd: number): string | undefined {
  const bytes = Buffer.alloc(READ_LIMIT + 1);
  let held = 0;

  while (held < bytes.length) {
    const read = readSync(fd, bytes, held, bytes.length - held, null);

    if (read === 0) {
      return bytes.toString('utf8', 0, held);
    }

    held += read;
  }

  return undefined;
}

/**
 * Reads `<cwd>/.chord/settings.json`: `.chord` opened no-follow, the name
 * opened inside that handle no-follow, so no later swap of either path counts,
 * and non-blocking, so a FIFO cannot hang it; then a regular file with one
 * link, as a hard link could reach anything the person can read, of a bounded
 * size, growth after the check included. Any error but
 * not-found is a refusal, and nothing is ever opened by name past `.chord`.
 */
export function readProjectFile(
  cwd: string,
  seam: ProjectReadSeam = {},
): ProjectRead {
  const open = 'openAt' in seam ? seam.openAt : libcOpenAt();
  let directory: number;

  try {
    directory = openSync(
      join(cwd, '.chord'),
      constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW,
    );
  } catch (error) {
    return notFound(error) ? ABSENT : REFUSED_DIRECTORY;
  }

  try {
    if (open === undefined) {
      return REFUSED_DIRECTORY;
    }

    seam.afterDirectory?.();

    const opened = open(
      directory,
      'settings.json',
      constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK,
    );

    if ('errno' in opened) {
      return opened.errno === system.errno.ENOENT ? ABSENT : REFUSED_FILE;
    }

    try {
      seam.afterFile?.();

      const found = fstatSync(opened.fd);

      if (!found.isFile() || found.nlink !== 1 || found.size > READ_LIMIT) {
        return REFUSED_FILE;
      }

      seam.afterStat?.();

      const text = boundedText(opened.fd);

      return text === undefined ? REFUSED_FILE : { kind: 'read', text };
    } catch {
      return REFUSED_FILE;
    } finally {
      closeSync(opened.fd);
    }
  } finally {
    closeSync(directory);
  }
}

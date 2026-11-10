/** A proposed file change, bound to the bytes the person was shown. */
import type { ToolCallContent } from '@agentclientprotocol/sdk/unstable';
import { createPatch } from 'diff';
import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, open, realpath } from 'node:fs/promises';
import { basename, dirname, join } from 'node:path';
import { notFound } from '../../not_found.ts';
import { openReal } from './paths.ts';

export const STALE =
  'the file changed since this edit was proposed; read it again';

/** The source bytes and destination shown before a permission can wait. */
export interface Proposal {
  readonly path: string;
  readonly real: string;
  readonly hash: string | null;
  readonly oldText: string | null;
  readonly newText: string;
  readonly patch: string;
  readonly content: ToolCallContent[];
}

const sha = (bytes: Uint8Array) =>
  createHash('sha256').update(bytes).digest('hex');

/** Resolves a new filename through its existing parent, never a guessed parent. */
export async function mutationPath(path: string): Promise<string> {
  try {
    return await realpath(path);
  } catch (error) {
    if (!notFound(error)) {
      throw error;
    }

    // A dangling link is an existing destination, not an absent file.
    const entry = await lstat(path).catch((error: unknown) => {
      if (!notFound(error)) {
        throw error;
      }

      return undefined;
    });

    if (entry !== undefined) {
      throw new Error('the destination is a dangling link; read it again');
    }

    return join(await realpath(dirname(path)), basename(path));
  }
}

/** Takes the pre-image and builds the proposed diff using jsdiff. */
export async function propose(
  path: string,
  change: (text: string | null) => string,
  signal: AbortSignal,
): Promise<Proposal> {
  signal.throwIfAborted();

  const real = await mutationPath(path);
  let bytes: Uint8Array | undefined;

  try {
    const opened = await openReal(real, { exact: true });

    try {
      bytes = await opened.handle.readFile();
    } finally {
      await opened.handle.close();
    }
  } catch (error) {
    // openReal supplies a readable refusal; lstat distinguishes absence
    // without treating other failures as a new file.
    await lstat(real).then(
      () => {
        throw error;
      },
      (missing: unknown) => {
        if (!notFound(missing)) {
          throw error;
        }
      },
    );
  }

  signal.throwIfAborted();

  const oldText =
    bytes === undefined ? null : Buffer.from(bytes).toString('utf8');
  const newText = change(oldText);
  const patch = createPatch(real, oldText ?? '', newText);

  return {
    path,
    real,
    hash: bytes === undefined ? null : sha(bytes),
    oldText,
    newText,
    patch,
    content: [{ type: 'diff', path: real, oldText, newText }],
  };
}

/** Rechecks the approved path and bytes before changing the held file. */
export async function apply(
  proposal: Proposal,
  signal: AbortSignal,
): Promise<void> {
  signal.throwIfAborted();

  const { path, real, hash, newText } = proposal;

  if ((await mutationPath(path)) !== real) {
    throw new Error('the file destination changed; read it again');
  }

  signal.throwIfAborted();

  const flags =
    constants.O_RDWR |
    constants.O_NOFOLLOW |
    constants.O_NONBLOCK |
    (hash === null ? constants.O_CREAT | constants.O_EXCL : 0);
  const handle = await open(real, flags).catch((error: unknown) => {
    if (notFound(error) || (error as { code?: string }).code === 'EEXIST') {
      throw new Error(STALE);
    }

    throw error;
  });

  try {
    const [held, current] = await Promise.all([handle.stat(), lstat(real)]);

    if (
      !held.isFile() ||
      held.dev !== current.dev ||
      held.ino !== current.ino ||
      current.isSymbolicLink()
    ) {
      throw new Error('the file changed while it was opened; read it again');
    }

    const bytes = await handle.readFile();

    if (hash !== null && sha(bytes) !== hash) {
      throw new Error(STALE);
    }

    signal.throwIfAborted();

    // Explicit position avoids readFile's advanced offset; truncate only
    // after the identity and pre-image checks have succeeded.
    const output = Buffer.from(newText);
    let offset = 0;

    while (offset < output.length) {
      signal.throwIfAborted();

      const result = await handle.write(
        output,
        offset,
        output.length - offset,
        offset,
      );

      offset += result.bytesWritten;
    }

    await handle.truncate(output.length);
  } finally {
    await handle.close();
  }
}

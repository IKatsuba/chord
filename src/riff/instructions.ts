/**
 * riff's instructions: chord's base text, then the `AGENTS.md` files from
 * the repository's root down to the session's directory, then the user's
 * own `AGENTS.md` in chord's config directory, read once at session start.
 */
import { constants } from 'node:fs';
import { open, stat } from 'node:fs/promises';
import { dirname, join, relative, sep } from 'node:path';
import { notFound } from '../not_found.ts';

/** What the instructions may take of libfx's 64 KiB: the owner's cap. */
export const INSTRUCTIONS_CAP = 32 * 1024;

/** Ends instructions cut at the cap, so the model knows some are missing. */
export const TRUNCATED_NOTE =
  '[chord: the instructions above were cut at 32 KiB; read the AGENTS.md files themselves for the rest.]';

/** chord's own words, before any file. */
export const BASE_INSTRUCTIONS = [
  'You are riff, the coding agent built into chord, working in the session directory named below.',
  'The AGENTS.md files below were read at the start of this session and hold the rules of the project and of the person.',
  'When you work in a folder deeper than the session directory, read any AGENTS.md in that folder and in the folders between, and follow it there: a deeper file adds to or overrides the ones above it.',
].join(' ');

const FILE = 'AGENTS.md';

export interface InstructionSources {
  /** The session's directory, as its real path. */
  readonly directory: string;
  /** chord's config home (`~/.config`); none reads no user file. */
  readonly configHome: string | undefined;
}

/** The instructions for a session in `directory`, capped. */
export async function readInstructions(
  sources: InstructionSources,
): Promise<string> {
  const parts = [
    `${BASE_INSTRUCTIONS}\n\nSession directory: ${sources.directory}`,
  ];

  const files = (await foldersOf(sources.directory)).map((folder) =>
    join(folder, FILE),
  );
  let cut = false;

  if (sources.configHome !== undefined) {
    files.push(join(sources.configHome, 'chord', FILE));
  }

  for (const file of files) {
    const read = await readOptional(file).catch((error: unknown) => {
      // The file's name and the reason, for the start's refusal.
      throw new Error(
        `${file}: ${error instanceof Error ? error.message : String(error)}`,
      );
    });

    if (read !== undefined) {
      parts.push(section(file, read.text));

      cut ||= read.cut;
    }
  }

  return capped(parts.join('\n\n'), INSTRUCTIONS_CAP, cut);
}

/**
 * The folders whose `AGENTS.md` apply, root first: the repository's root
 * down to `directory`, or `directory` alone outside a repository.
 */
export async function foldersOf(directory: string): Promise<string[]> {
  const root = await repositoryRoot(directory);

  if (root === undefined) {
    return [directory];
  }

  const folders = [root];
  let at = root;

  for (const name of relative(root, directory).split(sep).filter(Boolean)) {
    at = join(at, name);

    folders.push(at);
  }

  return folders;
}

/** The nearest folder at or above `directory` holding a `.git`. */
async function repositoryRoot(directory: string): Promise<string | undefined> {
  for (let at = directory; ; at = dirname(at)) {
    // A worktree or submodule has a `.git` file, not a folder: both count.
    if (await exists(join(at, '.git'))) {
      return at;
    }

    if (dirname(at) === at) {
      return undefined;
    }
  }
}

async function exists(path: string): Promise<boolean> {
  try {
    await stat(path);

    return true;
  } catch (error) {
    if (notFound(error)) {
      return false;
    }

    throw error;
  }
}

/**
 * `file`'s text, at most the cap's bytes of it: only a regular file, so a
 * FIFO or a device by that name never holds the session's start.
 */
async function readOptional(
  file: string,
): Promise<{ readonly text: string; readonly cut: boolean } | undefined> {
  let handle;

  try {
    if (!(await stat(file)).isFile()) {
      return undefined;
    }

    // Non-blocking, should the path become a FIFO after the stat.
    handle = await open(file, constants.O_RDONLY | constants.O_NONBLOCK);
  } catch (error) {
    if (notFound(error)) {
      return undefined;
    }

    throw error;
  }

  try {
    if (!(await handle.stat()).isFile()) {
      return undefined;
    }

    // One byte over the cap is enough for the cut to add its note.
    const buffer = new Uint8Array(INSTRUCTIONS_CAP + 1);
    let filled = 0;

    while (filled < buffer.length) {
      const { bytesRead } = await handle.read(
        buffer,
        filled,
        buffer.length - filled,
      );

      if (bytesRead === 0) {
        break;
      }

      filled += bytesRead;
    }

    const cut = filled > INSTRUCTIONS_CAP;

    return {
      text: whole(buffer.subarray(0, Math.min(filled, INSTRUCTIONS_CAP)), cut),
      cut,
    };
  } finally {
    await handle.close();
  }
}

function section(file: string, text: string): string {
  return `Instructions from ${file}:\n\n${text.trimEnd()}`;
}

/** `bytes` as text; when `cut`, without a character the cut split. */
function whole(bytes: Uint8Array, cut: boolean): string {
  const text = new TextDecoder().decode(bytes);

  return cut ? text.replace(/\uFFFD$/u, '') : text;
}

/**
 * `text` within `cap` UTF-8 bytes, cut on a character with the note; with
 * the note too when `cut` says a source was already cut short.
 */
export function capped(text: string, cap: number, cut = false): string {
  const encoder = new TextEncoder();

  if (!cut && encoder.encode(text).length <= cap) {
    return text;
  }

  const tail = `\n\n${TRUNCATED_NOTE}`;
  const room = cap - encoder.encode(tail).length;
  const bytes = encoder.encode(text).subarray(0, room);
  // A cut inside a character leaves a replacement mark: drop it.
  const kept = whole(bytes, true).trimEnd();

  return `${kept}${tail}`;
}

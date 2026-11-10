/**
 * riff's instructions: chord's base text, then the `AGENTS.md` files from
 * the repository's root down to the session's directory, then the user's
 * own `AGENTS.md` in chord's config directory, read once at session start.
 */
import { readFile, stat } from 'node:fs/promises';
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

  for (const folder of await foldersOf(sources.directory)) {
    const file = join(folder, FILE);
    const text = await readOptional(file);

    if (text !== undefined) {
      parts.push(section(file, text));
    }
  }

  if (sources.configHome !== undefined) {
    const file = join(sources.configHome, 'chord', FILE);
    const text = await readOptional(file);

    if (text !== undefined) {
      parts.push(section(file, text));
    }
  }

  return capped(parts.join('\n\n'), INSTRUCTIONS_CAP);
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

async function readOptional(file: string): Promise<string | undefined> {
  try {
    return await readFile(file, 'utf8');
  } catch (error) {
    // A folder by that name, or no file, is no instructions.
    if (
      notFound(error) ||
      (error instanceof Error && 'code' in error && error.code === 'EISDIR')
    ) {
      return undefined;
    }

    throw error;
  }
}

function section(file: string, text: string): string {
  return `Instructions from ${file}:\n\n${text.trimEnd()}`;
}

/** `text` within `cap` UTF-8 bytes, cut on a character with the note. */
export function capped(text: string, cap: number): string {
  const encoder = new TextEncoder();

  if (encoder.encode(text).length <= cap) {
    return text;
  }

  const tail = `\n\n${TRUNCATED_NOTE}`;
  const room = cap - encoder.encode(tail).length;
  const bytes = encoder.encode(text).subarray(0, room);
  // A cut inside a character leaves a replacement mark: drop it.
  const kept = new TextDecoder().decode(bytes).replace(/�$/u, '').trimEnd();

  return `${kept}${tail}`;
}

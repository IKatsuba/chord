import type { ContentBlock } from '@agentclientprotocol/sdk';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { globby } from 'globby';

/**
 * The files under `cwd` that `@` offers, as paths relative to it, the ones
 * nearest the top first: what git would track or could, so `.gitignore`d
 * output and `.git` itself stay out. globby reads every `.gitignore` in the
 * tree, nested ones included, and works outside a repository as well.
 */
export async function listFiles(cwd: string): Promise<string[]> {
  const files = await globby('**', {
    cwd,
    gitignore: true,
    dot: true,
    ignore: ['**/.git/**'],
  });

  return files.sort((a, b) => depth(a) - depth(b) || a.localeCompare(b));
}

/**
 * The `resource_link` blocks a prompt's mentions send, once each, in the
 * order typed: only the paths `@` would offer under `cwd`, so a directory, a
 * path to nothing or one outside the tree stays text alone. Each is named as
 * typed, since Codex's adapter writes the name back into the prompt.
 */
export async function mentionLinks(
  paths: readonly string[],
  cwd: string,
): Promise<ResourceLink[]> {
  if (paths.length === 0) {
    return [];
  }

  let files: Set<string>;

  // The links only add to the text, which names the paths already, so a
  // walk that fails costs the prompt nothing.
  try {
    files = new Set(await listFiles(cwd));
  } catch {
    return [];
  }

  return [...new Set(paths)]
    .filter((path) => files.has(path))
    .map((name) => ({
      type: 'resource_link',
      name,
      uri: pathToFileURL(join(cwd, name)).href,
    }));
}

/** A prompt's `resource_link` block, which ACP's own type leaves untagged. */
export type ResourceLink = Extract<ContentBlock, { type: 'resource_link' }>;

function depth(path: string): number {
  return path.split('/').length;
}

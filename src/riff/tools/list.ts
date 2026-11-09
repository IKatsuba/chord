/**
 * riff's `list` (CHD-485, "Tools"): files under the session's directory
 * matching fff's pattern, or its directories, on fff's own semantics and in
 * its order (owner). chord does not filter fff's answer.
 */
import { z } from '@zod/zod';
import type { Finder } from '../../platform/fff.ts';
import { LIMITS } from './limits.ts';

export const ListInput = z
  .object({
    pattern: z.string().describe('The glob, or the query.'),
    directories: z
      .boolean()
      .optional()
      .describe('List directories rather than files.'),
    offset: z.int().min(0).optional().describe('How many entries to skip.'),
    limit: z
      .int()
      .min(1)
      .max(LIMITS.listMax)
      .optional()
      .describe('How many entries to return.'),
  })
  .strict();

export type ListInput = z.infer<typeof ListInput>;

export const LIST_DESCRIPTION = [
  "List files under the session's directory whose path matches `pattern`,",
  "fff's glob: `*` also matches `/`, and a pattern without `/` matches at",
  'any depth (`*.ts` finds every TypeScript file, `src/*` everything under',
  "src/). Files only, as paths relative to the directory, in the index's",
  'order, not by name. With `directories: true`, lists directories instead,',
  'and `pattern` is a fuzzy query (empty for all). It leaves out files git',
  'tracks that match an ignore rule and every symlink, does not read',
  '.git/info/exclude, and outside a git repository leaves out dotfiles and',
  `node_modules. At most ${LIMITS.listPage} entries unless \`limit\` says`,
  `(up to ${LIMITS.listMax}); the answer says which \`offset\` lists on.`,
  'Nothing outside the directory can be listed.',
].join(' ');

export async function list(
  finder: Finder,
  input: ListInput,
  signal: AbortSignal,
): Promise<string> {
  const offset = input.offset ?? 0;
  const options = {
    pageIndex: offset,
    pageSize: Math.min(input.limit ?? LIMITS.listPage, LIMITS.listMax),
  };
  const { paths, total } = input.directories
    ? await finder
        .directorySearch(input.pattern, options, signal)
        .then(({ items, totalMatched }) => ({
          paths: items.map((item) => item.relativePath || './'),
          total: totalMatched,
        }))
    : await finder
        .glob(input.pattern, options, signal)
        .then(({ items, totalMatched }) => ({
          paths: items.map((item) => item.relativePath),
          total: totalMatched,
        }));

  if (paths.length === 0) {
    return total === 0
      ? 'Nothing matches.'
      : `${total} match; nothing from offset ${offset}.`;
  }

  const shownTo = offset + paths.length;
  const footer =
    shownTo < total
      ? `\n… ${shownTo} of ${total}; list on with offset ${shownTo}.`
      : '';

  return `${paths.join('\n')}${footer}`;
}

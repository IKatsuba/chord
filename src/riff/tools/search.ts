/**
 * riff's `search` (CHD-485, "Tools"): fff's grep over the session's
 * directory, on fff's own semantics and in its order (owner). chord does not
 * filter fff's answer.
 */
import { z } from '@zod/zod';
import type { GrepCursor, GrepMatch } from '@ff-labs/fff-bun';
import type { Finder } from '../../platform/fff.ts';
import { LIMITS } from './limits.ts';

export const SearchInput = z
  .object({
    query: z.string().min(1).describe('What to find.'),
    regex: z
      .boolean()
      .optional()
      .describe('Read the query as a regular expression.'),
    context: z
      .int()
      .min(0)
      .max(LIMITS.searchContext)
      .optional()
      .describe('Lines to show before and after each match.'),
    limit: z
      .int()
      .min(1)
      .max(LIMITS.searchMax)
      .optional()
      .describe('How many matches to return.'),
    page: z
      .string()
      .optional()
      .describe('The page an earlier search named, to read on.'),
  })
  .strict();

export type SearchInput = z.infer<typeof SearchInput>;

export const SEARCH_DESCRIPTION = [
  "Search the contents of the files under the session's directory. The",
  'query is plain text, or a regular expression with `regex: true`; there',
  '`\\s` also matches a line break, so a match may span two lines and is',
  'reported at its first. Case-insensitive when the query is all lowercase.',
  'Narrow it by a constraint before the text: `src/ needle` searches under',
  "src/, `*.ts needle` only TypeScript files. Matches come in the index's",
  'order (recently changed files first), not by path, as `path:line: text`,',
  `with \`context\` lines around each (up to ${LIMITS.searchContext}); at`,
  `most ${LIMITS.searchPerFile} from one file and ${LIMITS.searchPage} in`,
  `all unless \`limit\` says (up to ${LIMITS.searchMax}). When more is left,`,
  'the answer names a `page` that reads on. It skips binary files, files git',
  'tracks that match an ignore rule and symlinks, does not read',
  '.git/info/exclude, and outside a git repository skips dotfiles and',
  'node_modules. Nothing outside the directory can be searched.',
].join(' ');

/**
 * A session's searches: fff's cursors cannot be written by hand, so each
 * one it gives is kept here under a name the model passes back.
 */
export function searcher(finder: Finder) {
  const pages = new Map<string, GrepCursor>();
  let named = 0;

  return async (input: SearchInput, signal: AbortSignal): Promise<string> => {
    const cursor = input.page === undefined ? null : pages.get(input.page);

    if (cursor === undefined) {
      throw new Error(`no page ${input.page ?? ''}; search again without it`);
    }

    const context = Math.min(input.context ?? 0, LIMITS.searchContext);
    const found = await finder.grep(
      input.query,
      {
        mode: input.regex ? 'regex' : 'plain',
        cursor,
        pageSize: Math.min(input.limit ?? LIMITS.searchPage, LIMITS.searchMax),
        maxMatchesPerFile: LIMITS.searchPerFile,
        timeBudgetMs: LIMITS.searchMs,
        // A bound even when nothing has matched yet, which fff waives by default.
        enforceTimeBudget: true,
        beforeContext: context,
        afterContext: context,
      },
      signal,
    );
    const out = found.items.map(shownMatch);

    if (found.regexFallbackError !== undefined) {
      out.unshift(
        `The expression did not compile (${found.regexFallbackError}); searched as plain text.`,
      );
    }

    if (found.items.length === 0) {
      out.push('Nothing matches.');
    }

    if (found.nextCursor !== null) {
      const page = `p${++named}`;

      pages.set(page, found.nextCursor);
      out.push(`… more matches; search again with page "${page}".`);
    }

    return out.join('\n');
  };
}

function shownMatch(match: GrepMatch): string {
  const at = (line: number, text: string, mark: string) =>
    `${match.relativePath}${mark}${line}${mark} ${text}`;
  const before = match.contextBefore ?? [];
  const after = match.contextAfter ?? [];

  return [
    ...before.map((text, index) =>
      at(match.lineNumber - before.length + index, text, '-'),
    ),
    at(match.lineNumber, match.lineContent, ':'),
    ...after.map((text, index) => at(match.lineNumber + 1 + index, text, '-')),
  ].join('\n');
}

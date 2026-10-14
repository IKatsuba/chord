/**
 * `@` file mentions: the part of a path being typed at the cursor, the files
 * it matches, and what picking one does to the draft. The window walks the
 * files, draws the list and dispatches; nothing here touches a terminal.
 */
import { byLengthAsc, Fzf } from 'fzf';
import type { Cursor } from './prompt.ts';

/** An `@` and the path typed after it, up to the cursor. */
export interface Mention {
  /** What follows the `@`, which the files are matched against. */
  readonly query: string;
  /** Where the `@` is: its line, and its column on that line. */
  readonly line: number;
  readonly column: number;
}

/**
 * The mention the cursor is at the end of: an `@` at the start of a line or
 * after a space, then no space up to the cursor. An `@` inside a word, as in
 * an email address, is none.
 */
export function mentionAt(
  draft: string,
  [line, column]: Cursor,
): Mention | undefined {
  const before = draft.split('\n')[line]?.slice(0, column);
  const found = before === undefined ? null : /(^|\s)@(\S*)$/.exec(before);

  if (!found) {
    return undefined;
  }

  const query = found[2] ?? '';

  return { query, line, column: column - query.length - 1 };
}

/**
 * The most files the finder matches at once. The list shows a few rows, and
 * scoring a whole large tree on every key costs more than it shows.
 */
const MATCH_LIMIT = 100;

/**
 * The files `query` matches, best first, by fzf's scoring: the letters in
 * order anywhere in the path, the shorter path first on a tie, whatever the
 * case. The files in their order for an empty query.
 */
export function matchFiles(files: readonly string[], query: string): string[] {
  if (query === '') {
    return files.slice(0, MATCH_LIMIT);
  }

  return new Fzf(files, {
    casing: 'case-insensitive',
    limit: MATCH_LIMIT,
    tiebreakers: [byLengthAsc],
  })
    .find(query)
    .map(({ item }) => item);
}

/**
 * The draft with `path` in place of the mention being typed, and the cursor
 * after it. A space follows, so the next word starts clear of it and the list
 * closes; a path with a space in it is quoted, as Claude Code writes it.
 */
export function insertMention(
  draft: string,
  cursor: Cursor,
  mention: Mention,
  path: string,
): { readonly text: string; readonly cursor: Cursor } {
  const lines = draft.split('\n');
  const current = lines[mention.line] ?? '';
  // The rest of a path the cursor stood inside goes with the part before it.
  const rest = current.slice(cursor[1]).replace(/^\S*/, '');
  const written = `@${/\s/.test(path) ? `"${path}"` : path}`;

  lines[mention.line] =
    current.slice(0, mention.column) +
    written +
    (rest.startsWith(' ') ? rest : ` ${rest}`);

  return {
    text: lines.join('\n'),
    cursor: [mention.line, mention.column + written.length + 1],
  };
}

/**
 * The paths a prompt mentions, in the order typed: each `@` at the start of a
 * line or after a space, then a path as `insertMention` writes it, quoted
 * when it has a space in it. Whether each is a file is for the session to
 * find out.
 */
export function mentionsIn(text: string): string[] {
  return [...text.matchAll(/(?:^|\s)@(?:"([^"\n]+)"|([^\s"]\S*))/g)].map(
    (found) => found[1] ?? found[2] ?? '',
  );
}

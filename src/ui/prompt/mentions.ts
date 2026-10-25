/**
 * File and agent mentions: the query being typed at the cursor, the names
 * it matches, and what picking one does to the draft. The window walks the
 * files, draws the list and dispatches; nothing here touches a terminal.
 */
import { AsyncFzf, byLengthAsc } from 'fzf';
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
  const found = before === undefined ? null : /(^|\s)@(?!@)(\S*)$/.exec(before);

  if (!found) {
    return undefined;
  }

  const query = found[2] ?? '';

  return { query, line, column: column - query.length - 1 };
}

/** A quoted agent query can contain spaces up to its closing quote. */
export interface AgentMention extends Mention {
  readonly quoted: boolean;
}

/** Agent completion shares file mention boundaries, with a second `@`. */
export function agentMentionAt(
  draft: string,
  [line, column]: Cursor,
): AgentMention | undefined {
  const before = draft.split('\n')[line]?.slice(0, column);
  const found =
    before === undefined
      ? null
      : /(^|\s)@@(?:"([^"\n]*)|([^\s"]*))$/.exec(before);

  if (!found) {
    return undefined;
  }

  const quoted = found[2] !== undefined;
  const query = found[2] ?? found[3] ?? '';

  return {
    query,
    line,
    column: column - query.length - (quoted ? 3 : 2),
    quoted,
  };
}

/** The agent trigger takes precedence over an `@` inside a quoted name. */
export function completionAt(
  draft: string,
  cursor: Cursor,
): Mention | AgentMention | undefined {
  const before = draft.split('\n')[cursor[0]]?.slice(0, cursor[1]) ?? '';

  // A completed quoted agent name may itself contain ` @`; that text
  // cannot reopen the file finder before the next separating space.
  if (/(^|\s)@@"[^"\n]*"[^\s]*$/.test(before)) {
    return undefined;
  }

  return agentMentionAt(draft, cursor) ?? mentionAt(draft, cursor);
}

/** Equal names insert the same text, which routing resolves to the first. */
export function mentionRecipients<T extends { readonly name: string }>(
  recipients: readonly T[],
): readonly T[] {
  return recipients.filter(
    (each, at) =>
      recipients.findIndex((other) => other.name === each.name) === at,
  );
}

/**
 * The most files the finder matches at once. The list shows a few rows, and
 * scoring a whole large tree on every key costs more than it shows.
 */
const MATCH_LIMIT = 100;

/** The files an empty query shows: the walk's first, in its order. */
export function firstFiles(files: readonly string[]): readonly string[] {
  return files.slice(0, MATCH_LIMIT);
}

/**
 * The AsyncFzf built over the last files list. fzf's own async finder
 * scores in chunks and yields between them, so a key typed after an `@`
 * on a large tree never blocks the window; a newer find cancels the one
 * still running.
 */
let finder:
  | {
      readonly files: readonly string[];
      readonly fzf: AsyncFzf<readonly string[]>;
    }
  | undefined;

/**
 * The files `query` matches, best first, by fzf's scoring: the letters in
 * order anywhere in the path, the shorter path first on a tie, whatever the
 * case. None when a newer match cancelled this one before it finished.
 */
export async function matchFiles(
  files: readonly string[],
  query: string,
): Promise<readonly string[] | undefined> {
  if (finder?.files !== files) {
    finder = {
      files,
      fzf: new AsyncFzf(files, {
        casing: 'case-insensitive',
        limit: MATCH_LIMIT,
        tiebreakers: [byLengthAsc],
      }),
    };
  }

  try {
    return (await finder.fzf.find(query)).map(({ item }) => item);
  } catch (error) {
    // AsyncFzf rejects the find a newer one took the place of.
    if (error === 'search cancelled') {
      return undefined;
    }

    throw error;
  }
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
 * Agent names use the file finder's quoting, without escaping: the sent
 * mention is plain text, so chord never has to parse the chosen name back.
 */
export function insertAgentMention(
  draft: string,
  cursor: Cursor,
  mention: AgentMention,
  name: string,
): { readonly text: string; readonly cursor: Cursor } {
  const lines = draft.split('\n');
  const current = lines[mention.line] ?? '';
  const suffix = current.slice(cursor[1]);
  const closing = suffix.indexOf('"');
  const rest = mention.quoted
    ? closing < 0
      ? ''
      : suffix.slice(closing + 1)
    : suffix.replace(/^\S*/, '');
  const written = `@@${/\s/.test(name) ? `"${name}"` : name}`;

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
  // Consume agent tokens, including quoted spaces, so their contents cannot
  // turn into file attachments. Only the single-@ alternative captures paths.
  return [
    ...text.matchAll(
      /(?:^|\s)(?:@@(?:"[^"\n]*(?:"|$)|\S*)|@(?:"([^"\n]+)"|([^@\s"]\S*)))/gm,
    ),
  ].flatMap((found) => {
    const path = found[1] ?? found[2];

    return path === undefined ? [] : [path];
  });
}

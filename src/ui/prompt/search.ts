/**
 * Reverse history search, as ctrl+r has it in a shell and in Claude Code: the
 * newest earlier prompt containing what is typed, and each ctrl+r after it
 * the next older one. The match is plain substring, as in Claude Code.
 */

export interface Search {
  /** What is typed after `search prompts:`. */
  readonly query: string;
  /**
   * The prompt shown, as an index into history's prompts; undefined until the
   * query matches one, while the box shows the draft.
   */
  readonly match: number | undefined;
  /**
   * The last query or ctrl+r found nothing. The last match, if any, stays in
   * the box, as a shell's search keeps it.
   */
  readonly failed: boolean;
}

export const emptySearch: Search = {
  query: '',
  match: undefined,
  failed: false,
};

/**
 * The newest prompt before `before` that contains `query`. A prompt sent more
 * than once counts where it was sent last, so ctrl+r never shows it twice. An
 * empty query matches nothing.
 */
function find(
  prompts: readonly string[],
  query: string,
  before: number,
): number | undefined {
  if (query === '') {
    return undefined;
  }

  for (let index = before - 1; index >= 0; index--) {
    const prompt = prompts[index]!;

    if (prompt.includes(query) && prompts.lastIndexOf(prompt) === index) {
      return index;
    }
  }

  return undefined;
}

/** The query changed: the newest prompt that contains it, from the top again. */
export function searched(
  search: Search,
  prompts: readonly string[],
  query: string,
): Search {
  const match = find(prompts, query, prompts.length);

  if (match === undefined) {
    return {
      query,
      match: query === '' ? undefined : search.match,
      failed: query !== '',
    };
  }

  return { query, match, failed: false };
}

/** ctrl+r again: the next older prompt that contains the query. */
export function searchedOlder(
  search: Search,
  prompts: readonly string[],
): Search {
  const match = find(prompts, search.query, search.match ?? prompts.length);

  if (match === undefined) {
    return search.query === '' || search.failed
      ? search
      : { ...search, failed: true };
  }

  return { ...search, match, failed: false };
}

/** The prompt the search shows, or undefined while the box shows the draft. */
export function matched(
  search: Search,
  prompts: readonly string[],
): string | undefined {
  return search.match === undefined ? undefined : prompts[search.match];
}

/** What a key does to the query: undefined when it is not an edit of it. */
export function editedQuery(
  query: string,
  input: string,
  key: {
    readonly ctrl: boolean;
    readonly meta?: boolean;
    readonly backspace?: boolean;
    readonly delete?: boolean;
  },
): string | undefined {
  if (key.backspace || key.delete) {
    // By code point, so an emoji goes in one press.
    return Array.from(query).slice(0, -1).join('');
  }

  if (key.ctrl || key.meta) {
    return undefined;
  }

  // A paste of several lines searches for its first; prompts are matched
  // whole, but a newline cannot be typed into the search line.
  const text = input.split(/\r?\n|\r/)[0]!.replace(/\p{Cc}/gu, '');

  return text === '' ? undefined : query + text;
}

/** The search line under the box, where the status line is. */
export function searchLabel(search: Search): string {
  return search.failed ? 'no matching prompt:' : 'search prompts:';
}

/** Finds `query` in the shown match, for the box to highlight it. */
export function queryPattern(query: string): RegExp | undefined {
  return query === '' ? undefined : new RegExp(RegExp.escape(query), 'g');
}

/**
 * `text` in runs, each with whether it is `query`, for the box to draw what
 * was found inverse: split by the string, so nothing is measured.
 */
export function foundPieces(
  text: string,
  query: string,
): { text: string; found: boolean }[] {
  const pattern = queryPattern(query);
  const pieces: { text: string; found: boolean }[] = [];
  let at = 0;

  for (const match of pattern === undefined ? [] : text.matchAll(pattern)) {
    if (match.index > at) {
      pieces.push({ text: text.slice(at, match.index), found: false });
    }

    pieces.push({ text: match[0], found: true });

    at = match.index + match[0].length;
  }

  return at < text.length || pieces.length === 0
    ? [...pieces, { text: text.slice(at), found: false }]
    : pieces;
}

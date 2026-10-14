/**
 * An edit as the rows drawn under its call: jsdiff's hunks, numbered and
 * marked, folded to a few rows until ctrl+o.
 */
import { structuredPatch } from 'diff';
import { highlightLines, pathLanguage } from '../highlight.ts';
import type { CodeTones } from '../../theme/theme.ts';

/** One drawn row of a diff; a `gap` stands between two hunks. */
export type DiffRow =
  | {
      readonly kind: 'added' | 'removed' | 'context';
      readonly number: number;
      readonly text: string;
      /** `text` coloured by the file's language, when the theme colours it. */
      readonly code?: string;
    }
  | { readonly kind: 'gap' };

/** What one diff content of a call draws as. */
export interface DiffView {
  readonly path: string;
  readonly added: number;
  readonly removed: number;
  readonly rows: readonly DiffRow[];
  /** Changed and context lines folded away; gaps are not counted. */
  readonly hidden: number;
  /** Cells the widest line number shown takes, so the marks line up. */
  readonly numberWidth: number;
}

/** Lines of unchanged text kept around each change, as in `diff -u`. */
export const DIFF_CONTEXT = 3;

/**
 * Rows a folded diff shows: enough to read a small edit whole, few enough
 * that a large one leaves the prompt on an 80×24 screen.
 */
export const DIFF_ROWS = 10;

/** A tab is as wide as the terminal's next stop, which a layout cannot know. */
const TAB = '  ';

/**
 * The rows of the edit from `oldText` to `newText`; with a theme's `tones`,
 * each row's code too, coloured by `path`'s extension: the changed rows' on
 * the tint, which a theme without one leaves plain.
 */
export function diffView(
  path: string,
  oldText: string | null | undefined,
  newText: string,
  expanded: boolean,
  tones?: CodeTones,
  {
    context = DIFF_CONTEXT,
    rows: kept = DIFF_ROWS,
  }: {
    /** Unchanged lines around each change. */
    context?: number;
    /** Rows a folded diff keeps. */
    rows?: number;
  } = {},
): DiffView {
  // A line ending is not an edit: agents differ on CRLF and the final newline.
  const patch = structuredPatch(
    path,
    path,
    withFinalNewline(oldText ?? ''),
    withFinalNewline(newText),
    '',
    '',
    { context, stripTrailingCr: true },
  );
  const code = tones && coloured(path, oldText ?? '', newText, tones);
  const rows: DiffRow[] = [];
  let added = 0;
  let removed = 0;

  for (const [index, hunk] of patch.hunks.entries()) {
    if (index > 0) {
      rows.push({ kind: 'gap' });
    }

    let oldNumber = hunk.oldStart;
    let newNumber = hunk.newStart;

    for (const line of hunk.lines) {
      const text = line.slice(1).replaceAll('\t', TAB);
      const row = (kind: 'added' | 'removed' | 'context', number: number) =>
        withCode({ kind, number, text }, code);

      switch (line[0]) {
        case '+':
          added += 1;

          rows.push(row('added', newNumber++));
          break;
        case '-':
          removed += 1;

          rows.push(row('removed', oldNumber++));
          break;
        case ' ':
          rows.push(row('context', newNumber++));
          oldNumber++;
          break;
      }
    }
  }

  const shown = expanded ? rows : fold(rows, kept);

  return {
    path,
    added,
    removed,
    rows: shown,
    hidden: lineCount(rows) - lineCount(shown),
    numberWidth: Math.max(
      1,
      ...shown.map((row) =>
        row.kind === 'gap' ? 0 : String(row.number).length,
      ),
    ),
  };
}

/** `Updated src/a.ts with 2 additions and 1 removal`. */
export function diffHeadline(view: DiffView): string {
  return `Updated ${view.path} with ${plural(view.added, 'addition')} and ${plural(
    view.removed,
    'removal',
  )}`;
}

/** `row` with its line's coloured code, when there is some. */
function withCode(
  row: DiffRow & { kind: 'added' | 'removed' | 'context' },
  code: Coloured | undefined,
): DiffRow {
  const lines =
    row.kind === 'removed'
      ? code?.old
      : row.kind === 'added'
        ? code?.new
        : code?.context;
  const own = lines?.[row.number - 1]?.replaceAll('\t', TAB);

  return own === undefined ? row : { ...row, code: own };
}

/**
 * Each side of an edit, a coloured line to each of its lines: both sides for
 * the changed rows' tint, and the new side again for the unchanged rows, which
 * sit on the terminal's own background.
 */
interface Coloured {
  /** None where the theme has no tint: its changed rows go uncoloured. */
  readonly old: readonly string[] | undefined;
  readonly new: readonly string[] | undefined;
  readonly context: readonly string[] | undefined;
}

/**
 * Both texts' lines highlighted whole, so a row inside a comment or a string
 * that opened rows above it is coloured as one; none for a file whose
 * language highlight.js does not know. Line endings go as they do for the
 * diff, so a line's number finds its line.
 */
function coloured(
  path: string,
  oldText: string,
  newText: string,
  tones: CodeTones,
): Coloured | undefined {
  const language = pathLanguage(path);

  if (language === undefined) {
    return undefined;
  }

  const lines = (text: string, on: CodeTones['tint']) =>
    on === undefined
      ? undefined
      : highlightLines(text.replaceAll('\r\n', '\n'), language, on);

  return {
    old: lines(oldText, tones.tint),
    new: lines(newText, tones.tint),
    context: lines(newText, tones.terminal),
  };
}

function withFinalNewline(text: string): string {
  return text === '' || text.endsWith('\n') ? text : `${text}\n`;
}

/** The first rows, never ending on a gap that leads to nothing shown. */
function fold(rows: readonly DiffRow[], kept: number): readonly DiffRow[] {
  const shown = rows.slice(0, kept);

  return shown.at(-1)?.kind === 'gap' ? shown.slice(0, -1) : shown;
}

export function lineCount(rows: readonly DiffRow[]): number {
  return rows.filter((row) => row.kind !== 'gap').length;
}

export function plural(count: number, word: string): string {
  return `${count} ${word}${count === 1 ? '' : 's'}`;
}

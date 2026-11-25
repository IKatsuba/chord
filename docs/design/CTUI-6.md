# CTUI-6: Diff

A passive numbered diff, following `../chord/src/ui/transcript/tools/diff.ts`,
Tool.tsx's DiffRows and `../chord/docs/images/edit.png`. Highlighting is
CTUI-5's shared module; styles are CTUI-3's DiffTheme and CodeTones.

## Call site and API

```dart
Diff(oldText, newText, title: 'src/greeting.ts');
Diff('', newFile, title: 'lib/new_file.dart');
Diff.fromUnified(patch, title: 'src/greeting.ts');

class Diff extends StatefulWidget {
  const Diff(this.oldText, this.newText, {
    super.key,
    this.title,
    this.context = 3,
  });
  factory Diff.fromUnified(String patch, {Key? key, String? title});
  final String oldText;
  final String newText;
  final String? title;
  final int context;
}
```

The named constructor represents parsed unified input internally; the
pseudocode fields above describe the old/new constructor, not a required
storage representation. context is non-negative and controls unchanged
lines around generated hunks (default 3, chord's DIFF_CONTEXT). Unified
input keeps its supplied hunk boundaries; it has no context argument.

Title is optional, dim and wrapped to available width, immediately above
the rows without a blank row. It is also the path passed to pathLanguage.
For unified input an explicit title wins; otherwise use the new header's
path (old path for a deleted file), removing the conventional a/ or b/
prefix. A raw hunk with no file headers is accepted; absent an explicit
title it has no title and draws plain code. No guessed language. Do not
invent Updated/count wording, a tool marker or result gutter: those are
the port's, as in edit.png. No box or outer padding is added.

Diff takes available width and content height; an ancestor scrolls or
clips it. No folding, selection, focus, buttons or actions are built in,
so there are no additional shortcuts-panel entries. CTUI-16 supplies the
port's ctrl+o folding and surrounding tool headline. The framework always
lays out all supplied hunks; no ten-row cutoff or hidden-row message.

## Diff model and hunks

Use a maintained diff package, with the package trials and AOT result in
developer's handover. Compare lines, not characters. Follow chord's
stripTrailingCr: CRLF versus LF is not an edit, and a missing final newline
alone is not an edit. Empty oldText means a new file; empty newText means
removal. Equal inputs produce no rows; an explicitly supplied title still
draws. Preserve all actual blank lines and spaces within content.

Generated hunks keep context unchanged lines around each change and merge
when their context ranges overlap or meet. Like diff.ts, draw one dim gap
row `…` between disjoint hunks, in the sign column; no leading or trailing
gap and no printed @@ range heading. Never show an orphan gap with no
following hunk. This widget does not fold, so every changed/context row is
shown and no rows are counted as hidden. The hunk model keeps both old and
new starts/counts for numbering even though ranges are not printed.

The lead settled the ambiguous request for old/new gutters: use chord's
one shared gutter, old line numbers on removals, new numbers on additions
and context. Advance old only for removal, new only for addition, both for
context. Number width is the digits of the largest displayed number,
at least one, shared by all hunks. Numbers are right-aligned in theme.dim,
then a space, a sign (`+`, `-`, or space), then a space, then code.

## Highlighting, tint and wrapping

Highlight complete old and new sources before taking their diff rows, so
multiline grammar state survives context omitted from the view. Context
uses the new source and theme.code.terminal. Added and removed lines use
their respective source and theme.code.tint on tinted rows.

| Row | Number | Sign | Code and row background |
| --- | --- | --- | --- |
| Context | theme.dim | Plain space | Inherited/theme.text with terminal code tones |
| Added, tint present | theme.dim | theme.diff.added | tint.added background, tint.text base, code.tint tokens |
| Removed, tint present | theme.dim | theme.diff.removed | tint.removed background, tint.text base, code.tint tokens |
| Added, no tint | theme.dim | theme.diff.added | Entire code in theme.diff.added; no syntax tones |
| Removed, no tint | theme.dim | theme.diff.removed | Entire code in theme.diff.removed; no syntax tones |

Tint fills the complete available row, number gutter and trailing empty
cells included, on every continuation too. Unknown language still gets
tint and tint.text without tokens. theme.code null disables highlighting;
plain theme has neither tint nor syntax colour and retains visible signs.
An empty changed line still paints its tint and sign.

Tabs render as two spaces as in diff.ts. Source lines wrap by cells at the
width left after the gutter, preserving whitespace and whole graphemes.
Continuations have blank numbers and signs and start at exactly the code
column. No ↪ here: DiffRows uses the hanging gutter to show continuation,
which also keeps a code character out of the diff sign column. Width
changes rewrap without diffing or highlighting again. When the usual gutter
leaves no code room, clip furniture/content to the actual constraint and
never paint outside it; zero width draws nothing. Vertical overflow is
clipped only by ancestors; no ellipsis replaces unseen content here.

## Unified input

Accept one file's ordinary unified diff with optional ---/+++ headers,
@@ ranges and context/add/remove lines. Validate through dartdiff's jsdiff
rules, as chord's own library does: a count of 1 with no corresponding
lines reads as 0 (the omitted-count rule); an empty line inside a hunk is
a blank context line; any line beginning with `\` is metadata and is not
drawn. These are accepted input semantics, not validation failures. Other
malformed input and multi-file patches still raise FormatException, as
settled by the lead. Do not silently draw a partly parsed patch. The
package trial must establish whether unified parsing is provided; a
missing capability goes to the lead before any parser workaround.

Unified input has only the visible hunk content. Build old/new contiguous
runs within each hunk, highlight each as a whole, and reset grammar state
across omitted regions. Context rows use new-side highlighting. A comment
opened outside a hunk cannot be recovered; this is a documented input
limitation, unlike the old/new constructor which sees complete files.
Styles, number increments and wrapping otherwise match generated diffs.

Cache parsed/generated rows for the current input, independent of width
and theme; cache highlighting through CTUI-5. Changed source/context drops
the generated model. A theme change recolours without diffing; a resize
only relays out. Keep reducers/models pure Dart so tests reach their logic.

## Text sketches

Layout sketches, not runtime captures; unshown viewport rows are blank.
The title is dim. Changed rows in these examples have full-width green/red
tints with highlighted code; numbers stay dim. The edit.png content at
120x40, without the port's Edit/Updated words or its outer gutter:

```text
src/greeting.ts
1 + /** Greets someone by name. */
2   export function greet(name: string): string {
2 -   return "hello " + name;
3 +   return `hello, ${name}`;
4   }
```

80x24, same content: identical rows, tint stops at column 80 instead of
120. An overflowing edit at 80x24 shows its continuation under code:

```text
src/greeting.ts
12 -   return 'A message about terminal cells, 日本語, and preserving every
     grapheme while the source line wraps';
12 +   return 'A shorter message';
   …
47     save();
```

The gutter width is two; code begins at column 6 (shown indentation in the
source follows it). Only the first visual row has `12 -`. At 120x40 this
same source line fits on one row. Empty/equal files have no diff rows;
unknown language and plain theme keep this geometry. Focus changes nothing.

## Differences and acceptance

No deliberate row-layout difference from chord. The lead explicitly chose
the original's shared gutter. Title-only decoration and showing all hunks
are framework boundaries: the port supplies chord's surrounding text and
fold state in CTUI-16. Unified input's missing grammar context is inherent
in that representation and must be reported with its captures.

Checks cover generated and unified equivalence, insertion/deletion, empty
and equal files, CRLF/final-newline handling, hunk context/merging/gaps,
old/new numbering, malformed/multi-file patches, multiline grammar state,
unknown language, tint/no tint/plain, blank changed lines, trailing tint,
whitespace and wide graphemes. Verify wrapped code's first column and blank
continuation gutters at 120x40 and 80x24. Developer supplies a runnable
fixture at visual handover; designer checks only the handed-over unit and
saves captures before reviewer handover.

# CTUI-4: Markdown

Markdown drawn as cells using a maintained parser, Code and the framework's
text layout. References: `../chord/src/ui/transcript/markdown.ts`, Reply.tsx,
CHD-394 (code boxes) and CHD-396 (soft wrapping and block gaps). CTUI-16's
reply gutter, code picking, copy/run actions and folding are outside this
framework slice.

## Call site and API

```dart
Markdown(text);
ListView.builder(
  itemCount: replies.length,
  itemVersion: (i) => replies[i],
  itemBuilder: (context, i) => Markdown(replies[i]),
);

class Markdown extends StatefulWidget {
  const Markdown(this.text, {super.key});
  final String text;
}
```

A String is sufficient. No port-specific TextRun, stream, width or theme
parameter. Constraints provide width, Theme supplies styles, State retains
parsing work while the widget stays mounted. A stable key preserves that
state across parent rebuilds. No focus, pointer requirement or actions:
links are styled text; opening links and copying are future app actions.
No new shortcut is needed for this passive widget.

## Blocks and inline text

| Part | Drawing |
| --- | --- |
| h1 | Bold and underlined text; omit the source's hash marks |
| h2–h6 | Bold text, no hashes |
| Paragraph | Soft source breaks join with spaces; explicit hard breaks remain |
| Strong / emphasis / strike | Bold / italic / strikethrough |
| Inline code | theme.inlineCode; preserve its text |
| Link | Underlined theme.link text, then dim ` (url)` when URL differs from text; mailto links plain |
| Reference definition | Its source line, shown where it stands |
| Image | Draws nothing |
| Rule | Dim `—` repeated min(width, 40) times |
| Unordered list | Dim `- ` marker, hanging content |
| Ordered list | Dim numbers counted from the list's start, then `. ` |
| Task list | Dim `[ ] ` or `[x] ` marker |
| Nested list | Indented within the parent's content column; never under its marker |
| Quote | Dim `│ ` before dim italic content, nesting repeats the inset |
| Table | Single-line grid, bold headings, dim borders, source alignment |
| Code | A single-border box labelled with the fence's first word; Code inside |

All body text starts from inherited style merged with theme.text; inline
roles and weight/slant overlay it. Input escape sequences cannot install
terminal styles or control the terminal. No colour literals or parser HTML
output reach the renderer. Parser extension choices must cover the task's
GFM tables and task lists; package trials are developer's handover evidence.
If the selected package cannot supply the required parse boundaries, ask
the lead before adding a parser workaround.

Lists hang wrapped text under their content. Nested blocks receive only
the width remaining after markers and insets. Quotes keep their bar on
every visual row. Tables have one cell of padding on each side of each
cell's content. Cap each padded column at 40 cells (38 content cells).
Shrink the widest column using markdansi's fit arithmetic, including its
extra two cells per column, even where this shrinks more than a strict
grid-width fit requires. This matches chord at the same width. Cells wrap
within the resulting content widths. If a word still overflows, render every cell as one line cut
with `…`, rather than mixing wrapped and truncated cells. At widths smaller
than table furniture, clip the grid to the constraint without splitting a
wide grapheme. Headers stay bold, borders dim, and source alignment is
retained. This widget does not add the future public Table API.

Code boxes use Border.single and theme.border, one space each side, no
vertical padding. Each body row is `│ ` + Code's two-cell mark gutter +
source + ` │`: six cells beyond the source width. Width is the lesser of
available width and the larger of widest source line plus six cells or
label plus four cells. The top border is `┌ dart ─…┐`, with the label in
theme.border, not bold. Omit the label below label width plus four cells. Unknown labels remain visible, their code
plain; no label gives an unlabelled box. Code receives language from
fenceLanguage(label), softWrap true and lineNumbers false. Preserve code's
leading/interior/trailing blank lines as parsed content; the fence's own
structural final newline is not an extra blank code row. Indented code
uses the same unlabelled box. Quotes and list items use the same code
content at their inset width. Boxes remain ordinary layout decoration,
with no buttons in this slice.

## Spacing

CHD-396's decisions, not the number of blank lines in source:

| Between | Blank screen rows |
| --- | --- |
| Any two visible top-level blocks | One |
| Two loose-list items, or blocks within a loose-list item | One |
| Tight-list items, an item's text and nested list/code | None |
| Blocks inside a quote | None |
| Before the first block / after the last | None |

Empty input draws no rows. Blank-only source draws no blocks. Unfinished
inline delimiters stay literal until paired, as the parser decides. An
open fence is a code box to the end of the current String; appending its
closing fence completes it without losing the visible body. A table header
without its delimiter is a paragraph; once the delimiter arrives, the
active tail becomes a table. An incomplete final table row draws the cells
received so far. No placeholder, spinner or error is added for streaming.

## Streaming and cache lifetime

Keep the previous String, source offsets and parsed top-level blocks in
State. On an identical String reuse everything. Otherwise test length and
startsWith(previous): one allocation-free prefix comparison identifies an
append exactly. This is O(previous length), not a claim of constant-time
append detection; a String-only API cannot establish prefix equality
without reading it. Do it once per widget update, never during layout or
paint, and do not hash or slice the frozen prefix as a second scan.

For an append, retain all top-level blocks before the last and re-parse
from the last block's source start, retaining its surrounding separator
information. The final block is always provisional: a paragraph can become
a setext heading or table, a list can extend, and a fence can stay open.
Cache frozen parse trees and their rendered spans; append-only work parses
only that active tail, not the whole reply. A reply made of one huge block
still requires parsing that block: report that limit in benchmarks.

Subclass the package's definition syntax through the same public block
syntax extension point used to retain source boundaries. Each tail parse
starts with the definitions retained from the frozen blocks, so the tail
resolves links against that prefix. Compare the resulting definition set
with the previous text's set. When an append changes it, discard frozen
parse state and re-parse the whole String: reference definitions can change
earlier links. Compare parsed definitions rather than scanning for a
`[label]:` line start. This also catches definitions that become valid only
when a continued destination or label arrives on a later line, including
text split across appends. The lead approved this mechanism from ae1e350.
Any non-append edit, shortening or replacement also resets parsing.

A width change invalidates block layout, not parsing. A theme change
invalidates rendered styles, not parsing. A repeated unchanged frame does
neither. Bound retained data to this widget's current source and blocks;
remove obsolete tails and release all state on dispose. Virtualised-list
unmounting may reparse on remount; there is no global transcript cache.

## Text sketches

Illustrative layout, not runtime evidence. Unshown viewport rows are blank;
bold/italic/colour are described above. At 120x40:

```text
Terminal cells

A paragraph with emphasis, a link, and 日本語 that wraps in the width it receives.

- A first item
- A second item
  - A nested item

│ A quoted paragraph.
│ Another quoted paragraph.

┌ dart ──────────────────────────┐
│   void main() {                │
│     print('Hello 日本語');      │
│   }                            │
└─────────────────────────────────┘

┌──────────┬─────────┐
│ Name     │ Status  │
├──────────┼─────────┤
│ renderer │ ready   │
└──────────┴─────────┘
```

At 80x24 the same short blocks retain their sizes. For an overflowing
paragraph and code line, the content excerpt is:

```text
A paragraph with emphasis and 日本語 takes the available width and then
continues at the same left edge.

┌ dart ───────────────────────────────────────────────────────────────────────┐
│     print('A long message about terminal cells, 日本語, and keeping every     │
│ ↪ grapheme together on screen.');                                           │
└────────────────────────────────────────────────────────────────────────────┘
```

These lines show placement, not counted padding. Code's two-cell mark
gutter is inside the box and additional to its one-cell padding on each
side. First rows therefore have three cells before source; continuations
start `│ ↪ `. No reply bullet or tool gutter belongs to Markdown.
Focus produces no visual change; ancestors clip overflowing height.

## Differences and acceptance

main approved wrapped code boxes with ↪, unlike chord's clipped boxes,
so the whole code is readable by keyboard. The lead settled the resulting
six-cell inset (two borders, two padding cells and Code's two-cell mark
gutter), preserving Code's API. Copy/run buttons and picked-box
borders are excluded by the slice; no other deliberate visual difference.
Incremental parsing is an implementation difference with unchanged output.
If parser behaviour cannot reproduce a listed state, escalate with options.

Check all block and inline forms, the 40-cell rule cap, visible reference
definitions, omitted images, link URL suffixes and plain mailto links,
table padding/column caps/shrinking and whole-table truncation fallback,
tight/loose/nested lists, spacing pairs,
quotes, labelled/unlabelled/unknown and open fences, incomplete tables,
wide graphemes and narrow constraints. Check a chunked reply against its
one-shot equivalent, including splits in reference definitions and fences;
verify frozen prefix reuse, append parsing, replacement and width/theme
invalidation. Developer provides a bounded long-reply streaming benchmark
and runnable fixture. Designer captures handed-over fixtures at 120x40 and
80x24 in dark/light/plain before reviewer handover.

# CTUI-37 framework draft: teams on the framework

Owner of this file: framework. Answers the brief's framework questions 1
and 2, names what in `lib/` and in the port each team screen stands on, and
ends with ship units and questions.

**Revised after review.** The critic's finding on Unicode was accepted by
the lead: section 2.3 is rewritten (no blanket equivalence; cliffy's
code-point stepping and its own width table followed; cases recorded
from cliffy pinned; the differences that remain are questions U1-U3 in
section 6). The lead's decisions on F1 (b: port only what `Tool.tsx`'s
drawing reaches) and F2 (`example/chord/lib/ui/teams/cliffy_row.dart`)
are applied to sections 2, 4 and 5.

Sources read: `../chord` `src/ui/transcript/tools/proposal.ts`,
`src/ui/transcript/tools/Tool.tsx` (`Proposal`, `TableRow`),
`src/ui/teams/teams.ts` (`runningTable`), `src/ui/agents/agents.ts`
(`teamRows`, `listRows`, `laidRows`), `tests/ui/transcript/tools/
proposal_test.ts`, `docs/design/M5-teams.md` (the proposal, the change, the
"one rule" on `@cliffy/table`), and `@cliffy/table` 1.3.1 as chord's
`bun.lock` pins it (`_layout.ts`, `consume_words.ts`). In this repository:
`lib/src/widgets/table.dart`, `lib/src/foundation/table_widths.dart`,
`lib/src/text/{diff,layout}.dart`, `lib/src/widgets/diff.dart`,
`example/chord/lib/ui/agents/agents.dart`,
`example/chord/lib/ui/transcript/tools/{tool,diff}.dart`,
`example/chord/lib/agents.dart` (`agentTable`), `docs/design/CTUI-35.md`
sections 6 and 9.

## 1. Answer: nothing new in `lib/`

Teams need no new widget, render object, layout rule or input path in the
framework. Every piece is either already in `lib/` or is chord's own
layout and belongs in the port as pure Dart:

| Team screen | Stands on (existing) | New code, where |
|---|---|---|
| Proposal / change table | `cellWidth`; `Text`/`RichText` per line | `example/chord/lib/ui/transcript/tools/proposal.dart` (pure), plus a small cliffy-row helper (section 2.3) |
| Body as markdown | framework `Markdown`, as `transcript.dart` already draws replies | none |
| Instructions under the table | port `wrapLine` (`ui/transcript/message.dart`) | none |
| Body change as a diff | `diffTexts(…, context:).view(maxRows:)`, `Diff.fromView`, the port's `Folded` line | `bodyChange` in `proposal.dart` |
| Save box | the port's permission box (`ui/dialogs/permission*.dart`) | the team choices, interface's |
| `/team` picker | the port's `ui/pickers/picker.dart` over the framework picker pieces | a teams kind, interface's |
| `/team show` running table | `cellWidth`, `TextLayout.wrapAnsi(hard: true)` | `ui/teams/teams.dart` (pure), same cliffy-row helper |
| Agents list: nesting, folding | the port's `ui/agents/agents.dart` (pure) on `cellWidth`/`wrapAnsi` | `teamRows`, `listRows` with a limit, folded lead rows |
| Member box title, header | the port's `ui/prompt/named_top.dart`, `ui/dialogs/asker.dart` | words only |
| Resources, receipts, `List teams` | `wrapLine`, transcript tool rows | `resource_lines.dart`, `selection_lines.dart` (pure) |

How Flutter would see it, and why that is enough: Flutter's `Table` lays
out columns by `TableColumnWidth` and lets each cell wrap itself; it has
no column spans and no "cut this column before that one" priority. The
framework's `Table` (`lib/src/widgets/table.dart`, `solveColumnWidths`) is
that shape. The proposal table is not a general table: its column widths
come from a chord-specific priority (role, then a changed effort's `was`,
then agent · model; mode and effort never), it has one spanning cell (the
opened role), and its paint needs string ranges per line (mode in the
warning colour, `was …` dim). Flutter apps that need such a thing write it
as their own `RenderBox` or, in a cell grid, as lines of text; a widget for
it in `lib/` would have exactly one caller shape (two call sites, both
chord's), which AGENTS.md's "only what a terminal app generally needs"
rules out. The same reasoning CTUI-35 section 6 gave for the agents list
(rows "counted against a line budget", "a generic one would be chord's
alone") holds for team folding.

No change to the element tree, the render tree, the renderer or the focus
path: there is no new key (M5's "Keys" table), and every new row is drawn
by widgets the transcript and the list already build.

## 2. The proposal table

### 2.1 What the original does (source holds over M5-teams.md)

M5-teams.md describes a first version: columns name, `runtime · model`,
mode, role; folded, the role is cut, then the model; opened, the role goes
under the row and the mode wraps before the model. The source moved on in
four ways, and the port follows the source:

1. **Nothing is cut** (CHD-422). Folded, the role and agent · model *wrap
   in their columns*, never cut with `…`; M5-teams.md's "the role is cut
   first, then the model" is superseded.
2. **An effort column** sits between agent · model and the mode, only when
   some row sets or had an effort (`hasEfforts`); `—` for the runtime's
   own. Its `was …` is the first thing dropped after the role narrows
   (folded only); opened, the effort wraps after the mode and before the
   model.
3. **A change marks rows** `+` / `~` / `-` in a first one-cell column,
   removed members last and dim; a `~` row with a changed mode or effort
   says `<new> was <old>` dim. Opened, a changed cell wider than its column
   is broken before `was` (`brokenBeforeWas`), so the new value has a line
   of its own.
4. **The body and the change's diff are drawn whole** in the transcript.
   `Tool.tsx`'s `Proposal` passes `expanded: true` to `bodyChange` and to
   `proposalBody` (commit "a tool's result is drawn whole and wrapped,
   never cut in the middle (CHD-422)"); ctrl+o only switches the *table*
   between folded and opened. `bodyLines(rows)` (2 at 30+ rows),
   `changeRows(rows)` (5 at 30+ rows) and the folded branches of
   `bodyChange`/`proposalBody` are still exported and tested in
   `proposal_test.ts`, but no drawing reaches them. M5-teams.md's "folded
   it keeps its changed lines with one line of context, at most five" is
   therefore not what a person sees today. Lead's decision (F1, b): the
   port has only what the drawing reaches — `bodyChange` and
   `proposalBody` without their folded branches and without `keep`/`rows`,
   and no `bodyLines` or `changeRows`; the lead logs the omission.

`@cliffy/table` is used only as a row printer: each agent row is its own
`new Table().body([row])` with `minColWidth == maxColWidth == widths` and
`padding(2)`, no border. The widths are computed by `proposalTable` itself;
cliffy contributes only how a cell's text is broken into lines inside its
fixed column, and one `Cell(role).colSpan(n)` for the opened role.

### 2.2 The algorithm, in words

Inputs: rows (`agentRows(team, before)`), `width` (the cells beside `⎿`
and its gutter), `marked` (a change with a team before), `whole`
(ctrl+o). Constants: `PADDING = 2`, `MIN_ROLE = 12`.

Folded (`whole == false`):

1. Natural widths: names, mode cells (`mode` or `mode was old`), effort
   cells (with and without `was`), runtimes, roles; `leastRole =
   min(12, roles)`.
2. The effort keeps its `was` only while `width - base - effortsWhole -
   2 - runtimes - 2 >= leastRole` (the model stays whole beside a
   `MIN_ROLE` role).
3. `fixed` = mark column + names + mode + effort with paddings; `shared =
   width - fixed - 2` is what agent · model and the role split.
4. If `shared < min(longest word of the runtimes, runtimes) + leastRole`,
   the table falls back to the opened layout (step "Opened" below), so no
   word ever leaves its column.
5. Else runtime column = `min(runtimes, max(runtimeWord, roleRoom-derived),
   shared - leastRole)`, role column = `max(1, min(roles, shared -
   runtimeColumn))`.
6. Each row is laid out on its own in those columns; its first line
   carries the mode range `[before, before + mode.length)`, the `was`
   range after it, and the effort's `was` range; later lines carry none.

Opened (`whole == true`), every cell whole:

1. `room = width - mark - names - 2`. The mode column shrinks first to
   `max(widest mode word, room - runtimes - 2 - effortsWhole - 2)`, then
   the effort column likewise, then agent · model gets what is left
   (at least 1).
2. A filler column takes what the row leaves of the width, so the role
   reaches the right edge; when the mode leaves none (`filler < 0`) the
   row is wider than `width` (the mode is never cut) and the role spans
   only the runtime's and mode's columns.
3. Each row: one laid row of the cells (changed cells broken before
   `was` where wider than their column), then one laid row of
   `['', (''), Cell(role).colSpan(rest)]`, its lines flagged `role` and
   drawn dim. `wasesIn` re-finds where each wrapped part of a changed
   cell landed, to paint `was …` dim on every line it is on.

Paint (`TableRow` in `Tool.tsx`): a removed row or a role line is all
dim; otherwise the line is split at the effort-`was` range (dim), the mode
range (warning colour where `skipsAsking(mode)`, plain otherwise), and the
mode-`was` range (dim). The ranges are UTF-16 string offsets computed by
adding string-width cell counts (`effortAt + row.effort.length`, `before +
mode.length`); they land where the characters are only while what precedes
them in the line is one code unit per cell. A team file is not ASCII-only
(`src/teams.ts` takes any string for model, effort and mode and one-line
prose for a role), so on a wide or combining character before the mode
the original paints the warning colour off its word. Dart strings are
UTF-16 as JavaScript's are, so the port does the same arithmetic on the
same strings and paints the same cells; it does not correct it (the paint
cases in section 4 pin a CJK name before a `bypassPermissions` mode).

### 2.3 Cliffy's cell wrapping, and how the port gets it

What the port must reproduce is cliffy 1.3.1's `renderCellValue`, read
from `_layout.ts`, `consume_words.ts` and `unicode_width.ts` and probed
under bun against chord's pinned copy:

- **Widths are cliffy's own, per code point.** `strLength` is
  `unicodeWidth(stripAnsiCode(s))`: the sum over *code points* of a
  Unicode 15.0 table (@std/cli's): ASCII 1, controls 0, U+007F-U+009F 0,
  the rest from the table (East Asian Wide/Fullwidth 2, nonspacing marks
  and ZWJ 0). It does not segment graphemes: `👩\u200d💻` is 2 + 0 + 2 = 4,
  where string-width (which `proposal.ts` uses for its own widths) and
  the framework both say 2.
- **Words**: the first `\n`-line of what is left, split on single spaces
  (a double space gives an empty word); words are added while `consumed +
  next < n`; at least one word.
- **A first word wider than `n`** is cut by `consumeChars`: code point by
  code point (`/(?:ansi)+|./gu`), adding while `consumed + next <= n`,
  and *at least one code point even if it alone is wider than `n`*. A
  zero-width code point (combining mark, ZWJ) at the edge is taken with
  the line before it, so a ZWJ sequence is cut after its joiner. The rest
  carries to the next line with no space removed; after whole words, one
  separator (space or `\n`) is dropped.
- **Padding** is `n - strLength(line)` spaces. When one code point wider
  than `n` was taken (a wide character in a one-cell column), that is
  negative and `" ".repeat` throws `RangeError`: the original's render
  throws.
- **A column of 0** (`maxLength <= 0`) renders `""` and *drops the rest of
  the cell*.
- Columns are joined by `padding` spaces after every cell whose *starting*
  column is not the last, so a span reaching the last column still gets
  its trailing padding; no border, no leading space. A span of `k` is its
  `k` columns' widths plus the paddings between them. A row is as many
  lines as its longest cell.

Recorded from cliffy 1.3.1 (`new Table().body([cells]).minColWidth(w)
.maxColWidth(w).padding(2).toString()`, lines split on `\n`, shown
untrimmed, `\u` escapes as JSON), by a bun script beside `../chord`
importing its `node_modules/@cliffy/table`:

| Case | Cells | Widths | Lines |
|---|---|---|---|
| CJK wraps | `"日本語 テキスト"` | 4 | `"日本"` / `"語  "` / `"テキ"` / `"スト"` |
| CJK word wider | `"日本語テキスト"` | 5 | `"日本 "` / `"語テ "` / `"キス "` / `"ト   "` |
| CJK at one | `"日本"` | 1 | throws `RangeError` |
| narrow then CJK at one | `"a日"` | 1 | throws `RangeError` |
| CJK at two | `"a日b"` | 2 | `"a "` / `"日"` / `"b "` |
| CJK beside a column | `"日本語"`, `"x"` | 3, 1 | `"日   x"` / `"本    "` / `"語    "` |
| combining | `"e\u0301te\u0301 cafe\u0301"` | 2 | `"e\u0301t"` / `"e\u0301 "` / `"ca"` / `"fe\u0301"` |
| combining at one | `"e\u0301e\u0301"` | 1 | `"e\u0301"` / `"e\u0301"` |
| ZWJ whole | `"👩\u200d💻 dev"` | 8 | `"👩\u200d💻 dev"` (draws 6 cells) |
| ZWJ at two | `"👩\u200d💻"` | 2 | `"👩\u200d"` / `"💻"` |
| ZWJ at three | `"x 👩\u200d💻"` | 3 | `"x  "` / `"👩\u200d "` / `"💻 "` |
| ZWJ at one | `"👩\u200d💻"` | 1 | throws `RangeError` |
| ZWJ beside a column | `"👩\u200d💻"`, `"x"` | 4, 1 | `"👩\u200d💻  x"` (x two cells left) |
| model in its string-width column | `"claude · 👩\u200d💻"` | 11 | `"claude ·   "` / `"👩\u200d💻       "` |
| zero room | `"abc"`, `"def"` | 0, 3 | `"  def"` |
| zero room, CJK | `"日本"`, `"x"` | 0, 1 | `"  x"` |
| zero room, ZWJ | `"👩\u200d💻"`, `"x"` | 0, 1 | `"  x"` |
| span to a zero filler | `""`, span 3 `"role words"` | 4, 3, 5, 0 | `"      role words    "` |
| span, CJK | `""`, span 3 `"日本語の役割"` | 4, 3, 1, 0 | `"      日本語の  "` / `"      役割      "` |

So, against the critic's point: the original's rows are not "the same as
graphemes" off ASCII. A ZWJ emoji counts 4 to cliffy and 2 to
`proposal.ts`'s column widths, so it wraps in a column it fits
("model in its string-width column") and pads two cells short, moving
later columns left; it can be cut between its joiner and its second
emoji; a wide character in a one-cell column throws. The one-cell case
is reachable: opened (ctrl+o), `agentRoom` is `max(1, …)`, so in a
window of about 30 columns with `bypassPermissions` in the mode column a
model starting with a wide character (or a ZWJ emoji) gets a one-cell
column, and the proposal row throws while drawing.

**The port follows the original's code points.** `cliffy_row.dart`
(`example/chord/lib/ui/teams/cliffy_row.dart`, the lead's F2):

```dart
/// One row as @cliffy/table 1.3.1 prints it with fixed column widths,
/// [padding] spaces after each cell not starting in the last column and
/// no border: a cell wraps at single spaces, a word wider than its
/// column cut by code points, widths counted per code point as cliffy
/// counts them.
List<String> cliffyRow(
  List<CliffyCell> cells,
  List<int> widths, {
  int padding = 2,
});

/// A cell's text and how many columns it spans.
final class CliffyCell {
  const CliffyCell(this.text, {this.span = 1});
  final String text;
  final int span;
}

/// A string's width as cliffy 1.3.1's `unicodeWidth` counts it: the sum
/// of its code points' widths in @std/cli's Unicode 15.0 table.
int cliffyWidth(String text);
```

- It steps by `String.runes` (code points), not by `characters`
  (graphemes), and keeps the original's slicing by UTF-16 length, so the
  same strings come out.
- `cliffyWidth` is cliffy's table, not the framework's `graphemeWidth`.
  Measured over all 1,114,112 code points, `graphemeWidth` of a lone code
  point differs from cliffy's on 2,169 of them (385 ranges, mostly marks
  of Indic and other scripts the framework's `_zero` list does not have,
  and wide-area code points the two tables place differently: 280 the
  framework counts 2 and cliffy 1, such as unassigned CJK radicals from
  U+2E9A, and 30 the reverse). A team string with any of them would wrap and pad
  differently. So the helper carries cliffy's three run-length tables
  (`unicode_width.ts`, about 3 KB of base64) and its decoder and lookup,
  ported as data with @std/cli's MIT notice, as `width.dart` already
  carries ansi-regex's. The table is what decides the original's lines,
  so it is the specification here. Unit 1 first searches pub.dev for a
  package exposing the same per-code-point widths; one that matches the
  recorded widths of every code point replaces the data, and the search
  goes into the handover either way.
- Where cliffy throws, the helper throws the same `RangeError` at the
  same input, unless the owner rules otherwise (U2).
- A column of 0 drops its cell, as cliffy does. In the proposal only the
  opened table's empty filler column can be 0, so nothing visible is
  dropped; in `runningTable` no column reaches 0.

`proposalTable` and `runningTable` measure their own widths (`widest`,
`brokenBeforeWas`, `stringWidth(...)` in `runningTable`) with string-width
8.3.0 in the original. The port has no string-width; its stand-in is
the framework's `cellWidth`. Over graphemes these agree on ASCII, CJK,
combining marks after a base and ZWJ sequences, but per lone code point
they differ on about 7,100 code points (5,521 string-width counts 0 and
the framework 1, lone combining marks among them; 1,331 that string-width counts 2 and the
framework 1, mostly symbols outside the framework's wide ranges such as
the trigrams from U+2630, only 10 of them above U+1F000; 231 the
framework counts 2 and string-width 1; 26 others). A column width
computed from one of those would differ by a
cell. That is the framework's measure against string-width's, wider than
this task; it is U1.

Then what the terminal draws. The line strings are the original's; each
program's renderer then puts them on cells. The framework draws
`👩‍💻` in two cells and a lone `👩‍` (cut after the joiner) as
one grapheme of two (`graphemeWidth`: a cluster holding U+200D is 2), so
a cut sequence draws as the original's string says, the short padding
included. Whether OpenTUI puts those exact strings on the same cells is
the general renderer question the framework already lives with, not
this table's; interface's captures of the ZWJ and CJK cases show it side
by side. Nothing in the terminal stops the port from following the code
points.

Why not `lib/`, and why not a package: the helper is one library's rule
with two callers, both chord's; the framework's own `Table` wraps by the
framework's text rules, which is right for a framework and wrong for a
copy of cliffy; and no Dart table printer reproduces cliffy's per-cell
rule with fixed widths and spans (`agentTable` in
`example/chord/lib/agents.dart` was written by hand for the same reason).

Rejected: drawing the proposal with the framework `Table` widget and
`FixedColumnWidth`. It would wrap at `-` and `/`, keep graphemes whole,
has no spans, and gives the paint no string ranges.

### 2.4 How the port draws it

`tool.dart` already sits in a `LayoutBuilder` that hands each chord tool
its `room` (the width beside `⎿`); `settingsRows(chord, expanded:,
width: room)` is the model. A `proposalRows(view, expanded:, width:,
theme)` in the same switch returns, in order, as `Tool.tsx`'s
`Proposal` draws:

- the description, `wrapLine`d, dim, the first under `⎿`;
- one blank row;
- the table lines, each a `RichText` of up to five spans from its
  `TableLine` ranges, under a blank gutter;
- the instructions (`instructionLines(team, width)`), then a blank row
  and the body through the framework `Markdown` at `width`, as replies
  are drawn — or, for a change whose body changed, the line
  `bugfix.md's body · 1 addition, 1 removal` and `Diff.fromView` of the
  whole diff (`diffTexts(before, after, context: 3).view()`, no row cap),
  as an edit's diff is drawn in the port today;
- the saved line, success colour or dim.

Nothing is folded under the table, so no `Folded` line: the source's
`hidden` is always 0 on this path, and F1 (b) leaves the folded branches
out.

At 120x40 a four-agent team (`bugfix`: lead, coder, tester, reviewer;
claude and codex models; modes up to `bypassPermissions`) fits folded on
one line per row, roles whole. At 80x24 the role narrows to its column
and wraps there (no `…`), agent · model keeps its longest word; ctrl+o
puts each role under its row from the runtime column to the right edge.
The captures are interface's plan; the table's lines are checked as
strings first (section 4).

## 3. Team folding in the agents list

All pure, in the port's `ui/agents/agents.dart`, which today says "teams'
folding and branches come with CTUI-37" and returns `List.of(agents)` from
`listRows`. Ported from `agents.ts`:

- `AgentRow` gains `team` (the lead's key, on the lead and each member),
  `branch` (`├─` / `└─`) and `folded` (the open members, on a folded
  lead).
- `teamRows(agents, fold:)`: members under their lead with `├─` and, for
  the last member, `└─`; with `fold`, every team but the one whose agent
  is picked becomes its lead's row carrying `folded`. A lead with no open
  member has nothing to fold.
- `listRows(agents, limit, height)`: fold only when the unfolded rows'
  height (wrapped rows count each line, CHD-471) exceeds the limit
  (`agentsRowLimit`, the queue's 4 at 24 rows, 6 at 40). The port adds
  `agentsHeight(rows, width)` beside its private `_heights` for this.
- A folded lead's state is the most urgent of lead and members, naming
  the member (`teamState`); its mark the first unseen of them; its size
  `N agents` stands where its model would.
- `_laidRows` counts a folded team's members under their branch as if
  unfolded, so folding never moves a column.
- `listTimed` looks into `folded`, so a folded team's working member keeps
  the shared clock running.
- `ctrl+x a` to a waiting member picks it, and the pick's team is the one
  not folded, so the list unfolds to it with no code of its own.

Cost per frame: `listRows` lays the rows out twice at most (unfolded to
measure, then folded) — O(agents × row width), the same as the original.
With `N` open agents in a window this is tens of rows; nothing is cached
across frames, as now. Per update, a child's state change rebuilds the
list as today. Runtime's draft owns the many-runs performance check; from
this side, `benchmark/list_view.dart` is not involved (the agents list is
not a `ListView`).

## 4. Tests

All under the port, `example/chord/test/`.

- `test/ui/teams/cliffy_row_test.dart`:
  - every row of the table in 2.3, verbatim (the escapes decoded),
    with the bun command that recorded them in the file's header; the
    two `RangeError` rows as U2 decides;
  - the ASCII rules: fits; wraps at a space on the `<` boundary;
    overlong first word cut and carried with no space eaten; overlong
    later word moved to its own line; `\n` honoured; double space; an
    exhausted cell padding blank; span width = its columns + paddings;
    trailing padding after a span that starts before the last column;
    none after a last-column cell; a zero column dropping its cell;
  - `cliffyWidth` against cliffy for every code point: a fixture of
    `(first, last, width)` runs recorded from cliffy's `unicodeWidth`
    over U+0000-U+10FFFF (surrogates skipped), and the test walks all of
    them; plus named samples from the 2,169 code points where it and
    `graphemeWidth` differ, so a later "use the framework's width" fails.
- `test/ui/transcript/tools/proposal_test.dart`: the tests of
  `proposal_test.ts`, same names, same expectations (folded fit, opened
  role under the row, change marks and `was`, removed last, member named
  `lead`, efforts with and without `was`, narrow fallback to opened,
  CHD-422's block), except what F1 (b) leaves out: no `bodyLines` or
  `changeRows`, and of "a change's body counts itself as not yet
  written…" and "the body folds to its first lines…" only the
  assertions on the whole (expanded) result and `bodyChangeLine`. Added:
  a team with a CJK name, a combining mark in a role and a ZWJ emoji in
  a model, folded and opened at 120 and 80 and at the width where
  `agentRoom` is 1, with lines recorded from the original's
  `proposalTable` under bun (the same script, importing
  `src/ui/transcript/tools/proposal.ts`), and its `mode`/`was` ranges
  as the original computes them.
- Widget tests through `package:chorded_tui/testing.dart`: the proposal
  row at 120x40 and 80x24, folded and after ctrl+o, a change with a body
  diff; the warning colour on `bypassPermissions` and `full-access`, plain
  under `NO_COLOR`; the `was` spans dim; the CJK-name row's warning
  colour on the cells the original paints.
- `test/ui/agents/agents_test.dart`: `teamRows` branches, folding only
  over the limit, the picked team unfolded, a folded lead's state naming
  its member and its size, columns unmoved by folding, `listTimed` through
  `folded`, as `tests/ui/agents/agents_test.ts` has them.
- `test/ui/teams/teams_test.dart`: `runningTable` as
  `tests/ui/teams/teams_test.ts` has it, plus a CJK and a ZWJ row
  recorded from the original. The window-level team list cases of
  `tests/ui/agents/Teams*_test.tsx` are interface's capture plan.

## 5. Proposed ship units, ordered

1. **Cliffy row helper** (`example/chord/lib/ui/teams/cliffy_row.dart`:
   `cliffyRow`, `CliffyCell`, `cliffyWidth` with @std/cli's table and MIT
   notice) with its test and the width fixture. First, the pub.dev search
   for a package with the same per-code-point widths, reported in the
   handover. No caller yet; it unblocks 2 and 4.
2. **Proposal table and body** (`ui/transcript/tools/proposal.dart`:
   `proposalOf`, `agentRows`, `proposalTable`, `savedLine`,
   `instructionLines`, `proposalBody` and `bodyChange` whole only,
   `bodyChangeLine`, `skipsAsking`) with `proposal_test.dart` as in
   section 4. Needs `teamChanges` from runtime's `lib/teams.dart` unit.
3. **Proposal rows in the transcript** (`tool.dart`'s chord switch):
   description, table paint, instructions, markdown body or whole body
   diff, saved line; widget tests at both sizes. Lands with the save box
   (interface's unit).
4. **`/team show` tables** (`ui/teams/teams.dart`: `runningTable`,
   `runningHeader`, `teamChoices` columns) with their tests, on the
   helper.
5. **Team rows in the agents list** (`ui/agents/agents.dart`:
   `teamRows`, `listRows` with limit and height, `agentsHeight`, folded
   state, size, branches, `listTimed`) with the ported list tests, then
   the widget at 120x40 and 80x24 with a folded and an unfolded team.

No unit touches `lib/`. U1-U3 decide details of units 1, 2 and 4, not
their order; until they are answered, unit 1 follows the recommended
options below.

## 6. Questions

Decided by the lead: F1 (b), F2 (`example/chord/lib/ui/teams/
cliffy_row.dart`), applied above.

**U1 (owner). The proposal's and `/team show`'s own column widths.** The
original measures them with string-width 8.3.0; the port has no
string-width and uses the framework's `cellWidth` for it everywhere.
They agree on ASCII, CJK, a mark after its base and ZWJ sequences, and
differ on about 7,100 lone code points (mostly lone marks, and symbols such
as the trigrams from U+2630 that string-width counts 2 and the framework
1). A team string holding one gets a column a cell
wider or narrower than the original's, so its wrap can differ. Options:

- (a) Port string-width 8.3.0's measure (its East Asian Width data,
  emoji test and grapheme rules) into the port, for these two tables
  only. Exact; a second width table beside cliffy's, used by two
  callers.
- (b) Keep `cellWidth`, as every other port of a string-width call
  does; record it in `docs/decisions.md` with a test pinning one
  differing case. Recommended: it is the measure the port's renderer
  draws with, and the cases are rare in a team file.
- (c) Bring the framework's `graphemeWidth` to string-width 8.3.0. A
  framework task touching every screen; out of this task's scope.

**U2 (owner). The original throws on a wide character in a one-cell
column.** Cliffy takes at least one code point, then pads by a negative
count and `" ".repeat` throws `RangeError`; the proposal row (and the
transcript with it) fails to draw. Reachable after ctrl+o in a window of
about 30 columns with `bypassPermissions` and a model starting with a
wide character or a ZWJ emoji. Options:

- (a) Throw the same `RangeError` at the same input; the port's drawing
  failure path then shows whatever it shows for a widget that throws,
  which is not the original's screen either.
- (b) Treat it as the original's slip: pad by `max(0, …)`, so the
  character overflows its column by one cell and the row is one cell
  wider; recorded in `docs/decisions.md`, a test pins the line.
  Recommended: the only visible difference is a row that draws where the
  original's fails.
- (c) Fix it the other way: give the column a minimum of the widest code
  point. Changes widths elsewhere; not recommended.

**U3 (lead, or owner if the lead holds it is a reversal). Code points
against CTUI-57's "graphemes whole".** `docs/decisions.md` has main's
choice, for wrap-ansi, to keep graphemes whole where the original pulls
a combining mark off a space. Following the critic, this draft follows
cliffy's code points instead: a ZWJ sequence can be cut after its
joiner, as the original cuts it. Options:

- (a) Code points, as cliffy does (this draft): the same strings as the
  original's.
- (b) Graphemes whole, as CTUI-57 chose for wrap-ansi: the cut moves to
  before the sequence on those rows; recorded, with the recorded cases
  in 2.3 changed to the port's lines.

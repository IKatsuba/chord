# CTUI-8: Fold, Table, Picker and Dialog

Framework building blocks, following Flutter's call sites and chord's visual
vocabulary. Read with CTUI-1 (ListView, scroll geometry and bindings), CTUI-2
(Overlay and focused entries), CTUI-3 (theme roles) and CTUI-4 (grid table
geometry). Sources are `../chord/src/ui/dialogs/Fold.tsx`, `fold.ts`,
`Form.tsx`, `Permission.tsx`, and `../chord/src/ui/pickers/picker.ts`,
`Pickers.tsx`, `mcp.ts`. These are framework widgets, not a port of those
screens' permission, elicitation, session or model state machines.

## Fold

```dart
Actions(
  bindings: [Binding('ctrl+o', 'Toggle tool details',
    () => setState(() => expanded = !expanded))],
  child: Fold(title: call.title, open: expanded,
    child: Code(call.output, language: 'shell')),
);

const Fold({Key? key, required String title, required bool open,
  required Widget child});
```

Fold is controlled: no internal open state, onChanged or default key. The
app's Actions flips open and its shortcuts panel lists that action. The
header is one line: `▸ title` when closed, `▾ title` when open; the marker
is theme.dim, title theme.text, cut with an ellipsis at the right edge.
The body starts on the next row, without padding or border. A caller can
indent it with Padding. A closed body is not laid out or painted but stays
mounted, preserving state. It cannot request or retain focus while closed;
focus leaving a collapsed subtree falls back within the enclosing scope
using CTUI-2's eligibility rules. Neither Fold nor its header takes focus.

The lead settled that the original's automatic height folding is included
in this same widget, without a flag. The title takes one available row.
An open body's natural height is measured at its actual width with
unbounded height; its visible height is bounded by the rows remaining after
the title. If it fits, show all. Otherwise show max(0, room-1) body rows and
one dim `… N more lines` row, where N counts hidden visual rows, singular
`line` for one. At body room zero paint neither body nor count; at room one
paint only the count. Prefix the count with two spaces, as dialogs/Fold.
Long count text is cut at the right edge. Natural height zero adds no body
row. At total room zero nothing paints. All paint clips to the allocated
rectangle, including wide graphemes. A width change remeasures before the
count is drawn. Natural measurement and clipped paint belong to RenderFold,
using the same child once; LayoutBuilder supplies available constraints,
not an invented measurement API or duplicate hidden element tree. An
unbounded-height body must be finite; a scroll viewport should be explicitly
sized by its caller before putting it in Fold.

This header is a framework affordance from the task/README. The original's
held dialog Fold has no header; a later port composes the same pure
foldOf/moreLines geometry with its dialog header instead of drawing an
extra tool title. The pure height-fold helper must be reusable internally
without requiring a second public held-request widget.

## Table

The lead settled Flutter's parameters rather than literal columns/rows
parameters, and a borderless default because chord's non-Markdown tables
are aligned columns. Table itself has no focus, selection, keys or parsing.

```dart
Table(
  columnGap: 2,
  columnWidths: const {
    0: IntrinsicColumnWidth(maxWidth: 32),
    1: FixedColumnWidth(9),
    2: FlexColumnWidth(),
  },
  children: [
    TableRow(children: [Text('Name'), Text('Transport'), Text('Command or URL')]),
    TableRow(children: [Text('memory'), Text('stdio'), Text('npx -y memory')]),
  ],
);

Table({Key? key, Map<int, TableColumnWidth>? columnWidths,
  TableColumnWidth defaultColumnWidth = const FlexColumnWidth(),
  int columnGap = 0, TableBorder? border, List<TableRow> children = const []});
TableRow({Key? key, required List<Widget> children});
FixedColumnWidth(int value);
IntrinsicColumnWidth({int? maxWidth});
FlexColumnWidth([double value = 1]);
TableBorder.all({Style? style});
```

Dimensions are content cells, excluding gap, border and grid-cell padding.
Widths, caps and gaps are nonnegative, flex weights positive and finite.
Rows have the same number of cells; reject a ragged row. Empty children
produce zero natural rows. Cells align top; use Align/TextAlign inside them
for horizontal alignment. The default is no border and zero padding. Gap
is between columns only, never outside; `columnGap` is a clear terminal
extension where Flutter has none. Default flex columns divide bounded
remaining width equally, assigning remainder cells in column order.

First reserve gap and border furniture. Fixed widths reserve their specified
content width. Intrinsic columns measure the widest natural cell at
unbounded width, capped when requested. This is a render-local measurement
layout, then final layout at assigned widths, not a new RenderBox intrinsic
API. Cells in intrinsic columns must have finite natural width; callers
use fixed/flex widths for content needing a bounded axis. Remaining width
is divided among flex columns; on unbounded width, flex columns use natural
width. If fixed/intrinsic widths already exceed room, flex gets zero and
all paint clips to the table's bounds. The caller uses LayoutBuilder to
choose narrower widths or a stacked form. No implicit reordering or
path-specific truncation. Each final row is as tall as its tallest cell;
short cells leave blank rows, and the next row starts below that maximum.
Changing row content or width recomputes its geometry without losing keyed
cell state. No horizontal scrolling or virtualisation is added.

A cell controls wrapping and ellipsis through Text, Code or its own widget.
For a one-line cell use `Text(label, softWrap: false,
overflow: TextOverflow.ellipsis, maxLines: 1)`. Table never slices strings.
A cell that cuts a directory from its start is the port's cutPath work,
not Table's. Wrapping a command at slashes is likewise the port's cell.

TableBorder.all supplies CTUI-4's single grid: one-cell outer edges and
separators, one-cell padding each side of cell content, no vertical padding,
header separator only when supplied by a future richer border API (not an
implicit header concept in TableRow). Border style defaults to theme.border.
Use `columnGap: 0` with this grid. Share the pure width arithmetic and grid
painting with Markdown where applicable; do not change Markdown's existing
40-cell padded cap, early shrinking arithmetic, bold header, wrapping and
whole-table truncation fallback. Public Table cells remain widgets and keep
their own overflow policy. TableBorder and row geometry must not silently
change the already approved Markdown output. More border shapes and custom
row decoration are outside this slice.

### The port's table shapes

These sketches show composition; domain functions stay in the port.
In /mcp the source order is Name, Transport, Command or URL, Defined in.
The wrapping column is third, not last. mcpRows reserves path width first
and gives command the remainder, with its source constants (name cap 32,
command reservation up to 16 and two-cell gaps). Compute those widths with
LayoutBuilder and the port's pure reducer; Table only lays out the result.

```dart
LayoutBuilder(builder: (context, room) {
  final widths = mcpWidths(servers, room.maxWidth);
  return Table(columnGap: 2, columnWidths: {
    0: FixedColumnWidth(widths.name),
    1: FixedColumnWidth(widths.transport),
    2: const FlexColumnWidth(),
    3: FixedColumnWidth(widths.from),
  }, children: [
    TableRow(children: mcpHeadingCells),
    for (final server in servers) TableRow(children: [
      oneLine(server.name), oneLine(server.transport),
      CommandCell(server.target), // wraps at spaces/slashes, per the original
      PathCell(server.from), // cutPath using this column's actual constraints
    ]),
  ]);
});
```

/resume reserves relative time, optional `open now`, and optional directory
(cut from the start to DIRECTORY_WIDTH=30) before its final flexible title.
Compute shared prefix widths once for all choices, then use them for each
Picker item, retaining virtualisation rather than building a whole table
inside one ListView item. The row's trailing content wraps under its start.
When prefix columns would leave less than half the row for the title, the
original puts the title on subsequent full-width lines; a row's
LayoutBuilder chooses that composition, not Table.

```dart
Table(columnGap: 2, columnWidths: {
  0: FixedColumnWidth(widths.when),
  if (showOpen) 1: FixedColumnWidth(widths.open),
  directoryColumn: FixedColumnWidth(widths.directory),
  titleColumn: const FlexColumnWidth(),
}, children: [TableRow(children: [
  Text(when), if (showOpen) Text(openNow),
  PathCell(directory), Text(title),
])]);
```

## Picker

```dart
Picker<String>(
  items: const [
    PickerItem(value: 'fast', label: 'Fast'),
    PickerItem(value: 'careful', label: 'Careful'),
  ],
  initialValue: 'careful',
  maxVisibleRows: 8,
  onSelected: choose,
  onCanceled: close,
);

Picker<T>({Key? key, required List<PickerItem<T>> items,
  required void Function(T) onSelected, required void Function() onCanceled,
  T? initialValue, int maxVisibleRows = 8, bool searchable = false,
  PickerFilter filter = const FzfPickerFilter(),
  Widget Function(BuildContext, PickerItem<T>, List<int> matchedPositions)? itemBuilder,
  bool autofocus = true});
PickerItem<T>({required T value, required String label});
abstract interface class PickerFilter {
  List<PickerMatch> match(String query, List<String> labels);
}
PickerMatch({required int index, required List<int> matchedPositions});
const FzfPickerFilter(); // implements PickerFilter
```

Values must be unique and stable (equality identifies selection across
updates). Default label is plain text; itemBuilder supplies multiline or
rich content. Picker supplies the highlight gutter, the number and the
selected-row decoration outside that builder. Builder items take no focus,
following CTUI-1's NoFocusRequests. The list owns one ScrollController with
Follow.none, disposed with the picker. State and key reducers are plain
Dart: selected value, ranked results, row window and filter mode.

With searchable false there is no input row. Initial highlight is initialValue
when present, else the first choice. Results retain original order. With
searchable true, show one `Filter: ` row, initially in navigation mode;
`/` enters its editor and returns focus to navigation on Enter. The filter
is not an internal fuzzy implementation: it receives query and labels,
returns ranked original item indices and matched positions; no scores are
required. Empty query bypasses matching and returns original order with
no matched positions. Position indices count UTF-16 code units in the
original unstyled label, not terminal cells. A custom row that emphasizes hits maps them to whole graphemes using the
existing characters package, preserving emoji and combining sequences.
The default adapter documents its upstream index units.
Main settled the matcher after the package trial: port fzf-for-js's
FuzzyMatchV2, basic match, sort, byLengthAsc and limit into lib/.
FzfPickerFilter is the default implementation; callers can supply another
PickerFilter. Preserve the upstream matching/scoring semantics and compare
pure Dart results against golden cases generated by a bun oracle. This is
an approved port, not a further package trial or a home-grown substitute.
Keep query/label/ranked-index/position boundaries small and testable.

On query change preserve selected value if still in results, otherwise
highlight first. No result means no selected value. Reset the row window
to reveal selection. Items change: remove stale results and re-run matching;
never accept an index against an older item snapshot. Matcher calls are
synchronous in this slice; no debounce, isolate or cancellation protocol.
Default rows do not emphasize matched glyphs: chord does not use the
matcher's positions in its UI. Pass positions through to itemBuilder for
apps that want match styling. Selected rows use theme.focus with a `❯` gutter and bold, legible in plain theme.
Use theme.selection only if an app's row chooses a filled selection.
No ANSI supplied by a matcher is executed or rendered as styles.

Picker has no outer frame/title/hint policy: Dialog provides that. Its
list is CTUI-1 ListView.builder; use exact itemTop/itemRows and jumpTo to
keep the highlighted row in sight. Up/down clamp at ends, as pickerKey;
multiline choices taller than the viewport move through their lines before
leaving the item, as lineKey. Resize reveals the highlighted item's first
line, as fromFirstLine. Draw numbers as `${index + 1}.`.padEnd(`${resultCount}.`.length),
followed by one space before the label, exactly as linedRows. Continuation
lines use blank number cells of that same width plus the separating space.
Numbers are positions in the current ranked result,
not the visible slice; number 1 selects first even when scrolled away.
Draw `↑`/`↓` edge markers when choices extend beyond the viewport and a dim
`… +N more` footer for choices below, inset four cells as PickerList draws it. Count hidden choices, not wrapped
lines; suppress the footer when the highlighted item alone takes the whole
viewport or more, as linedRows does. The footer reserves one row only when needed; it cannot squeeze a
positive list budget into negative rows. At no visible choice rows, disable
navigation and acceptance, even numbers selecting an offscreen result;
retain only filter and cancel actions that can act. No pending selection
fires when room returns. Empty result draws `No matches.`; empty unfiltered
items draw `No choices.` in dim text, no fabricated first row.

### Picker keys and conflict handling

All actions below are Binding instances in Actions, with these descriptions,
visible through KeyHelp. No selection logic is hidden in raw onKey.
Filter editing uses existing TextInput for text/paste, with navigation and
acceptance bindings above it only for keys TextInput does not consume.

| Mode | Keys | Description / effect |
| --- | --- | --- |
| Navigation | up / k, down / j | Previous choice / Next choice |
| Navigation | enter | Choose highlighted item |
| Navigation | 1–9, for existing results | Choose item N |
| Navigation | pageup, pagedown | Scroll up a page / Scroll down a page |
| Navigation | home, end | Scroll to the top / Scroll to the bottom |
| Navigation, searchable | / | Edit filter |
| Navigation | esc | Cancel picker |
| Filter editor | enter | Finish editing filter |
| Filter editor | esc | Finish editing filter |
| Scope | tab, shift+tab | Next control / Previous control (CTUI-2) |

Typing j/k/digits while editing always edits the query. In navigation they
act as the original's shortcuts. A second Esc after leaving the editor
cancels the picker, without silently clearing the query. This two-mode
filter is a framework API decision, not a claim that chord's model picker
has a filter field; the port sets searchable false there. Page/end bindings come
from scrollBindings, and change viewport only; selection is kept until the
next highlight movement or Enter. Shift+arrows remain unbound here so the
window can route them as the original does. A narrower panel may ellipsize
its hint; its shortcuts panel still lists every enabled action.

## Dialog

```dart
final entry = OverlayEntry(builder: (context) => CompositedTransformFollower(
  link: promptEdge, targetAnchor: Alignment.topLeft,
  followerAnchor: Alignment.bottomLeft,
  child: Dialog(
    title: Text('Allow command?'),
    child: Text('Run the requested command in this session.'),
    choices: const [
      PickerItem(value: true, label: 'Allow once'),
      PickerItem(value: false, label: 'Reject'),
    ],
    onSelected: answer,
    onCanceled: close,
  ),
));
Overlay.of(context).insert(entry);

Dialog<T>({Key? key, required Widget title, required Widget child,
  List<PickerItem<T>> choices = const [], void Function(T)? onSelected,
  required void Function() onCanceled, Widget? hint});
```

The constructor keeps Flutter's Dialog(child:) concept with explicit terminal
slots for title and choices; there is no Material route, animation or mouse
barrier. Overlay owns placement, opaque paint, focus containment and return.
Dialog owns a rounded frame, as borderOf in Pickers.tsx, in theme.focus when active, theme.border
otherwise, one-cell horizontal padding and no vertical padding. Title is
bold in theme.focus, one row and ellipsized. Then body, a blank row before
choices when present, and a blank row before the hint. Body takes natural
height until constrained; short room cuts body from the bottom, keeping
title and choices. The automatic Fold height reducer supplies a dim hidden
line count when one row fits. Do not draw a second Fold title in Dialog.
Hint joins enabled parts with ` · `, as hintOf in app/context.tsx,
used by Pickers.tsx. The generic choice hint is `↑↓ or j/k to move`,
`Enter or 1–9 to select`, then `Esc to close`; omit the first two when no
choice is visible. Filter editing adds its actual editor actions. Hints are
dim and one line. Specific port pickers pass their source wording, e.g.
`Enter to choose`, `Enter to set` or `Enter to resume`, rather than replacing
the original's choice of words with the generic hint. An explicit hint replaces its text only, never its bindings.
An empty choice list is a notice: no acceptance keys, Esc still closes.

Dialog choices use the same row drawing as Picker, but their up/down and
j/k wrap as the original ChoiceList does. Numbers and Enter select. This
wrap/clamp distinction is explicit in the pure reducer; do not add an
exposed boolean Picker mode just for Dialog. Key descriptions are Choose
highlighted item, Previous choice, Next choice, Choose item N, Close dialog.
All are Actions bindings. With insufficient room, body goes first, then
its gap, then hint and its gap; title and choices have priority. If even
those do not fit, clip choices to visible rows and disable numbers for
unpainted choices; at zero visible choices disable acceptance/navigation.
At zero surface rows nothing paints and the overlay suspends entry keys.
A generic Dialog never invents a rejection, confirmation timeout or default
answer. The port supplies permission/form actions and wording from source.

## What the fixtures draw

Mocks only, not captured runtime evidence. The same short content occupies
the same rows at 120x40 and 80x24, with unused cells/rows blank. All widgets
receive parent width; no centered desktop-width card is introduced.

At 120x40, a tool Fold expanded at row zero:

```text
▾ Run checks
$ dart analyze
No issues found!

Name       Transport  Command or URL
memory     stdio      npx -y memory
```

At 80x24, with Fold allocated three total rows and a four-row body:

```text
▾ Run checks
$ dart analyze
  … 3 more lines
```

Closed at either size: `▸ Run checks` alone. Empty open body: `▾ Run checks`
alone. At very narrow width the header is cut with a final ellipsis.
Fold's app-level ctrl+o changes only the controlled open value.

A gridless resume-style row at 120 columns has time, optional directory and
remaining title on one line; at 80 a long title continues under its title
column. When less than half the inner row remains, the caller stacks it:

```text
just now  …/workspace/project  A session title that can wrap under its start
                              without rotating the list's row order
```

A focused picker in an upward layer at 120x40 (long borders elided here):

```text
╭──────────────────────────────────────────────────────────────────────…╮
│ Models                                                               │
│ Choose a model for this session.                                     │
│                                                                      │
│ ❯ 1. Fast                                                             │
│   2. Careful                                                          │
│                                                                      │
│ ↑↓ or j/k to move · Enter or 1–9 to select · Esc to close                      │
╰──────────────────────────────────────────────────────────────────────…╯
[prompt gap]
> /model
[permanent status]
```

At 80x24 it keeps the same title/choices/hint; body description wraps or
folds in the reduced room. A filtered standalone Picker adds `Filter: ca`
above its choices and shows only `1. Careful`, with no default matched-glyph decoration.
With no matches it shows `No matches.` and only editing/cancel actions.
A long list shows `↑` at its upper boundary, `↓` below, and `… +N more`;
selected multiline content retains its gutter on the first line. Plain
mode retains the `❯` and bold selection. Unfocused content has no selected
marker; focus restored after closing is visible in the underlying input.

A small Dialog at either size:

```text
╭──────────────────────────────────────────────────────────────────────…╮
│ Allow command?                                                       │
│ Run the requested command in this session.                            │
│                                                                      │
│ ❯ 1. Allow once                                                       │
│   2. Reject                                                           │
│                                                                      │
│ ↑↓ or j/k to move · Enter or 1–9 to select · Esc to close                      │
╰──────────────────────────────────────────────────────────────────────…╯
```

The permission example illustrates framework slots, not a completed port
screen. Later permission/form slices must compare actual source captures
and preserve reason, choices and deadline at 80x24, with the proposed action
scrolling above them. This slice introduces no domain wording differences.

## Units and evidence

1. Pure height folding and RenderFold/Fold: controlled open, natural row
   measurement, 0/1-row budgets, singular count, width changes, state kept
   and closed-body focus disabled. App owns toggle Actions.
2. Pure table width solver, render Table and widget cells; fixed/intrinsic/
   flex, two-cell gaps, borderless default, optional grid. Test unequal
   heights, intrinsic caps, flex rounding, narrow overflow, wide graphemes,
   zero rows/columns and cell-controlled wrapping/ellipsis. Preserve CTUI-4
   output with reached Markdown table tests if sharing its internals.
3. fzf port (pure, golden cases from the bun oracle), default filter adapter
   and plain Picker reducers:
   ranking, positions, selection preservation, empty/no-room and stale item
   changes. The port must compile AOT and retain upstream matching semantics.
4. Picker over ListView, described Actions, filter editor and geometry.
   Test both modes, all shortcuts, nonrotation, tall rows, resize,
   exact hidden counts, disabled acceptance and KeyHelp's enabled keys.
5. Dialog on CTUI-2 entries, shared choice rows and body-fold geometry.
   Test wrap versus Picker clamp, priority under small room, no hidden
   acceptance, Esc, passive notice, nested focus and focus return.
6. Runnable framework fixtures for all four widgets at 120x40 and 80x24,
   dark/light/plain, empty/focused/overflow/narrow. Developer hands the
   exact command and commits to designer before live tmux captures; only
   after the look goes to reviewer. No implementation of the port's forms,
   permissions, model/session pickers, path logic or shortcuts panel here.

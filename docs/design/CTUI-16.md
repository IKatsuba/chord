# CTUI-16: transcript screen

The original is `../chord/src/ui/transcript/`. CTUI-15 supplies the folded
state and intents; its table "What the screens read and dispatch" applies.
This addition specifies the framework gap raised by developer for U2.
The remaining transcript units follow the original, with runtime captures
under `docs/design/evidence/CTUI-16/`.

## U2a: a reusable diff view

Original runtime clarification: ordinary tool diff content is rendered with
`expanded: true` by `../chord/src/ui/transcript/tools/tools.ts`; `rewrite`
is unchanged by ctrl+o. The ten-row helper is used by proposal views. The
selection API below supports callers that need a preview; it does not
authorize folding ordinary tool diffs in the port.

Extend CTUI-6's existing pure model rather than diffing again in the port.
The package and parsing decisions in docs/decisions.md remain applicable:
`dartdiff` produces hunks, and highlighting uses complete source runs.
No new package or parser is needed for selecting already parsed rows.

### Call site

```dart
final model = diffTexts(oldText, newText); // context defaults to 3
final view = model.view(maxRows: expanded ? null : 10);

Column(children: [
  Text('Updated $path with ${view.added} additions and '
      '${view.removed} removals'), // the port owns wording and plurals
  Diff.fromView(view, title: path, showTitle: false),
  if (view.hidden > 0) Text('… ${view.hidden} more lines'),
]);
```

Ordinary callers still write `Diff(oldText, newText, title: path)` or
`Diff.fromUnified(patch)`. Both use the same full view internally. Neither
existing constructor folds or gains a cutoff by default.

### Public surface

Export the existing `diffTexts`, `parseUnifiedDiff`, `DiffModel`, `DiffHunk`,
`DiffLine` and `DiffKind` through `chorded_tui.dart`, plus the additions below.
Do not export the remembered-parser cache or its test counters.
Existing constructors and fields retain their meanings.

```dart
// Pure data: no widgets, styles, terminal cells or highlighted spans.
sealed class DiffRow { const DiffRow(); }
// The existing DiffLine becomes a DiffRow; its fields are unchanged.
final class DiffLine extends DiffRow { /* existing constructor and fields */ }
final class DiffGap extends DiffRow { const DiffGap(); }

// An addition to the existing DiffModel.
DiffView view({int? maxRows});

final class DiffView {
  // Created by DiffModel.view; no public constructor is required.
  final DiffModel model;
  final List<DiffRow> rows;
  final int added;
  final int removed;
  final int hidden;
  final int numberWidth;
}

// An addition to Diff.
Diff.fromView(DiffView view, {
  Key? key,
  String? title,
  bool showTitle = true,
});
```

`DiffModel.view` flattens its hunks in order with one `DiffGap` between
hunks. No gap leads or trails the full view. A `DiffLine` retains its source
index and line index so the renderer highlights its complete model source,
then selects rows. Selecting rows must never truncate the highlighting
input or regenerate the patch. `rows` is unmodifiable; selecting a view
does not mutate its model or another view.

`maxRows: null` selects all rows. A non-negative value selects the first
that many model rows, then removes a trailing gap. A gap consumes one place
in this limit. This is a limit before wrapping, not a height in terminal
cells. Negative values throw RangeError; zero yields an empty row list.
`hidden` counts all unselected added, removed and context lines, excluding
gaps. `added` and `removed` always count the complete model, even when no
rows are selected. `numberWidth` is the digits of the largest selected
line number, at least one. Empty and equal inputs have zero counts and no
rows. All views use the existing CRLF and final-newline normalization.

`Diff.fromView` renders exactly the selected rows using CTUI-6's gutters,
tints, wrapping and source highlighting. `title` overrides `view.model.path`
for both the optional title and language lookup. `showTitle: false` hides
only the title row: the path still selects the language. With no path,
there is no title and no guessed language. This avoids duplicating the
file name beneath a caller's own headline. `showTitle` is needed only on
this new constructor for this slice; keep the existing APIs unchanged.

### Drawn states and sizes

These are layout sketches. Runtime captures are required at U2a handover.
At 120x40 and at 80x24 a small edit has identical source rows; tint fills
the available width and the rest of each viewport is blank:

```text
1   export function greet(name: string) {
2 -   return "hello " + name;
2 +   return `hello, ${name}`;
3   }
```

A separated hunk starts with `…` in the sign column. If `maxRows` lands
on that gap, neither it nor the next hunk is drawn. For example, nine lines
of the first hunk followed by a gap and a second hunk, with `maxRows: 10`,
shows nine lines and no gap. The hidden count includes every line of the
second hunk. The full additions/removals still describe both hunks.

An overflowing source line wraps at 80 columns, and may fit at 120:

```text
12 -   return 'A message about terminal cells, 日本語, and preserving every
     grapheme while the source line wraps';
12 +   return 'A shorter message';
```

A wrapped continuation consumes no extra place in `maxRows` and does not
increase `hidden`. A selected row always renders whole subject to ancestor
clipping. Narrow widths, zero width, unknown languages, no tint and plain
theme retain CTUI-6's behavior. Empty views draw no rows; an explicitly
shown title can still draw. Focus changes nothing.

### Actions and ownership

The model and Diff are passive. They bind no keys and add no shortcuts.
The port's `Actions` binds ctrl+o to toggle details and lists it in
the shortcuts panel. A consumer that folds a diff can select a full or
capped view; ordinary tool diff content stays full, as the original does. Headline,
hidden-row wording, tool marker and result gutter remain in the port.

### Acceptance and handover

Pure tests cover full counts, zero/negative/unbounded limits, a cap before,
on and after an inter-hunk gap, gap-excluded hidden counts, selected number
width, and views retaining the complete sources without mutation. Existing
CTUI-6 normalization and unified-parser cases remain valid. Rendering
checks establish equivalence of an uncapped view and the existing Diff,
multiline highlighting across omitted source, title suppression preserving
language, and wrapping independent of the source-row limit. Developer
provides a runnable fixture at 120x40 and 80x24 for designer before review.

The general row/view API is new; the port's ten-row default is not a
framework default. There is no new visual departure from the original.

## U4a: middle overflow for Text

Reviewer found that a long finished-plan step was clipped instead of
matching the original's `CUT`. Runtime checks of the original `PlanRecord`
and the installed OpenTUI text renderer confirm a middle ASCII `...` with
both ends retained. The lead chose a general framework mode, with no port
workaround. This adds one enum value; `TextOverflow.ellipsis` is unchanged.

### Call site and API

```dart
Text.ansi(step.content,
  softWrap: false,
  maxLines: 1,
  overflow: TextOverflow.middle,
  style: completedStepStyle,
);

DefaultTextStyle(
  softWrap: false,
  maxLines: 1,
  overflow: TextOverflow.middle,
  child: Text('A path or a single-line label that may be too long'),
);
```

Add `TextOverflow.middle` to the existing enum. It flows through the
existing Text, Text.ansi, Text.rich, DefaultTextStyle and TextLayout APIs;
there is no new constructor, marker parameter or truncation helper for the
port. Names and parameter placement follow the existing Text overflow API.
The mode does not change wrapping or line limits: single-line consumers
set `softWrap: false, maxLines: 1` explicitly or by inheritance.

For each horizontally overflowing retained line with bounded width W:

- If W is below 4, draw no glyphs. Otherwise reserve three cells for `...`.
- Allocate floor((W - 3) / 2) cells to the head and the remaining cells to
  the tail. Thus an odd spare cell goes to the tail.
- Keep the longest contiguous prefix and suffix fitting those respective
  budgets. Stop at complete grapheme boundaries; do not skip a wide
  grapheme to take text behind it, split an emoji/combining cluster, or
  transfer unused cells from one budget to the other.
- Join head, marker and tail without padding. Keep original whitespace,
  including spaces adjacent to the marker. The result may be narrower
  than W when a wide grapheme does not fit a budget.
- Kept glyphs retain their original styles. The three marker glyphs take
  the Text's resolved base style, not an inline span's style. OpenTUI's
  mixed-color runtime probe keeps a default-color marker between colored
  head/tail spans; this matters for styled rule rows and completed steps.

A fitting line, even at widths below four, is unchanged. Unbounded width
has no truncation. Width zero draws nothing for an overflowing line.
Newlines still delimit lines, wrapping still precedes overflow, and
maxLines still limits which lines remain. This mode marks horizontal
omission only; it does not imply joining paragraphs or exposing the last
paragraph after vertical truncation. Focus changes nothing. The model
uses existing grapheme segmentation and cell widths; no new package is
needed for this terminal-layout behavior.

### Original M1 consumer audit

Read before designing this API: the original's `CUT` definition in
`../chord/src/ui/theme/text.ts`, all its uses in transcript, tools, plan,
prompt, dialogs/Permission, status, header, shortcuts and app/Start.
No other direct `truncate:` setting occurs in those M1 screen modules.

| Original place | Original behavior and scope |
| --- | --- |
| `plan/Plan.tsx`, PlanEntry | CUT on completed, in-progress and pending step text; U4 finished PlanRecord needs middle overflow now. The separate mark stays outside the truncated text. |
| `plan/Plan.tsx`, Plan | CUT on summary and folded-count row; future M1 plan/status screen can use the same mode. |
| `transcript/tools/Tool.tsx`, Guardian reviewing branch | CUT on its dim one-line review message; U5 adopts middle. |
| `transcript/tools/Tool.tsx`, Folded | CUT on hidden-line count/key hint; U5 adopts middle. |
| `transcript/Transcript.tsx`, Below | CUT on composed styled rule segments; U6 adopts middle after its existing width-aware indicator builds the text. Do not replace the indicator's fitting/wording rules. |
| `transcript/tools/Tool.tsx`, HeadlineText and DiffText | No CUT: tool headlines are laid out into wrapped rows and the Updated/path/count headline uses FILL. Preserve wrapping. |
| `transcript/tools/paths.ts`, shownFile/shownDirectory | Semantic relative/home shortening only, no width truncation. A path uses the overflow/wrapping policy of the screen that draws it. |
| `dialogs/Permission.tsx` | CUT on pinned title, count, input/location/title rows and scroll rules; CTUI-18 can reuse middle. Settled permission receipts in U4 wrap and do not adopt it. |
| `prompt/Prompt.tsx`, queue | CUT on queued text and overflow count; CTUI-17 can reuse middle. Fixed headers keep their existing separate treatment. |
| `prompt/Prompt.tsx`, prompt edge and Overlay | CUT on border label and overlay hints; use middle when these M1 consumers land. Search, command and path finder rows also use CUT but belong to later prompt features. |
| `header/Header.tsx` and `app/Start.tsx` | CUT on header lines and compact start/version/directory labels; later header/start work can reuse middle. This does not bring those screens into CTUI-16. |
| `status/Status.tsx` | CUT on left/right status parts and leader-key line; the separate working spinner line is not changed by this API. |
| `shortcuts/Shortcuts.tsx` | CUT on help rows and below-rule; later M1 shortcuts work can reuse middle. |

Other transcript CUT branches are fork, self-started turn, background-item
end and inter-agent message furniture. They are outside M1 and do not
expand this slice. Form, question and asked-plan dialogs are likewise not
brought into this task.

### Layout sketches and acceptance

Original runtime probes with `ABCDEFGHIJKLMNOPQRSTUVWXYZ` gave:

```text
W=3:  [empty]
W=4:  ...Z
W=5:  A...Z
W=6:  A...YZ
W=8:  AB...XYZ
W=9:  ABC...XYZ
```

For `abc日本語👩‍💻XYZ`, W=10 and W=11 both gave `abc...XYZ`, W=12 gave
`abc...👩‍💻XYZ`, and W=13 gave `abc日...👩‍💻XYZ`. At W=14 it fits whole.
A 120x40 plan fixture and the same fixture at 80x24 keep one row per step,
the checkmark and result gutter aligned; a long step preserves its ending
with `...` between. The rest of the viewport stays unchanged. Empty text
and fitting steps draw as before; there is no new key or shortcut.

Developer adds focused layout/widget checks for fitting and empty text,
bounded/unbounded widths, widths zero through four, odd budgets, Unicode
and combining graphemes at both cuts, preserved whitespace and styles,
ANSI/rich input and inherited defaults. Include an overflow-mode change
on the same mounted Text and verify the existing ellipsis behavior remains
unchanged. A long finished-plan fixture/test closes reviewer's U4 finding;
U5's two CUT consumers and U6's rule use this same mode. Designer checks the
handed-over framework fixture and the corrected plan at both screen sizes
before corrected U4 returns to reviewer.

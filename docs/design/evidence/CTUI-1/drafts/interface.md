# CTUI-1, interface draft: the call site, the states, the keys

By interface. Answers the brief's questions for interface (1–3). The
scrollbar (question 4) is dropped by the owner; the controller exposes
`contentRows`, `viewRows` and `offset` so one can be added later, and this
draft says nothing more of it.

Sources read: the brief; `lib/src/widgets/focus.dart`, `focus_manager.dart`,
`key_help.dart`, `text_input.dart`, `lib/testing.dart`; in `../chord`:
`src/ui/transcript/scroll.ts`, `Transcript.tsx` (`Below`),
`src/ui/app/state.ts` (`scrollStep`, `withNews`), `src/ui/pickers/picker.ts`,
`Pickers.tsx` (`PickerList`), `src/ui/prompt/commands.ts` (`visibleRange`),
`src/ui/background/view.ts` (`logStep`, `viewWindow`, `edgeMarked`),
`src/ui/dialogs/permission.ts` (`requestView`, `requestStep`, `requestRule`,
`requestCount`), `src/ui/shortcuts/bindings.ts`, `keys.ts`. The transcript
captures below were taken from the original with the fake agent's `long`
scenario (`bun dev chord --qa <name> --fake`, then `long`, in tmux at 80x24
and 120x40); the picker and log captures are drawn from the code.

## 1. The principle that splits the work

The framework gives the **mechanism**: a list that builds only what is in
sight, a controller that holds where the view is and whether it follows, and
steps (page, line, top, bottom, ensure visible). The **wording and the
exact rules of chord's own boxes** stay chord's: the transcript's rule row,
the log box's `↑`/`↓` rules and their room arithmetic (`requestView`), the
picker's `… +N more` line. Those are ported as pure Dart in
`example/chord/lib/` with the original's tests and drive the framework's
list through the controller.

One rule moves into the framework whole: the transcript's follow rule
(`reduceScroll`, `pageRows`), because "follow the bottom, a scroll up stops
following, reaching the bottom resumes it" is what any log or chat view
needs, and README promises it as `Follow.bottom`. runtime owns its exact
transitions; this draft only names how they are reached.

## 2. The public API, as call sites

### 2.1 The transcript (the README case)

```dart
class _WindowState extends State<Window> {
  final scroll = ScrollController();

  @override
  Widget build(BuildContext context) => ScrollActions(
        controller: scroll,
        keys: chordScrollKeys,             // the port's: see 4.3
        child: Column(children: [
          Expanded(
            child: Stack(children: [
              ListView.builder(
                controller: scroll,
                follow: Follow.bottom,
                itemCount: session.entries.length,
                itemKey: (i) => session.entries[i].id,  // keeps the anchor on backfill
                itemBuilder: (context, i) => EntryView(session.entries[i]),
              ),
              // chord's rule over the view's last row; draws nothing while following
              Positioned(bottom: 0, left: 0, right: 0,
                  child: ListenableBuilder(
                    listenable: scroll,
                    builder: (context) => BelowRule(scroll, bottomKey: 'end'),
                  )),
            ]),
          ),
          Prompt(controller: draft),       // holds focus; scroll keys pass it by
          StatusLine(...),
        ]),
      );
}
```

`Positioned` belongs to the overlays task (FEATURES "Layers over the
window"); until it lands the port can use `Stack` with an `Align` to the
bottom. The rule is an overlay, not a row taken from the list, because in
the original the view counts the rule's row (`Scroll.view` is "the
indicator's row included") and `rowsBelow` counts the row it covers.

### 2.2 `ScrollController`

A `ChangeNotifier`, plain Dart, no widget in it; the state it holds is
runtime's reducer (`ScrollState` + `reduceScroll`), and the controller is
that state plus the place a list reports its measurements to.

```dart
/// Where a scrolling view is, and the steps that move it.
class ScrollController extends ChangeNotifier {
  ScrollController({int initialOffset = 0});

  // What the list measured on its last layout. Zero until attached.
  int get contentRows;        // rows of all items at the view's width (see framework for exact vs estimated)
  int get viewRows;           // rows the view has
  int get offset;             // rows above the view: 0 at the top, contentRows - viewRows at the bottom
  int get rowsAbove;          // == offset
  int get rowsBelow;          // max(0, contentRows - offset - viewRows)
  bool get fits;              // contentRows <= viewRows
  bool get atTop;             // offset == 0
  bool get atBottom;          // rowsBelow == 0
  bool get isFollowing;       // the view shows the end and will keep showing it
  bool get hasNews;           // something arrived since the view left the bottom
  ScrollAnchor get anchor;    // (index, rowsInto): the item at the view's top row
  int get firstVisible;       // index of the first item in sight, partly or whole
  int get lastVisible;        // index of the last item in sight, partly or whole

  // Steps: the original's ScrollStep, one method each, so a Binding can name them.
  void pageUp();              // a page is viewRows - 2, one at least (pageRows)
  void pageDown();
  void lineUp([int rows = 1]);
  void lineDown([int rows = 1]);
  void toTop();
  void toBottom();            // follows again where the list follows, clears news
  void step(ScrollStep step); // the same, for code that holds a step as data

  // Placing.
  void jumpTo(int offset);                              // clamped; a scroll back stops following
  void jumpToIndex(int index, {int rowsInto = 0});      // that item's row at the view's top
  void ensureVisible(int index, {TallItem tall = TallItem.showStart});

  // News.
  void markNews();            // no-op while following; the app's rule decides when
}

enum ScrollStep { pageUp, pageDown, lineUp, lineDown, top, bottom }

/// Which end of an item taller than the view [ScrollController.ensureVisible] shows.
enum TallItem { showStart, showEnd }

/// The item at the top row of the view, and how many of its rows are above it.
class ScrollAnchor { final int index; final int rowsInto; }
```

Notes on the names:

- `offset`, `jumpTo`, `ScrollController` are Flutter's names; a Flutter
  reader guesses them. `pageUp`…`toBottom` are not Flutter's (Flutter has
  `animateTo` and intents); they exist because every one of them is a key.
- Offsets are `int` rows, never `double`: layout is in cells.
- `rowsBelow` is the framework's plain count. chord's rule says
  `max(1, content − top − (view − 1))`, one more, because its rule covers a
  row; the port computes that from `contentRows`, `offset`, `viewRows`.
  The framework does not know about the covered row.
- `ensureVisible` is the least move that brings the item into sight
  (`visibleRange`'s rule: the window moves only when the item leaves it).
  An item taller than the view shows its first row, or its last with
  `TallItem.showEnd`, which is what a picker moving up wants (`lineTop`,
  CHD-445).
- `markNews` is explicit. The original sets news when the session's entries
  change while scrolled back (`withNews`), and not on a relayout such as
  ctrl+o unfolding, which also changes `contentRows`. The framework cannot
  tell those apart, so it never guesses: the port calls `markNews()` where
  `withNews` is called today. **Open, for the lead:** `ListView` could also
  mark news by itself when `itemCount` grows at the end while scrolled back
  (useful to any log); I lean to no automatic news in CTUI-1, one rule only.
- A controller attached to two lists is an error (runtime's failure list);
  the call site makes one per list, as in Flutter.
- Backfill: the port listens to the controller and pages its record in
  when `scroll.rowsAbove < scroll.viewRows` (the original's `backfilled`).
  No new callback is needed for that.

### 2.3 `ListView.builder` and `Follow`

```dart
ListView.builder({
  Key? key,
  ScrollController? controller,        // one is made and owned when absent
  Follow follow = Follow.none,
  required int itemCount,
  required IndexedWidgetBuilder itemBuilder,
  Object? Function(int index)? itemKey, // identity across insertions; see below
})

ListView({ScrollController? controller, Follow follow, required List<Widget> children})

/// Whether a list keeps its end in sight as it grows.
enum Follow { none, bottom }
```

- `Follow.bottom`: the transcript and the log boxes. The list starts
  following; a scroll up stops it; reaching the bottom by any step resumes
  it; a list that fits always follows (runtime's rule).
- `Follow.none`: pickers. The offset only moves when asked.
- `itemKey`: when items are inserted above (backfill), indices shift; the
  key lets the list find the anchored item again, the way Flutter's
  `findChildIndexCallback` does, but as a key per index because that is
  what the port already has (entry ids). Without it, the anchor is by index
  and insertion above moves the view. How the list uses it is framework's.
- `ListView` binds no keys and takes no focus. Keys reach the controller
  through `ScrollActions` or the app's own `Actions` (section 4). A list
  that is never focused is the transcript's case: the prompt holds focus.

### 2.4 `ScrollActions` and `ScrollKeys`

A convenience over `Actions`; anything it does an app can write as plain
`Binding`s.

```dart
/// Binds the scroll steps of [controller] to keys for everything under it.
class ScrollActions extends StatelessWidget {
  const ScrollActions({
    required this.controller,
    this.keys = const ScrollKeys(),
    required this.child,
  });
  // build: Actions(bindings: keys.bindingsFor(controller), child: child)
}

/// Which keys press which scroll step, and how the shortcuts panel says it.
class ScrollKeys {
  const ScrollKeys({
    this.pageUp = const ['pageup'],
    this.pageDown = const ['pagedown'],
    this.lineUp = const [],              // the app's to choose: none by default
    this.lineDown = const [],
    this.top = const ['home'],
    this.bottom = const ['end'],
    this.descriptions = ScrollDescriptions.standard,
  });

  List<Binding> bindingsFor(ScrollController controller);
}
```

An empty list leaves a step unbound. One key per `Binding` today, so a step
with two keys becomes two bindings with one description (see 4.4).

### 2.5 What a picker writes

A picker owns its highlight; the list only keeps it in sight.

```dart
class _PickerState extends State<Picker> {
  final scroll = ScrollController();
  var highlighted = 0;

  void move(int by) {
    final next = (highlighted + by).clamp(0, widget.choices.length - 1);
    if (next == highlighted) return;                 // stops at either end
    setState(() => highlighted = next);
    scroll.ensureVisible(next, tall: by < 0 ? TallItem.showEnd : TallItem.showStart);
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        child: Actions(
          bindings: [
            Binding('up', 'Move up', () => move(-1)),
            Binding('k', 'Move up', () => move(-1)),
            Binding('down', 'Move down', () => move(1)),
            Binding('j', 'Move down', () => move(1)),
            Binding('enter', 'Select', () => widget.onPick(highlighted)),
          ],
          child: ListView.builder(
            controller: scroll,
            itemCount: widget.choices.length,
            itemBuilder: (context, i) =>
                ChoiceRow(widget.choices[i], highlighted: i == highlighted,
                    edge: edgeOf(i)),  // ↑/↓ gutter: from scroll.firstVisible/lastVisible
          ),
        ),
      );
}
```

The picker widget itself (`❯`, numbers, digits 1–9, the frame) is FEATURES'
"Fold, Table, Picker, Dialog" task, not CTUI-1. What CTUI-1 must give it:
`ensureVisible` with the least-move rule and `TallItem`, `firstVisible` /
`lastVisible` for the `↑` `↓` gutter marks and the `… +N more` count, and a
list that accepts items of more than one row (`linedRows`).

The `… +N more` line sits **inside** the picker's budget in the original
when choices are multi-line (`room`), and outside it when they are one line
(`pickerRows`). That arithmetic is the picker's; it sizes the list
(`SizedBox(height: budget - more)`) and draws the line under it.

### 2.6 What a log box writes

The log box's rules take rows of its room and change how many log rows it
shows (`requestView`: room − 1 at either end, room − 2 between, special
rooms of 0/1/2). That is chord's arithmetic, so it stays pure in the port
(`example/chord/lib/ui/dialogs/permission.dart`, `requestView`,
`requestStep`, `logStep`, with the original's tests), and the box drives a
list with it:

```dart
final view = requestView(total, room, top);   // the port's pure function
Column(children: [
  if (view.above) Text(requestRule('↑', view.top, pageUpKey, width), style: Style.dim),
  SizedBox(
    height: view.shown,
    child: ListView.builder(
      controller: log..jumpTo(view.top),      // in practice set in the reducer, not in build
      itemCount: total,
      itemBuilder: (context, i) => Text(lines[i], softWrap: false),
    ),
  ),
  if (view.below) Text(requestRule('↓', below, pageDownKey, width), style: Style.dim),
])
```

and binds its own page keys, which call `requestStep`/`logStep` rather than
the controller's `pageUp` (CHD-246's page is not the transcript's
view − 2). This is the case that proves "the keys are the app's": same
keys, different step.

## 3. The states, drawn

Styles named beside each capture: `dim` (Style.dim), `accent` (bold in the
theme's accent), `permission` (the picker's highlight colour). Rows of the
window that are not the scrolled box are shown for orientation and are not
CTUI-1's to draw.

### 3.1 The transcript

The transcript area is the window less the prompt box (3 rows), the status
line and the spinner rows; at 80x24 it is about 17 rows, at 120x40 about 35.
Every row has a one-cell left margin.

**Fits** (content ≤ view). Follows by definition; no rule; home, end,
pageup do nothing (`scrolled`: "Nothing to scroll").

```text
80x24                                                                     
 ▀▄     chord v0.71.0
 ▀▀▀▄   fake · Fake Large with a 1M context window
 ▄▀▀▀   <the qa directory>
 ▀▀     ? for shortcuts · /help
                                                     (blank rows to the box)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts          Fake Large with a 1M context window · medium effort
```

At 120x40 the same, wider; nothing scrolls. The content sits at the top of
the view, not the bottom (`following` while it fits shows "all of it, from
the top").

**Following, streaming.** The view's bottom on the content's; each frame's
new rows push the top up. No rule.

```text
80x24 (captured)
   55. Line 55 of 200, streamed one at a time.
   56. Line 56 of 200, streamed one at a time.
   57. Line 57 of 200, streamed one at a time.
   58. Line 58 of 200, streamed one at a time.

 ››› Working… (5s · esc to interrupt)

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
```

**Scrolled back, no news** (pageup once, the turn ended). The view's last
row is the rule, `dim`; the count includes the covered row.

```text
120x40 (captured; rows 1–31 are lines 133–163)
   164. Line 164 of 200, streamed one at a time.
   165. Line 165 of 200, streamed one at a time.
   166. Line 166 of 200, streamed one at a time.
 ── ↓ 34 lines below · end to jump to the bottom ───────────────────────────────────────────────────────────────────────
                                                                                                       ^ whole row: dim

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

```text
80x24
   …
 ── ↓ 34 lines below · end to jump to the bottom ───────────────────────────────
```

**Scrolled back with news** (pageup while the reply streams). The count
keeps climbing as output arrives below; the rows in sight hold still.
`↓ new output` is `accent`, the rest `dim`.

```text
80x24 (captured)
 ⏺ 1. Line 1 of 200, streamed one at a time.
   2. Line 2 of 200, streamed one at a time.
   …
   13. Line 13 of 200, streamed one at a time.
 ── ↓ new output · 111 lines below · end to jump to the bottom ────────────────
    ^^^^^^^^^^^^ accent; the rest dim

 ››› Working… (12s · esc to interrupt)
```

```text
120x40 (captured after a resize from 80x24: the top row stayed "› long")
   31. Line 31 of 200, streamed one at a time.
 ── ↓ new output · 169 lines below · end to jump to the bottom ────────────────────────────────────────────────────────
```

**At the top** (home). The same rule as scrolled back; there is no "above"
marker in the transcript. Rows 1.. are the first entries (or the backfill
boundary, which the port pages in as the view nears it).

**Narrow.** When the whole rule does not fit, the key part goes first
(`indicator`): at 24 columns, ` ── ↓ 1 line below ─────`. At 80 and 120
both forms fit for counts under 10⁹.

**A relayout keeps the top.** ctrl+o or a resize keeps the anchored entry's
row at the view's top, as far into the entry as it still reaches (`topOf`).
The capture above (80x24 → 120x40, top row unchanged) is the expected
result.

**View of 0 or 1 rows.** 0: nothing is drawn, steps are no-ops. 1: the rule
alone covers the one row while scrolled back (the original's behaviour,
`rowsBelow` is at least 1); runtime confirms.

### 3.2 A picker

From `PickerList`: `❯` in the gutter, `permission` colour on the
highlighted row; `↑`/`↓` `dim` in a second gutter only while the list
scrolls; `… +N more` `dim`, indented 4, under the rows.

**Fits** (captured, 80x24, `/model`). No edge gutter.

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                 │
│ Switch fake's model for this session.                                        │
│                                                                              │
│ ❯ 1. Fake Large with a 1M context window ✔                                   │
│   2. Fake Small                                                              │
│                                                                              │
│ Enter to switch · ←/→ for effort · Esc to close                              │
╰──────────────────────────────────────────────────────────────────────────────╯
```

**Scrolled, highlight in the middle** (drawn; 12 sessions, 5 rows).

```text
│ ❯ ↑  4. fix the flaky test · 2h                    │   ❯ permission, ↑ dim
│      5. port the shortcuts panel · 3h              │
│      6. read the ACP spec · 1d                     │
│      7. CTUI-1 design · 1d                         │
│   ↓  8. renderer diffing · 2d                      │   ↓ dim
│     … +4 more                                      │   dim
```

Moving down from 8 to 9 slides the window by one (least move); moving up
from 4 to 3 likewise; the rows hold still while the highlight walks inside
them. At 1 and at 12 the highlight stops. 120x40 shows the same rows
wider; the budget is the picker's, not the window's.

**A choice of several lines** (drawn, 80x24, CHD-445): every line of the
highlighted choice takes `permission`; `❯` and the number on its first
line only; a choice taller than the budget shows its first line when
reached by down, its last when reached by up (`TallItem`).

**Empty.** No rows; the picker's own text says so. The list draws nothing
and its steps are no-ops.

### 3.3 A log box (background detail, permission request)

Rules are `dim`, drawn to the box's inner width (`requestRule`), with the
key that scrolls toward the hidden rows: `pgup` above, `pgdn` below. The
log follows its end (`FOLLOWING`); a scroll up stops it; reaching the end
resumes it; `end` always resumes it.

Room of 6 rows, 160 lines, following (the end view: `↑` rule over room − 1):

```text
80x24
│ ── ↑ 155 lines above · pgup to scroll ────────────────────────────────────── │  dim
│ line 156                                                                     │
│ line 157                                                                     │
│ line 158                                                                     │
│ line 159                                                                     │
│ line 160                                                                     │
```

Scrolled to the middle (both rules round room − 2):

```text
120x40
│ ── ↑ 120 lines above · pgup to scroll ────────────────────────────────────────────────────────────────────────────── │
│ line 121                                                                                                             │
│ line 122                                                                                                             │
│ line 123                                                                                                             │
│ line 124                                                                                                             │
│ ── ↓ 36 lines below · pgdn to scroll ─────────────────────────────────────────────────────────────────────────────── │
```

At the top (home): the first room − 1 lines over the `↓` rule.

**Room of 2:** one line and one rule: `↓` while lines are below, else `↑`.
**Room of 1:** one line, no rule; the count moves to the box's title row
(`requestCount`: `↑ 3 above · ↓ 5 below`, no key). **Room of 0:** nothing;
the title row's count still says it. **Fits:** all lines, no rules, keys
do nothing.

### 3.4 The missing states, cell-exact (critic C13)

Every capture below is the whole window, every row of it, at the size named; the log box frames (3.4.3) are drawn alone, as said there.
"Captured from the original" means `tmux capture-pane` of
`bun dev chord --qa <name> --fake` in `../chord`, pasted as captured; the
one change is the qa directory's path on the splash, replaced by
`<qa directory>` padded to the same width. Styles are not in a text
capture; they are named under each screen. The rows under the status line
in the picker captures are the session tabs that the `/new` presses made
for the capture; they are part of the window, not of the picker.

#### 3.4.1 The transcript at the top (home)

Captured from the original: the `long` scenario after its turn ended,
then `home`. The rule is `dim`; the count includes the row the rule
covers (8 lines in sight and 192 below at 80x24, 24 and 176 at
120x40, 200 in all). There is no "above" marker: the first rows are the start of the
record.

80x24, captured from the original:

```text
 ▀▄     chord v0.71.0
 ▀▀▀▄   fake · Fake Large with a 1M context window
 ▄▀▀▀   <qa directory>   
 ▀▀     ? for shortcuts · /help

 › /resume
   ⎿  No earlier fake session to resume, here or in any other directory.

 › long

 ⏺ 1. Line 1 of 200, streamed one at a time.
   2. Line 2 of 200, streamed one at a time.
   3. Line 3 of 200, streamed one at a time.
   4. Line 4 of 200, streamed one at a time.
   5. Line 5 of 200, streamed one at a time.
   6. Line 6 of 200, streamed one at a time.
   7. Line 7 of 200, streamed one at a time.
   8. Line 8 of 200, streamed one at a time.
 ── ↓ 192 lines below · end to jump to the bottom ─────────────────────────────

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts       Fake Large with a 1M context window · medium · 1% used
```

120x40, captured from the original:

```text
 ▀▄     chord v0.71.0
 ▀▀▀▄   fake · Fake Large with a 1M context window
 ▄▀▀▀   <qa directory>   
 ▀▀     ? for shortcuts · /help

 › /resume
   ⎿  No earlier fake session to resume, here or in any other directory.

 › long

 ⏺ 1. Line 1 of 200, streamed one at a time.
   2. Line 2 of 200, streamed one at a time.
   3. Line 3 of 200, streamed one at a time.
   4. Line 4 of 200, streamed one at a time.
   5. Line 5 of 200, streamed one at a time.
   6. Line 6 of 200, streamed one at a time.
   7. Line 7 of 200, streamed one at a time.
   8. Line 8 of 200, streamed one at a time.
   9. Line 9 of 200, streamed one at a time.
   10. Line 10 of 200, streamed one at a time.
   11. Line 11 of 200, streamed one at a time.
   12. Line 12 of 200, streamed one at a time.
   13. Line 13 of 200, streamed one at a time.
   14. Line 14 of 200, streamed one at a time.
   15. Line 15 of 200, streamed one at a time.
   16. Line 16 of 200, streamed one at a time.
   17. Line 17 of 200, streamed one at a time.
   18. Line 18 of 200, streamed one at a time.
   19. Line 19 of 200, streamed one at a time.
   20. Line 20 of 200, streamed one at a time.
   21. Line 21 of 200, streamed one at a time.
   22. Line 22 of 200, streamed one at a time.
   23. Line 23 of 200, streamed one at a time.
   24. Line 24 of 200, streamed one at a time.
 ── ↓ 176 lines below · end to jump to the bottom ─────────────────────────────────────────────────────────────────────

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                Fake Large with a 1M context window · medium effort · 1% context used
```

#### 3.4.2 A picker with a choice taller than its room

Captured from the original: `/resume` over sessions whose first prompts
are long, so that a choice wraps (`hang`) to more lines than the picker's
budget (6 lines at 80x24, 10 at 120x40, from `framedRows`). Styles: `❯`
and every line of the highlighted choice in `permission`; `↑` and `↓`
in the edge gutter `dim`; `… +N more` `dim`; the frame's border in
`permission`.

**Reached by down** (from choice 1, one `down`): `lineKey` places it
from its first line (`placed(…, 'first')`); the `❯` and number are in
sight; `↓` on the last line in sight; no `… +N more`, because the
highlighted choice takes the whole budget (`linedRows`: `hidden` is 0
then). Each further `down` scrolls the choice by one line until its last
line is in sight; only then does the highlight move on.

80x24, captured from the original:

```text
 fake 8 · fake · Fake Large with a 1M context window · opened by main 19s ago

╭──────────────────────────────────────────────────────────────────────────────╮
│ Resume a session                                                             │
│ fake's earlier sessions in this directory.                                   │
│                                                                              │
│     1. just now       open now  fake 7 · echo a short one                    │
│ ❯   2. just now       open now  fake 6 · echo Review the CTUI-1 design end   │
│                                 to end and answer each point in order:       │
│                                 whether the controller holds the follow rule │
│                                 as a pure reducer that a test reaches        │
│   ↓                             without a widget, whether the list builds    │
│                                                                              │
│ Enter to resume · Ctrl+a for all directories · Esc to close                  │
╰──────────────────────────────────────────────────────────────────────────────╯

╭─ fake 8 ─────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts          Fake Large with a 1M context window · medium effort
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake    fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    fake 2  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    … +6 more
```

120x40, captured from the original:

```text
 fake 8 · fake · Fake Large with a 1M context window · opened by main 4s ago











╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Resume a session                                                                                                     │
│ fake's earlier sessions in this directory.                                                                           │
│                                                                                                                      │
│     1. just now       open now  fake 7 · echo a short one                                                            │
│ ❯   2. just now       open now  fake 6 · echo Review the CTUI-1 design end to end and answer each point in order:    │
│                                 whether the controller holds the follow rule as a pure reducer that a test reaches   │
│                                 without a widget, whether the list builds only the items in sight during layout      │
│                                 without breaking the sync of render children from the element tree, how item heights │
│                                 are cached by index and width and invalidated when a streaming reply grows or a fold │
│                                 opens, what total height is used for paging and for the rule that says how many      │
│                                 lines are below, how the anchor is kept across a relayout, a resize, and an          │
│                                 insertion above when older entries are paged in, how a partly visible item is        │
│   ↓                             clipped at the top and at the bottom of the view, what a frame costs at ten thousand │
│                                                                                                                      │
│ Enter to resume · Ctrl+a for all directories · Esc to close                                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭─ fake 8 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                  Fake Large with a 1M context window · medium effort
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake    fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    fake 2  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    fake 3  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    fake 4  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    … +4 more
```

**Reached by up.** First the screen before it: the highlight walked
down through choice 2 line by line and on to choice 3 (also taller than the
80x24 budget). Then one `up`: the highlight goes back to choice 2 and
`lineKey` places it from its last line (`placed(…, 'last')`), the least
move that brings that line into sight. At 80x24 the last lines were already
in sight, so the view does not move; the `❯` is on choice 2's first line,
which is out of sight, so no `❯` shows at all and only the `permission`
colour of its lines says it is highlighted. At 120x40 the view moves up by
one line. Further `up`s scroll through choice 2 a line at a time until its
first line, with the `❯`, is in sight.

80x24, on choice 3, captured from the original:

```text
 fake 8 · fake · Fake Large with a 1M context window · opened by main 46s ago

╭──────────────────────────────────────────────────────────────────────────────╮
│ Resume a session                                                             │
│ fake's earlier sessions in this directory.                                   │
│                                                                              │
│   ↑                             scroll keys, how the log box degrades for    │
│                                 rooms of zero, one and two rows, and finally │
│                                 which of the original's tests carry over,    │
│                                 which are dropped, and which new tests the   │
│                                 framework needs at both sizes                │
│ ❯ ↓ 3. 1 minute ago   open now  fake 5 · echo Walk through the whole frame   │
│                                                                              │
│ Enter to resume · Ctrl+a for all directories · Esc to close                  │
╰──────────────────────────────────────────────────────────────────────────────╯

╭─ fake 8 ─────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts          Fake Large with a 1M context window · medium effort
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake 2  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    … +6 more
```

80x24, one `up`: choice 2 reached by up, captured from the original:

```text
 fake 8 · fake · Fake Large with a 1M context window · opened by main 47s ago

╭──────────────────────────────────────────────────────────────────────────────╮
│ Resume a session                                                             │
│ fake's earlier sessions in this directory.                                   │
│                                                                              │
│   ↑                             scroll keys, how the log box degrades for    │
│                                 rooms of zero, one and two rows, and finally │
│                                 which of the original's tests carry over,    │
│                                 which are dropped, and which new tests the   │
│                                 framework needs at both sizes                │
│   ↓ 3. 1 minute ago   open now  fake 5 · echo Walk through the whole frame   │
│                                                                              │
│ Enter to resume · Ctrl+a for all directories · Esc to close                  │
╰──────────────────────────────────────────────────────────────────────────────╯

╭─ fake 8 ─────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts          Fake Large with a 1M context window · medium effort
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake 2  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    … +6 more
```

120x40, on choice 3, captured from the original:

```text
 fake 8 · fake · Fake Large with a 1M context window · opened by main 53s ago











╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Resume a session                                                                                                     │
│ fake's earlier sessions in this directory.                                                                           │
│                                                                                                                      │
│ ❯ ↑ 3. 1 minute ago   open now  fake 5 · echo Walk through the whole frame pipeline from the moment a key arrives to │
│                                 the moment the last changed cell reaches the terminal: how the parser turns bytes    │
│                                 into key events, how the focus path is walked, which bindings shadow which, how a    │
│                                 chord waits for its second key, how setState marks an element, how the build walks   │
│                                 the tree, how render children are synced from the element tree before layout, how    │
│                                 constraints go down and sizes come up in whole cells, how text is measured in        │
│                                 graphemes and wrapped, how the buffer is painted, how it is diffed against the last  │
│                                 frame, which escape sequences are written, how synchronized output is used, and      │
│                                 finally what a long streaming reply costs per frame at ten thousand entries, with    │
│   ↓                             numbers for each step and a short list of what to measure first                      │
│                                                                                                                      │
│ Enter to resume · Ctrl+a for all directories · Esc to close                                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭─ fake 8 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                  Fake Large with a 1M context window · medium effort
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake 2  fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake 3  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    fake 4  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    … +4 more
```

120x40, one `up`: choice 2 reached by up, captured from the original:

```text
 fake 8 · fake · Fake Large with a 1M context window · opened by main 54s ago











╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Resume a session                                                                                                     │
│ fake's earlier sessions in this directory.                                                                           │
│                                                                                                                      │
│   ↑                             and which new tests the framework needs at both sizes                                │
│     3. 1 minute ago   open now  fake 5 · echo Walk through the whole frame pipeline from the moment a key arrives to │
│                                 the moment the last changed cell reaches the terminal: how the parser turns bytes    │
│                                 into key events, how the focus path is walked, which bindings shadow which, how a    │
│                                 chord waits for its second key, how setState marks an element, how the build walks   │
│                                 the tree, how render children are synced from the element tree before layout, how    │
│                                 constraints go down and sizes come up in whole cells, how text is measured in        │
│                                 graphemes and wrapped, how the buffer is painted, how it is diffed against the last  │
│                                 frame, which escape sequences are written, how synchronized output is used, and      │
│   ↓                             finally what a long streaming reply costs per frame at ten thousand entries, with    │
│                                                                                                                      │
│ Enter to resume · Ctrl+a for all directories · Esc to close                                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭─ fake 8 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                  Fake Large with a 1M context window · medium effort
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake    fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake 2  fake · Fake Large with a 1M context window · medium  ◦ idle 3m
    fake 3  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    fake 4  fake · Fake Large with a 1M context window · medium  ◦ idle 2m
    … +4 more
```

For the framework: `ensureVisible(index, tall: TallItem.showEnd)` is
this placement, and "a tall highlighted row is read a line a press before
the highlight moves on" is the picker's own key logic (`lineKey`), which
calls `lineUp`/`lineDown` on the controller.

#### 3.4.3 The background log box at rooms of 0, 1 and 2 rows

Drawn from the code: `WorkDetail` in `BackgroundView.tsx`,
`requestView`, `requestCount`, `countRoom`, `requestRule` in
`permission.ts`, `workHead` in `background/view.ts`, and
docs/design/CHD-487.md ("A short room"). Only the frame is drawn: these
rooms come from a short window (the frame's room is half the window less
its chrome, six lines at 80x24), so at 24 and 40 rows the window itself
never gives them; the frames are drawn at 120 and 80 columns with the
detail's room forced, as a shorter window would. The log has 48 lines and
follows its end unless said otherwise. Styles: `Background` bold in
`permission`, ` · 1 of 2` `dim`; the name bold; the state `running …`
in the running colour, ` · 6 tool uses` `dim`, `main` in its owner's
colour; rules and counts `dim`; the hint `dim`; the border
`permission`.

**Room 0:** no row for the work. The state line takes one line, cut to
leave the count room; the count (`requestCount`, never `0`: at the end
it is `↑ N lines above`) is right-aligned at its end. `pageup` and
`pagedown` still page it as a room of one row would, and the count
changes.

120 columns, drawn from the code:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Background · 1 of 2                                                                                                  │
│                                                                                                                      │
│ Read the renderer and explain how frames are diffed                                                                  │
│ running 2m 14s · 6 tool uses · main                                                                 ↑ 47 lines above │
│                                                                                                                      │
│ Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

80 columns, drawn from the code:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Background · 1 of 2                                                          │
│                                                                              │
│ Read the renderer and explain how frames are diffed                          │
│ running 2m 14s · 6 tool uses · main                         ↑ 47 lines above │
│                                                                              │
│ Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back  │
╰──────────────────────────────────────────────────────────────────────────────╯
```

**Room 1:** one row of work, laid out narrower by `countRoom(48) + 1`
cells (the widest count the log can say, `↑ 99 above · ↓ 99 below`, so
the row does not jump as the count changes), the count right-aligned beside
it; no rule rows.

120 columns, drawn from the code:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Background · 1 of 2                                                                                                  │
│                                                                                                                      │
│ Read the renderer and explain how frames are diffed                                                                  │
│ running 2m 14s · 6 tool uses · main                                                                                  │
│ ⏺ Done: read 3 files.                                                                               ↑ 47 lines above │
│                                                                                                                      │
│ Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

80 columns, drawn from the code:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Background · 1 of 2                                                          │
│                                                                              │
│ Read the renderer and explain how frames are diffed                          │
│ running 2m 14s · 6 tool uses · main                                          │
│ ⏺ Done: read 3 files.                                       ↑ 47 lines above │
│                                                                              │
│ Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back  │
╰──────────────────────────────────────────────────────────────────────────────╯
```

**Room 2:** one row of work and one rule: `↓` while lines are below,
else `↑` (`requestView`, `room <= 2`). Following, it is at the end, so
the `↑` rule over the last line; after `home`, the first line over the
`↓` rule.

120 columns, following, drawn from the code:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Background · 1 of 2                                                                                                  │
│                                                                                                                      │
│ Read the renderer and explain how frames are diffed                                                                  │
│ running 2m 14s · 6 tool uses · main                                                                                  │
│ ── ↑ 47 lines above · pgup to scroll ─────────────────────────────────────────────────────────────────────────────── │
│ ⏺ Only the changed runs of each row are written, inside synchronized output.                                         │
│                                                                                                                      │
│ Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

120 columns, at the top after `home`, drawn from the code:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Background · 1 of 2                                                                                                  │
│                                                                                                                      │
│ Read the renderer and explain how frames are diffed                                                                  │
│ running 2m 14s · 6 tool uses · main                                                                                  │
│ › Read the renderer and explain how frames are diffed against the last one                                           │
│ ── ↓ 47 lines below · pgdn to scroll ─────────────────────────────────────────────────────────────────────────────── │
│                                                                                                                      │
│ Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

80 columns, following, drawn from the code:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Background · 1 of 2                                                          │
│                                                                              │
│ Read the renderer and explain how frames are diffed                          │
│ running 2m 14s · 6 tool uses · main                                          │
│ ── ↑ 47 lines above · pgup to scroll ─────────────────────────────────────── │
│ ⏺ Only the changed runs of each row are written, inside synchronized output. │
│                                                                              │
│ Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back  │
╰──────────────────────────────────────────────────────────────────────────────╯
```

80 columns, at the top after `home`, drawn from the code:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Background · 1 of 2                                                          │
│                                                                              │
│ Read the renderer and explain how frames are diffed                          │
│ running 2m 14s · 6 tool uses · main                                          │
│ › Read the renderer and explain how frames are diffed against the last one   │
│ ── ↓ 47 lines below · pgdn to scroll ─────────────────────────────────────── │
│                                                                              │
│ Enter to go to its call · ↑ ↓ for the others · x to stop · Esc ← to go back  │
╰──────────────────────────────────────────────────────────────────────────────╯
```

#### 3.4.4 An empty picker

Captured from the original: `/team` with no team saved. The list is not
drawn and its keys go (`listed` is 0); the picker says why in its own
words, and the hint keeps only the close key. For the framework this is a
`ListView` with `itemCount: 0`, or no list at all: it draws nothing and
every step is a no-op. Styles: `Teams` bold in `permission`; the
description `dim`; the empty text plain; the hint `dim`; the border
`permission`.

80x24, captured from the original:

```text
 ▀▄     chord v0.71.0
 ▀▀▀▄   fake · Fake Large with a 1M context window
 ▄▀▀▀   <qa directory>   
 ▀▀     ? for shortcuts · /help

 › /resume
   ⎿  No earlier fake session to resume, here or in any other directory.

 › /team

╭──────────────────────────────────────────────────────────────────────────────╮
│ Teams                                                                        │
│ For this project in .chord/teams, for every project in ~/.config/chord/      │
│ teams.                                                                       │
│                                                                              │
│ No teams yet. /team new and a few words about the work makes one.            │
│                                                                              │
│ Esc to close                                                                 │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts          Fake Large with a 1M context window · medium effort
```

120x40, captured from the original:

```text
 ▀▄     chord v0.71.0
 ▀▀▀▄   fake · Fake Large with a 1M context window
 ▄▀▀▀   <qa directory>   
 ▀▀     ? for shortcuts · /help

 › /resume
   ⎿  No earlier fake session to resume, here or in any other directory.

 › /team


















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Teams                                                                                                                │
│ Saved for this project in .chord/teams, and for every project in ~/.config/chord/teams.                              │
│                                                                                                                      │
│ No teams yet. /team new and a few words about the work makes one.                                                    │
│                                                                                                                      │
│ Esc to close                                                                                                         │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                  Fake Large with a 1M context window · medium effort
```

## 4. The keys

### 4.1 The actions and their defaults

| Step | Framework default (`ScrollKeys()`) | Description | chord's keys (`bindings.ts`, context `Scroll`) |
|---|---|---|---|
| pageUp | `pageup` | Scroll up a page | `pageup`, `shift+pageup` |
| pageDown | `pagedown` | Scroll down a page | `pagedown`, `shift+pagedown` |
| lineUp | none | Scroll up a line | `shift+up` |
| lineDown | none | Scroll down a line | `shift+down` |
| top | `home` | Scroll to the top | `home`, `shift+home` |
| bottom | `end` | Scroll to the bottom | `end`, `shift+end` |

Line keys have no framework default (owner: "line keys are the app's to
choose"). Plain `up`/`down` are never a scroll default: they belong to the
prompt (history) and to pickers (highlight).

### 4.2 How keys reach the list

Through the focus path, with what exists today: `FocusManager.dispatchKey`
walks from the focused node up, and at each node runs its `onKey` before
its bindings. So:

- **The transcript.** `ScrollActions` sits above the prompt (2.1). The
  prompt is focused; a key it does not handle walks up to the scroll
  bindings. Nothing about the list needs focus.
- **A picker or a dialog in front.** It takes focus (`Focus(autofocus:)`)
  under the window's scope; its own `Actions` (up/down/j/k; a request box's
  pageup/pagedown/home/end) are nearer on the path and shadow the window's
  `ScrollActions` for the same keys. This is exactly the original's routing:
  while a permission request taller than its box is shown, pgup scrolls the
  request, not the transcript (`keys.ts`, "request_page_up").
- Two scopes binding one key is allowed (inner shadows outer);
  `checkBindings` only forbids it within one scope, so the port keeps
  `ScrollActions` in its own `Actions`, not merged with the window's.

**A conflict to resolve, for the lead (and the prompt task):** the
framework's `TextInput` handles `home` and `end` in its `onKey` (cursor to
line start/end) and returns true, so with the prompt focused they never
reach `scroll:top` / `scroll:bottom`. In the original the prompt does not
take them; they always scroll. Options: (a) the port's prompt is built
without home/end (its own keymap, ctrl+a/ctrl+e only), (b) `TextInput`
gets a way to leave named keys unhandled. Either belongs to the prompt
task; CTUI-1's tests should bind `home`/`end` above a focused widget that
does not take them. I recommend (b), since any app with a scrolled view
over an input hits it.

### 4.3 How the port and pickers override

The port declares chord's keymap once and passes it:

```dart
const chordScrollKeys = ScrollKeys(
  pageUp: ['pageup', 'shift+pageup'],   // Terminal.app passes pgup only with shift
  pageDown: ['pagedown', 'shift+pagedown'],
  lineUp: ['shift+up'],
  lineDown: ['shift+down'],
  top: ['home', 'shift+home'],
  bottom: ['end', 'shift+end'],
);
```

The rule's `end to jump to the bottom` names `chordScrollKeys.bottom.first`
(the original reads it from the keymap, `useHintKey('scroll:bottom')`, and
omits the clause when nothing is bound). When the rebinding file lands, the
same `ScrollKeys` is built from it.

A picker does not override the scroll keys; it binds its own highlight
keys (2.5) in a nearer scope. A log box binds the same page keys to its own
steps (2.6).

### 4.4 The shortcuts panel

`KeyHelp` lists `activeBindings` one per binding. With two keys per step,
the panel shows `pageup Scroll up a page  shift+pageup Scroll up a page`.
The original groups them (`pgup pgdn or wheel  to scroll`, `shift + ↑ ↓  to
scroll a line`, `home end  for the top and the bottom`). Grouping is the
shortcuts panel's task; CTUI-1 only needs every step bound with a
description. **Owner to confirm:** the original's panel says "or wheel";
the port has no wheel in CTUI-1 (non-goal), so the port's line would say
`pgup pgdn  to scroll` until the mouse task.

## 5. What is whose

| State | Owner |
|---|---|
| offset / anchor, following, news, contentRows, viewRows | `ScrollController` (plain Dart, runtime's reducer) |
| item heights, which items are built | `ListView`'s render object (framework) |
| the items, `itemKey`, when news happens (`markNews`) | the app |
| picker highlight, `… +N more` arithmetic | the picker (pure functions in its state) |
| log box rooms and steps (`requestView`, `requestStep`, `logStep`) | the port, pure, with the original's tests |
| rule wording (`indicator`, `requestRule`, `requestCount`) | the port, pure |

Tests the interface side expects (the tester reaches all of them): at
120x40 and 80x24, a `ListView.builder` of 10 000 one-line items following
the bottom shows the last rows; `pageup` shows the rule (in a test app that
draws one from the controller) and `end` removes it; appending while
scrolled back leaves the rows in sight unchanged; `markNews` while
following does nothing; `ensureVisible` moves the least; `shift+up` does
nothing under `ScrollKeys()` and scrolls a line under the port's keys; a
focused child that binds `pageup` shadows `ScrollActions`.

## 6. Where the port differs from the original (owner to confirm)

1. The panel's "or wheel" is dropped until the mouse task (4.4).
2. Two bindings per step until the panel can group them (4.4).
3. Home/end reaching the scroll through a focused prompt needs the
   prompt task's choice (4.2); without it the port would differ.

No other difference: the rule wording, the page of view − 2, the log box's
rooms and the picker's least move are the original's, carried as pure
logic or as the framework's follow rule.

# CTUI-1: scrolling and virtualised lists

The design the ship team builds. The record of how it was reached is in
`docs/design/evidence/CTUI-1/drafts/` (the brief, the framework, interface
and runtime drafts, and the critic's findings as resolved in the last
section here). The decisions are logged in `docs/decisions.md`.

## What it is for

A list that builds, lays out and paints only the items in sight, a
controller that says where the view is and moves it, and a rule that keeps
the view on the bottom while output streams. Three users in the port, and
nothing beyond them:

- **the transcript**: entries of any height, following the bottom, the
  `── ↓ 12 lines below · end to jump to the bottom ──` rule while scrolled
  back (`../chord/src/ui/transcript/scroll.ts`, `Transcript.tsx`);
- **pickers**: choices of one or more lines, a highlight kept in sight
  (`../chord/src/ui/pickers/picker.ts`);
- **background logs and the permission request box**: a box of N rows over
  rich content that follows its end, with `↑`/`↓` rules taking rows of the
  room (`../chord/src/ui/background/`, `../chord/src/ui/dialogs/permission.ts`).

Out: a scrollbar (dropped by the owner), the mouse wheel and drag, horizontal
scrolling, slivers in general, nested scrolling, animation, keep-alive of
items out of sight, insertion above the view (the port passes every entry,
see `docs/decisions.md`).

## The call sites

### The transcript

```dart
class _WindowState extends State<Window> {
  final scroll = ScrollController(follow: Follow.bottom);

  @override
  Widget build(BuildContext context) => Actions(
        bindings: scrollBindings(scroll, keys: chordScrollKeys),
        child: Column(children: [
          Expanded(
            child: Stack(children: [
              ListView.builder(
                controller: scroll,
                itemCount: session.entries.length,
                itemVersion: (i) => (session.entries[i], expanded),
                itemBuilder: (context, i) => EntryView(session.entries[i]),
              ),
              // chord's rule, painted over the list's last row; nothing while following
              Align(
                alignment: Alignment.bottomLeft,
                child: ListenableBuilder(
                  listenable: scroll,
                  builder: (context) => BelowRule(scroll, bottomKey: 'end'),
                ),
              ),
            ]),
          ),
          Prompt(controller: draft),   // holds focus; keys it does not take reach the bindings
          StatusLine(...),
        ]),
      );
}
```

`BelowRule`, its wording and its count are the port's
(`example/chord/lib/ui/transcript/scroll.dart`, `indicator()` and the
original's `rowsBelow`, with the original's three rule tests). The rule is
painted over the last row, not taken from the list, so the view's size never
depends on the scroll state: the original counts the covered row the same
way (`Scroll.view` is "the indicator's row included").

When `Positioned` lands (the overlays task) it may replace the `Align`.

### A picker

```dart
ListView.builder(
  controller: scroll,                      // ScrollController() : Follow.none
  itemCount: choices.length,
  itemBuilder: (context, i) => ChoiceRow(choices[i], highlighted: i == highlighted),
)
```

The picker owns its highlight and the original's rules for moving it
(`pickerKey`, `lineKey`, `lineTop`, `visibleRange`, ported as pure Dart with
the original's tests). After a key it computes the top row the original
would show and calls `scroll.jumpTo(top)`, reading item geometry from
`scroll.itemTop(i)` and `scroll.itemRows(i)`. A tall choice is scrolled a
row at a time while it stays highlighted, as `lineKey` does; the list does
nothing clever on its own. The picker widget itself is FEATURES' "Fold,
Table, Picker, Dialog" task.

### A log box

```dart
// top: null while following, as the original's FOLLOWING
final view = requestView(log.contentRows, room, top ?? log.contentRows);
Column(children: [
  if (view.above) Text(requestRule('↑', view.top, pageUpKey, width), style: Style.dim),
  SizedBox(
    height: view.shown,
    child: ListView.builder(controller: log, itemCount: blocks.length, ...),
  ),
  if (view.below) Text(requestRule('↓', below, pageDownKey, width), style: Style.dim),
])
```

`requestView`, `requestStep`, `requestRule`, `requestCount` and `logStep` are
the port's, pure, with the original's tests; the box's page keys call them
and then `log.jumpTo(view.top)`. The content is rich (the task text and
`AgentWork`'s blocks), so its rows come from the list's measurement:
`log.contentRows` is exact even when the box has 0 rows (see "Measuring"),
which is what the original gets by laying the scrollbox out invisibly for a
room of 0.

## The public API

```dart
/// Whether a list keeps its end in sight as it grows.
enum Follow { none, bottom }

/// Where a scrolling list is, and the steps that move it.
class ScrollController extends ChangeNotifier {
  ScrollController({this.follow = Follow.none, int initialOffset = 0});
  // initialOffset is for Follow.none; a Follow.bottom list starts at the bottom.

  final Follow follow;

  // What the list measured on its last layout; zero until attached.
  int get contentRows;    // every item's rows at the list's width, exact
  int get viewRows;       // the rows the list has
  int get offset;         // rows above the view
  int get rowsBelow;      // max(0, contentRows - offset - viewRows)
  bool get isFollowing;   // Follow.bottom only: the view shows the end and keeps it
  bool get hasNews;       // Follow.bottom only: markNews() since the view left the end
  int get firstVisible;   // item at the view's top row; -1 when empty
  int get lastVisible;    // item at the view's last row; -1 when empty
  int itemTop(int index); // row of the item's first row in the content
  int itemRows(int index);

  // The steps; each is one key.
  void pageUp();          // a page is max(1, viewRows - 2), the original's pageRows
  void pageDown();
  void lineUp();
  void lineDown();
  void toTop();
  void toBottom();        // Follow.bottom: follows again and clears news
  void jumpTo(int offset);  // clamped; a move off the end stops following

  void markNews();        // no-op while following or with Follow.none
}

/// A list that builds only the items it shows.
class ListView extends StatefulWidget {
  ListView.builder({
    Key? key,
    ScrollController? controller,  // one is made and owned when absent
    required int itemCount,
    required Widget Function(BuildContext context, int index) itemBuilder,
    Object? Function(int index)? itemVersion,
  });
}

/// The standard bindings for a controller's steps, with their descriptions.
List<Binding> scrollBindings(
  ScrollController controller, {
  ScrollKeys keys = const ScrollKeys(),
});

/// Which keys press which step; an empty list leaves a step unbound.
class ScrollKeys {
  const ScrollKeys({
    this.pageUp = const ['pageup'],
    this.pageDown = const ['pagedown'],
    this.lineUp = const [],         // the app's to choose
    this.lineDown = const [],
    this.top = const ['home'],
    this.bottom = const ['end'],
  });
}
```

`contentRows`, `viewRows` and `offset` are what a scrollbar would need; one
can be added later without changing the controller. All counts are plain
geometry, `offset + viewRows + rowsBelow == max(contentRows, viewRows)`;
the transcript's rule count (`max(1, content − top − (view − 1))`, null while
following) stays the port's.

`ListView` binds no keys and takes no focus: in the transcript the prompt
holds focus and the bindings sit above it on the focus path. An unbound line
step and plain up/down never scroll by default; up/down belong to the
prompt's history and to a picker's highlight.

## The keys

| Step | `ScrollKeys()` | Description | the port's `chordScrollKeys` (`bindings.ts`, context `Scroll`) |
| --- | --- | --- | --- |
| pageUp | `pageup` | Scroll up a page | `pageup`, `shift+pageup` |
| pageDown | `pagedown` | Scroll down a page | `pagedown`, `shift+pagedown` |
| lineUp | none | Scroll up a line | `shift+up` |
| lineDown | none | Scroll down a line | `shift+down` |
| top | `home` | Scroll to the top | `home`, `shift+home` |
| bottom | `end` | Scroll to the bottom | `end`, `shift+end` |

One `Binding` per key, so a step with two keys is two bindings sharing one
description. `KeyHelp` lists both until the shortcuts panel groups them.

A nearer scope shadows the window's bindings: a picker binds up/down/j/k, a
permission request box taller than its room binds the same page keys to its
own steps, as the original routes them (`keys.ts`, `request_page_up`).

Known gap, handed to the text area task: `TextInput` takes `home` and `end`
itself, so with it focused they never reach `scroll:top`/`scroll:bottom`. In
the original the prompt leaves them to the transcript. CTUI-1's tests bind
them above a focused widget that does not take them.

## The follow rule

Plain Dart, `lib/src/foundation/scroll_state.dart`: an immutable
`ScrollState(content, view, top, following, news)` and pure reducers ported
from `reduceScroll`, case by case. `held` (mouse drag) is left out; the
three places it would enter are named in runtime's draft §3.4.

**Follow.bottom**, from `scroll_measured` and `scrolled()`:

| # | Case | Result | Original |
| --- | --- | --- | --- |
| M1 | content, view, top unchanged | the identical state; no notify | `same` |
| M2 | now fits | following, news cleared | `fits(next) && !next.held` |
| M3 | following | content/view only; the view shows the end | `if (next.following)` |
| M4 | scrolled back | `top = clamp(top, 0, bottomTop)` | `Math.min(action.top ?? scroll.top, bottomTop(next))` |
| S1 | bottom | following, news cleared | `atBottom` |
| S2 | fits | unchanged | "Nothing to scroll" |
| S3 | down while following | unchanged | `if (scroll.following) return scroll` |
| S4 | down reaching the end | following, news cleared | `to >= bottom ? atBottom(scroll)` |
| S5 | down short of the end | `top = to` | |
| S6 | up at the top | unchanged | `to === from && !scroll.following` |
| S7 | up otherwise | not following, `top = to`, news kept | |

`jumpTo` is S5/S7 with the given row (S4 when it reaches the end).
`markNews()` sets news only when not following (`withNews`); news is never
inferred from growth, because a relayout (ctrl+o, a resize) also changes
`content` and the original does not call that news. The port calls
`markNews()` where the original calls `withNews`, and `toBottom()` when a
prompt is sent.

**Follow.none** has no following: the state starts at `initialOffset`,
`following` and `news` stay false, M2 clamps `top` to 0, M3 never applies,
S1/S4 set `top = bottomTop`, and growth never moves the view. A picker of two
choices that grows to fifty stays where it was.

## Inside the trees

### Building during layout

`ListView` is a `StatefulWidget` (it owns a controller when none is given,
attaches it, and swaps it in `didUpdateWidget`) whose build returns a
`ListViewport`, a `RenderObjectWidget` with element `ListViewportElement`
and render object `RenderListViewport` (`lib/src/widgets/list_viewport.dart`,
`lib/src/rendering/list_viewport.dart`).

The element is the render object's child manager, as Flutter's
`SliverMultiBoxAdaptorElement` is:

```dart
abstract interface class ListChildManager {
  int get itemCount;
  RenderBox? itemAt(int index);        // builds the item if it is not built
  void release(int index);             // unmounts it
}
```

`itemAt` runs inside `performLayout` under a new
`BuildOwner.buildDuringLayout(fn)`, which mounts the item (the builder, or
`ErrorWidget` when it throws), syncs that item's own render subtree, and
leaves `structureChanged` as it was, so the next frame does not walk the
whole tree for what the viewport already synced. "Render children are synced
from the element tree" still holds: the full walk runs whenever the build
phase changed structure and reaches the viewport, which hands its render
object the built items by index.

`update` (the parent rebuilt the list) rebuilds the built items with the new
builder and drops those past `itemCount`, before layout, as any rebuild.

### Measuring

Every item's height is known exactly at the list's width; there are no
estimates. `ItemExtents` (`lib/src/rendering/list_viewport.dart`, plain Dart,
unit-tested) holds one height and one version per index and a running sum.
A height is dropped when:

- the width changes (all of them);
- `itemVersion(i)` differs from the version it was measured under
  (`identical`, then `==`), compared for every index on each rebuild of the
  list: about 20 µs at 10 000 items;
- the list was rebuilt and has no `itemVersion` (all of them: right, and
  cheap for pickers and short lists).

The version must change with anything that changes the item's height,
global inputs included: the port's transcript passes `(entry, expanded)`,
and adds the theme when themes can change wrapping.

At each layout, before filling the view, the viewport measures every item
whose height is unknown: builds it with `itemAt`, lays it out at the width
with unbounded height, records the height, and releases it unless it is in
sight. Measurement is synchronous and in the frame. Steady state is the
items that changed (the streaming reply) plus those in sight. After a width
change, or on the first frame of a resumed session, it is every item once.
A list whose box has 0 rows still measures, so `contentRows` is right for a
log box with no room; a width of 0 measures nothing and reports 0 rows.

The bet is that a frame measuring 10 000 entries is affordable, as the
original lays out its whole mounted window every frame. The ship task writes
a hand-run benchmark (`benchmark/list_view.dart`, 10 000 markdown-like
entries, a resize, and 1 000 appends a second, under `dart compile exe`),
and reports the frame times. If the resize frame is too slow, the fallback
(exact below the view, estimated above it, with the anchor protecting the
view) is a new decision, not a change made on the ship team's own call.

Items built for measurement are mounted and unmounted within one layout:
their `initState` and `dispose` run. Items in a `ListView` take no focus; a
`Focus` that asks for it inside an item asserts in debug. A timer started in
`initState` and cancelled in `dispose` is harmless.

### Filling, the anchor and retention

While following, the viewport fills from the last item upward; when item 0
is reached with rows to spare the content fits and is drawn from the top
(the original: "all of it, from the top, while it fits"). While scrolled
back, the anchor `(index, rowsInto)` is the item at the view's top row: on a
relayout (an item above changes height, ctrl+o, a resize) the viewport puts
the anchor's item back at the top, `rowsInto` clamped to its height − 1
(`topOf`), and passes that row to the reducer as M4's `top`. A step moves
`top` in the reducer, and the anchor is read again from it (`anchorAt`).
Heights being exact, the two never disagree. When `itemCount` drops below
the anchor, the anchor moves to the new last item and M4 clamps.

Only the items in sight stay mounted; the rest are released at the end of
layout. Bounds, each a test: live item states after a frame ≤ the items
intersecting the view; builder calls in a steady frame ≤ items in sight plus
items whose version changed. Zero-height items are allowed; those between
visible items are built with them.

### Clipping

Items are laid out whole and painted at their row, negative for one cut at
the top, through `canvas.clipped(...)`; `Canvas.put` already drops cells
outside the clip, wide graphemes included. To keep a 5 000-line reply cut to
40 rows cheap, `RenderParagraph.paint` paints only lines inside the clip and
`RenderFlex.paint` skips children outside it.

### Constraints

The viewport takes the size it is given. Unbounded height or unbounded width
is a programming error and throws from layout with a message naming the
fix (wrap it in `Expanded` or a `SizedBox`), as Flutter does; under the
tester the error reaches the test. Zero rows or zero columns are not errors.

## The frame

`AppHost.drawFrame`, in order:

1. `buildScope`; sync the render tree if the structure changed.
2. Layout. The viewport measures, fills, and sets the controller's state
   without notifying; the controller records that its state changed.
3. The controllers that changed notify. A listener that `setState`s marks
   its element dirty.
4. If anything is dirty: `buildScope`, sync, and layout once more. Changes
   from this second layout notify, but are drawn in the next frame (a frame
   is requested); there is no third pass.
5. Paint.

For the transcript rule and the log box, the second layout changes nothing
(the rule is an overlay; the box's size changes but no height does), so one
`tester.pump()` gives a settled screen. A listener that keeps moving the
scroll shows its latest state one frame late, never a loop.

Listeners are never called during layout. A controller mutation made while
the controller is notifying (a listener calling `lineUp()`) is applied after
the current round and notifies once more, never re-entrantly.
`ChangeNotifier` gets a disposed flag: attaching, mutating or notifying a
disposed controller throws, and one controller attached to two lists throws
on the second attach.

## Tests

Framework, at 120x40 and 80x24 where a screen is checked:

- `test/foundation/scroll_state_test.dart`: the original's
  `tests/ui/transcript/scroll_test.ts` under the same names and numbers,
  except the rule tests (the port's) and the held/drag tests (out); one test
  per M/S row above; Follow.none's transitions, including a fitting list that
  grows past its room and does not move.
- `test/rendering/item_extents_test.dart`: sum after record, replace,
  truncate; version change drops one height; width change drops all;
  `anchorAt`/`topOf` with the original's anchor data.
- `test/widgets/scroll_controller_test.dart`: notifies once per change and
  never for an identical state; `markNews` while following does nothing; a
  listener that steps again notifies twice, not recursively; dispose,
  second attach.
- `test/widgets/list_view_test.dart` through the tester: 10 000 one-row
  items following the bottom show the last rows and build only those in
  sight; paging through all of them never leaves more live states than rows;
  1 000 appends between two pumps keep the last line on the bottom row;
  `pageup`, 200 appends, one pump: the rows in sight unchanged, `rowsBelow`
  grown by 200, a test overlay drawn from the controller right on that pump;
  an item above the view changing height keeps the top item and its row;
  a resize while scrolled back keeps the top item; items of 1, 3 and 20 rows,
  one clipped at both edges; a builder that throws gives one error row and
  the rest draw; `itemCount` shrinking under the view and to 0; views of 0
  and 1 rows; unbounded height and width throw; `scrollBindings` with the
  defaults and with `shift+up`/`shift+down`; a nearer scope's `pageup`
  shadows it; sustained streaming into the last item re-measures only that
  item.

The port, in the tasks that put its screens on the list (not CTUI-1): the
rule tests, `requestView`/`requestStep`/`logStep`, `visibleRange`/`lineKey`,
the window's `TranscriptBack` cases, and the fake agent's `slow` and `long`
scenarios.

## What it draws

The framework draws only the items; every rule, gutter mark and count on
these screens is the port's, drawn from the controller. The full matrix
(transcript fits, following, scrolled back, with news, at the top, after a
relayout; pickers fitting, scrolled, tall, empty; log boxes following, in
the middle, at rooms 0, 1 and 2), at 120x40 and 80x24, captured from the
original or drawn from its code and labelled so, is in
`docs/design/evidence/CTUI-1/drafts/interface.md` §3 and §3.4. Two of them:

Scrolled back, with news, 80x24 (captured from the original, `long`):

```text
 ⏺ 1. Line 1 of 200, streamed one at a time.
   2. Line 2 of 200, streamed one at a time.
   …
   13. Line 13 of 200, streamed one at a time.
 ── ↓ new output · 111 lines below · end to jump to the bottom ────────────────

 ››› Working… (12s · esc to interrupt)
```

`↓ new output` in the accent, the rest dim. At 120x40 the same rule runs to
the 120th column; the rows in sight hold still while the count climbs.

Log box, room of 6, 160 lines, following, 80x24 (drawn from the code):

```text
│ ── ↑ 155 lines above · pgup to scroll ────────────────────────────────────── │
│ line 156                                                                     │
│ line 157                                                                     │
│ line 158                                                                     │
│ line 159                                                                     │
│ line 160                                                                     │
```

## Where the port differs from the original

1. `mount.ts` is not ported: home reaches the first entry in one press,
   where the original stops at the top of the mounted window and loads more
   (owner, via main).
2. No mouse: the drag hold (`scroll_held`) is out, and the shortcuts panel's
   "or wheel" has nothing behind it until a mouse task. The wording of that
   line is the shortcuts panel task's question for the owner.
3. Two `KeyHelp` lines per step until the shortcuts panel groups bindings.

## The critic's findings, as resolved

| # | Finding | Resolution |
| --- | --- | --- |
| C1 | estimates can resume following and lose the anchor | accepted: no estimates; every height is measured exactly, with a benchmark gate |
| C2 | `Follow.none` undefined | accepted: its transitions are defined above and tested |
| C3 | three insertion contracts | accepted, and made moot: no insertion above (owner chose not to port `mount.ts`) |
| C4 | logs are rich, not lines | accepted: logs sit on `ListView`; `contentRows` is measured even at 0 rows |
| C5 | picker skips a tall choice's lines; `TallItem` insufficient | accepted: the picker ports `lineKey`/`lineTop` and drives `jumpTo` with item geometry; `ensureVisible` and `TallItem` dropped |
| C6 | invalidation contracts disagree | accepted: one contract, `itemVersion`, on the call site; global inputs go into the version |
| C7 | retention and bounds contradict | accepted: only items in sight stay mounted; bounds stated and tested |
| C8 | background measuring has lifecycle effects | accepted in part: no background measurer; measurement is synchronous, items built for it run `initState`/`dispose`, and items take no focus (asserted) |
| C9 | settle protocol incomplete | accepted: one phase order, at most one extra pass, later changes drawn next frame |
| C10 | reentrant notification, no disposed flag | accepted: mutations during delivery queued; disposed flag added |
| C11 | `rowsBelow` with three meanings | accepted: plain geometry in the framework; the rule's count in the port |
| C12 | unbounded constraints unspecified | accepted: both axes throw with a message; zero size is not an error |
| C13 | the state matrix incomplete | sent back to interface once; the missing captures are in its draft §3.4 |
| C14 | `ScrollActions`/`ScrollKeys` a second keymap API | accepted in part: the widget layer is dropped and `ListView` binds nothing; `scrollBindings` and `ScrollKeys` stay as one function, because the task asks for the keys bound through `Actions` with descriptions and defaults |

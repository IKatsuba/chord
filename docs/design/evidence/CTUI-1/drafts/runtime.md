# CTUI-1 runtime draft: scrolling and virtualised lists

Runtime architect's answer to the brief: how the list behaves at run time,
what state it holds and where, what goes wrong and what happens then, and
how all of it is tested. Citations to the original are to `../chord`.

## 1. The shape at run time, in one paragraph

Output arrives (an ACP chunk, a log line, a key) and changes the app's
model; the model notifies, an element is marked dirty, and `runApp`
coalesces every such request into at most one frame per 16 ms
(`lib/src/widgets/run_app.dart`, `scheduleFrame`). A thousand chunks between
two frames cost a thousand model updates and one frame. In that frame the
viewport lays out: it reads cached heights, re-measures only the items whose
element rebuilt, builds the items in sight, and feeds the measured content
and view rows into a pure reducer that decides where the view is. Nothing
about scrolling runs between frames except the reducer, on key presses.

## 2. Module layout

Logic lives where a test reaches it; tests mirror the sources (AGENTS.md).

| Source | What it holds | Test |
| --- | --- | --- |
| `lib/src/foundation/scroll_state.dart` | `ScrollState` (immutable), `ScrollStep`, `reduceMeasured`, `reduceStep`, `withNews`, `pageRows`, `rowsBelow`, `rowsAbove`, `bottomTop`, `Anchor`, `anchorAt`, `topOf`. Plain Dart, no widget, no notifier. | `test/foundation/scroll_state_test.dart` |
| `lib/src/foundation/height_cache.dart` | Heights by index at one width; sum kept incrementally; estimate for holes; truncate, insert-above, invalidate-one, invalidate-all. Plain Dart. | `test/foundation/height_cache_test.dart` |
| `lib/src/widgets/scroll_controller.dart` | `ScrollController extends ChangeNotifier`: holds a `ScrollState` and the anchor, exposes the metrics, `step(ScrollStep)`, `toBottom()`, `jumpTo(top)`, `ensureVisible(index)`, `markNews()`, `insertedAbove(n)`; attach/detach. | `test/widgets/scroll_controller_test.dart` (no widget tree: drive `attach` with a fake viewport) |
| `lib/src/rendering/viewport.dart` | The render object that measures and asks for children (framework's draft owns its shape). | `test/rendering/viewport_test.dart` |
| `lib/src/widgets/list_view.dart` | `ListView.builder` and its element (framework's and interface's drafts own the shape). | `test/widgets/list_view_test.dart`, through the tester |

The existing tests are flat (`test/widgets_test.dart`); the new ones go in
the mirrored folders AGENTS.md asks for, without moving the old ones.

In the port, the original's file names hold (AGENTS.md, layout):

| Port source | From | What stays chord's |
| --- | --- | --- |
| `example/chord/lib/ui/transcript/scroll.dart` | `src/ui/transcript/scroll.ts` | `indicator()` (the rule's wording, the accent split, key-first cutting). The reducer itself is the framework's; this file re-exports nothing and only draws. |
| `example/chord/lib/ui/dialogs/permission.dart` | `src/ui/dialogs/permission.ts` | `requestView`, `requestStep`, `hiddenRows`, `requestCount`: the rules-take-a-row policy and its 0/1/2-row degradation. |
| `example/chord/lib/ui/background/view.dart` | `src/ui/background/view.ts` | `logStep`, `FOLLOWING` (as `null` or a sentinel, see 4.3). |
| `example/chord/lib/ui/pickers/picker.dart` | `src/ui/pickers/picker.ts` | `visibleRange`, `linedRows`, the highlight's clamp. |

`src/ui/transcript/mount.ts` (tail and backfill windows, entry weights) is
**not ported as such**: it exists because OpenTUI lays out every mounted
renderable (its own header says so). A virtualised list builds only what is
in sight, so every entry is an item and nothing needs a mount window. What
survives of it is the anchor across insertion above, for when the port pages
older entries in from the session record (section 5.4). This is a deviation
from the original's structure, not its behaviour; the lead should put it to
the owner as AGENTS.md asks (open question Q1).

## 3. The reducer, ported transition by transition

`ScrollState` carries the original's fields (`scroll.ts`, `interface
Scroll`): `content`, `view`, `following`, `top`, `news`. `held` is left out
(mouse is a non-goal); the seam is described in 3.4.

`view` is the whole area the list has, **including the row the port's rule
covers**. The rule is painted over the list's last row, not taken from it.
This is what the original does (`layout.ts` adds the indicator's row back to
`view`, and `rowsBelow` counts "the row the indicator covers") and it is a
runtime requirement here: if the rule took a row, its appearing would shrink
the view, which changes `rowsBelow`, which can remove the rule, which grows
the view, a loop between two layouts. With the rule as an overlay, `view`
does not depend on scroll state and one measurement settles.

### 3.1 `reduceMeasured(state, content, view, {int? top})`, from `case 'scroll_measured'`

| # | Condition | Result | Original |
| --- | --- | --- | --- |
| M1 | `content`, `view` unchanged and (`top` null or equal) | the same instance (identical, so no notify) | `const same = …; if (same) return scroll;` |
| M2 | new `content <= view` (fits) | `following = true, news = false` (identity kept if already so) | `if (fits(next) && !next.held) return following(next);` |
| M3 | already following | only `content`/`view` change; the view shows the bottom | `if (next.following) return next;` |
| M4 | scrolled back | `top = clamp(top ?? state.top, 0, bottomTop)` | `Math.min(action.top ?? scroll.top, bottomTop(next))`, `Math.max(0, top)` |

M4 is what keeps the view still while output streams below it: `top` does
not move, only `content` grows, so `rowsBelow` grows. `top` passed in is the
anchor's row after a relayout (3.3).

### 3.2 `reduceStep(state, step)`, from `scrolled()`

`from = following ? bottomTop : top`; `to = clamp(from + by, 0, bottomTop)`;
`by` is `-pageRows`, `+pageRows`, `-1`, `+1`, `-from` (`top`).

| # | Condition | Result | Original |
| --- | --- | --- | --- |
| S1 | step `bottom` | `following = true, news = false` | `if (step === 'bottom') return atBottom(scroll);` (non-held branch: `following(scroll)`) |
| S2 | fits | unchanged | `if (fits(scroll)) return scroll;` |
| S3 | `by > 0` and following | unchanged | `if (by > 0) { if (scroll.following) return scroll; …` |
| S4 | `by > 0`, reaches `bottomTop` | following again, news cleared | `to >= bottom ? atBottom(scroll)` |
| S5 | `by > 0`, short of the bottom | `top = to` | `: { ...scroll, top: to }` |
| S6 | `by <= 0`, `to == from`, not following | unchanged (at the top) | `if (to === from && !scroll.following) return scroll;` |
| S7 | `by <= 0` otherwise | `following = false, top = to` (news kept) | `return { ...scroll, following: false, top: to };` |

S7 with `following` and `to == from` would need `bottomTop == 0` while not
fitting, which cannot happen (not fitting means `bottomTop >= 1`); the
condition is kept as the original writes it.

Helpers, each from the original:

- `pageRows = max(1, view - 2)` (`pageRows`).
- `bottomTop = max(0, content - view)` (`bottomTop`).
- `rowsBelow`: `null` while following, else `max(1, content - top - (view - 1))`
  (`rowsBelow`, non-held branch).
- `withNews(state)`: sets `news` when not following and not already set
  (`src/ui/app/state.ts`, `withNews`). It is **not** inferred from growth:
  the original sets it when the transcript's entries change, not when ctrl+o
  or a resize changes `content`. The framework cannot tell those apart, so
  the app calls `controller.markNews()`; the port calls it where the original
  calls `withNews` (the two call sites in `reduceApp`).
- "Sending a prompt brings the view back to the bottom" is the port calling
  `controller.toBottom()` (S1).
- `jumped_to` (`src/ui/transcript/state.ts`: `following: false, news: false`
  plus a target entry) is `controller.ensureVisible(index, top: true)` in
  the port; the framework's part is that the anchor is set to that index and
  the next measurement resolves it (3.3). Search jumps are a later task; the
  seam is the anchor.

### 3.3 The anchor, from `anchorAt` / `topOf` and `layout.ts`'s `measure`

While scrolled back the controller keeps `Anchor(index, within)`. Each frame
the viewport:

1. re-measures dirty items and, on a width change, the items it lays out;
2. computes `topNow = topOf(anchor)` from the height cache's prefix rows
   (`placed.top + min(within, max(0, height - 1))`, as `topOf`);
3. calls `reduceMeasured(content, view, top: topNow)`;
4. sets `anchor = anchorAt(state.top)` again, so a key that moved `top` moves
   the anchor (the original distinguishes "the top it set" from "the
   person's own scroll" with `anchors.top/from` because React draws one
   frame late; here the reducer and the layout run in the same frame, so a
   key's step updates the anchor at once and that bookkeeping is not needed).

While following, no anchor is kept (`anchors.current.delete(front)`): the
view is pinned to the bottom.

Carried tests: `an anchor is the entry a row falls in, and how far in`,
over a `HeightCache` instead of a `Placed[]`.

### 3.4 The mouse seam

Not designed. What is left: `ScrollState` is a class whose constructor can
take one more field; M2 and S1 are the two places the original consults
`held` (`fits(next) && !next.held`, `atBottom`), and `rowsBelow` the third.
The controller's public steps go through one `_apply(ScrollState)` that a
`hold()`/`release()` pair would also use. No `held` field, no API.

## 4. The three users at run time

### 4.1 The transcript

`ListView.builder(controller, follow: Follow.bottom, itemCount, itemBuilder)`
with the port's rule in a stack over its last row, built from
`controller.state` (or the metrics getters). Keys: the port binds
`scroll:pageUp` and the rest (`../chord/src/ui/shortcuts/bindings.ts`,
context `Scroll`) to `controller.step(…)` through `Actions`.

### 4.2 Pickers

A picker's state (choices, highlight) is the port's; on each highlight move
it calls `controller.ensureVisible(highlight)`, which sets `top` so the item
is in view (no follow; `Follow.none`). `visibleRange` stays the port's pure
function for its tests; whether the picker even needs the virtualised list
or a sliced column is the interface's call (pickers rarely exceed a few
hundred choices).

### 4.3 Logs and the permission request box

Their rule is different from the transcript's, not a variant: the `↑`/`↓`
rules take rows *of the room*, page down starts after the last row shown,
and rooms of 0, 1 and 2 rows degrade (`requestView`, `requestStep`). That is
chord's policy and stays in the port as pure functions, ported with their
tests. Each log line is one row once wrapped to the room, so `total` is
known in plain Dart before layout, and the box can draw `lines[top, top +
shown)` directly; the virtualised list adds nothing a slice does not. The
original's `FOLLOWING = +Infinity` becomes `int? top` with `null` meaning
following (Dart has no infinite `int`); `logStep` returns `null` where it
returned `FOLLOWING`.

Recommendation: the framework's `ScrollState` covers the transcript's rule
only; logs and the request box use the port's functions over a slice. If the
lead wants them on `ListView` anyway, they drive it with `Follow.none` and
`jumpTo(top)`. Open question Q2.

## 5. Streaming and following

### 5.1 A thousand chunks between two frames

- Each chunk updates the model and marks one element dirty;
  `BuildOwner.scheduleBuildFor` calls `onNeedsFrame`, which `runApp`
  coalesces. No scroll code runs per chunk.
- At the frame, `buildScope` rebuilds the last item's element once.
- The viewport sees that item's element rebuilt and drops its cached height;
  only that item and the items in sight are laid out.
- `content` is the cache's running sum (maintained on each height change, so
  O(1) per changed item, not O(n) per frame).
- `reduceMeasured`: following, M3, the view shows the new bottom; scrolled
  back, M4, the view stays and `rowsBelow` grows. The port called
  `markNews()` when the entry list changed, so the rule says "new output".

The fake agent's `slow` scenario (`tests/fixtures/fake_agent/scenarios/text.ts`:
`Working` then 1000 `.` chunks) is exactly this case; `long` (a numbered
reply taller than any window, one line per 19 steps) is the scroll-back
under streaming case.

### 5.2 One frame, settled

The controller's state changes during layout (M1 to M4 run inside the
viewport's layout). Anything that draws from it, the port's rule above all,
was already built earlier in the same frame from the old state. Two ways
this can go:

- (a) the controller notifies after paint, the rule's element is marked
  dirty, and the next frame draws it: the rule lags a frame (16 ms in the
  app, but a stale screen after one `tester.pump()`).
- (b) **proposed:** `AppHost.drawFrame` settles: after paint, if building
  dirtied elements (notifications deferred from layout are flushed at that
  point), it builds, lays out and paints once more, into a fresh buffer, at
  most twice in total. The second pass is cheap: the viewport's measurement
  is unchanged (M1 returns the same instance, so nothing notifies again).
  A third dirtiness waits for the next frame, so a buggy listener cannot
  spin the frame loop; in debug it asserts.

(b) keeps "one `pump()` is one settled screen" for the tester and needs no
change to `runApp`. It relies on the overlay rule of section 3 (view
independent of scroll state). The framework draft owns where the flush
happens; runtime asks only for the bound of two passes. Notifications must
never run listeners *during* layout: a listener's `setState` during layout
would mark an element dirty in the middle of a tree walk.

### 5.3 Ordering

Between two frames, key presses and chunks interleave in arrival order on
one isolate. A key reduces against the last measured `content`/`view`, at
most one frame stale. Examples, each a test:

- `page_up` while following, then 200 rows arrive, then the frame: the view
  is at `bottomTop(old) - pageRows` and stays there (S7 then M4). It does not
  jump to the new bottom: the original's "new rows below do not move the
  view".
- 50 rows arrive, then `end`, then the frame: following (S1), the view shows
  the newest rows.
- `pageup` pressed 1000 times by key repeat between frames: 1000 reductions,
  stops at `top = 0` (S6), one frame.

### 5.4 Relayout and insertion above

- **ctrl+o** (an entry above the view unfolds): its element rebuilds, its
  height changes, the anchor's row is recomputed from the prefix sum, M4 with
  that `top`. The entry at the top of the view stays there. Original test:
  `TranscriptBack_test.tsx`, `ctrl+o while scrolled back keeps the entry on
  top in view`.
- **Resize to another width:** all cached heights are stale. The viewport
  measures the items in sight at the new width and the anchor's item first;
  items not measured at the new width count with an estimate (5.5). The
  anchor holds the entry; `within` is clamped to its new height. Original:
  `a resize while scrolled back keeps the entry on top in view`.
- **Resize to another height only:** heights stay; `view` changes; M2 if it
  now fits, else M3/M4.
- **Insertion above** (the port pages older entries in from the record):
  `controller.insertedAbove(n)` shifts the anchor's index and the height
  cache by `n` before the next layout; the new items are holes, estimated,
  then measured as they come into sight. Without the call, the list cannot
  know index 0 changed meaning; a keyed lookup (Flutter's
  `findChildIndexCallback`) is the alternative. Open question Q3 for the
  framework draft.
- **Several sessions in one window** (the original keeps an anchor per
  session, `anchors` keyed by `front`): one controller per session, owned by
  the port's session view state, so switching sessions swaps controllers
  rather than resetting one. Only the shown session's controller is attached.

### 5.5 Heights and the total

- **Cached by index, at one width.** A `List<int?>` of heights plus a
  running sum of the measured ones and a count of holes. A width change
  clears it (the alternative, a map per width, keeps memory for widths the
  window will rarely return to).
- **Holes are estimated** with the mean of the measured heights (1 when none
  is), so `content` is `measuredSum + holes * mean`. "N lines below" is exact
  whenever every item below the view has been measured at this width, which
  is always true in the steady state (items are measured as they stream in,
  at the bottom) and true again after a resize once the backlog is done.
- **The backlog after a resize** is measured over several frames, a bounded
  budget per frame (items or milliseconds; a number to be set from a
  benchmark, say 4 ms), nearest to the view first, requesting another frame
  while holes remain. A resize of a 10 000-entry transcript so never holds a
  frame for the whole transcript's layout. During the backlog the rule's
  count may move by a few rows as estimates become heights; the anchor keeps
  the screen still.
- **No isolate.** Measuring is laying out widgets, and elements and render
  objects cannot cross isolates. A parse (markdown, highlighting) that would
  hold a frame can go to an isolate in the task that builds it; not here.

Cost at 10 000 items and 1 000 chunks a second, per frame: one rebuild of
the last item, layout of the items in sight (bounded by view rows + 2 items),
O(1) sum update, the reducer, the diff of changed cells. Memory: 10 000
`int?` heights, about 80 KB on a 64-bit VM, and nothing else per item.

## 6. Failure modes

| # | Scenario | Expected outcome |
| --- | --- | --- |
| F1 | `itemBuilder` throws for index i | The viewport's build-on-demand path catches it as `ComponentElement.performRebuild` does and mounts `ErrorWidget` for that item. `RenderError` under an unbounded height lays out one row, so the item is one red row and the list goes on. The app does not exit. |
| F2 | An item's own `build` throws | Already caught by `ComponentElement`; same one-row error. |
| F3 | A render object throws in layout or paint | Not caught by the list: it reaches `runApp`'s `runZonedGuarded`, which restores the terminal and prints the error (current behaviour). The tester rethrows it to the test. |
| F4 | `itemCount` shrinks under the view | The cache is truncated, the sum adjusted. The anchor's index past the end makes `topOf` `null`; the viewport passes no `top`, and M4 clamps `top` to the new `bottomTop`. Shrunk to fit: M2, following. Shrunk to 0: `content = 0`, following, nothing built. |
| F5 | `itemCount` grows while following | M3; the last rows show. While scrolled back: M4, view still. |
| F6 | View of 0 rows | `pageRows = 1`; nothing is built or painted; the reducer still runs, so a later resize to a real size resumes from a consistent state. The port draws no rule (no row). Steps are harmless. |
| F7 | View of 1 row | The rule, when drawn, covers the only row; `rowsBelow` counts it (`max(1, …)`). A page is one row. |
| F8 | Width change mid-stream | Cache cleared; streaming item and items in sight measured first; anchor held (5.4). |
| F9 | Width of 0 | Items are laid out at width 0; text widgets must lay out to height 0 or 1 without looping (a wrap at width 0 must not produce infinite lines). A test pins it. |
| F10 | One controller attached to two lists | Throws `StateError` at the second attach, naming the controller, like two bindings claiming one key throw at mount. Its state is one list's `content` and `view`; sharing it would make both wrong silently. |
| F11 | A controller swapped for another on rebuild | The list detaches the old one in `didUpdateWidget` and attaches the new one; the new one's state is laid out next frame from its own anchor. |
| F12 | The list is disposed | It detaches from the controller (removing its listener); the controller keeps its state and may be attached again later (a session view shown again). Disposing the controller is its owner's job; a disposed controller attached throws. |
| F13 | A listener calls `step()` while being notified | Notifications go to a copy of the listener list (`ChangeNotifier.notifyListeners` already copies) and are never sent during layout (5.2), so the step reduces and schedules a frame, nothing reentrant. |
| F14 | An item whose height does not converge (a widget whose layout depends on the scroll state) | Bounded by the two passes of 5.2; asserts in debug. |
| F15 | A key with nothing to scroll (fits) | S2: no state change, no notify, no frame. |

Item elements off screen are unmounted (section 7), so item-local `State`
(an unfold toggled inside an entry widget) is lost when it scrolls away.
The port keeps such state in its model, as the original does (`expanded` in
`ViewState`, folds in the transcript state). The framework documents it on
`ListView`.

## 7. Memory over a long session

- **Elements and render objects**: only for items in the built window, the
  items in sight plus at most one partly visible at each end. They are
  unmounted when they leave it. Bounded by view rows, not by session length.
  (A cache extent of off-screen items is not needed: building one item is
  cheap next to the frame budget, and keeping none makes the bound exact and
  testable.)
- **Heights**: one `int?` per item at the current width (5.5). This grows
  with the item count, as the model does; it is a few percent of what the
  entries themselves hold.
- **Controller**: a `ScrollState` and an anchor, constant.
- **Listeners**: the list adds one to the controller at attach and removes
  it at detach; tests count `hasListeners` after dispose.
- **What stays flat**: frame cost and element count do not grow with the
  session. What grows linearly is the model and the height list, both
  owned by the app's own retention policy (the port's record), not the list.
- The original's long-run check (`soak` scenario, for `scripts/memory.ts`) is
  the port's to rerun once the transcript sits on the list; it is not a
  framework test.

## 8. The test plan

### 8.1 `test/foundation/scroll_state_test.dart`, carried over

From `../chord/tests/ui/transcript/scroll_test.ts`, with the same fixtures
(`tall` = content 90 in view 33, the design's 120x40 mock) and the same
numbers, under the same names:

| Original test | Carried | Notes |
| --- | --- | --- |
| a page is the view less two rows | yes | |
| the view follows the bottom until a key moves it up | yes | |
| new rows below do not move the view, and count as below | yes | |
| the way back down follows again once it reaches the bottom | yes | |
| up at the top, or with nothing to scroll, does nothing | yes | identity checks via `identical` |
| a view that comes to fit everything follows again | yes | |
| a relayout keeps the row it is given, within the transcript | yes | |
| the bottom clears the news | yes | |
| an anchor is the entry a row falls in, and how far in | yes | over `HeightCache` |
| the rule says how much is below, and the key back | port | `indicator()` is chord's: `example/chord/test/ui/transcript/scroll_test.dart` |
| the rule names new output in words and in the accent | port | same |
| a narrow rule drops the key before the count | port | same |
| a drag holds … (CHD-172), three tests | no | mouse, out of scope |
| a press at the bottom draws no rule … (CHD-397) | no | held |
| a view scrolled back to the bottom with no press keeps its rule (CHD-397) | yes | the non-held half: `rowsBelow` is 1 at `top == bottomTop` while not following |
| tester: held view resizing; held rule boundaries | no | held |

New, one per transition not covered above: M1 returns the identical
instance; M2 clears news; S3 down while following is identical; S6;
`withNews` while following does nothing; `withNews` twice is identical.

### 8.2 `test/foundation/height_cache_test.dart`

Sum after set/replace/truncate; holes estimated with the mean; width change
clears; `insertedAbove(n)` shifts indices and keeps the sum; prefix row of
index i; `anchorAt`/`topOf` over the cache (the original's anchor test data).

### 8.3 `test/widgets/scroll_controller_test.dart`

Steps notify once per change and not at all when the reducer returns the
same instance (F15); `markNews` while following does nothing; attach to a
second viewport throws (F10); detach removes the listener (F12);
`ensureVisible` above, below and inside the view.

### 8.4 `test/widgets/list_view_test.dart`, through the tester

Each at 120x40 and at 80x24 where the screen is checked (AGENTS.md).

- **Virtualisation**: 10 000 one-row items; a counting `itemBuilder` records
  the indices built per `pump()`: at most view rows + 2, and only around the
  view. Scroll to the top with `home`: the same bound.
- **Unmounting**: items are a `StatefulWidget` counting `initState`/
  `dispose`; after paging through all 10 000, live states never exceed view
  rows + 2.
- **Following under streaming**: a model whose last item grows by 1 000
  appends between two pumps; one `pump()`; the last line is on the bottom row
  and `controller.state.following`.
- **Scrolled back under streaming**: `press('pageup')`, append 200 rows,
  `pump()`: the screen's rows are unchanged, `rowsBelow` grew by 200; after
  `markNews` the port-style rule (a test overlay built from the controller)
  shows on the same `pump()` (5.2 settled frame).
- **Ordering** (5.3): the three examples, each as a test.
- **Relayout**: an item above the view changes height between pumps; the
  item at the top row is the same item, the same rows into it. Resize
  120x40 to 80x24 while scrolled back: the top item stays (the original's
  `TranscriptBack_test.tsx` cases, minus chord's entries).
- **Variable heights**: items of 1, 3 and 20 rows; a 20-row item partly
  above and partly below the view is clipped at both edges.
- **Failures**: F1 (a throwing builder shows one error row, the rows after
  it still draw), F4 (shrink to 0, shrink under the view), F6/F7 (views of 0
  and 1 rows via a sized box), F9.
- **Keys**: the test binds `pageup`, `pagedown`, `home`, `end` to the
  controller's steps through `Actions` and presses them; a second test binds
  `shift+up`/`shift+down` to show the keys are the app's.
- **Resize backlog** (5.5): 10 000 items of mixed height, resize; the first
  `pump()` builds no more than the bound; repeated pumps fill the holes, and
  once none remain the `rowsBelow` count equals the exact sum.

No test depends on time: the tester's `pump()` draws one settled frame
(5.2), and the backlog is driven by repeated `pump()` calls, not by timers.
The tester needs no new API for this; `pump()` after appending, `press()`,
`resize()`, `screen`. Optional, if the framework draft wants it:
`tester.pumpUntilSettled()` that pumps while a frame is requested (bounded),
for the resize backlog.

### 8.5 The port

- Pure modules directly: `scroll_test.dart` (the three rule tests above),
  `permission_test.dart` (`requestView`, `requestStep`, `hiddenRows` from
  `../chord/tests/ui/dialogs/`), `background/view_test.dart` (`logStep`),
  `pickers/picker_test.dart` (`visibleRange`, `linedRows`).
- The window through the tester, with the transcript on the list:
  `TranscriptBack` cases (ctrl+o and resize keep the entry on top).
- The session layer through the original's fake agent (docs/decisions.md):
  `slow` (1000 chunks, following), `long` (scroll back while it streams; the
  rule counts and says new output). No new scenario is needed for CTUI-1.
  These belong to the task that puts the port's transcript on the list, not
  to CTUI-1 itself, which builds the framework pieces.
- Never a real model, agent or terminal.

### 8.6 Not tests

A benchmark (`benchmark/list_view.dart`, run by hand, not in `dart test`):
10 000 markdown-ish items, 1 000 appends a second for ten seconds, frame
time percentiles, and the resize backlog's per-frame time. It sets the
budget of 5.5. Open question Q4.

## 9. What `dart compile exe` asks

Nothing special: no mirrors, no code loaded at run time; the builder is a
closure. The settled frame and the backlog use the existing `onNeedsFrame`
path, so the `Terminal` interface does not change. A terminal that lacks a
protocol is irrelevant here (scrolling is drawn, not asked of the terminal;
no scroll regions, no `DECSTBM`, as the alternate screen and the diffing
renderer make them unnecessary).

## 10. Open questions

- **Q1 (owner, via the lead).** `mount.ts`'s tail and backfill windows are
  not ported: the virtualised list makes them unnecessary. The behaviour
  (entry on top kept, new output not moving the view) is kept. Confirm the
  deviation in structure.
- **Q2 (lead).** Logs and the permission request box on the port's pure
  functions over a slice (recommended), or on `ListView` with `Follow.none`.
- **Q3 (framework).** Insertion above: an explicit
  `controller.insertedAbove(n)` (recommended, simple, testable) or a keyed
  lookup of the anchor's item.
- **Q4 (lead).** A hand-run benchmark under `benchmark/` to set the resize
  budget, or a fixed budget written into the design.
- **Q5 (framework).** The settled frame (5.2): flushing deferred controller
  notifications after paint and a second pass in `AppHost.drawFrame`, at
  most two. If the framework prefers the rule built inside the viewport's
  layout (a `footerBuilder` given the fresh metrics), the second pass is not
  needed for the rule, but other readers of the controller would still lag.
- **Q6 (interface).** `news` set only by `markNews()`, never inferred from
  growth: confirm the call site for the port is enough.

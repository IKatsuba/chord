# CTUI-1 framework draft: the viewport inside the trees

Owner: framework. Answers the brief's framework questions 1–5: how a list
builds only what is in sight during layout, how items of any height are
measured and cached, the anchor, clipping, and the cost at 10 000 items.
The public call site (`ListView.builder`, `ScrollController`, `Follow`,
keys) is interface's; the follow rule and its reducer are runtime's. This
draft names the seam each of those plugs into.

## How Flutter does it, and what a grid of cells keeps

Flutter's `ListView.builder` is a `Scrollable` around a `Viewport` holding
one `SliverList`. `RenderSliverList.performLayout` walks from the first
child it already has, asks `RenderSliverBoxChildManager.createChild(index)`
for the next one, and the manager, `SliverMultiBoxAdaptorElement`, runs
the delegate's builder inside `owner.buildScope(this, ...)` while the render
object is in the middle of layout (`invokeLayoutCallback`). Children that
leave the cache extent are released with `collectGarbage`. Sizes of
children never laid out are estimated from the average of those that were
(`estimateMaxScrollExtent`); when the estimate was wrong above the view, the
sliver returns a `scrollOffsetCorrection` and the viewport lays out again.
Live children are rebuilt when the element rebuilds; a moved child is found
again with `findChildIndexCallback`.

What we keep:

- **Building children during layout**, through a child manager that is the
  element: the only way to build exactly what the measured heights put in
  sight, in the frame they are measured.
- **Children held by index** in the element, released outside a small
  window.
- **`findChildIndexCallback`**, for the one case where an item moves
  (insertion above).
- **`itemExtent`-free variable heights**, measured by laying the child out.

What we leave:

- Slivers, `SliverGeometry`, `Viewport` with several slivers, `Scrollable`,
  `ScrollPhysics`, overscroll, `ScrollPosition.pixels` as a double,
  scroll-offset correction passes. One list in one box needs none of it
  (the brief's non-goals).
- Layers, repaint boundaries, relayout boundaries, dirty marking: deferred
  by decisions.md. Nothing here depends on them.
- Estimates as the final word. Flutter can live with a scrollbar that is a
  little off; chord's rule says "12 lines below", so heights are measured
  and cached, and the estimate only fills the gap until they are.

What the grid adds: offsets are whole rows, so the position is an item and
a row into it, never a fraction, and an item is either laid out at the
view's width or not at all.

## The classes

New files:

- `lib/src/rendering/list_viewport.dart`: `RenderListViewport`,
  `ListChildManager`, `ItemExtents`, `ListAnchor`, `ScrollMetrics`.
- `lib/src/widgets/list_viewport.dart`: `ListViewport` (the
  `RenderObjectWidget`) and `ListViewportElement`.

`ListView` and `ListView.builder` are interface's: a `StatelessWidget` that
binds the actions and returns a `ListViewport`. Whatever interface names
the controller, it hands the viewport the `ScrollPosition` below.

### `ListChildManager`: what the render object asks the element

```dart
/// What a [RenderListViewport] asks of the element that owns its items.
abstract interface class ListChildManager {
  /// How many items the list has now.
  int get itemCount;

  /// The render box of item [index], built if it was not; null for an
  /// index out of range. Only called from inside performLayout.
  RenderBox? itemAt(int index);

  /// Unmounts every built item outside [first]..[last], both included.
  void releaseOutside(int first, int last);

  /// Whether item [index] is built now (an element exists for it).
  bool isBuilt(int index);
}
```

### `ListViewport` and `ListViewportElement`

```dart
/// A box that shows part of a list of [itemCount] items, building only
/// the items it lays out.
class ListViewport extends RenderObjectWidget {
  const ListViewport({
    super.key,
    required this.position,
    required this.itemCount,
    required this.itemBuilder,
    this.itemVersion,
    this.findChildIndexCallback,
  });

  final ScrollPosition position;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// A cheap value that changes when item [index]'s height may have
  /// changed: the entry object itself, when entries are immutable. Without
  /// it every cached height is dropped whenever the list is rebuilt.
  final Object? Function(int index)? itemVersion;

  /// Where the item whose widget had [key] is now, after items were
  /// inserted or removed before it; Flutter's name and meaning.
  final int? Function(Key key)? findChildIndexCallback;

  @override
  Element createElement() => ListViewportElement(this);
  @override
  RenderListViewport createRenderObject(BuildContext context);
  @override
  void updateRenderObject(BuildContext context, RenderListViewport ro);
}

class ListViewportElement extends RenderObjectElement
    implements ListChildManager {
  final SplayTreeMap<int, Element> _items; // index -> item's element
  ...
}
```

`ListViewportElement` does five things.

1. **`mount`** builds no items: it has no size yet.
2. **`update(newWidget)`** (the parent rebuilt the list: a chunk arrived,
   an entry was added) first remaps indices if items moved (below, "the
   anchor"), then calls `renderObject.extents.reconcile(...)` with the new
   `itemCount` and `itemVersion` (below, "measuring"), then rebuilds every
   live item with `updateChild(_items[i], itemBuilder(this, i))`, dropping
   those with `i >= itemCount`. This is Flutter's
   `SliverMultiBoxAdaptorElement.performRebuild`. It runs in `buildScope`,
   before layout, as every other rebuild does.
3. **`itemAt(index)`**, from inside layout, builds the item if it has no
   element:
   ```dart
   owner.buildDuringLayout(() {
     final w = _safeBuild(index); // itemBuilder, or ErrorWidget if it threw
     final e = updateChild(null, w)!;
     _items[index] = e;
     syncRenderTree(e);           // the item's own subtree, nothing else
   });
   return RenderObjectElement.firstRenderObject(_items[index]);
   ```
4. **`releaseOutside(first, last)`** unmounts the other items, also under
   `buildDuringLayout`.
5. **`visitChildren`** visits `_items.values` in index order, so
   `syncRenderTree`, `unmountTree`, focus and `findRenderObject` see the
   built items as any other children; **`syncRenderChildren`** hands the
   render object `{index: firstRenderObject(e)}`.

### `BuildOwner.buildDuringLayout`: the one change to the element tree

```dart
/// Runs [fn], which mounts or unmounts elements from inside layout, and
/// keeps [structureChanged] as it was: the caller syncs what it touched.
void buildDuringLayout(void Function() fn);
```

Today `Element.mount` and `unmount` set `owner.structureChanged = true`, and
`AppHost.drawFrame` clears it before layout. Items mounted during layout
would set it again and make the next frame walk the whole tree for nothing,
since `itemAt` already synced the new item's subtree and the viewport keeps
its own child map. `buildDuringLayout` saves the flag, runs `fn`, and puts
it back. It also sets `_inLayout`, so that an element marked dirty during
it (an item's `initState` calling `setState`, a focus change) is queued for
the next frame as now (`scheduleBuildFor` already requests one), and an
assert catches a mount under `_inLayout` that is not inside a viewport's
callback.

"Render children are synced from the element tree" (decisions.md) still
holds: the full walk still runs whenever the build phase changed structure,
and it reaches the viewport's `syncRenderChildren`. The viewport only adds a
second, local sync for what it builds itself after that walk.

### `RenderListViewport`

```dart
/// Lays out and paints only the items of a list that fall in its rows.
class RenderListViewport extends RenderBox {
  ListChildManager manager;
  ScrollPosition position;
  final ItemExtents extents;

  /// The built items' boxes, by index; set by syncRenderChildren.
  Map<int, RenderBox> items;

  /// The items laid out this frame and their rows, top to bottom.
  List<(int index, int y)> _placed;

  @override
  void visitChildren(void Function(RenderBox child) visitor); // _placed only
}
```

## Layout, in words

The viewport takes the size it is given: `constraints.biggest` when both
axes are bounded. Unbounded height is an error, as in Flutter ("Vertical
viewport was given unbounded height"), drawn with `RenderError`. Items are
laid out with `BoxConstraints(minWidth: w, maxWidth: w)` and unbounded
height, at their natural height; `extents.record(index, height)` after each.

1. **Width.** If `size.width != extents.width`, `extents.resetForWidth(w)`
   drops every height (tokens are kept). The anchor stays as it is.
2. **Resolve the intent.** `position` holds the anchor (below) and at most
   one pending intent from the controller: `toEnd`, `toStart`,
   `byRows(n)`, `reveal(index)`, `toRow(r)`. Each turns into an anchor by
   walking items from the current one, calling `manager.itemAt` and laying
   out each item it passes, so a page of 38 rows moves exactly 38 rows
   whatever was estimated.
3. **Fill.**
   - *Following the end:* from the last item upward, laying out until the
     rows are filled; if item 0 is reached with rows to spare, the content
     fits and is laid out again from the top (the original: "all of it,
     from the top, while it fits").
   - *Anchored:* the anchor's item at `y = -rowsInto`, then downward until
     `y >= height`. If the last item ends above the bottom, the list fills
     upward from the anchor instead, so the view never shows empty rows
     below the end while content above exists (the reducer's
     `min(top, bottomTop)`).
   - *Reveal(i):* if `i` is above the first fully shown item, anchor
     `(i, 0)`; if below the last, fill upward from `i`'s bottom on the last
     row; else nothing moves (picker's `visibleRange`, the highlight kept in
     sight with the least movement).
4. **Anchor again.** The new anchor is the item at row 0 and the rows of it
   above the view.
5. **Release** items outside `[first - keep, last + keep]` with
   `manager.releaseOutside`, where `keep` is enough items to cover one view
   of rows on either side (by cached height). They stay built so a line
   step back and forth does not dispose and rebuild their state (a spinner
   in a tool call), and are not laid out while out of sight.
6. **Measure in the background**, inside the time left of a per-frame
   budget (below).
7. **Report.** `position.didLayout(ScrollMetrics(...))`.

```dart
/// What one layout of a list measured, for the controller and the
/// port's rules.
class ScrollMetrics {
  final int viewRows;       // the rows the viewport has
  final int contentRows;    // every item's rows, estimates included
  final int rowsAbove;      // content above row 0 of the view
  final int rowsBelow;      // content below the view's last row
  final int firstVisible, lastVisible; // item indices, -1 when empty
  final bool exact;         // no estimate in contentRows
  final ListAnchor anchor;
}
```

`rowsAbove + viewRows + rowsBelow == max(contentRows, viewRows)` always
holds; when `exact` is false only `rowsAbove` and `rowsBelow` can be off,
and the view itself never is.

### The seam with the reducer

The original's reducer works in absolute rows (`top`, `content`, `view`).
The viewport's truth is the anchor, because absolute rows above the view
may include estimates that are refined later. They meet as the original
meets OpenTUI in `layout.ts`:

- After layout, `didLayout` gives the reducer `scroll_measured(content,
  view, top)` with `top = rowsAbove`, derived from the anchor. A refined
  estimate above changes `top` without moving the view, which is the
  original's "keeps the entry at the top" case.
- When the reducer moves `top` on a key, the viewport turns that into
  `byRows(newTop - lastReportedTop)`: a delta, so estimates cannot move the
  view by a wrong amount. `following` turning true is `toEnd`.

Which steps exist, when following starts and stops, and news are runtime's.

## Measuring items of any height

`ItemExtents` is plain Dart with no widget in it, unit-tested directly:

```dart
/// The height of each item at one width, as far as it is known.
class ItemExtents {
  int width;
  final List<int> _heights;    // -1: not measured at this width
  final List<Object?> _tokens; // itemVersion(i) when measured
  int _knownSum, _knownCount;

  int heightOf(int i);         // the height, or the estimate
  int get estimate;            // mean of known heights, 1 when none
  int rowsBefore(int i);       // sum over 0..i-1, estimates included
  bool get exact => _knownCount == _heights.length;
  void record(int i, int height, Object? token);
  void reconcile(int count, Object? Function(int)? version, {int? shift});
  void resetForWidth(int width);
}
```

**What is cached:** one height per index, for the current width only, with
the `itemVersion` token it was measured under. A resize back and forth is
rare enough not to keep a second width.

**Invalidation.** There is no dirty marking to tell the viewport that an
item off screen grew, and calling the builder for every item to look would
build 10 000 widgets a frame. So the list is told cheaply:
`reconcile` runs on every `update` and compares `itemVersion(i)` with the
stored token for each measured index (`identical`, then `==`), dropping the
height of each that differs. With the port's immutable entries, a streaming
reply replaces its entry object, so exactly the last item is dropped; a
global fold state (ctrl+o) goes into the token (`(entry, expanded)`), so
all are. Without `itemVersion`, every height is dropped on every rebuild:
correct, and fine for pickers and short lists. Items in sight are laid out
every frame anyway, so their heights are always fresh.

**Unknown heights** count as the estimate until measured. The background
measurer, step 6 of layout, picks unmeasured indices nearest the view
(below first, as "lines below" is what the port shows), builds each with
`itemAt`, lays it out, records it, and releases it if it is outside the
kept window, until the frame's budget is spent (proposed 4 ms; a constant
to profile). While any height is unknown it asks for another frame
(`owner.requestFrame()`). Those frames paint the same cells, so the diff
writes nothing but the rule's number when it changes.

**Totals.** `rowsBefore(i)` is a loop over the list of ints, done once per
layout for the anchor: about ten microseconds at 10 000 items, so no
prefix-sum tree.

**What each user gets:**

- Transcript following the bottom: everything in sight is exact;
  `rowsBelow` is 0. After a resize the measurer works the rest out in the
  background.
- Transcript scrolled back by keys from the bottom: every item passed was
  laid out on the way, so `rowsBelow` is exact at once. Only a jump (home)
  over unmeasured items shows an estimate, refined over the next frames.
- Pickers and logs: short or one-line items; measured in the first frame or
  two.

## The anchor

```dart
/// The item at the top of the view and how many of its rows are above it.
class ListAnchor {
  final int index;
  final int rowsInto;
  final Key? key; // the item's widget key, when it has one
}
```

- **Relayout** (an item above or the anchor itself changes height, ctrl+o):
  the anchor's item is laid out first at `y = -rowsInto`, with `rowsInto`
  clamped to `height - 1` (the original's `topOf`). What is above moves
  out of sight; the view does not move.
- **Resize:** the same, after `resetForWidth`. The text at the top of the
  view stays at the top, rewrapped.
- **Insertion at the end:** while following, the fill starts from the new
  last item; while anchored, nothing moves and `rowsBelow` grows (news is
  the reducer's).
- **Insertion above (backfill):** the anchor item is always built (it is in
  sight), so its widget key is known. On `update`, if
  `findChildIndexCallback` is given and the anchor has a key, the new index
  comes from the callback, `ItemExtents.reconcile(shift: newIndex - old)`
  moves the cached heights with it, and the live elements are re-indexed by
  the same shift. Without a callback, indices are taken as stable, as in
  Flutter.
  Recommendation for the port: the transcript is append-only and the
  framework builds only what is in sight, so `backfilled` and `mount.ts`
  (a cure for OpenTUI laying out everything mounted) need not be ported at
  all; the port passes all entries, indexed from the first.
- **Shrink under the view** (`itemCount` drops below the anchor): the
  anchor moves to the new last item and the fill goes upward.

## Clipping

Items are laid out at their whole natural height and painted with their
origin at their row, which is negative for an item cut at the top, through
`canvas.clipped(Rect.fromOffsetSize(origin, size))`. `Canvas.put` already
drops every cell outside the clip, wide graphemes split by an edge included
(they become a space), so a partly shown item needs no help to be right.

To keep it cheap, two small changes in existing render objects:

- `RenderParagraph.paint` starts at line `max(0, clip.top - origin.y)` and
  stops at the clip's bottom, so a 5 000-line reply cut to 40 rows paints
  40 lines, not 5 000.
- `RenderFlex.paint` skips a child whose rect does not meet the clip, so a
  markdown entry of many blocks paints only the blocks in sight.

Truncating items by laying them out with a max height was rejected: it
changes their layout (a box would draw its bottom border in the wrong row).

## Cost

At 10 000 items, following, 1 000 chunks a second into the last item,
120x40. `runApp` already draws at most one frame per 16 ms, so the chunks
of one frame cost one rebuild.

| Step                      | Work                                                    | Grows with |
| ------------------------- | ------------------------------------------------------- | ---------- |
| build                     | the list's parent rebuilds; `reconcile` compares 10 000 tokens; the built items (about a view's worth plus `keep`) rebuild | n (tokens, ~20 µs), view |
| layout                    | the items in sight; the last item's text rewrapped      | view, the last item's length |
| `rowsBefore`              | one loop over 10 000 ints                               | n (~10 µs) |
| background measure        | nothing once all heights are known                      | 0 in steady state |
| paint                     | 4 800 cells, lines outside the clip skipped             | screen |
| diff, write               | the changed cells                                       | change |

Memory: two lists of 10 000 (heights, tokens), about 160 KB, plus the
elements and render objects of the built items only. A long session stays
flat in the framework; the entries themselves are the port's.

The one cost that grows within a frame is the streaming item: its whole
text is wrapped again every frame, as everything is laid out every frame
(decisions.md). A 100 KB reply is a few milliseconds. Two remedies, neither
needed by this task: the markdown widget lays a reply out as one paragraph
per block, and `RenderParagraph` keeps its `TextLayout` when text, style and
constraints are unchanged (`identical(text)` first, then `==`), so only the
last block is wrapped again. The second is a dozen lines in
`rendering/basic.dart` and is proposed here as optional.

After a width change, the measurer builds and lays out every item once in
the background: at an assumed 20–50 µs per transcript entry, 0.2–0.5 s of
work, 4 ms a frame, done in one to two seconds while the screen is already
right.

## Changes in existing files

- `lib/src/widgets/framework.dart`: `BuildOwner.buildDuringLayout` and its
  `_inLayout` assert. Nothing else; `updateChild`, `unmountTree` and
  `syncRenderTree` are used as they are.
- `lib/src/widgets/host.dart`: one settle pass in `drawFrame`. Layout
  reports metrics; a listener (the port's rule) that rebuilds on them would
  otherwise show last frame's number. If `owner.hasDirtyElements` after
  layout, `drawFrame` runs `buildScope`, the sync if needed, and layout once
  more before painting; at most once, so a listener that never settles
  costs a frame, not a loop. The tester then sees the rule right after one
  pump. (The original has the same one-frame lag and lives with it; this
  removes it for a second layout of a few items.)
- `lib/src/rendering/basic.dart`: `RenderParagraph.paint` skips lines
  outside the clip; optionally, its layout cache.
- `lib/src/rendering/flex.dart`: `RenderFlex.paint` skips children outside
  the clip.
- `lib/chorded_tui.dart`: exports the new public names.

## Options rejected

1. **Lay out the whole list every frame** (today's rule): 10 000 markdown
   entries a frame. The reason virtualisation exists (decisions.md).
2. **The original's shape**: mount a window of entries, lay all of it out,
   cull paint, backfill near the top (`mount.ts`, `layout.ts`). It ports an
   OpenTUI workaround, keeps the cost proportional to the window, and needs
   backfill bookkeeping to page up.
3. **Flutter's slivers and estimates whole**: `Viewport`, `SliverGeometry`,
   scroll-offset correction passes. General machinery for nested and mixed
   scrolling the brief rules out, and estimates alone cannot give chord's
   exact "N lines below".
4. **Choose the visible range during build, from cached heights**, so
   nothing is built during layout. Heights are unknown until layout, so a
   wrong guess shows a frame with a gap and needs a second frame to fix.
5. **Measure all items synchronously** on first sight and on resize:
   hundreds of milliseconds in one frame at 10 000 entries.
6. **Keep every item's element alive** to know its height: memory grows
   with the transcript; states of items far out of sight keep running.
7. **Ask the builder for every item on rebuild to spot changes**: 10 000
   widgets a frame, and two widgets cannot be compared for height anyway.
   `itemVersion` is the cheap form of the same question.
8. **A Fenwick tree for prefix sums**: needless at 10 000 (a loop is ten
   microseconds); worth it at a million.
9. **Dirty marking of render objects**: still deferred by decisions.md;
   tokens give the cache its invalidation without it.

## Open questions

1. **`itemVersion`** is a name and a parameter Flutter does not have.
   Interface may prefer it on `ListView.builder` or folded into another
   name; the framework needs the function, not the name. Without it the
   list works, at the cost of re-measuring after every rebuild.
2. **Backfill in the port.** The draft recommends not porting `mount.ts`
   and `backfilled` (the framework makes them unnecessary). It is a
   departure from the original's structure, though not from what the
   screen shows; per AGENTS.md, the owner's call.
3. **Focus inside a released item.** A focused widget in an item that
   scrolls out of the kept window is unmounted and loses focus. Nothing in
   the transcript, pickers or logs is focusable inside an item, so the
   draft does not add keep-alive; flagged for later.
4. **Measuring has side effects.** The background measurer builds and
   disposes items, so an item's `initState`/`dispose` run for items never
   seen. Items should keep work out of `initState` (a spinner's timer
   starts on mount anyway, and stops on release).
5. **The settle pass** changes `AppHost.drawFrame` for every app, not only
   lists. Runtime and the tester's author should agree; the alternative is
   to accept the one-frame lag of the original and `pump` twice in tests.
6. **The 4 ms measuring budget and the 20–50 µs per entry** are
   assumptions to be checked with a benchmark in the ship task, under
   `dart compile exe`.

# CTUI-1 brief: scrolling and virtualised lists

The lead's brief to the architects. Task: `board show CTUI-1`.

## The problem

The framework lays out and paints the whole tree every frame
(docs/decisions.md, "The whole tree is laid out and painted every frame").
A transcript of thousands of entries cannot be laid out whole each frame, so
the list that shows it must build, lay out and paint only the items in
sight. chord draws on the alternate screen, which has no scrollback, so the
window scrolls its own transcript and must follow the bottom while output
streams.

Scope is what three users in the port need, no more:

1. **The transcript** (`../chord/src/ui/transcript/scroll.ts`,
   `Transcript.tsx`, `src/ui/app/layout.ts`, `src/ui/app/state.ts`
   `scrollStep`). Entries of any height (markdown, diffs, folds that open and
   close). Follows the bottom; a scroll up stops following; reaching the
   bottom again resumes it; "news" is set when output arrives while scrolled
   back. While scrolled back, the view's last row is a rule:
   `── ↓ 12 lines below · end to jump to the bottom ──…`, or
   `── ↓ new output · 12 lines below …` with "new output" in the accent.
   A relayout (ctrl+o unfolding, a resize) keeps the entry at the top of the
   view where it was (`anchorAt` / `topOf`: entry index plus rows into it).
   A page is the view less two rows. Older entries are mounted lazily when the
   view nears the top (`backfilled`); that is the port's paging of its record,
   but the list must not lose its anchor when items are inserted above.
2. **Pickers** (`../chord/src/ui/pickers/picker.ts`): a list of choices with
   a highlight moved by up/down and j/k, kept in sight (`visibleRange`); the
   highlight stops at either end. Choices may take more than one line
   (`linedRows`).
3. **Background logs** (`../chord/src/ui/background/BackgroundView.tsx`,
   `view.ts`, `../chord/src/ui/dialogs/permission.ts` `requestView`): a box of
   N rows over a growing log that follows its end, pages with pageup/pagedown,
   home/end, with "↑ N above · pageup" / "↓ N below" rules taking a row each
   when there is room, and degrading for rooms of 0, 1 and 2 rows.

The original's keys (`../chord/src/ui/shortcuts/bindings.ts`, context
`Scroll`): pageup/shift+pageup, pagedown/shift+pagedown, shift+up,
shift+down, home/shift+home, end/shift+end. Plain up/down belong to the
prompt (history) and to pickers (highlight).

## What an app's author writes

Roughly, to be settled by the drafts:

```dart
final scroll = ScrollController();            // offset, jumpTo, page/line steps, listener
ListView.builder(
  controller: scroll,
  follow: Follow.bottom,                       // README's name
  itemCount: entries.length,
  itemBuilder: (context, i) => EntryView(entries[i]),
)
```

The rules ("↓ 12 lines below") are chord's wording, drawn by the port from
what the controller exposes (content rows, view rows, rows above and below,
following, news). Whether the framework draws a scrollbar is an open owner
question (below).

## Constraints

- AGENTS.md is binding. Written from scratch; no terminal UI package.
- Layout in whole cells. Constraints down, sizes up.
- The viewport builds children during layout (Flutter's slivers / `LayoutBuilder`
  shape) without breaking "render children are synced from the element tree"
  (docs/decisions.md) or the current element/render tree in
  `lib/src/widgets/framework.dart`, `lib/src/rendering/`.
- Item heights are unknown until laid out at the view's width. Total content
  height must be known well enough for "N lines below" and paging; say how
  (measure all, estimate, cache by index and width) and what it costs at
  10 000 items.
- Every action has a key, bound through `Actions` with a description; the
  shortcuts panel lists it. The keys must be the app's to choose: the port
  binds the original's, a picker binds up/down/j/k.
- State is plain Dart a test reaches: the scroll position and the follow
  rule as a reducer or a `Listenable` with no widget in it.
- Tested with `package:chorded_tui/testing.dart` at 120x40 and 80x24.

## Non-goals

- Mouse wheel and drag (`scroll_held` / `scroll_released` in the original).
  The keyboard first; leave a seam, do not design it.
- Horizontal scrolling, slivers in general, nested scrolling, `GridView`,
  overscroll, animation of scrolling.
- The port's own screens; this task builds the framework pieces and says
  how the port's transcript, pickers and logs sit on them.
- Dirty-marking render objects (still deferred by decisions.md).

## Open questions

For **framework** (elements, render objects, layout, the renderer):

1. How the viewport builds only visible items during layout: the element
   that creates children on demand, the render object that asks for them,
   how this fits the full-tree sync walk.
2. How items of any height are measured: what is cached (by index, by
   width), how invalidation works when an item changes (a streaming reply
   grows, a fold opens), what total height is used for paging and the rule.
3. The anchor: how the top item and rows into it are kept across relayout,
   resize, and insertion above (backfill) and at the end.
4. Clipping: how a partly visible item (top or bottom) is painted.
5. Cost per frame at 10 000 items, 1 000 chunks a second into the last item.

For **interface** (call site, states, keys):

1. The public API: `ScrollController`, `ListView.builder`, `Follow`,
   whatever a picker needs (`ensureVisible(index)` or similar), what the
   controller exposes for the port's rules.
2. The states: fits; following; scrolled back; scrolled back with news; at
   the top; and how each looks at 120x40 and 80x24 for the transcript, a
   picker and a log box (the latter's rooms of 0/1/2 rows).
3. The keys: the actions, their default bindings and descriptions, how an
   app overrides them (the port's shift+ keys, a picker's up/down/j/k), and
   how they reach the list (focus, scope).
4. The scrollbar, if the owner keeps it: what it draws in one column.

For **runtime** (streams, failure, performance, testability):

1. Following the bottom under streaming: chunks batched per frame, the
   last item growing, the follow rule's exact transitions (port them from
   `reduceScroll`, cite each case), news.
2. The reducer: the plain-Dart state the controller holds and its tests;
   which of the original's tests (`../chord/tests/ui/transcript/`) carry over.
3. Failure modes: item builder throwing, itemCount shrinking under the
   view, view of 0 or 1 rows, width changes, a controller attached to two
   lists, disposal.
4. Memory: what is retained for off-screen items (elements, heights), and
   how a long session stays flat.
5. How the tester drives all of it (pump after appending, press keys,
   check the screen).

## Owner questions (sent to main)

- **The scrollbar.** The task asks for "a scrollbar drawn in one column".
  The original draws none: every scrollbox in `../chord/src` has
  `verticalScrollbarOptions={{ visible: false }}`, and the transcript and logs
  say what is hidden with a rule row instead. Options: (a) keep a small
  `Scrollbar` widget in the framework, unused by the port; (b) drop it from
  CTUI-1, the controller exposing enough for one to be added later.
  Lead recommends (b). Drafts should keep any scrollbar section separable.

**Answered by main (for the owner):** (b). The scrollbar is dropped from
CTUI-1; the controller exposes content rows, view rows and offset so one can
be added later. Line keys are the app's to choose: agreed.

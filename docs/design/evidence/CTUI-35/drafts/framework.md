# CTUI-35 framework draft: the agents list, the chat switch, the room

Framework architect. Answers the brief's three framework questions against
`lib/` as it is on `CTUI-35` and against `../chord` `src/ui/agents/`
(`agents.ts`, `Agents.tsx`, `glyphs.ts`), `src/ui/app/` (`App.tsx` around
the list, `layout.ts`), `src/ui/dialogs/` and `src/ui/prompt/Prompt.tsx`.
Short answer: the list, the room and the prompt box's named top need
nothing new from `lib/`; the chat switch needs one change in `lib/`, a
scroll controller that owns its anchor (F1).

Revised once after the critic: section 2 (one scroll authority, the
anchor's rules while detached), section 3 (the room as a contract per
request kind, saturation, units), section 4 (the titled border) are new or
rewritten.

## 1. The agents list: nothing new in `lib/`

### What the original is

`src/ui/agents/agents.ts` is a pure layout over at most a handful of rows,
and `Agents.tsx` only paints its result line by line:

- `laidRows`: one pass per way of fitting (`FITS`: effort goes, then model,
  then a mark's words), a name column of at most a third of the width that
  wraps long names, and past the last fit the rows that need most room put
  their state and mark under the detail, wrapped at spaces. Widths come from
  `string-width`, wrapping from `wrap-ansi` with `hard: true, trim: true`,
  every width clamped to at least 1 (`Math.max(1, width)`).
- `agentsLayout`: whole rows within `limit` lines, `… +N more` on the last
  line past it, the window moved so the picked row is in sight while the
  list has the keys, and a row taller than the limit read by line with
  `↑`/`↓` in the gutter (CHD-445, CHD-471, `AgentsView`).
- `agentsLines`: the lines the list takes at a limit; the window uses it
  for the full size and the floor (CHD-464).
- `agentState`/`agentMark`/`listTimed`/`agentsHint`/`childLine`/
  `leftOpenLine`: words, glyphs and tones.
- `AgentsList`: a box with `paddingX=2`, each line a `CUT` text of spans
  (`wrapMode: 'none', truncate: true, selectable: false`), the `❯` in the
  permission colour, `↑`/`↓` dim; one shared one-second clock for the list
  and a child's opening line.

### What `lib/` already gives it

| The original's need | In `lib/` today |
|---|---|
| `string-width` | `cellWidth` (`lib/src/text/width.dart`) |
| `wrap-ansi(…, {hard, trim})` | `TextLayout.wrapAnsi(span, columns, hard: true, trim: true)` (`lib/src/text/layout.dart`, `wrap_ansi.dart`); it throws below 1 column, so the port clamps to 1 exactly where the original does; the port already calls it in `lib/agents.dart`, `pickers/picker.dart`, `transcript/message.dart` |
| a `CUT` line of styled spans | `Text.rich(…, softWrap: false, maxLines: 1, overflow: TextOverflow.middle)`, as the port's status line already maps OpenTUI's `truncate` |
| `paddingX=2` box of lines | `Padding` + `Column` |
| not selectable | `SelectionContainer.disabled`, the window's `_furniture` |
| the per-second clock | a `Timer.periodic` in widget state, as `status/working.dart` and `dialogs/questions_box.dart` do |
| agent colours | `agentColour` and the palettes' `agents` (`example/chord/lib/ui/theme/theme.dart`) |

The rows are furniture, not selectable: the original draws every list line
with `CUT`, which is `TEXT` plus no wrap, and `TEXT` is `selectable: false`,
documented in `src/ui/theme/text.ts` as "chord's furniture: gutters, …, the
status line, lists and boxes".

### What does not fit and should not be bent to fit

- `ListView`/`ListViewport` scroll by rows from a controller, build lazily
  and measure every item exactly; the list is at most nine rows (main and
  eight children), has `… +N more`, a line window with gutter arrows, and
  folds teams by a line count. None of that is a viewport's job, and lazy
  building buys nothing at nine rows.
- `Picker` has its own keys, filter and numbering; the list takes no keys
  itself (the window routes them, as in the original).
- A generic "line-budget list" in `lib/` would have callers that each
  differ (the queue's `queueRows`, the plan, this list, later CTUI-36's
  background rows): their rules are chord's own CHD numbers, not a terminal
  app's general need. AGENTS.md puts chord's own screens in the port.

### So

Port `agents.ts` file for file into `example/chord/lib/ui/agents/agents.dart`
(and `glyphs.ts` into `glyphs.dart`), pure Dart, `cellWidth` and
`TextLayout.wrapAnsi` in place of the two npm packages; port `Agents.tsx`
into `example/chord/lib/ui/agents/agents_view.dart` (the port's `queue.dart`
/ `queue_view.dart` naming), drawing `AgentsLayout.rows[].lines` as `CUT`
lines inside `_furniture`. Team folding (`teamRows`, `teamState`) is
CTUI-37's: `AgentRow` keeps `team`/`branch`/`folded` as optional fields so
CTUI-37 adds behaviour, not shape; `listRows` without teams returns the
rows as they are (confirmed by the lead). The list sits in the window's
footer after the status line.

Cost: `laidRows` is O(rows × 4 fits) with a `wrapAnsi` per wrapped name or
detail; at nine rows that is microseconds. It runs per build of the list:
on a state change of any agent and on the one-second tick while
`listTimed`. The renderer's diff writes only the cells whose time changed.
The room (section 3) adds three `agentsLines` runs per window build; same
order of cost. No caching.

## 2. The chat switch: one transcript view, one scroll authority

### How the original does it

One transcript tree, drawn for the front session (`front` in
`useMeasured`). Picking another agent re-renders the transcript with that
session's entries; only a window of the last entries mounts and older ones
back-fill (`mount.ts`). What survives per session is the scroll anchor:
`anchors: Map<session, {at: {entry, rowsInto}, top, from}>`, "one shown
again finds its entry where a resize meanwhile moved it". Selection is
OpenTUI's screen selection over what is drawn; the transcript it was over
is replaced.

### Flutter's options, and which a grid of cells needs

- Keep every session's subtree mounted offstage (`Offstage`/`IndexedStack`
  with keep-alive). `lib/` has neither, CTUI-1 decided "no keep-alive", and
  hidden transcripts would still rebuild and measure on every update of a
  working child. Not this.
- Retain per-session `ItemExtents` across viewports: machinery the brief
  does not need; only a fallback if U5 measures the switch too slow.
- One `Transcript` built for the picked session, its place held per
  session in a `ScrollController` the window keeps per session: the
  original's shape and Flutter's ordinary one (a controller outlives its
  scrollable). Chosen.

### One authority for scroll

The retained `ScrollController` of a session, its `ScrollState` and its
anchor, is the only place that session's scroll lives. Interface's draft
drops `SessionState.scroll`; any scroll value a reducer or the status line
reads (rows below, news, following) is a projection read from the
controller, never written back into it. The window keeps
`Map<sessionKey, ScrollController>`: main's is today's `_scroll`; a child's
is made when the child is first shown and disposed when the child closes,
is cleared (`/clear`, `clear_agent`: a new controller, as `Cleared` already
replaces main's selection session) or the window goes. News for a hidden
session is `markNews` on its controller (`Follow.bottom`), which moves
nothing.

The `Transcript` gets `key: ValueKey(sessionKey)` and that session's
controller, transcript, header (`ChildLine` for a child) and selection
sources. The key makes a new `ListViewport` per switch, so its
`ItemExtents` start cold; not keying would cost the same, since
`itemVersion` is a record holding the entry and every height of the other
session would be dropped. Selection: the window-wide `SelectionController`
is cleared and its selection session replaced on a switch; the picked code
block (ctrl+x b) ends the same way. Sources are lazy (CTUI-48).

### F1: the anchor moves into the controller

Today `RenderListViewport._anchor` (`lib/src/rendering/list_viewport.dart`)
holds the item at the view's top and the rows into it; the controller holds
only `ScrollState` in rows. A controller detached while scrolled back and
attached to a new viewport keeps `state.top` in rows; if the width changed
meanwhile, or `ctrl+o` changed heights above, that row is in another entry.
The original handles exactly this case.

The value type: `ListAnchor` (index, `rowsInto`, unchanged) moves from
`rendering/list_viewport.dart` to `lib/src/foundation/scroll_state.dart`,
beside `ScrollState`, so `widgets/scroll_controller.dart` keeps importing
only foundation. `chorded_tui.dart` exports both files today, so the public
name is unchanged; `list_viewport.dart` imports it from foundation.

`ScrollController` gets `@internal ListAnchor? anchor` with one `///` line.
Its rules, the only behaviour F1 adds:

1. **Attached**, as today: the viewport writes `controller.anchor` where it
   writes `_anchor` now, at the end of `performLayout` (null while
   following or with content 0, else `extents.anchorAt(next.top)`) and in
   `scrollChanged` (null while following, else read from `state.top`
   against the heights the step was taken over). Before `reduceMeasured`
   the viewport reads `controller.anchor`, clamped to the last item where
   items were removed (`ListAnchor(count - 1, 0)`), and passes
   `extents.topOf(anchor)` as `top`, as now. `rowsInto` is kept;
   `ItemExtents.topOf` already clamps it to the item's height.
2. **Detached, a step that moves the view** (`jumpTo`, `toTop`,
   `toBottom`, `lineUp`/`lineDown`, `pageUp`/`pageDown`, and `release`
   where it normalises the top): the reducer runs on the last measured
   `ScrollState`, as it does today, and if `top` or `following` changed the
   anchor is set to null. The next attach reads that top in rows against
   the new heights (clamped by `reduceMeasured`). There is no geometry to
   rebase an index against while detached, so the rows the person asked for
   win over a stale entry. `toBottom` on `Follow.bottom` follows again, so
   null is also the following rule. Implemented in `_mutate` and the queued
   loop of `notifyListeners`: where `_client == null`, compare and clear.
3. **Detached, a step that does not move the view** (`markNews`, `hold`, a
   `release` that keeps the top): the anchor stays.
4. **Empty content and zero width**: unchanged from today. A layout with
   no items or a width of 0 reports content 0 (`list_view_test.dart`'s
   "a width of 0 measures nothing and reports 0 rows" and
   `list_view_extents_test.dart`'s zero-width round trip pin this), which
   `reduceMeasured` turns into fits/at-bottom, and the anchor is set to
   null. Keeping a place through a zero-width frame would need a new
   reducer case; nothing in the brief asks for it (a hidden session's
   controller is detached, not laid out at 0 columns).
5. **Clear**: a cleared session gets a new controller (anchor null). Items
   removed under an attached controller clamp as in rule 1.
6. **Swaps**: the `controller` setter detaches the old controller, which
   keeps its anchor, and attaches the new one, whose anchor the next layout
   reads. The setter no longer writes any anchor. `dispose` drops it.

No public API changes; `ScrollController`'s other behaviour is untouched.

### Cost

- Per switch: the first frame of the picked session measures every entry
  once, exactly the first frame of a resumed session. CTUI-1's AOT
  benchmark: about 110 ms at 10 000 markdown-like entries (63 002 rows),
  0.11 ms for a steady frame. One hitch per switch; the original pays its
  own re-render per switch.
- Per update: only the shown session is in the tree. An update to a hidden
  child runs its reducer and rebuilds the agents list; no transcript
  layout. The shown one costs what it costs today.
- Memory: a controller (a `ScrollState` and an anchor) per open child.
- Selection: a switch is O(1); sources resolve lazily.

## 3. The room: a contract computed before layout

### The original's order (CHD-464)

From what gives way first: (1) the transcript, to no rows; (2) the agents
list, from `agentsRowLimit(rows)` = `max(2, rows ~/ 6)` lines down to its
floor, `agentsLines(limit: 1)` (one agent row and `… +N more`: 2 lines with
two or more rows, 1 with a single row drawn, 0 with no child); (3) only
then a request's shrinkable part. Nothing else gives way: status line,
prompt box, queue rows, working line, a request's pinned rows, the summary
line (CTUI-36). The original reaches this with Yoga in two frames and a
latch (`folded`) against the list and the permission box trading rows.
Computed before layout, there is no feedback and no latch; the steady
states are the same (tests below match them).

### One unit

Every term is in **lines**: terminal rows on screen. The list's `limit` is
lines, a wrapped agent row counts each of its lines, `… +N more` is one
line, and `agentsLines` returns lines; `agentsRowLimit` keeps the
original's name but returns a line count.

### Each request kind: natural, fixed, shrinkable

`maxRows` below is the parameter each box already takes; today the window
passes `_requestRoom`. All five draw a top margin, a border and a hint, and
count them in `maxRows`. "Natural" is the box's height with `maxRows`
unbounded, under its own caps, which do not depend on the list.

| Kind (port file) | Fixed (never gives way) | Shrinkable | Natural | Gives way |
|---|---|---|---|---|
| permission (`permission_prompt.dart`) | `pinnedRows`: margin 1, border 2, title 1, asker rows, between 1, question gap and rows, review gap, choices, hint gap and hint | the request body, from `min(wholeHeight, max(windowRows ~/ 2, 1))` down to 0 (a room of 0 or 1 says its count beside the title) | `pinnedRows + min(wholeHeight, max(windowRows ~/ 2, 1))` | after the list (CHD-464, the original's `givesWay={listFolded}`) |
| plan (`plan_box.dart`) | `pinned`: border 2, title 1, gap 1, question rows, choices, gap 1, hint gap 1, hint rows; plus the margin 1 | the Note, from `min(windowRows ~/ 2, noteTotal)` down to 1 (`max(…, 1)`) | `1 + pinned + min(windowRows ~/ 2, max(noteTotal, 1))` | see open question 1 |
| form (`form_box.dart`) | the whole box while not held: margin, border, hint and gap (5) and `lines`, already capped by `formRowLimit(windowRows)` | only while held (another request has the keys): `lines` fold into `maxRows - 5` by `HeldFold`/`foldOf` | `5 + lines` | only when held, as the original's `flexShrink={held ? 1 : 0}` |
| question (`questions_box.dart`) | as form; `lines = 4 + body.rows`, body capped by `formRowLimit - questionBoxChrome` | only while held, into `maxRows - 5` | `5 + lines` | only when held |
| link (`link.dart`) | as form; `lines` from message, URL, host and choices | only while held, into `maxRows - 5` | `5 + lines` | only when held |

To make "natural" reachable before layout without a second measurement,
each box's existing height arithmetic, which today sits inside its
`LayoutBuilder`, is lifted into a pure function in the same file and called
both by the box and by the window: `permissionNatural`, `planNatural`,
`formNatural`, `questionNatural`, `linkNatural`, each
`(wait, state, width, windowRows) → (fixed, natural)`. This is a move of
code already written, not new arithmetic; `requestHeight` stays the
permission body's.

A permission or plan and a held form, question or link can be up together.
How those two share rows is today's port behaviour (each is passed the same
`maxRows`) and is not changed by CTUI-35; the list term below is subtracted
before either sees its room.

### The arithmetic

```text
rows      window height in lines (the window LayoutBuilder's maxHeight)
fixed     what never gives way, as _requestRoom counts it today
          (status 1, working 2 while shown, plan rows, queue rows, editor,
          prompt border 3), plus the summary line's slot (0 until CTUI-36)
avail     max(0, rows - fixed)
need      sum of natural heights of the requests drawn (0 for none)
full      agentsLines(limit: agentsRowLimit(rows))
floor     agentsLines(limit: 1)                        floor <= full
limit     clamp(avail - need, 1, agentsRowLimit(rows))
list      clamp(agentsLines(limit: limit), floor, full) (0 with no child)
maxRows   max(0, avail - list)                      passed to every box
transcript  Expanded: what is left, possibly 0
```

Read in order: with `avail - need >= full` the list is whole and the
transcript gets the rest; between, the transcript is 0 and the list shows
`avail - need` lines; below `floor`, the list stays at its floor and
`maxRows < need`, so a permission body or plan Note gives way, each to its
own minimum (0 and 1). The list returns to its limit as soon as rows come
back, as CHD-464 says.

**Saturation.** When `fixed + list + Σ fixed parts of the requests > rows`
nothing is left to give: the transcript is 0, the list is at its floor, the
bodies at their minimum, and the column is taller than the window.
`RenderFlex` lays the non-flex children at their size and the window clips
at its bottom edge, so the last lines (status line, list) are cut. That is
the original's behaviour too (CHD-464's "before" capture, summary line
off the bottom) and no design orders more; `maxRows` is never negative
(`max(0, …)`) and every box already clamps its room to 0.

**Inputs.** `rows` and `width` are finite in the window (a terminal). 0
rows: `avail = 0`, `list = floor`, `maxRows = 0`, the screen clipped. A
width of 0 or 1: `agentsLayout` and the request functions clamp to 1
column as the original does, and painting clips. Unbounded `rows` (only a
test can give it) has no `agentsRowLimit`, so `agentsRoom` takes finite
rows only and throws an `ArgumentError` otherwise, as `ListView` does for
unbounded height; the window's `LayoutBuilder` is always bounded.

This lives in a pure function next to the window,
`agentsRoom({rows, fixed, need, linesAt}) → (limit, list, maxRows)` in
`example/chord/lib/ui/app/agents_room.dart`, `linesAt` being
`(limit) => agentsLines(…, limit: limit, width: columns - 4)`.
`_requestRoom` becomes its `maxRows`. Cost: three `agentsLayout` runs and
up to two natural-height functions per window build.

## 4. The prompt box's named top: drawn by the port

The original: when a child is picked, the prompt box's top border carries
its name, `╭─ docs ─────╮` (`NamedTop` in `src/ui/prompt/Prompt.tsx`;
captures in `../chord` `docs/design/CHD-493.md`, `CHD-431.md`). Exact
cells: `╭─` in the edge style, ` name` bold in the agent's colour, for a
member ` · team` dim (CTUI-37), then ` ` and `─` × `max(1, width -
w(name + after) - 5)` and `╮` in the edge style; the whole is one `CUT`
line. The edge style is the agent's colour, or dim. The original draws this
as a row over a box that has no top border because OpenTUI's border title
takes no colour of its own.

`Box.title` (`lib/src/rendering/basic.dart`) draws ` name ` at the first
cell after the corner, `╭ docs ───╮`, in the border's style made bold. The
gaps are exactly two: no `─` between the corner and the title, and the
title cannot take a style other than the border's. Both are the original's
own choice for this one row, not a general border convention (the original
itself bypasses its framework's title), so no `Box` change. The port draws
it: the prompt box's `Box` keeps its full rounded border in the edge style,
and a `Stack` around it puts a one-line `Text.rich` of those spans at
`Positioned(top: 0, left: 0, right: 0, height: 1)`, painting over the top
border row. Narrow: the line is cut like any `CUT` line; 0 width: the
`Box` draws no border below 2 cells and the line clips to nothing. Port
tests in U4; no framework unit and no new border.

## Changes to existing files

- `lib/src/foundation/scroll_state.dart`: `ListAnchor` moved here.
- `lib/src/rendering/list_viewport.dart`: imports `ListAnchor`; `_anchor`
  reads and writes go to `controller.anchor`; the setter writes no anchor.
- `lib/src/widgets/scroll_controller.dart`: `@internal ListAnchor? anchor`
  and the detached rules (2, 3).
- `test/widgets/scroll_controller_test.dart`: F1's tests.
- No change to `framework.dart`, the renderer, text, input, focus or `Box`.
- Port: `ui/agents/` (new), `ui/app/agents_room.dart` (new), the natural
  functions lifted inside the five `ui/dialogs/` box files, `window.dart`
  (controller map, keyed `Transcript`, list in the footer, `_requestRoom`
  from `agentsRoom`), `ui/prompt/prompt_input.dart` (named top).

## Open questions

1. Lead (a possible slip of the original): the original's plan box has
   `flexShrink={1}` with no `givesWay` gate, so Yoga shares a short
   window's shrink between the plan's Note and the list in proportion to
   their sizes; CHD-464 names only the permission box. I propose the plan's
   Note gives way after the list, like the permission body (CHD-464's order
   applied to the other shrinkable body). The alternative, Yoga's
   proportional share, has no rule to port.
2. Owner, only if measured: if U5's switch frame is too slow, the fallback
   is per-session extents kept outside the viewport, a new `lib/` decision.
   I propose not building it now, as CTUI-1 accepted the same hitch for
   resume.

## Units for ship (my part, in order)

**F1. `lib/`: the scroll controller owns its anchor.** Files above. Tests
in `test/widgets/scroll_controller_test.dart` through the tester, items of
heights that differ by width (3 lines at 80 columns, 6 at 40):
- detached and reattached across a width change: scrolled back to item 40
  row 0 at 80 columns, the list removed, the same controller in a new
  `ListView` at 40: `firstVisible == 40`, `offset == itemTop(40)`. Fails
  today (rows kept, another item on top).
- an offset inside an item: scrolled to item 40 row 2, reattached at 40
  columns: `offset == itemTop(40) + 2`; scrolled to its row 5 at 40,
  reattached at 80: clamped into item 40 (`itemTop(40) + 2`). Fails today.
- scrolled `Follow.bottom`: scrolled back, detached, items appended and
  `markNews` called while detached, reattached at another width: same top
  item, not following, `hasNews` true. Fails today.
- a detached `jumpTo(r)`: the anchor is dropped and the view is at row `r`
  (clamped) against the new heights, not at the old entry. Fails without
  rule 2 (the stale anchor would win).
- a detached `toBottom`: follows again on reattach (`Follow.bottom`), at
  the bottom for `Follow.none`. Fails without rule 2.
- an empty or zero-width interlude: an attached list given 0 items, or 0
  columns, then restored: the anchor is gone and the view follows the
  current rules (bottom for `Follow.bottom`), as today. Guard for rule 4.
- controller swaps: A and B swapped on one `ListView` across a width
  change each come back on their own top item. Fails today (the setter
  drops the anchor).
- a following controller reattached is at the bottom (guard).

**U1. Port: `ui/agents/glyphs.dart` and `agents.dart`, pure.**
`agentState`, `agentMark`, `listTimed`, `agentsRowLimit`, `listRows`
(teams later), `moveListFocus` (summary stop kept for CTUI-36),
`agentsLayout`, `scrolledView`, `enteredView`, `agentsLines`,
`agentsHint`, `summaryHint`, `childLine`, `leftOpenLine`. Tests:
`test/ui/agents/agents_test.dart`, the non-team cases of
`../chord/tests/ui/agents/agents_test.ts` case by case (columns, picked
mark, states and marks gravest first, `… +N more` and moving to the pick,
narrow fits dropping effort/model/mark words, wrapping into a third,
detail wrapping, read by line with `↑`/`↓`, the CHD-464 floor, CHD-523,
CHD-445, the L1b every-line-reachable sweep, hints at 80 and 120), plus
widths 0 and 1 (clamped to 1 column, no throw) and a name wider than the
list. Each fails without the function it names.

**U2. Port: `ui/agents/agents_view.dart`, `AgentsList` and `ChildLine`.**
Tests: `test/ui/agents/agents_view_test.dart` through
`package:chorded_tui/testing.dart` at 120x40 and 80x24: rows and columns as
`AgentsList_test.tsx` shows them, a wrapped name and a state under its
detail drawn whole, a picked row taller than the limit drawn in the
limit's lines with gutter arrows, theme colours (and none without colour),
a selection drag across the list copying none of it, the clock ticking
while timed and stopping when all are gone, two subscribers sharing one
timer released on the last dispose.

**U3. Port: the room.** `ui/app/agents_room.dart`, the five natural
functions lifted, `window.dart`. Tests: `test/ui/app/agents_room_test.dart`,
pure: at 40 and 24 rows the list whole with room; shrinking alone while
the transcript is 0; at its floor before any request row gives way; the
permission body and the plan Note shrinking only past the floor, each to
its minimum; form, question and link never shrinking unless held, then
folding; `avail` 0 and 1; saturation (`maxRows` 0, list at floor);
wrapped rows counted as lines; one child (floor 1 line) and none (0).
Window tests at 120x40 and 80x24 with three children and each request kind
in turn (permission, plan, form, question, link; and a permission over a
held form): status line and the request's choices on screen, the list's
lines and `… +N more` as the steady state of the original's captures
(CHD-464's 80x24 "after"), and the list back at its limit once the request
is answered. Each fails without `agentsRoom` (the list overflows the
window, or the request gives way first).

**U4. Port: the chat switch and the named top.** `window.dart`,
`prompt_input.dart`. Tests in `test/ui/app/` and `test/ui/prompt/` through
the tester: scrolled back in main, pick a child, back to main: the same top
entry; the same with a resize while main was hidden (needs F1); news on a
hidden child shown when it is picked again; a selection in main gone after
the switch; a closed or cleared child's controller disposed (no listener
left); the named top at 120 and 80 columns matching `╭─ docs ───╮` cell
for cell with the name bold in the agent's colour and the edges in the
edge style; a name wider than the box cut; a box 0 and 1 cells wide
drawing nothing and not throwing.

**U5. Benchmark: the switch frame.** Extend `benchmark/list_view.dart`
with a cold attach of a retained controller at 10 000 entries, AOT,
numbers into `docs/decisions.md` beside CTUI-1's. No test; it decides open
question 2.

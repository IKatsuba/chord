# CHD-172 — runtime draft

The runtime architect's answers to the brief's six runtime questions: the
mouse modes, a drag against chord's own scroll and mounting, streaming
under a selection, the copy's failures, the tests, and the cost. Every
claim marked *ran* was run on OpenTUI 0.6.0 and Bun 1.4.3 in a scratch git
worktree under `mktemp -d` (removed after), with `selectable` flipped to
`true` in `src/ui/theme/text.ts` there and nothing else changed; chord's
whole window was driven on the fake agent through `tests/ui/harness.tsx`
at 80×24. No clipboard was written: every OSC 52 went to a fake stdout or
a recording adapter, and every host write to a stub. The captures are
beside this draft:

- `spike-runtime-modes.txt` — the DEC private modes OpenTUI writes.
- `spike-runtime-window.txt` — the window spikes (wheel, edges, streaming,
  unmount, cull, click, keys).
- `spike-runtime-osc52.txt` — OSC 52 bytes through the renderer. Its
  service lines ran on a *remote* renderer (a renderer on a custom stdout
  is remote) and are superseded by `spike-runtime-copy.txt`.
- `spike-runtime-cost.txt` — motion reports and frame cost.
- `spike-runtime-sources.txt` — the first round's scratch scripts and
  tests, as run.

The second round, after the critic's review, in the same kind of scratch
worktree, with a probe (`src/ui/app/probe.ts` there) logging every
selection transition, the copy a stub with chord's bound and a generation
counter, a pinned mount window, and three scratch-only fake scenarios
(`rewrap`, `boxlater`, `manysteps`):

- `spike-runtime-lifecycle.txt` — every transition, in order, through
  public hooks (§3).
- `spike-runtime-mutations.txt` — content changing under a selection (§4).
- `spike-runtime-copy.txt` — the clipboard service on an explicitly local
  adapter with stub hosts, and the window's superseded, late and
  pending-at-quit copies (§5, §6).
- `spike-runtime-growth.txt` — a selection held while 600 entries stream
  in, pinned and not (§7).
- `spike-runtime-sources-2.txt` — the second round's probe, tests and the
  scratch diff, as run.

## In short

| Question | Answer |
| --- | --- |
| Mouse modes today | `?1000h ?1002h ?1003h ?1006h` on start (*ran*). Any-motion tracking is already on; a drag already reports motion. CHD-31's "1002 in place of 1000" was done by the move to OpenTUI. `"mouse": false` writes none. |
| The wheel during a drag | The selection keeps its anchor on the text it started in and its focus on a screen cell. A scroll moves the highlight with the content and leaves the focus behind until the next motion report, which re-reads the cell (*ran*). `renderer.requestSelectionUpdate()` re-reads it at once. |
| A drag past the edges | It stops at the transcript's top row and at whatever is on the last row. chord's view does not scroll on its own; OpenTUI's edge autoscroll is the scrollbox's, which chord does not use (*ran*). |
| Streaming under a selection | A released selection stays on its text as the view follows and the reply grows (*ran*). A held drag that does not move keeps its text; its next motion extends it to whatever is now under the pointer (*ran*). |
| An entry unmounted | Its text silently leaves the selection: 150 more entries took a selected call out of the tail, and `getSelectedText()` went from `Read(step-148.ts)` to `""` with the selection still "present" (*ran*). Culling (CHD-327 A) loses nothing: off screen, the text is still there (*ran*). |
| The lifecycle | Every transition is seen through public API: the press and motion on `onMouse`, the release on the renderer's `selection` event, chord's own clears where chord makes them, and OpenTUI's own clears (a press elsewhere, a textarea edit or cursor move) only at the next `frame` event, one frame late (*ran*, §3). |
| Content changing under a selection | The highlight keeps its cells, not its characters: a rewrapped word, a widened table, a tool's output and a rewritten plan all change what the same cells select; a removed plan left the highlight on the entry that took its place (*ran*, §4). |
| The copy | Asynchronous and off the frame. The host's timeout is `createHostClipboard`'s `timeoutMs` (1 s default), not per write. A host that ignores abort leaves the write **and** the service's `dispose()` pending for ever (*ran*), so chord bounds both itself (§5, §6). OSC 52 has no size cap (*ran*). |
| Held and growing | Pinning the mount window under a selection grows about 6 renderables an entry: 3,645 renderables and +28 MB of JS heap after 600 entries, against 257 and +4 MB unpinned (*ran*, §7). |
| Tests | Raw SGR bytes through the harness's `write`, which chord's tests already do; `selected()` already exists; the copy is a prop. Cross-entry selections need several motion reports in a test, not one. |
| Cost | `selectable` costs nothing per frame (*ran*: 0.90 vs 1.09 ms at 400 texts). Hover motion with 1003 costs about 15 µs a report and no frame; a selecting drag about 100 µs a report and a frame per report. |

## 1. Mouse modes

`openTerminal` creates the renderer with `useMouse: mouse` and leaves
`enableMouseMovement` at OpenTUI's default, `true`. The renderer then asks
its native session for mouse mode `"motion"` (`enableMouseMovement ?
"motion" : "drag"`); the bytes, captured from a renderer on a fake stdout:

```text
chord today (useMouse: true, enableMouseMovement default)
  start: ?2031h ?25l ?1049h ?25l ?2027h ?2004h ?1000h ?1002h ?1003h ?1006h
  end:   ?25h ?1003l ?1002l ?1000l ?1006l ?2004l ?1049l ?2031l ?25h ?25h
useMouse: true, enableMouseMovement: false
  start: ... ?1003l ?1000h ?1002h ?1006h
useMouse: false ("mouse": false)
  start: ?2031h ?25l ?1049h ?25l ?2027h ?2004h       (no mouse mode)
```

So:

- **1002 is on, and 1003 with it.** Every pointer move over the window is
  reported, button down or not. CHD-31's "1002 in place of 1000" needs no
  change: the move to OpenTUI did it. The question left is whether 1003
  (hover reports) should stay; nothing in chord or in this task uses hover.
  `enableMouseMovement: false` gives 1000 + 1002 + 1006, which is exactly
  what a drag selection needs, and a terminal sends nothing while the
  pointer merely passes over. It is a documented option of
  `createCliRenderer`, one line in `openTerminal`. (Owner question 1.)
- **`"mouse": false` still leaves the mouse to the terminal entirely**: no
  mode is written, so OpenTUI never sees a press and never starts a
  selection, and the terminal's own selection is the only one. Nothing in
  this task changes that, and the copy key (interface's) must then copy
  nothing and say so, or be inert; it never finds an OpenTUI selection.
- **The bypass modifier is the terminal's** (option in iTerm2, fn in
  Terminal.app, shift elsewhere) and depends on mouse reporting being on,
  not on which of 1000/1002/1003 it is. Not verifiable in tmux (tmux takes
  the drag itself); it is a hand check in iTerm2 and Terminal.app for the
  ship team.
- The modes are restored on every way out already: `?1003l ?1002l ?1000l
  ?1006l` are in the destroy bytes, and `renderer.tsx`'s `leave` runs
  destroy on a quit, a signal and a crash. Nothing new to give back.

## 2. A drag against chord's own scroll and mounting

### How OpenTUI's selection is held (read and run)

From `@opentui/core`'s renderer (`processSingleMouseEvent`,
`startSelection`, `updateSelection`, `finishSelection`) and its
`Selection` class:

- A selection **starts only on a left press over a selectable text** that
  says it can start there. A press on a box, a gutter, a blank row, the
  prompt's textarea (`selectable={false}`) or the border starts none
  (*ran*: a drag from the prompt box up into the transcript selected `""`).
  A press with ctrl held never starts one; ctrl+press *extends* the one
  there is.
- **The anchor is relative to the renderable it started in**
  (`SelectionAnchor` keeps `x - renderable.x`), so it moves with that text.
  **The focus is a screen cell**, the last motion report's.
- Each motion report while the button is down re-hit-tests the cell, walks
  the selectable renderables inside the bounds (from a *container*: the
  anchor's parent at first, climbing one parent per motion report that
  lands outside it), and tells each its local selection. Each text keeps
  that local selection **in its own coordinates**, so the highlight moves
  with the text when the text moves, until the next walk.
- The release emits the renderer's `selection` event (React:
  `useSelectionHandler`) with the `Selection`; `getSelectedText()` joins
  the selected texts by their rows, filtering destroyed ones.
- **A click also emits `selection`**, with `""` (*ran*). Double click
  selects a word, triple a line (`nextClickBehavior`, 400 ms, ±1 cell), for
  nothing (*ran*: a double then triple click on a row selected the whole
  row). Copy-on-release must skip an empty selection, or a click copies
  nothing and says `copied 0 chars`.

### The wheel while the button is held (*ran*, `long`, stopped)

```text
B before wheel:              "5. Line 35 … 36. Line 36 … 37. Line"
B after 3 wheel-up, no motion: (same)
B after a motion at the same cell: "e 34 of 200, streamed one at a time.\n35"
B released, wheel down 2:    (unchanged)
```

The wheel reaches chord's outer box (`useMouse`'s `onWheel`), which moves
chord's `scroll.top`; OpenTUI's selection is not told. The highlight rides
the content (the texts' local selections), so for a moment it no longer
reaches the pointer. The next motion report, even at the same cell,
re-reads the focus under the pointer: three rows up the content, the
selection now runs from line 35 back to line 34. This is how a browser
behaves (scroll extends the drag), and it is right, but the frame between
is wrong. **Fix inside OpenTUI's API:** after chord's own scroll moves the
view while `renderer.getSelection()?.isDragging`, call
`renderer.requestSelectionUpdate()`, which re-hit-tests the last pointer
cell and updates the focus in the same frame (it is public, and is what
OpenTUI's textarea does after its own autoscroll). The move is in
`layout.ts`'s frame (`offsetElement`), so the call belongs there, after
the offset is set; not in the reducer.

Once released, a wheel moves the highlight with its text, as expected.

### A drag past the edges (*ran*)

Dragged to row 0, the selection ends at the transcript's top visible text;
dragged to the last row, it ends at the last text of the transcript above
the status line (the status line's text was not taken in one report, as
the container climbs one level a report; with more reports it would be,
see below). **The view does not scroll** while the pointer is held at an
edge: chord's transcript is a clipping box moved by `translateY`, and
OpenTUI's autoscroll on selection is inside `ScrollBoxRenderable`
(`autoScrollThreshold*`, `autoScrollSpeed*`), which chord does not use
("OpenTUI part 4"). So a selection longer than the view needs either the
wheel while holding (works, above) or an edge autoscroll of chord's own.

An edge autoscroll would be chord's: a timer while the button is down and
the pointer is on the view's first or last row, stepping `scroll:lineUp`
or `lineDown` and calling `requestSelectionUpdate()`. That is writing
around the library (its autoscroll lives in a widget chord declined), so it
is an owner question, not a decision (Owner question 3). Claude Code's
reference does not say it scrolls at the edges.

The **container rule** matters for what a drag takes: a selection is
walked from the anchor's parent until the pointer leaves it, then from
one level up per motion report. A drag that leaves the transcript reaches
the status line's and the prompt's texts once it has climbed to the
window; which texts are selectable at all is interface's call
(`selectable` per text), and that is the only control there is.

### Holding the view still, or not

The selection survives the view moving (wheel, pgup, End, following new
output) as long as its texts stay mounted. It does not survive its texts
unmounting. The lead's lifecycle stops following while the left button is
down (§3), so new output does not move the text under the pointer; past
that, the **mounting** must hold:

- **Tail-first mounting (CHD-327 D) unmounts selected text.** At the
  bottom, following, a selection over `Read(step-148.ts)`, then a second
  `steps` turn of 150 entries: the entry left the 40-entry tail and
  unmounted; `getSelectedText()` became `""` while `getSelection()` was
  still non-null and `hasSelection` true (*ran*). With auto-copy that is
  harmless (the copy happened on release); with a copy key it copies
  nothing, silently.
- **Proposal (the lead's lifecycle):** `src/ui/transcript/mount.ts` takes
  one more input, "a non-empty selection is held", and while it is true it
  keeps the window's first entry where it was when the hold began, as it
  already does while scrolled back, whether or not the view follows. New
  output then mounts below; nothing above unmounts. The flag clears when
  the selection does; the window then goes back to the tail as it does at
  the bottom today. This is opencode's rule, which CHD-327 D noted. It is
  pure and tested in `tests/ui/transcript/mount_test.ts`. Prototyped and
  measured in §7, with its cost.
- **Culling (CHD-327 A) loses nothing.** Four pgup with a selection held:
  its text still read whole, the entry still mounted; back with End, the
  highlight was on the same characters (*ran*). The native scene skips
  painting, not the text buffers.
- **Other unmounts clear the selection rather than hold it:** a tab
  switch (only the front session is mounted), `ctrl+x w`'s pick, `/clear`,
  `/resume`, opening or closing a long-lived child's view, and a resize
  (the texts rewrap; OpenTUI refreshes local selections on a text's
  `updateTextInfo`, but cell-anchored ranges over rewrapped text select
  different characters). Each calls `renderer.clearSelection()`. That is
  interface's list of when the highlight goes; the runtime point is that
  each of these unmounts or rewraps, so keeping the selection is not an
  option for them.

### Things already clearing it (*ran*)

Typing a character into the prompt cleared the transcript's selection:
OpenTUI's edit buffer calls the renderer's `clearSelection()` on every
edit and every cursor move (`setCursor`, the arrow and word moves),
whatever is selected. So with `copyOnSelect` off, a selection lives only
until the next keystroke that edits the draft or moves its cursor; the copy
key must reach chord before the textarea (`usePress` already runs
listeners before the textarea). A click elsewhere also left nothing
selected. A key that edits nothing (pgup) kept it. How chord sees each of
these is §3.


## 3. The lifecycle, through public API (critic #1)

What the lead merges: OpenTUI's selection model as it is; while the left
button is down the view stops following; a wheel step during a held drag
scrolls and calls `requestSelectionUpdate()`; after release the selection
stays until cleared; the mount window is held while a non-empty selection
exists; plain scrolling keeps the selection.

### What OpenTUI tells, and when (*ran*)

A probe in the scratch tree logged, in order, each `onMouse` event the
window's outer box hears (OpenTUI bubbles every press, drag and release
there), the renderer's `selection` event (`useSelectionHandler`), each
`frame` event on which the selection's state changed (`CliRenderEvents.FRAME`,
public), and the textarea's `onContentChange`, each with
`renderer.getSelection()` as it stood. Excerpts from
`spike-runtime-lifecycle.txt`:

```text
== press on a text
mouse down b0 at 4,12 target=TextRenderable2 | start,dragging:""
frame event: selection none -> empty
== motion x3
mouse drag b0 at 8,12 … | dragging:"5. Li"
mouse drag b0 at 20,14 … | dragging:"5. Line 25 … 27. Line 27 of 200"
== release
mouse up b0 at 20,14 … | dragging:"5. Line 25 … 27. Line 27 of 200"
selection event | done:"5. Line 25 … 27. Line 27 of 200"
== empty click on a text
mouse down b0 at 30,12 … | start,dragging:""
mouse up b0 at 30,12 … | start,dragging:""
selection event | start,done:""
== a press on the gutter (a box, not a text), with a selection
mouse down b0 at 0,12 target=BoxRenderable2 | done:"5. Line 25 … 26. Line 26 o"
frame event: selection text -> none
mouse up b0 at 0,12 target=BoxRenderable2 | none(has=false)
== type a character, with a selection
textarea content change | done:"5. Line 25 … 26. Line 26 o"
frame event: selection text -> none
== pgup, with a selection
   (after pgup: done:"5. Line 25 … 26. Line 26 o")
```

What that settles:

- **A press that starts a selection is seen at once.** OpenTUI calls
  `startSelection` before it dispatches the press, so chord's `onMouse`
  `down` already reads `getSelection()` with `isStart` and `isDragging`
  true and an empty text.
- **The release is two steps:** the `up` event first, with the selection
  still `isDragging`, then the `selection` event with it done. The
  `selection` event is the one place the finished text is read.
- **An empty click is a selection too:** `selection` fires with `""`,
  `isStart` still true, and the `Selection` stays non-null
  (`hasSelection` true) until the next press. It selects nothing visible.
- **A press elsewhere clears after chord's handler.** OpenTUI clears the
  selection after dispatching a press that started none (unless a handler
  called `preventDefault`, which chord does not), so chord's `down`
  handler still sees the old one. The `up` and the next `frame` see none.
- **A textarea edit or cursor move clears after `onContentChange`.** The
  textarea's change event fires with the selection still there; the clear
  comes after, and no event says so. The next `frame` sees none.
- **No event says "cleared".** There is none on `clearSelection`, on
  start, or on a renderable destroyed. The only public points after
  OpenTUI's own clears are the next `frame` event, the next mouse event,
  and a read of `renderer.getSelection()` at any later moment.

### The transitions, their owners and their hooks

chord keeps, for the front session, one value in its state (interface's
slice; the name is theirs): `selection: 'none' | 'dragging' | 'held'`, and
beside it while dragging `wasFollowing: boolean` and `moved: boolean`.
`selection.ts` (pure, §8) maps each observed fact to actions; the hook
that observes is one function in `src/ui/app/terminal.ts`.

| Transition | Who does it | Public hook chord observes | What chord does |
| --- | --- | --- | --- |
| Press on a selectable text | OpenTUI (`startSelection`) | `onMouse` `down`, button 0, with `getSelection()?.isStart && isDragging` | `selection_started`: records `wasFollowing = scroll.following`, `moved = false`; if following, the view is held where it is (scrolled back at the bottom's top), so new output stops moving it. `selection: 'dragging'`. |
| Motion while down | OpenTUI (`updateSelection`) | `onMouse` `drag` | Nothing; no action per report. |
| Wheel step while down | chord (`onWheel`) | `onMouseScroll` | The step as today, `moved = true`; after `layout.ts` sets the new offset in the frame, `renderer.requestSelectionUpdate()` while `getSelection()?.isDragging`. |
| pgup, shift+↑ and the other scroll keys while down | chord | `usePress` | As the wheel. |
| Release | OpenTUI (`finishSelection`) | the renderer's `selection` event | `text = getSelectedText()`. Non-empty: `selection: 'held'` (the mount window holds, §7), the copy if `copyOnSelect` (§6), and the view follows again if `wasFollowing && !moved`. Empty: `selection: 'none'`, no copy, no hold, the same rule for following. |
| Empty click | OpenTUI (a selection with no motion) | the `selection` event with `""` | As an empty release. The empty `Selection` OpenTUI keeps is left to it; it draws nothing and the next press replaces it. |
| Press elsewhere (box, gutter, prompt, border) | OpenTUI, after chord's handler | the next `frame` event: `!renderer.hasSelection` while chord says `held` | `selection_gone`: `selection: 'none'`, the mount hold ends. |
| Textarea edit or cursor move | OpenTUI's edit buffer | the next `frame` event, as above | `selection_gone`. |
| Entry unmount | chord (`mount.ts`) | — | Cannot happen to a held selection: the hold keeps it mounted. An unheld one is empty. |
| Tab change, `ctrl+x w`'s pick, `/clear`, `/resume`'s pick, a child's view picked, a resize | chord | chord's own action | `renderer.clearSelection()` first, then `selection_gone` in the same step, so nothing waits on a frame. |
| Quit, a signal, a crash | chord (`leave`, `giveBack`) | the renderer's `destroy` event | The copies are disposed (§6); no state is kept. |

The **frame watcher** is one listener on `renderer.on('frame')` that reads
`renderer.hasSelection` (a field, no walk) only while chord's state says
`held` or `dragging`, and dispatches `selection_gone` when it turns false.
It dispatches nothing on other frames. A selection that becomes empty
without being cleared (its texts gone) cannot happen while it is held.

**Following, recorded and restored.** `wasFollowing` is taken at the
press that started the selection, before chord holds the view. The view is
held as "scrolled back" at the bottom's own top, which `scroll.ts` already
draws as the bottom with no rule moving. On release, the view follows
again only if it followed at the press and nothing moved it during the
drag (`moved`, set by a wheel step or a scroll key); then any output that
came during the drag shows at once. If the person scrolled during the
drag, the view stays where they left it, as any scroll does. The mount
hold is separate: it starts at the release with a non-empty text, whether
the view follows or not, and ends with `selection_gone`.

### What public API cannot observe, plainly

1. **OpenTUI's own clears are seen a frame late**, through the `frame`
   event: a press elsewhere, and a textarea edit or cursor move. Every
   clear OpenTUI makes requests a frame (each text told of the change
   asks for one), so the frame comes; until it does, the mount window
   stays held one frame longer. Nothing reads a stale selection meanwhile
   except the copy key, which reads `getSelection()` itself at the press.
   Not seeing it sooner would need a hook OpenTUI does not offer (an
   event on `clearSelection`) or wrapping its method, which the lead
   ruled out. An owner question only if one frame of extra hold matters;
   recommended: it does not.
2. **Content changing under a held selection** has no event at all (§4).
3. **Which entries a selection covers** is not said in chord's terms:
   `Selection.selectedRenderables` is public, but they are OpenTUI
   renderables, not transcript entries. Nothing in this design needs the
   entries.

### The proof (*ran*)

`spike-runtime-lifecycle.txt` is the window test that drove all of the
above with the copy a stub: six releases with text made six copies with
the text highlighted, the empty click made none, the clears by a press
elsewhere, a typed character, `/clear` and a new tab each turned up as a
`frame` event with `text -> none`, and pgup kept the selection. The same
test, with assertions in place of the log, is the ship team's
`tests/ui/app/App_test.tsx` case "the selection's lifecycle".

## 4. Content changing under a selection (critic #3)

*ran*, `spike-runtime-mutations.txt`; "lit" is the cells painted in
OpenTUI's selection colour, read from the frame. `rewrap` and `boxlater`
are scratch-only fake scenarios.

| Case | What happened |
| --- | --- |
| A reply rewraps as it grows (`rewrap`: `supercal` fits, then `ifragilisticexpialidocious` makes the word too long for the row, so it moves down) | Selected over two rows, released: `"… while it streams supercal"`. After the word moved: the same cells, now `"… while it streams"`; the highlight did not follow the word. |
| A table widens as a row comes (held, button down) | Before: `│ 1  │ 2  │`. After, no motion: the same cells, now `│ 1                         ` (the `2` is out of the cells); a motion and release did not bring it back, as the focus cell had not moved. |
| A tool's output grows and folds (`shell`) | Released over `Task test deno test`; after the output ran on and folded to its latest lines: the same row, now `3/3`. |
| A plan rewritten (`proposal`) | `1. Read the code` became `1. Inspect the code` under the same highlight; when the draft plan was removed, the highlight stood on `file:///plans/proposal.md`, the entry drawn in its place. |
| A permission box takes rows, released selection (`boxlater`) | The reply moved from row 7 to row 5; the highlight moved with it; the text unchanged. |
| A permission box takes rows, held drag | The text unchanged until the next motion, which re-read the focus at the same screen cell, now over other text, and extended to it. |
| The agents list takes rows | Not run: its scenario needs chord's MCP server in the window test. It is the same layout change as the permission box (a box below the transcript grows), so the same outcome is expected. |

So: OpenTUI keeps a selection as cell ranges in each text. A layout move
carries the highlight with its text; a change of the text inside its own
renderable keeps the cells and changes what they hold; a renderable that
React reuses for other content carries the highlight onto that content.

**Proposed outcome, rewriting no library input:**

- **What is copied is what is highlighted at the moment of the copy.**
  Auto-copy reads `getSelectedText()` in the `selection` event, at the
  release, which is what the person sees then. The copy key reads it at
  the key press, which is what the person sees then, even when the content
  moved under it since the release.
- **The view's own moves cannot change the selection while the button is
  down**: following stops at the press (§3). What remains is content
  changing inside a selected entry while the person holds or before a
  manual copy, which only the agent's output causes.
- **chord does not rewrite or re-anchor the selection** on a reducer
  change, and does not clear it either: clearing on "an entry under the
  selection changed" would need entries mapped from
  `selectedRenderables` and would fire on every streamed chunk under a
  selection, which is most of the time a selection is held while a turn
  runs.
- **A snapshot is the owner's** (Owner question 7): chord could keep the
  text read at the release and have the copy key copy that, so a
  highlight that has since shifted is not what is copied; the cost is that
  the highlight and the copied text can then disagree.

The plan entry that took the removed one's renderable is worth a look by
interface: the highlight landing on another entry means React reused the
renderable across entries (a key by position), which no selection rule
can fix.

## 5. The copy: failure modes, timeouts, frames (critic #4)

The first round's host-failure, timeout and hang lines ran on a renderer
written to a custom stdout, which OpenTUI makes **remote**
(`remote: config.remote ?? (!usesProcessStdout && !memoryBufferedOutput ? true : undefined)`),
so `best-available` never tried the host. They are re-run here with
`createClipboard` on an **explicitly local** terminal adapter
(`remote: false`, recording each OSC 52 instead of writing it) and a stub
host, `spike-runtime-copy.txt`:

```text
local, host written:            host=written     terminal=not-attempted   OSC 52 fallback 0
local, host failed:             host=failed      terminal=attempted       OSC 52 fallback 1
local, host unsupported:        host=unsupported terminal=attempted       OSC 52 fallback 1
local, host timed-out:          host=timed-out   terminal=not-attempted   OSC 52 fallback 0
local, host hang-honours-abort: host=cancelled   terminal=not-attempted   after 301 ms (abort at 300)
local, host hang-ignores-abort: still pending at 1000 ms (abort at 300 ms did not settle it)
   dispose: still pending at 1000 ms
superseded (first aborted at once, host ignoring the signal for 200 ms):
   first host=written, second host=written
pending at dispose (host honours abort): dispose 0 ms; the write settled host=cancelled
   a write after dispose rejects: Clipboard service is disposed
remote adapter, for contrast: host=not-attempted terminal=attempted
```

**Where the timeout is set.** `timeoutMs` is `createHostClipboard`'s
option (`HostClipboardOptions.timeoutMs`, default 1,000 ms), read once
into its config and passed to the native backend on every read, write and
clear. A write takes no timeout of its own (`ClipboardWriteOptions` has
`destination`, `selection`, `allowRemoteHost` and `signal`), and
`createClipboard` adds none. The native host's own timing out was read in
the source, not run: running it means the real clipboard.

| Case | What happens | Status line |
| --- | --- | --- |
| Local, host write works | `host: written` (*ran*, stub) | `copied N chars to clipboard` |
| Host `failed` or `unsupported` (no provider on Linux, no display) | OSC 52 written as the fallback, `terminal: attempted` (*ran*, local adapter, stub host) | `copied N chars`; OSC 52 cannot confirm (protocol's question whether to soften it) |
| Host `timed-out` | No OSC 52: `best-available` falls back only on `failed` or `unsupported` (*ran*) | `couldn't copy: the clipboard did not answer` |
| Host honouring the abort chord sends | `cancelled`, no OSC 52 (*ran*) | nothing (a superseded copy) |
| Host ignoring the abort | The write never settles, and `dispose()` never settles (*ran*, stub) | chord's own bound (§6) |
| Remote (SSH, or any renderer on a custom stdout) | Host not attempted, OSC 52 only (*ran*) | `copied N chars` |
| tmux without `allow-passthrough` | OSC 52 dropped by tmux, unknowable (protocol) | `copied N chars`, wrong and unknowable |
| Text over the host's `maxWriteBytes` (8 MiB default) | `writeText` rejects `RangeError` before anything is written (*ran*) | `couldn't copy: selection too large` |
| Empty text, or NUL in it | Rejects `TypeError` (*ran*) | nothing: an empty selection never reaches the copy |
| Large text over OSC 52 | No cap: 1,000,000 chars → one 1.33 MB escape (*ran*, renderer on a fake stdout) | as sent |
| `pbcopy` missing (Linux) | Not used: the host clipboard is native in `libopentui`, which the binary embeds and loads to draw at all | — |
| The renderer destroyed mid-copy | chord's copies are disposed at `destroy` (§6); an OSC 52 after it throws inside the service, which chord's bound and generation drop | none |

Never on the frame's path: the `selection` handler reads the text
(bounded by what is mounted), starts the write and returns; the note comes
from the promise through the reducer later. OSC 52 goes through the native
session's queue between frames.

## 6. The clipboard service: one owner, one sequence (critic #7)

**One owner: `main.tsx`**, which already builds what the window is handed
from the renderer (`openTerminal`), and is where every way out passes.

1. **Build**, after `openTerminal` returns the renderer and before
   `render`: `createClipboard({ host: createHostClipboard({ timeoutMs:
   COPY_TIMEOUT_MS }), terminal: createRendererClipboardAdapter(renderer) })`.
   `COPY_TIMEOUT_MS` is chord's own named constant, 1,000 ms (OpenTUI's
   default, now said in chord's code).
2. **Configure**: `copy(text, signal)` calls `writeText(text, {
   destination: 'best-available', signal })` and maps the result to
   chord's `CopyResult` (`selection.ts`, pure). The prop goes to `App`;
   under `"mouse": false` it still goes (the copy key finds nothing).
3. **Use** (`terminal.ts`'s hook): one copy at a time. A new copy aborts
   the one in flight and bumps a generation number; a result is noted only
   when it belongs to the latest generation, arrives within chord's bound,
   and the window is not closing. The bound is `COPY_TIMEOUT_MS + 200`
   ms: the native host's own timeout normally answers first, with
   `timed-out`, and the bound is for a host or a fake that never settles,
   which then reads as timed out. Whatever settles after the bound or for
   an older generation is dropped.
4. **Dispose**, on the renderer's `destroy` event, which every way out
   reaches (`render`'s quit, and `leave` for a signal or a crash): bump the
   generation, abort the copy in flight, and call `clipboard.dispose()`
   without awaiting it beyond `DISPOSE_MS` (100 ms, `Promise.race`).
   **Quit does not wait for a copy.** It is not owned through
   `closeOnForcedExit`, which waits without a bound of its own; a host
   that ignores abort would hold the exit for ever (*ran*: `dispose()`
   never settled). A write abandoned at exit leaves the clipboard as it
   was or with the new text, never part of it.

**The injected fake's contract.** Tests pass `copy` directly. It may
resolve, reject, resolve late or never; it may ignore the signal. chord's
bound and generation make each of those safe, so the contract asks
nothing of the fake, and the native host's timeout is not chord's
correctness: it only decides whether the note says `timed-out` or chord's
bound says it.

**Tests** (*ran* in the scratch tree as `spike-runtime-copy.txt`'s window
lines; the ship team's in `tests/ui/app/App_test.tsx`):

- *A copy superseded by another*: the first copy's stub answers after
  400 ms, the second's after 50 ms; only `copied 23` is noted, and the
  first's `written` is dropped as an older generation.
- *A late result*: the stub answers after 2,000 ms; at 1.4 s the bound has
  noted the failure, and at 2.4 s the late `written` was dropped, the note
  unchanged.
- *A copy pending at quit*: the stub never settles and ignores the abort;
  the window's teardown (unmount, agent stopped, its processes proven
  gone) took 34 ms, the `destroy` disposed the copies, and 1.5 s later no
  note had come.

## 7. A selection held while the transcript grows (critic #8)

*ran*, `spike-runtime-growth.txt`, 120×40: a selection made on the first
line of `manysteps` (a scratch scenario: a line, a 1.5 s pause, then 600
tool calls), released, kept; renderables counted from the renderer's root,
the JS heap after a full GC (`bun:jsc`'s `heapStats`), frames from
OpenTUI's own stats over each interval.

| | renderables | JS heap | frames p95 | selected text |
| --- | --- | --- | --- | --- |
| at release | 43 | 25.4 MB | — | `Select me while th` |
| tail only (today), +150 entries | 261 | 31.3 MB | 4.8 ms | `""` (unmounted) |
| tail only, +300 | 261 | 32.4 MB | 1.1 ms | `""` |
| tail only, +600 | 257 | 34.4 MB | 3.1 ms | `""` |
| held, +150 | 1,153 | 37.6 MB | 3.7 ms | kept |
| held, +300 | 2,065 | 43.0 MB | 20.3 ms | kept |
| held, +600 | 3,645 | 58.3 MB | 8.4 ms | kept |

Each held entry costs about six renderables and 50 KB of JS heap, with
Yoga laying out all of them on every change. CHD-327 D measured 6,628
renderables at 50 ms frames while streaming; a held selection reaches that
after about 1,100 entries. **The trade-off, plainly:** a held selection
is kept by keeping everything that came after it mounted, so its cost
grows with the output that follows it, without a limit, until the
selection is cleared. Unheld (today's tail), the selection is lost the
moment its entry leaves the tail. A cap between the two is a choice of
how much output a selection survives (Owner question 8).

## 8. Module layout (critic #10)

The lead's proposal, agreed, with one addition:

- `src/ui/app/selection.ts` — **pure**, owned with interface: the observed
  facts (§3's table) to actions, the state it keeps, the following rule,
  the copy's result to the note (`CopyResult` and its mapping from
  OpenTUI's `ClipboardWriteResult` or a rejection), the character count,
  the generation and bound rules as pure functions. Tested in
  `tests/ui/app/selection_test.ts`. There is no `copy.ts`.
- **The copy is one `App` prop**, `copy(text, signal) => Promise<CopyResult>`.
  The addition is the `AbortSignal`: superseding and disposal abort the
  native host's work rather than leaving it to run, though chord's
  correctness does not depend on the signal being honoured (§6).
- `main.tsx` builds and configures it and disposes it on the renderer's
  `destroy`, as §6 orders. `renderer.tsx` is unchanged but for
  `enableMouseMovement` if the owner drops 1003.
- `src/ui/app/terminal.ts` — the one hook that listens: `onMouse`'s press
  (through `useMouse`, which hands chord's handler the bubbled events as
  today), `useSelectionHandler`, the `frame` watcher, the `destroy`
  listener; it dispatches what `selection.ts` says and runs the copy.
- `src/ui/app/layout.ts` — `requestSelectionUpdate()` after its own move
  of the view while dragging.
- `src/ui/transcript/mount.ts` — the held window's input.
- `src/ui/app/drag.ts`'s `pointed` and `selectHint` go, with the
  `drag:hint` timer.
- `src/platform/` — nothing: no `Bun.*`, no native code of chord's.

## 9. Test plan

**Never the real clipboard.** Window tests get the copy only through the
`copy` prop. No test calls `createHostClipboard()`: `testRender`'s
memory-buffered renderer is not remote, so a `best-available` write from
it would reach the host (read from the source, not run). The one test of
the real wiring builds `createClipboard` with a stub `host` and either a
`Logged` terminal's renderer (remote, OSC 52 in its log) or a recording
adapter with `remote: false` (the fallback), as `spike-runtime-copy.txt`
did. A guard test failing on `createHostClipboard` or `pbcopy` under
`tests/` is Owner question 6.

**Driving and reading**, as the first round found: raw SGR reports through
the harness's `write` (`App_test.tsx`'s `left`), a report per row for a
drag across entries (the container climbs a level a report), presses more
than 400 ms or a cell apart unless a double or triple click is meant,
`selected()` for the text and the frame with `chalk.level` raised for the
highlight.

**Tests by layer:**

- Pure: `selection_test.ts` (each transition of §3's table; the following
  rule with and without `moved`; an empty release; each `CopyResult` to
  its note; generation and bound), `mount_test.ts` (the held window while
  following and scrolled back; back to the tail when it ends),
  `bindings`/`keys_test.tsx` for the copy key (interface's).
- Window, on the fake agent:
  - the lifecycle (§3): press, motion, release copies once; an empty click
    copies nothing; a press elsewhere, a typed character, `/clear`, a tab
    switch and a resize each clear (`selected()` empty, the hold ended);
    pgup keeps it;
  - following stops at the press and comes back at the release; a wheel
    step during the drag keeps the view where it went, and `selected()`
    already reaches the pointer's cell without a motion;
  - a held selection over `steps` then 150 more entries: `mounted()` and
    `selected()` unchanged; cleared, the tail returns;
  - the copy: superseded, late, pending at quit (§6); each failure's note;
  - `copyOnSelect` off: no copy on release; the copy key copies what is
    highlighted at the press;
  - `mouse: false`: no modes, the copy key finds nothing.
- The real wiring, once (above). The modes, once, on a `Logged` terminal.

**Fake agent:** `text`, `long`, `steps`, `shell`, `proposal` and
`permission` cover the cases. Pinning §4's outcomes needs two small
scenarios, as the scratch ones were: a reply whose last word wraps once it
grows (`rewrap`), and a permission asked after a pause, so a selection can
stand while the box comes up without a key typed (`boxlater`); and §7's
measure needs a turn that waits before its many calls (`manysteps`, or
`steps` with a pause first). Recommended only where the ship team pins
those outcomes in tests.

## 10. Cost

- **`selectable: true` on every text costs nothing per frame** (*ran*:
  0.90 vs 1.09 ms at 400 texts). It only makes the text a target of the
  walk on mouse reports.
- **Hover reports (1003):** about 15 µs a report, no frame (*ran*).
- **A selecting drag:** about 100 µs a report and a frame per change
  (*ran*).
- **The frame watcher:** one field read per frame, only while a selection
  is held or being dragged.
- **A held selection:** §7.

## Concurrency and failure scenarios, with expected outcomes

| Scenario | Expected |
| --- | --- |
| Drag while a turn streams, following | Following stops at the press; the text under the pointer stays; release copies what is highlighted; the view follows again unless the person scrolled. |
| Content of a selected entry changes (a rewrap, a fold, a plan rewrite) | The highlight keeps its cells; the copy takes what they hold at the copy (§4). |
| Release while a previous copy is in flight | The first is aborted, its late result dropped; one note, the latest. |
| A copy that never settles | chord's bound notes a failure; a later result is dropped. |
| Release, then quit at once | Quit does not wait; the copies are disposed at `destroy` within 100 ms or abandoned. |
| A signal or crash during a copy | As a quit, through `leave`. |
| Selection held, the person types or moves the cursor | OpenTUI clears it; chord sees it at the next frame and ends the hold. |
| Selection held, a tab switch, `/clear`, a resize | chord clears it first, then acts. |
| Selection held across a long run of output | Mounted entries grow with the output (§7) until it is cleared or the owner's cap. |
| `mouse: false` | No modes, no selection, the copy key finds nothing. |

## Owner questions

1. **1003 (hover motion), on today by OpenTUI's default.**
   - a. Keep it: no change; about 15 µs a report as the pointer crosses
     the window, unused.
   - b. Turn it off with `enableMouseMovement: false`: 1000 + 1002 + 1006,
     what drag selection and the wheel need; one documented option.
   - Recommendation: **b**.
2. *(Following while the button is down: decided in the lead's merge,
   following stops at the press; withdrawn.)*
3. **A drag held at the view's top or bottom edge.**
   - a. Nothing scrolls; the wheel while holding extends a selection
     beyond the view (works).
   - b. chord scrolls a line per tick while the pointer is held on the
     edge row, and calls `requestSelectionUpdate()`: chord's own code for
     what OpenTUI's scrollbox does, around a widget chord declined.
   - c. Move the transcript onto `<scrollbox>` for its autoscroll,
     reopening "OpenTUI part 4"; not recommended.
   - Recommendation: **a** for this task, b as a follow-up if wanted.
4. **OSC 52's size.**
   - a. Send whatever is selected, up to the service's 8 MiB.
   - b. A cap of chord's own for OSC 52, the note saying the selection was
     too large to copy over the terminal.
   - Recommendation: **a**.
5. **A host clipboard that times out.**
   - a. OpenTUI's rule: no OSC 52 after a timeout; the note says the copy
     failed.
   - b. chord writes OSC 52 itself after a timed-out host write, a
     fallback OpenTUI chose not to make.
   - Recommendation: **a**.
6. **A guard against the real clipboard in tests.**
   - a. Convention: the copy is a prop, tests stub it.
   - b. Also a test failing on `createHostClipboard` or `pbcopy` under
     `tests/`.
   - Recommendation: **b**.
7. **What the copy key copies when the content changed under the
   highlight since the release (§4).**
   - a. What is highlighted at the key press, as OpenTUI reads it.
   - b. A snapshot of the text read at the release, kept by chord; the
     highlight may by then cover other characters.
   - Recommendation: **a**: the copy matches what the person sees, and
     auto-copy, the default, already copies at the release.
8. **How much output a held selection survives (§7).**
   - a. No limit: everything after it stays mounted until it is cleared.
   - b. A cap: past a number of entries mounted beyond the tail (for
     example 200, about 1,200 renderables), chord clears the selection and
     lets the window go back to the tail; with auto-copy the text was
     already copied, with `copyOnSelect` off it is lost.
   - c. No hold after the release: only while the button is down; a kept
     selection's text may unmount, and the copy key then copies nothing.
   - Recommendation: **b**, with the number measured by the ship team
     against CHD-327 D's frames.
9. **OpenTUI's own clears seen a frame late (§3).**
   - a. Accept: the hold ends one frame later than the clear.
   - b. Ask OpenTUI upstream for an event on `clearSelection`.
   - Recommendation: **a**, and b as an upstream issue at no cost to this
     task.

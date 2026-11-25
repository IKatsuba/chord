# CTUI-48 runtime draft

## Authority and present evidence

Read the brief, repository guidance, README, feature map, decisions and the
relevant scrolling, overlay, rich-text, terminal-services and cursor designs.
Current original inspected at `577b58167672e12c999aeaf4eed2a1a988513dc2`:
`../chord/src/ui/app/selection.ts`, `terminal.ts` useSelection,
`state.ts`, `timers.ts`, `layout.ts`, `App.tsx`,
`../chord/src/ui/transcript/scroll.ts`, `code_pick.ts`, and CHD-172/394
and their selection tests. This draft records source findings and proposed
acceptance; it does not claim a live capture, executed benchmark or AOT run.
The interface draft owns original/current-port captures at both required sizes.

The original stops bottom following during a drag, including when all content
fits. It reprojects the focus screen cell after scrolling has actually laid
out, not before. On release it resumes following only when the press found it
following and no scroll action occurred. Releasing a hold on fitting content
also restores the ordinary fitting-content follow rule. After release the
selection is source-local: later output/following must not extend its range.

The original's retained mount window is not the port's memory contract.
CTUI-1 already deliberately bounds mounted list states to visible items.
Selection retains logical source data, not invisible widget/render trees.

## Build units and source/test layout

These are proposed module boundaries; framework draft settles public names.
Every source module has a matching test path beneath its package's test tree.

| Unit | Logic and location | Failing acceptance before implementation |
| --- | --- | --- |
| R1 | Framework `foundation/selection.dart`: immutable source positions/ranges, phase and drag reduction; `text/selection_source.dart`: semantic extraction using existing text/Markdown/Code/Diff machinery | Cross-source reverse drag and wrapped Unicode selection produce exact text without furniture; a replacement source never inherits a removed source's range |
| R2 | Framework `foundation/scroll_state.dart`, `widgets/scroll_controller.dart`: held state and hold/release; rendering selection geometry in the existing layout/paint pipeline | Fit-to-overflow while pressed stays anchored; scroll then release in one input batch copies the newly laid-out range |
| R3 | Framework `widgets/selection_area.dart`, pointer parser/dispatch and terminal ownership: capture, cancellation, 1002 motion, finalization | Release outside initiating child is delivered once; cancellation never auto-copies; no motion/edge timer scrolls |
| R4 | Framework list selection delegate/provider and rich-text source binding; existing list viewport keeps normal disposal | A selection spanning unmounted entries still copies; mounted state count remains bounded by visibility during a long flood |
| R5 | Port `ui/app/selection.dart`: pure lifecycle and result mapping; `ui/app/copies.dart`: generation, adapter and clock coordination; app state/keys/window/timers integrate | Release-copy retains highlight, Ctrl+C success clears, failure retries, stale completion/timer cannot affect a later selection |
| R6 | Port `ui/transcript/code_pick.dart`: pure catalog/order/navigation; transcript rendering binds framework code action registry | Old offscreen closed block is reached without keeping old widgets alive; open fence never becomes a target until closed |
| R7 | Framework fixture plus port fake-window and compiled fake session coverage | Both required sizes, no real agent/model/clipboard, bounded cleanup and retained evidence |

Keep ACP/session process ownership unchanged. No parsing worker, process,
background timer or stream subscription is created per selectable leaf.
No isolates are justified without measured blocking; all selection positions
and ordering are synchronous. A future expensive worker would need immutable
input and source-revision cancellation, and requires a separate design.

## Event and frame order

1. A primary down on eligible, painted text establishes capture and a new
   selection epoch before callbacks. Record following and clear the previous
   copy note. Hold the relevant scroll controller synchronously. A down on a
   button uses that button's capture instead of starting text selection.
2. Drag motion records the latest pointer cell and requests a frame. Many
   motions/stream chunks may coalesce into one frame; semantic down/up/cancel,
   wheel steps and keys retain dispatch order. Wheel reports are not motion.
3. Explicit wheel/scroll keys mark `moved` even at a clamped boundary. Existing
   child wheel absorption stays in force; a consumed body scroll does not also
   scroll the transcript. Mark the drag moved when an actual routed scroll
   action occurs, not when a frame merely changes measured extents.
4. Build and layout settle using the existing bounded two-pass host sequence.
   After scroll translation, clipping, width and source revisions are current,
   reproject the captured focus cell and update range/paint. Do not read the
   old geometry between the press's hold and its first settled layout.
   Listener notification remains outside layout. A reentrant mutation queues
   through existing controller notification discipline; it does not recurse.
5. Up finalizes exactly once against current geometry. If a prior scroll or
   source mutation has invalidated geometry without a frame, flush the existing
   bounded layout/selection projection before taking the copy snapshot; do
   not finalize against yesterday's geometry or turn a pending up into motion.
   Snapshot text before releasing hold/resuming bottom follow. Empty selection
   is a click and starts no copy.
6. Release capture/hold before emitting external finalized callbacks. Callback
   disposal, a new drag, or source changes cannot cause a second release.
   Cancellation, missing capture owner or removed area clears without copying.
7. Shown selections retain source-local ranges. Scroll/output after release
   changes their painted locations only; it never reruns pointer hit testing
   to expand selection. Resize is the port's explicit clear before rewrap.

**No edge autoscroll:** motion at or beyond any viewport edge changes no
scroll offset and schedules no timer or repeated scroll work. Holding the
pointer still produces no recurring selection frame. Only explicit existing
scroll inputs move the view and extend a drag under the stationary focus
cell. No velocity, threshold, dwell delay, acceleration or reveal-on-motion.
Out-of-surface hit policy must use the framework draft's single clipped
source-position rule; it must never target clipped furniture or an overlay
through a hidden underlying text cell. Terminal silence/missing release
cannot be repaired by inventing a release timeout: explicit clear, ownership
loss and teardown cancel capture.

## Logical source lifetime and performance

The framework provider owns ordered stable source IDs, current revisions and
semantic source/range resolution. Mounted leaves register current geometry
only. A ListView delegate can resolve the same source for selection and normal
rendering; the port must not reimplement Markdown extraction. Resolve crossed
items on demand, retaining references needed by the active range until clear.
Virtual unmount removes geometry, not the identity/readability of a selected
logical source. Genuine source removal clears its range. If no selected text
survives, clear the selection and its hint; Ctrl+C resumes its ordinary meaning.

Existing local offsets survive same-source content updates, clamped to current
valid grapheme boundaries. Copy snapshots current selected text, not text
frozen at down. Appending after a finalized endpoint does not extend it.
Stable identity prevents deleting a selected plan row from transferring its
selection to its successor. Revision checks reject stale geometry/work; they
must not clear a selection on every streamed chunk. Source removal and mere
virtual unmount need distinct notifications. Arbitrary semantic replacement
must receive a new identity rather than pretending to be a streamed revision.

A logical selection can span all retained transcript text; its source/range
metadata may consequently scale with that selected text. It must not keep a
second transcript copy, every prior source revision, an unbounded parsed cache,
or any offscreen State/Element/render object. The transcript itself already
retains session data. Clear, session close and area disposal release selection
references. Code catalogs cache only current descriptors by stable entry
identity/revision and discard removed entries. Closed assistant/message code
blocks are listed even when unmounted; drawn-only tool/plan blocks are eligible
only with current visible geometry. Preserve original ordering and clamped
navigation, newest visible first or newest listed when none is visible.

Measure no-selection and held/shown-selection runs with 600 and 10,000 entries,
including one thousand updates before a frame. Report mounted counts, retained
source/range counts, builder calls, parse calls and frame timings separately.
An unchanged pointer frame must not parse or flatten the whole transcript.
Source extraction can be proportional to crossed sources; copying is linear
in selected text. Never flatten all selectable text on each paint or hover.
Resize retains CTUI-1's existing full measurement cost, not a new promise of
constant-time resize. Clear must return mounted counts and source references
to the baseline, without waiting for a copy future.

## Copy coordinator, notes and terminal ownership

One window-scoped coordinator serves both selection and code copies. The
production adapter calls the existing synchronous `Terminal.copyToClipboard`.
A completed call means only OSC 52 was sent; use `sent N chars to the terminal's
clipboard`, never host acknowledgement. Count with existing `characters`, not
UTF-16 units. Keep terminal escape construction/tmux forwarding behind Terminal.
Do not add a host command, clipboard reader, capability guess or new package.

The port preflights UTF-8 size against the original service's 8 MiB bound before
any write and maps oversize to `too large to copy`. This is port policy, not a
new generic Terminal limit. Production write throws become one-line failures.
An injected asynchronous copy adapter permits deterministic timeout testing:
1200 ms is the original application bound (1000 ms host allowance plus 200 ms),
not a delay applied to synchronous OSC 52 success and not an acknowledgement
window. A byte count failure starts no write.

Start captures immutable text, copy origin, session/selection epoch and copy
generation before invoking the adapter, including synchronously throwing or
reentrant adapters. A second Ctrl+C while selection is copying is ignored.
A new accepted code or selection copy supersedes the previous generation.
Only the latest live generation may publish. Selection completion additionally
requires the initiating selection epoch/session still in its copying state.
Clearing and then creating another selection cannot make an old completion
clear or annotate the new one. Code copies use their independent block note
path. This is the original reducer guard made safe against identity reuse.

| Scenario | Expected outcome |
| --- | --- |
| Release, copyOnSelect true | Snapshot, auto-copy, retain highlight on success; success note expires after 3000 ms |
| Release, copyOnSelect false | Show highlight and copy hint; no adapter call |
| Ctrl+C shown | Copy exclusively; no draft clearing, interrupt, quit arming; success clears highlight |
| Selection copy fails/throws/times out | Retain highlight and persistent retry note; next Ctrl+C can retry |
| Code button or pick-mode c | Snapshot raw closed block body, end pick, same coordinator; no selection retry clause; success or failure note expires after 3000 ms |
| Copy cancelled/superseded/disposed | No stale result or note; no unhandled asynchronous error |
| New note before old timer fires | Monotonic note ID rejects old expiry; new highlight is never timer-owned |
| Prefix or scroll key | Keep selection; route original action; a later noncopy/nonprefix/nonscroll key clears first |
| Key/paste, including empty paste | Clear first, then normal editing/action; never replace selected draft text |
| Resize, verbose toggle, clear/session switch, editor handover | Cancel active drag, release hold/capture and clear selection before action; reject old selection completion |
| Shutdown/crash/signal/adapter never settles | Dispose synchronously, increment generation, cancel owned timers/subscriptions, prevent any later terminal write; copy future is never awaited by quit |

The injected adapter cannot be forcibly cancelled by Dart Future. Cancellation
is cooperative plus generation rejection; a never-settling adapter must not
retain timers or selection references after disposal. Clear timeout handles
on settlement/supersession/disposal and settle the caller's wrapper promptly.
Never assume timing out has undone an external write. Delayed adapters must
check ownership before producing terminal effects. Terminal suspension removes
motion mode 1002 along with existing mouse modes; resume re-enables only while
still owned. Closing during suspension cannot re-enable modes on callback exit.
Existing process-group cleanup and bounded shutdown remain the sole port owner.

Main approved copyOnSelect as a default-true constructor seed pending CTUI-29
settings; it is not a new command or agent config option. Main also settled
inverse-only selection in plain mode and the agreed slate colours otherwise.
No `[run]`, r action or related help clause before CTUI-25.

## Deterministic validation and handoff

Pure tests cover range ordering, clipping/Unicode mapping, stable identity,
stream mutation, removal, reducer phases, held-fit transitions, code ordering,
UTF-8 bound, grapheme count, note text and clock IDs. Controlled clocks and
completers cover sync throw, delayed success/failure, timeout, ignored abort,
supersession, clear/new-drag race, clear/new-copy race and disposal. Assert
outstanding timer/subscription counts return to zero; use no real sleep.

Widget/window tests use `package:chorded_tui/testing.dart` and injected copy
recorders. Cover fragmented and concatenated SGR down/motion/wheel/up plus
trailing keys, stationary-pointer scroll and same-batch release, down-to-hold
layout change, wide/combining/emoji ranges, nested clips/overlays, reverse and
cross-entry drags, empty/dropped text, prompt paste ordering, dark/light/plain,
80x24 and 120x40, zero room and resize during drag/copy. No 1003 hover or edge
loop. Test code button press/release elsewhere, hidden narrow buttons still
reachable by keys, open-to-closed fences, navigation across unmounted entries,
and drawn-only targets disappearing while picked. Preserve CTUI-49 extents.

Use scripted/in-memory sessions for precise update ordering and removable plan
sources. Use the original fake through the existing harness for long/flood,
Markdown/code and ongoing stream scenarios where available; if a missing case
needs a new scenario, specify it to the owner without modifying `../chord`.
No real agent, model, clipboard, host reader or forwarded OSC 52 in a live sink.
Compiled PTY checks use a recording terminal/copy adapter and fake child only;
assert 1002 enter/off/resume ordering, actual binary key/mouse dispatch, bounded
exit while a copy is pending and child process-group cleanup. Compile native
framework fixture and port launcher with `dart compile exe`; no mirrors,
runtime code loading, Flutter SDK or new dependency is required.

Run relevant framework/port suites, compile-tag checks and static checks on the
named implementation head. Visual handoff separately compares original fake
and port at both sizes with copy interception, exact scripts and plain/ANSI
captures, recording source commits and cleanup. Source inspection, byte traces,
proposed sketches and physical pointer evidence must be labelled separately.
These are implementation acceptance requirements, not results claimed here.

## Remaining integration questions

Framework draft must settle the exact clipped outside-surface endpoint rule,
source delegate API and final-layout-before-release hook without a third frame
layout loop. The lead must reconcile these public contracts before ship starts.
No remaining product decision is proposed: preserve local source ranges on
same-source mutation, bounded mounted widgets, and no edge autoscroll.

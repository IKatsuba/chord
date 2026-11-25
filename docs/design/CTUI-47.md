# CTUI-47: mouse reports and transcript wheel

Main added this slice after CTUI-9 on the same task branch. Framework
input comes first (U7), then the port's wheel (U8). CTUI-48 owns drag
selection and copy. No hover, pointer capture, gestures or mouse-only
app actions are introduced here. The existing keyboard line-scroll
Actions remain the way to perform the same action without a pointer.

References: original `src/ui/app/input.ts` useMouse, App.tsx wheeled
callback, and state.ts wheeled reducer. Protocol reference:
https://invisible-island.net/xterm/ctlseqs/ctlseqs.html (Mouse Tracking,
SGR 1006). The lead approved normal tracking 1000 plus SGR 1006; movement
reporting waits for CTUI-48.

## Framework shape

```dart
Listener(
  behavior: HitTestBehavior.opaque,
  onPointerSignal: (event) {
    if (event.scrollDelta.y < 0) scroll.lineUp();
    if (event.scrollDelta.y > 0) scroll.lineDown();
  },
  onPointerDown: (event) => recordPress(event.position),
  onPointerUp: (event) => recordRelease(event.position),
  child: const ServicePage(),
);

enum MouseEventKind { wheel, press, release }
enum MouseButton { none, primary, middle, secondary }
enum HitTestBehavior { deferToChild, opaque, translucent }

// An InputEvent; every field is immutable.
MouseEvent(
  MouseEventKind kind, {
  required Offset position,
  MouseButton button = MouseButton.none,
  Offset scrollDelta = Offset.zero,
  bool shift = false,
  bool alt = false,
  bool ctrl = false,
});

Listener({
  Key? key,
  void Function(MouseEvent)? onPointerDown,
  void Function(MouseEvent)? onPointerUp,
  void Function(MouseEvent)? onPointerSignal,
  HitTestBehavior behavior = HitTestBehavior.deferToChild,
  bool absorbPointerSignal = false,
  required Widget child,
});
```

Listener's Flutter names communicate observation of pointer events rather
than focus or key bindings. This framework's MouseEvent carries whole-cell
positions and one-step wheel deltas. No float/pixel abstraction, custom
FocusManager mouse binding catalog or global listener registry is needed.
Event positions are zero-based terminal coordinates. No localPosition or
drag identity is promised in this slice. Down/up dispatch press/release;
signal dispatches wheel only. A wheel is not also a press.

## Parser

SGR input is CSI < button;x;y M (press/wheel) or m (release), with no
X10 offset of 32. Convert positive one-based cell coordinates to Offset.
Button low bits 0/1/2 map primary/middle/secondary. Modifier bits 4/8/16
map Shift/Alt/Ctrl; kitty keyboard modifier bit positions do not apply.
Wheel bit 64 plus low bits 0/1 means up/down: delta (0,-1)/(0,1), one
step per report. No acceleration, row multiplier or prompt-history key.
Horizontal wheel reports may carry (-1,0)/(1,0); the port ignores them.
Release uses the encoded button and lowercase final m. Invalid coordinates,
unsupported buttons, motion and unsupported reports are consumed without
producing keys or text. Keep legacy X10's existing consumed behavior.

Handle every fragmentation boundary and concatenated reports plus trailing
typed text. Recognize mouse before generic CSI keys. Apply U5's bounded
CSI limits; an overlong or malformed mouse candidate must drain safely and
not leave a permanent fragment or turn its digits into prompt text. Define
and test recovery to the following ordinary input. Bracketed paste stays
opaque even if its text resembles a mouse report. No tty is needed for
parser tests.

## Terminal ownership

Enable CSI ? 1000 h and CSI ? 1006 h on enter/resume while the app owns
the terminal. Disable both before suspend/leave on every successful or
failed exit path. Integrate with CTUI-9's acquired-mode bookkeeping so
exceptions and quit during editor suspension cannot re-enable modes late.
A terminal sending no reports retains the full key path. No terminal-name
inference or pointer requirement appears in app startup.

`runApp` adds the optional named parameter `bool handleSignals = true`. With true, standalone framework
apps install their per-run supported-signal handlers as described below.
With false, runApp installs no signal watchers; the embedding app owns its
signal lifecycle. This option does not alter normal key dispatch or raw
Ctrl+C input.

The port already owns `dieBySignal`, including child process-group cleanup,
terminal restoration and crash/exit handling. It passes `handleSignals: false`
to both the startup selector and the live window so there is one owner.
`selectStartupAgent` propagates optional `handleSignals`, defaulting true;
`bin/chord.dart` explicitly supplies false for startup and the session run.
Standalone framework examples retain the true default. No nested watcher,
forwarding scheme or second cleanup owner is added by the framework.

Supported catchable termination signals are HUP, INT and TERM. Main
approved routing these through bounded ordinary cleanup, then removing
handlers and re-raising the original signal so exit semantics survive.
Do not make a keypress Ctrl+C become a process signal in raw mode. Dart's
VM reserves QUIT, ABRT, PIPE and BUS; this slice installs no handlers for
them and adds no native workaround. SIGKILL and an external terminal crash
cannot run cleanup and are outside any restoration claim. All signal
subscriptions are per-run and removed; no persistent process-global handler.

Prove this ownership with bounded actual supported-signal PTY probes for
both standalone/embedded framework runs and the port, including startup,
active window and editor suspension. Assert native signal exit semantics,
child group cleanup where port-owned, deferral while a child owns the tty,
handler removal and no late terminal re-entry or mouse-mode re-enable.
Passing fake-signal or keypress tests alone is not this proof. If an actual
probe exposes an incompatible outer-owner lifecycle, stop and raise the
options to the lead before adding a workaround.

The services demo must release its owned sample file/directory in beforeExit
before a supported signal is re-raised, with idempotent finally cleanup for
other returns. This U7 integration change receives an explicit handoff and
U6 editor/cleanup recheck; earlier U6 captures do not prove signal cleanup.

Recheck U6's scripted-editor handoff with mouse reporting present: mode-off
bytes precede child ownership, no report reaches the child as prompt text,
and resume enables modes once. Failure and requested-exit paths leave them
off. Capture the terminal after exit as evidence and use byte assertions for
protocol balance; a screenshot cannot prove mode balance.

## Delivery and clipping

runApp dispatches MouseEvent to AppHost.handleMouse independently of focus.
The widget tester exposes a matching deterministic dispatch method. Use the
current laid-out geometry and ancestor clip rectangles. Hit-test children
in reverse paint order, then deliver to Listener ancestors deepest first.
Only the visible path under the coordinate participates. A clipped/offscreen
or zero-sized child receives nothing; translated and virtualised children
use their current offsets. A moved or removed widget has no stale callback.
A root opaque Listener covers blank space as well as painted descendants.

Paint leaves such as Text hit their laid-out rectangular bounds, including
spaces inside those bounds; hit testing does not inspect painted glyphs or
nonblank cells. Decorations hit their own decoration shape/bounds; a hollow
rectangular border still hits its interior. Layout-only Flex, Stack,
Padding, constraints and SizedBox do not hit themselves. A child can supply
a hit through them, but an empty SizedBox supplies none. Listener.opaque
is how an app explicitly makes otherwise blank space participate.

The lead approved a bounded shared paint-child geometry hook on RenderBox,
used by both painting and hit testing. It exposes actual child origins and
clips rather than building a parallel pointer geometry model. Special
Fold, ListViewport, Follower, Flex and Stack paths must use the hook while
preserving existing paint order, offsets and clipping exactly. A current
root-layout stamp excludes stale children retained only for measurement,
virtualisation or hidden followers. This is the required render-box and
Listener routing, not an overlay redesign. Verify reached paint/layout
regressions alongside overlapping Listener, virtualised-position and overlay
clipping tests before handing this unit onward.

`deferToChild` joins a child's hit path; `opaque` also hits its own bounds
and prevents siblings behind from joining; `translucent` also hits its own
bounds and allows underlying siblings to be tested. The path is fixed for
one event, like Flutter: rebuilding during a callback does not retest and
deliver the same event twice. Reuse render clipping and geometry rather
than approximating with focus order or mounted-widget order.

`absorbPointerSignal` defaults false. For a wheel event its own signal
callback still runs, then this Listener stops ancestor signal callbacks on
that hit branch when the snapshotted flag is true. It does not affect
press/release, sibling hit routes or MouseEvent immutability. Callbacks stay
void; no mutable input event, global propagation registry or boolean return
convention is added. Snapshot callbacks and the flag with the event's hit
path: a rebuild or flag change inside a callback cannot alter the same
dispatch. Translucent sibling branches keep their existing routes; shared
ancestors are delivered at most once if reached by an unconsumed branch.
Tests must exercise those sibling/shared-ancestor cases and rebuilding
while a callback changes the flag. The current layout/build at dispatch,
not a previously cached overflow result, determines the snapshot.

Overlay entries participate in reverse painting order with the same clip
rules. A root listener remains an ancestor of the port's entire window,
including its overlay host; wheel over a child therefore reaches it. No
outside-screen events reach a listener. There is no pointer capture:
release is hit-tested at its own current position. Selection behavior and
press-to-release target retention belong to CTUI-48.

If this requires a broader clipping/overlay subsystem rather than the
required render-box/Listener routing, developer must surface that boundary
to the lead before implementation. An approximation that routes to hidden
or wrong widgets is not acceptable.

## Public framework fixture

U7 adds `example/mouse.dart`: a title and last-event status, an Expanded
event log, a bounded framed TextArea and concise wrapping KeyHelp from its
active bindings. An opaque root Listener records press/release/wheel
independently of input focus. Expose the event kind, position and wheel
delta so one injected report is visibly one event. Wheel scrolls the log;
Shift+Up/Down provide existing keyboard equivalents, Ctrl+L clears the log
and Ctrl+Q quits. Typed draft and focus remain intact. This example is not
a port interaction or CTUI-48 selection feature. AppHost.handleMouse and
tester.mouse(MouseEvent) expose the same deterministic input path.

## Port mapping

Wrap the whole live window (header, transcript, prompt, help and overlay
host) with an opaque Listener. For one vertical wheel report, dispatch the
pure `wheeled` action carrying line_up or line_down. The reducer returns
unchanged while connection status is closing; otherwise it delegates to
existing scrolled behavior. Use existing transcript follow/offset/new-output
rules. Prompt history is never a wheel target. There are two current
exceptions to root transcript scrolling: an overflowing shortcuts body and an
overflowing permission proposal body consume wheel over their visible
scrollbox bounds, moving their own content by one row. A fitting body lets
the report reach the transcript. The listener covers the original
scrollbox body only, not its title, hidden-row rules or permission choices.
Use an opaque Listener with absorbPointerSignal set to the body's current
overflow condition; its callback scrolls the body only while overflowing.
Root and body callbacks must both leave state unchanged while closing.
There is no wheel-driven permission selection. This matches the original
rather than assigning every panel or picker a new wheel policy.

For the port, ShortcutsPanel and PermissionPrompt take optional
`bool Function()? isClosing`, with null meaning false. The window supplies
a live predicate reading its exiting flag or current connection app closing
state. Evaluate it inside each wheel callback, as the root window does,
before dispatching an action. A captured boolean from the last build is
insufficient: two queued reports can arrive before another redraw. This
fresh guard does not alter the framework's snapshotted overflow/absorption
route. Regress a transition to closing followed by another report in the
same chunk at root and each body. The pure closing state defaults false,
Closing sets it and Connected resets it, as settled by the lead.

Original input.ts observes vertical steps, App.tsx maps them to wheeled,
and state.ts routes to scrolled unless closing. The port's action remains
plain Dart and has reducer tests. Existing arrow keys remain prompt history
and text movement; Shift+Up/Down retain described transcript line scrolling.
No new shortcut-panel item is needed for the wheel's alternate input path.
Mouse press/release have no port action in this slice.

Main corrected the initial task's blanket "wherever the pointer is" claim
after designer's original captures. At 120x40 fitting shortcuts let wheel
move the transcript; at 80x24 overflowing shortcuts consume it, with one
down report exposing one hidden panel row and leaving the transcript
unchanged. Original Shortcuts.tsx lines 132-148 implements the explicit
stopPropagation condition, as does dialogs/Permission.tsx lines 374-389.
Both use new LinearScrollAccel; the installed OpenTUI implementation's
tick returns 1 and reset does nothing. One row/report is verified from
that source and the shortcuts capture, not an assumed default multiplier.

A scan of current original UI scrollboxes found only these two reached
consumers. Prompt.tsx's command/file completion scrollboxes and
background/BackgroundView.tsx's background scrollbox are future FEATURES
rows, outside this slice. No future completion/background behavior is
introduced. Standing owner authorization applies the same original rule
to any other already-implemented scroll area found during the unit; record
its original source and step size rather than guessing.

## Port visual fixture

`example/chord/tool/wheel.dart` draws the actual TranscriptWindow with 100
named entries and an unsubmitted draft. Its --help, --permission, --fitting,
--closing and --tall-draft flags compose real existing panel/window states;
no duplicate catalog, fabricated overflow calculation or pointer-only
product action is added. Ctrl+Q is the fixture's bounded exit. The closing
state removes active panels, so same-chunk body guard proof remains in
focused tests rather than a visual assertion about hidden callbacks.
Real fake long/permission/bigask captures supply payload parity; seeded
fixture captures are explicitly stress evidence.

## States and screens

No visual chrome changes. At 120x40 and 80x24 the existing window is drawn
with its original header/transcript/prompt/status/help arrangement. With an
empty transcript the wheel leaves the window unchanged. With overflowing
output and no consuming panel body under the pointer, one upward wheel step
exposes exactly one earlier transcript row; one downward step restores it
until bounds. Focus and prompt draft/cursor
stay unchanged. At narrow width existing layout/reflow rules determine row
heights, and each wheel step is still one visual row. Closing ignores wheel.

Illustrative excerpt at either size, before and after one upward step:

```text
before: transcript row n+1 ... transcript row n+height
after:  transcript row n   ... transcript row n+height-1
prompt: same text, cursor and focus
```

These are design sketches, not runtime captures. Original and port live
fake `long` state must be captured at both sizes, with equal setup and
bounded wheel input over transcript, prompt, header and help. Save before,
up, down and restored/quit evidence under docs/design/evidence/CTUI-47/.
The current port's staged M1 catalog has 19 entries, drawn in two columns
as 10 body rows at 80x24. It fits naturally at both required sizes, even
with a seven-line draft. The original's fuller catalog overflows at 80x24;
this existing staging difference is not a new wheel behavior or a reason
to add future shortcuts. Capture the actual fitting port states at 120x40
and 80x24, and record that distinction beside the original references.

Add a natural 40x12 whole-window overflow capture for both original and
port. Over the overflowing body, compare one-row panel movement and an
unchanged underlying transcript after dismissal. Over a fitting body,
compare transcript movement. Keep bounded panel overflow tests at 80x24
and 120x40 to cover the route at those widths without faking the live
window's available height. Add fitting and overflowing permission-proposal
states at both required sizes, with wheel inside the body and over its
title/choices/rules to check the actual hit boundary.

The developer-owned wheel fixture may retain --tall-draft as multiline
stress, seeded with `unsubmitted draft` and `draft line 2` through
`draft line 7`, separated by newlines with no trailing newline. Its actual
fitting result at 80x24/120x40 must be asserted; seven draft lines do not
force overflow. An initial assertion expecting 80-column overflow failed
and exposed that mistaken fixture expectation. It was not a product defect;
no catalog, prompt limit, window height or overflow calculation is changed
to make the assertion pass. Preserve draft/selection proof while correcting
the expectation and adding the genuine 40x12 case.
Compare row movement, draft preservation and follow behavior side by side;
do not call byte injection a physical trackpad measurement. Original
scheduling may produce different live partial counts: use completed output
for exact one-step comparison and separately observe streaming hold.

## Units and acceptance

U7 owns framework mode enable/disable, typed mouse parsing, Listener routes
and deterministic tester input. Tests cover byte chunks, modifiers, wheel
signs, press/release, invalid/motion recovery, paste opacity, focus-free
routing, ancestor order, sibling overlap, clipping, resize, virtualised
position, overlays, absorption/rebuild/sibling branch semantics, disposal
and suspend/exit/signal cleanup. This is not a request to implement every future pointer interaction.

U8 owns the port's pure wheeled action and root Listener. Regress wheel over
all window areas, one line per step, arrow-history independence, draft
preservation, following/hold/resume bounds, fitting/overflow body routes for
shortcuts and permission proposals, and closing no-op at root and body.
Designer checks the explicit handed commit in owned tmux at both sizes against the
original, then hands reviewer implementation commit plus saved captures.
No real agent/model, physical mouse claim or CTUI-48 selection/copy work.

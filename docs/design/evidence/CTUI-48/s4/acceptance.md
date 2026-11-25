# S4 designer acceptance

Implementation: `90de9ea22c7160d199650b87a5b6e392a9725fd0` on CTUI-48.
The assigned shared worktree stayed clean at that exact implementation during
this public API/demo look. No product finding; direct handoff is to reviewer.

ScrollState.held defaults false; ScrollController.hold()/release() and pure
reduceHeld/reduceReleased follow the approved explicit ownership shape.
The fixture integrates through public selection callbacks; no new SelectionArea
coordinator API was introduced. This is API/design acceptance, not code review
or independent verification of the handed unit tests.

## Setup and observations

Command: `dart run test/fixtures/selection_area.dart`, from the assigned task
worktree. Owned socket ctui48-designer, sessions designer-s4-120 (120x40) and
designer-s4-80 (80x24). Both use default dark styling; S4 changes scroll state,
not the S3 theme palette. No clipboard, fake agent or model. Each state has
capture-pane -p .txt and -p -e .ansi evidence.

1. initial-following starts at the bottom with held false/following true.
2. Header down ESC[<0;1;1M, motion ESC[<32;9;1M, then F2 appends record 12.
   held-append-stationary shows held true/following false and the same old log
   rows; the appended record is not followed while the drag remains held.
3. Release ESC[<0;9;1m then C-s yields release-restores-following: held false,
   following true, record 12 visible, synchronized finalized text Selection.
4. After clear, a first wheel attempt used fixed (10,10) while held before
   appending record 13. At 120x40 that cell is a blank gap, so it did not reach
   the fixture's defer-to-child log Listener. Release correctly followed new
   output because no transcript scroll action ran. The two gap-wheel-setup
   capture pairs retain this setup miss; it is not a product failure/fix.
   At 80x24 that coordinate did hit content. An intermediate exploratory
   upward-wheel gesture was cleared before the decisive rerun below.
5. C-l and End restore the baseline. A new header drag uses the same down and
   motion; downward wheel ESC[<65;10;5M at 120x40 or ESC[<65;10;3M at 80x24
   hits an observed print glyph at the current bottom. F2 appends record 14.
   held-clamped-wheel-append retains the old view and held true/following false.
   Release and C-s yield clamped-release-stays-paused: held false/following
   false, record 14 still below the unchanged view. Thus the clamped explicit
   transcript wheel action prevents follow restoration at both sizes.
6. C-l and End restore following; another header drag then S-Up performs a
   real one-row transcript step. held-key-scroll shows held true/following
   false and the changed log position. Release, C-l and literal ` typed`
   yield key-release-focus: held false/following false, and the draft remains
   focused with its original text plus the suffix. The release note counts
   nine selected header characters and performs no copy.

The whole fixture remains readable at both sizes, including its held/following
facts and two-row help. These are framework-only screens, so no original port
comparison is claimed. Fitting-to-overflow normalization, child-consumed wheel
isolation, stationary log endpoint projection and absence of periodic work
remain exact test/reviewer obligations; this short look is not a soak or a
proof of every reducer path. Production port coordination remains S5.

No compile, full suite, soak or physical pointer/cursor check was performed.
Both sessions exited normally with C-q. Final list-sessions reported no owned
server; process inspection found no surviving owned fixture or tmux. Capture
privacy and observed held/following state checks passed; no capture contains a
private filesystem path. Only this evidence directory was written.

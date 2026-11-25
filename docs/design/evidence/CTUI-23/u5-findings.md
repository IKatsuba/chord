# U5 visual gate: hidden completion hint finding

Exact handed commit831ccb358defdfc99c95c3dd99b95ed33c06dc3d, run from an
isolated git archive with both package roots pointing into it. No shared
WIP used. Original577b58167672e12c999aeaf4eed2a1a988513dc2 through its
isolated fake runner. Result: hold for one original-fidelity status hint.
No reviewer handoff yet; no implementation audit performed.

## Complete finding

At80x24 type /sta, then resize80x5 and press Tab. Both keep /sta and do
not accept the invisible /status item. Original status left says
not enough space; port left is blank. Paired zero-tab-80x5 captures show it.
Restore the original low-priority hint, preserving mode/real-notice priority,
width drop order and clearing it on room return. Developer agreed existing
base-page afterLayout observer fits, with live entry/rows/query reconciliation;
no new API, private reads, timer or duplicate page-height formula.

## Passed actual session comparisons

Default / menu uses10rows at120x40 and6at80x24. Staged port catalog has only
approved clear/config/effort/exit/fast/help/model/status plus agent commands;
original full catalog has more, so its global name column/window differ.
Up wraps to the last available staged command and reveals it. These catalog
differences are intentional, not alleged row parity.

Filtered /sta row and description match. Esc retains draft, editing to
/stat reopens it. Hidden Tab remains /sta, return-room does not accept by
itself, and hidden Enter submits typed /sta to the fake, which answers the
same Hello world instead of dispatching status. /ec Tab inserts /echo plus
space; hello then Enter draws same agent reply. /mod Enter opens matching
model picker at both sizes; Esc restores focus. Literal /j1k remains text.

/status draws original label alignment for Agent/Model/Mode/Session/Directory,
with Title/Account omitted per main; UUID/directory are fixture-specific.
/help opens staged shortcuts at both sizes, including completion arrows,
Tab and Esc. /clear empties the transcript. Reserved /new Enter remains in
the staged draft and is not sent; original /new was deliberately not run
because it would start an out-of-scope session. Local /exit exited normally.

With CHORD_FAKE_STEP_MS=100, slow is running while queued draft is queued;
/clear interrupts old session, restores queued draft and empties transcript
in both implementations, retained at both sizes. Existing original Markdown
scenario then supplies a scrollable transcript; filtered completion floats
above the prompt. Up-wheel over fitting completion body at(15,19) scrolls
underlying transcript while keeping menu/draft fixed, both implementations.
No synthetic overflowing completion scrollbox was invented to claim a
consumer; existing framework/port wheel tests are reviewer/tester scope.

## Palette and narrow CUT

True dark/light runs explicitly unset NO_COLOR and set FORCE_COLOR=3,
COLORTERM=truecolor plus COLORFGBG15;0 or0;15. Filtered selection uses the
same permission RGB177,185,249 dark and74,90,224 light, at both sizes.
Plain/default captures inherit NO_COLOR. Existing default-foreground ANSI
representation differs; no new palette-role difference was found.

Original fake's supported CHORD_FAKE_ALSO_COMMANDS advertises an identical
long name: 名字👩‍💻 followed by12 repetitions of long界👩‍💻 then tail.
Filter /名. Live original/port command row CUT matches at120x40,80x24,40x24,
including whole CJK/emoji and both ends. /config description at40columns
matches Change the a...ch as effort. No fake/original source was edited.

## Evidence, limits and cleanup

Paired u5-{original,port}-named states retain txt/ansi. Only isolated fixture
directory text is redacted. Known startup header version/help and approved
catalog/report differences remain visible. Current declared146/333 reached
test results are developer/tester responsibility; designer makes no suite,
AOT or test-pass claim, including the2 disclosed obsolete whitespace cases.
Second Esc during a running turn and dynamic menu replacement remain
reached-test coverage and a corrected-gate spot check, not claimed live here.

All text sent literally, Enter separately. Wheel is byte injection, not a
physical trackpad claim. Owned sessions exited local /exit or Ctrl+D; slow
work cancelled by clear; runtime/session cleanup checked and exact archive
removed after evidence retention. An approval review blocked one capture
command pointed at original cwd before execution; corrected captures wrote
only in the team worktree. Nothing under the original checkout was written.

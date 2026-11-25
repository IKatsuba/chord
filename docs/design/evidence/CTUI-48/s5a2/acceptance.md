# S5a2 designer acceptance

Exact clean combined implementation: `33892078778b394a9a7085b17e1cbcf32931a7b5`.
Observer/motion repair: `9a71fc2fafe3ea82a9f07dfc50f009e97bd43ed7`.
Developer held the assigned shared tree; S5b files remained isolated and were
not read or restored by designer. No product/API finding; handoff is to reviewer.

SelectionSourceChild adds only the approved immutable selectable flag, default
true. Its call site remains a normal named child option. The handed public
fixture uses the same source in its delegate and bound content, with the false
branch under SelectionContainer.disabled. This is an API/runtime look, not a
code audit or independent rerun of the handed tests.

## Runtime setup and states

Command: `dart run test/fixtures/selection_child.dart`, from the assigned task
worktree. Owned tmux socket ctui48-designer; designer-s5a2-120 (120x40) and
designer-s5a2-80 (80x24). All seven retained states at each size have
capture-pane -p .txt and -p -e .ansi files. No clipboard or agent is involved.
The fixture uses inverse selection; no theme/palette change is made in S5a2.

- initial-excluded: first eligible, wrapped decoration and code, last eligible
  are all painted. The last row is terminal row11 at 120 columns and row13 at
  80 columns. Wrap height is visibly retained even though the middle is excluded.
- excluded-drag-empty: literal primary down/motion/up over wrapped, followed by
  C-s and C-b, leaves phase none, empty snapshot and visible eligible code0.
- cross-excluded: down at (1,4), motion/up at (13,11) for120 or (13,13) for80,
  then C-s/C-b. Snapshot is exactly first eligible\nlast eligible. Only the two
  eligible endpoint lines are inverse; decorative text/code and their borders
  remain unselected, with no decorative separator inserted. Code query stays0.
- included-same-geometry: F2 and C-b expose code1. All content rows between the
  fixed header and footer compare exactly with initial-excluded; last row does
  not move. Existing finalized endpoints do not automatically select new middle
  content. The snapshot footer is a previously requested inspection, not an
  automatic copy or a promise that its text refreshes without C-s.
- middle-selected: C-l, primary down/motion/up from x1 to x7 on terminal row5,
  then C-s, reports wrapped at both sizes. The live fixture controller listener
  rebuilds its parent; the ordinary selection remains present.
- exclusion-drops-selection: F2, C-s, C-b yields phase none, empty snapshot,
  eligible code0, while decorative rows remain drawn in the same places.
- reinclude-no-resurrection: F2, C-s, C-b yields phase none/empty snapshot and
  code1. Re-enabling eligibility does not resurrect the old middle range.

All reports were literal send-keys -l SGR bytes using one-based terminal cells:
down ESC[<0;x;yM, motion ESC[<32;x;yM, up ESC[<0;x;ym. No physical pointer claim.
The whole fixture and key descriptions remain readable at both required sizes.
There is no port screen here, so no original pairing is needed. Authoritative
provider behavior without an explicit disabled wrapper, never-mounted copy,
first/last/all/nested variants and full lease accounting remain test/reviewer
obligations; this fixture shows the matching bound/disabled case.

## Handed observer/motion failure-to-fix evidence

The handed ignored logs and exact commands are recorded in
developer-reached-commands.txt; sanitized-failure-fix-excerpts.txt retains
selected log labels and line numbers without private stack paths. These are
developer-run results, not designer reruns or reconstructed old runtime frames.
The failing source was an uncommitted S5a2 chain based on `20d2867`, not an
independently addressable failing commit:

1. Missing selectable API produced named-parameter failures.
2. Same-fragment motion with a rebuilding controller/callback observer returned
   empty instead of single in four cases across120x40/80x24. The motion-order
   repair addresses synchronization before storing new motion.
3. Fresh-source snapshot/release with a rebuilding observer returned null/empty
   instead of current ABCD in four further cases. The approved host repair
   includes observer notification effects in the same total two-pass budget,
   with callbacks outside layout and reentrant input/capture guards.
4. An early assertion summed release plus a subsequent explicit snapshot as
   one budget. It was corrected to count these as separate synchronized
   operations, each bounded by two; the production budget was not relaxed.

Final handed results: focused56, root1097 and port396 passed; analyze clean,
format528 with zero changed, diff-check clean. Existing finalization regressions
retain old immutable final delivery after post-release reentrant new-down,
while pre-release supersession cancels the unfinished old gesture. Automated
fresh-source/epoch/pass-count claims remain those named test results; this
runtime fixture does not independently prove every observer/reveal path.
The generic settlement-exhaustion key guarantee remains main's separate task;
no third pass, fallback/replay or deferred public notification redesign is claimed.

## Cleanup and limits

Both fixtures exited normally with C-q. Final list-sessions reported no owned
server; process inspection found no surviving selection_child fixture. Geometry,
snapshot and capture privacy checks passed; no home/private path is retained.
Only this assigned evidence directory was written. No compile/AOT, full suite,
soak, clipboard, real model/agent or physical pointer/cursor check was performed.

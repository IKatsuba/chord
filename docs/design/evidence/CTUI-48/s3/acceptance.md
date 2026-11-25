# S3 designer acceptance

Implementation: `ae0ab8f60d7cafe03c9a5903cc18cb14a903e6a7` on CTUI-48.
Developer held the clean assigned worktree throughout the API and runtime look.
No finding; direct handoff is to reviewer, not tester.

Public SelectionArea/SelectionController/SelectionContainer.disabled and lazy
SelectionChildDelegate match the approved call site. Synchronized snapshot and
code query/reveal methods remain separate from the notification value. The
pure PaintCoverage declaration has the agreed immutable before/after rectangles,
exact declaring type and default-unknown shape. This is API/design acceptance,
not code review or independent verification of the handed test results.

## Setup

```sh
dart run test/fixtures/selection_area.dart
```

Run from the assigned task worktree in owned tmux socket ctui48-designer,
sessions designer-s3-120 (120x40) and designer-s3-80 (80x24). No environment
configuration, clipboard, fake agent or model was used. Both sessions used the
same fixture and initial sources. All states have capture-pane -p .txt and
capture-pane -p -e .ansi files. No compile, soak or full suite ran.

## Observed states and exact input

Coordinates below are SGR one-based terminal cells. Reports were sent literally
with send-keys -l. C-s inspects the synchronized snapshot; it is not a copy.

- initial-dark: header/log/draft/furniture read clearly at both sizes; help
  wraps into two rows at 80x24, without taking the draft away.
- held-dark: down ESC[<0;1;3M, motion ESC[<32;8;3M selects Record 0.
  release-last-motion: up ESC[<0;30;7m then C-s still reports
  finalized: Record 0, preserving last motion rather than release coordinates.
- known-overlay-range: C-o enables the known overlay. Down (1,3), motion
  (7,8), up (7,8), C-s selects the first record through its final code row.
  The overlay covers middle code cells without receiving highlight; visible
  code around it stays highlighted. The inspector retains the covered print
  source in the logical range. This is implemented framework behavior, not
  an original-overlay parity claim or exact raw tab-byte assertion.
- unknown-suppressed: C-u then C-s shows Snapshot unresolved and no selection
  background. recovered-light: C-u, C-s, C-t restores the finalized range
  and light styling. plain-selection: another C-t uses inverse selection.
- blank-lf-lane: C-o removes the overlay and C-l clears. Down (20,7), motion
  (7,8), up (7,8), C-s reports a leading LF followed by end. The far content-lane
  x on the genuine blank code row supplies a boundary without copying padding.
- reveal-last: C-l, C-r reports Reveal last: true and shows the entire last
  record's code container at both sizes. Home returns the log to its top.
- unknown-cancel-no-finalize: C-l, down (1,3), motion (8,3), C-u, up (8,3).
  With coverage false, the message remains the preceding Reveal last: true;
  release does not emit a new finalized note. C-u and C-l restore known/clear.
- mixed-forward: header down (1,1) through draft motion/up (5,38) at 120x40
  or (5,21) at 80x24, then C-s. The long inspector occupies a second row,
  moving the draft up one row. mixed-reverse: C-l, down at draft (5,37) or
  (5,20), motion/up (1,1), C-s. Forward/reverse plain captures are identical,
  with header/log/draft highlighted and disabled furniture excluded. Inspector
  text is intentionally capped, so this does not prove its entire copy string;
  exact mixed-source strings and never-mounted coverage remain test obligations.
- covered-interior-retained: C-l, C-o, down (23,6), motion (24,6), then motion
  into covered interior (10,6), up (10,6), C-s reports finalized: ); at both
  sizes. This checks our explicitly chosen retention rule, not original parity.
- draft-focus-cleared: C-l, C-o, send-keys -l sends ` typed` without Enter.
  Draft becomes draft stays focused typed; no selection highlight remains.
  The fixture keeps its prior inspector message until another inspection;
  that disabled message is not current selection/copy authority.

Dark selection ANSI is background 66; light is 152. Plain selection includes
inverse and no foreground/background SGR. Known overlay furniture is unselected,
and syntax attributes remain visible on eligible code. Japanese, the joined
emoji and combining accent remain whole in the visible mixed range. Capture
privacy, plain SGR, unknown-background suppression and visible forward/reverse
parity checks passed. No designer failure/fix evidence was needed.

Both sessions exited normally through C-q. Final list-sessions reported no
owned server; process inspection found no surviving owned fixture or tmux.
Captures contain no private filesystem path. No original source was edited.
Byte injection does not prove physical pointer/cursor behavior. Shared-pass
exhaustion, callback reentrancy, hidden/clipped endpoint variants and full
geometry query matrices remain reviewer/tester checks; held-scroll policy,
port copy controls and final compiled/performance evidence remain S4-S7.

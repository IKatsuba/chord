# CTUI-8 primitive API and screen assertions

Per the lead's primitive gate, public widgets with no runnable screen are
checked against the design and their headless screen assertions. Live tmux
captures remain the later fixture's gate. This is not a code audit.

## Table

Handed over 6787cb7: Table, TableRow, TableBorder.all, fixed/intrinsic/flex
column specifications and the pure width solver. Public call sites follow
the approved Flutter shape, borderless by default, with explicit columnGap.
Widget cells own their wrapping/ellipsis. The keyed-row synchronization
change in framework.dart belongs to review with this unit.

Read the tests' screen assertions and ran only
`dart test test/foundation/table_widths_test.dart test/widgets/table_test.dart`:
17 tests passed. At 120x40 and 80x24, headings and content align with the
two-cell gap and a stable row below. Assertions also show wrapping with
consistent row height, one-line cell ellipsis, wide characters, grid padding
and theme border, narrow clipping and keyed rows retaining their state while
moving visually. No API or screen-assertion finding. Markdown is unchanged;
no claim of shared-renderer validation or live fixture acceptance.

## Fold and ExcludeFocus

Handed over e2ed4fe. Fold(title:, open:, child:) remains controlled and
binds no key. ExcludeFocus(excluding:, child:) uses Flutter's naming.
Checked the API and screen assertions, then ran only
`dart test test/foundation/fold_test.dart test/widgets/fold_test.dart`:
16 tests passed in the handed-over files as run. Both 120x40 and 80x24
show the closed title alone and the open title/body without extra padding.
The short-room assertions show exact hidden visual-row counts, one/zero-row
budgets, remeasurement after width changes and clipped wide graphemes.
Collapsed state remains mounted and its focus is excluded, returning to an
eligible outside node or clearing focus when no fallback exists. No API or
screen-assertion finding. Live Fold appearance remains the combined fixture
or Dialog's body handover; this unit has no standalone runnable screen.

## Fold and Table live fixture: b217d91

Ran `dart run example/fold.dart` in an owned tmux session at 120x40,
80x24 and 80x10. The open Fold shows seven body rows, a clean header and
the aligned gridless Table below. Ctrl+o collapses to the title without
adding a widget-owned key or decoration. At 80x10 it shows the first four
body rows and a dim `  … 3 more lines`, with the table and KeyHelp retained.
The intrinsic/fixed/flex example columns align at both required widths.
Text/ANSI captures use fold-table-* names. No visual finding; live gates
for Fold e2ed4fe and Table 6787cb7 are now complete. Session removed.

## Completed Fold/Table theme looks

The reviewer correctly identified that the initial live section covered only
the default dark theme. Completed the missing light and plain runs at both
120x40 and 80x24: `env -u NO_COLOR COLORFGBG='0;15' dart run example/fold.dart`
and `env NO_COLOR=1 dart run example/fold.dart`. fold-table-light-* and
fold-table-plain-* pair text and ANSI. Plain/dim body and marker remain
legible; gridless columns and row geometry are unchanged. No additional
finding. All owned theme sessions removed. No waiver was used.

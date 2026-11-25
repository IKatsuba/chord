# B2 standalone permission prompt: visual acceptance

Screen handover: `a3d80af`. Fixture fix rechecked: `138846e`.

Ran `dart run example/chord/tool/permission.dart` with each of `diff`,
`review`, `failed`, `held`, and `one` in owned tmux sessions at 120x40 and
80x24. Ran the original with `bun dev chord --fake --qa` and an isolated
capture name; submitted `reviewpermission`, `reviewfailed`, `bigask` and
`bigaskleft` literally, with Enter in a separate call. The comparison
files put original and port captures side by side at matching sizes.

## Observed

The title stays visible above the scrolling request. At 80x24 the long
review reason wraps to two rows, and all three choices plus the deadline
hint remain visible. PageDown scrolls the diff above the answers, reaching
the final proposed line without moving the title, question or choices.
Overflow rules say what remains above/below. The constrained `one` fixture
moves the overflow count into the title at 80x24; answers still fit.

Ordinary question and failed-review wording follow the original's
composition. Held requests show `main asks · between turns`, unmarked
choices, and `ctrl+x a to answer`, without active scrolling hints.
Typing a number while held does not choose. After attending, the marker
and active hint return. Choosing option 2 records `always`; Esc records
`Rejected` in the standalone fixture. Both sizes read clearly.

The original `bigask` and `bigaskleft` confirm pinned title, scrolling
request, fixed answers and held presentation. `reviewpermission` and
`reviewfailed` confirm warning/failed wording and spacing. These are
composition comparisons: standalone B2 deliberately uses a synthetic diff,
long reason, three options and a fixed deadline, while the original fake
scenarios have different request data and surrounding transcript/prompt.
They do not establish exact same-data or whole-window parity. B3 is the
live integration handover for that comparison. ANSI captures retain the
observed attributes; this run's port rendered without chromatic colours,
so warning/error hue parity is unmeasured.

## Finding and fix

The first held fixture had no primary-focus descendant; its outer attend
chord did not run. Reported to developer. Fix `138846e` gives the preview a
focusable Answer row. Rechecked fresh held fixtures at both sizes:
`ctrl+x a` activates and focuses choices. The corrected narrow fixture
selects option 2 and scrolls after activation. The wide fresh fixture also
activates successfully. No remaining B2 visual finding.

## Cleanup and limits

All standalone fixtures quit through ctrl+c. The original exited through
two ctrl+c presses within its quit window. No owned tmux session, fixture
process or original fake agent remained after cleanup. No test suite was
run by designer. Window wiring, draft ownership and fake-flow parity are
B3 checks, not claims made by this standalone review.

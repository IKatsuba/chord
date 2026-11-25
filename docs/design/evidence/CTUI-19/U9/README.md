# U9 live plan visual check

Implementation 4ce9c46. Designer result: pass for reviewer.

Port command: `dart run example/chord/tool/dev.dart chord --fake`.
Original command: `(cd ../chord && bun dev chord --fake --qa designer-ctui19-u9)`.
Sent `plan` as literal text, Enter in a separate key call; captured while
running after 0.4 seconds and pressed Esc to retain its partial checklist.
Repeated at 120x40 and 80x24. Full pane captures have directory labels
redacted; ANSI captures retain styling; side-by-side files select the live
plan region. The original has an earlier completed Plan record above it.

All paired live checklist regions match exactly: left padding two cells,
three-cell result gutter, first `⎿`, completed `☒`, current `◐`, pending `☐`.
After Esc, both show `Plan · 1 of 3 done` above the identical checklist.
ANSI inspection confirms completed text dim and struck through, mark dim
and unstruck; current text/mark bold while running and normal when idle;
pending normal; summary and result gutter dim. Prompt margin and bottom
alignment match at both sizes. Working/status are pending U11 and are not
claimed. Fold limits/long-row truncation are covered by developer's tests,
not by this three-step live scenario; the fixture adds no different states
beyond this run and was not needed for the observed styles.

First port session exited before inspection, with no diagnostic retained.
Restarting in a persistent shell and waiting until startup was visible
succeeded; both subsequent plan/interrupt cycles completed normally. No
product cause is claimed for that unobserved exit. No tests/AOT were run.

Cleanup: Ctrl+D closed both apps; the persistent port shell was removed.
Both owned tmux sessions and all tracked descendants/fake agents were
checked gone.

## Follow-up on the initial session exit

Ship requested bounded diagnostics. Tester reported 20 early-input runs:
19 reached the prompt and quit cleanly with empty stderr; the remaining
exit 254 retained a compilation failure from developer's uncommitted U11a
edits in the shared tree. Ship accepts shared-tree compilation as the
explanation for the earlier disappearance. That original symptom still has
no direct exit/stderr measurement, so causation is inferred, not measured.
Tester repeats startup at both sizes on the final clean commit. Subsequent
designer launches check lib/ and example/ clean before starting a port app.

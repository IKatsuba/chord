# CTUI-21 baseline captures

Original revision: 577b58167. Port baseline: b6ca50b, before CTUI-21 units.
Live tmux panes at 120x40 and 80x24, owned by designer. Each `.txt` is
capture-pane -p; each `.ansi` adds -e. Home/worktree directory text in the
port baseline is replaced with <worktree>; no private path is evidence.
These are baseline/design evidence, not acceptance for later commits.

Original command: `(cd ../chord && bun dev chord --fake --qa ctui21-designer)`.
Idle includes the status hint. Type `?` for help; the full original panel
has two columns and a hidden-row rule at 80x24. PageDown gives the separate
scrolled capture. First Ctrl+C empty gives the armed status; capture both
sizes inside its two-second window. Type `error`, then Enter in a separate
send-keys call, for the error row. Type `ignorescancel`, then Enter, for a
bounded 30-second running turn; screenshots show its working line.

Port command: `dart run example/chord/tool/dev.dart chord --fake`.
Its baseline still has the pinned interim header and no help hint. The new
design replaces those. The original full help list includes future features;
the target deliberately includes only registered M1 actions.

Crash uses a temporary visual probe importing the original CrashBoundary,
openTerminal and render, with a throwing child matching the original's
Crash_test.tsx. Its Error message is `the window broke while drawing`; two
fixture stack frames make the source paths neutral and deterministic.
This is the running original boundary, not a painted mock or a failed-agent
scenario. The probe is outside ../chord and was deleted after captures.
A literal q exited once with status 1 and stderr output after restoration,
saved as original-crash-after-exit.txt. That probe receipt is not proof of
port shutdown or port stderr behavior.

Target mocks are in CTUI-21.md. Both-size original and intended port
composition is specified there; exact post-change comparison awaits each
developer handover. No implementation or test suite was run for this design.
All three owned tmux sessions were closed; process inspection found no
remaining fake-agent or port processes. No original source was edited.

# Unit 5 visual check

Implementation handed over: `9f2bd1b78455364fdb9c96e45919de2e46b76351`.
Visual pass at 120x40 and 80x24, in designer-owned tmux sessions.
No implementation review or test suite was run by designer.

## Captures

All names below have both size suffixes (`120`, `80`) and both `.txt`
and `.ansi` files in this directory. Directory text in port captures is
redacted to `<directory>` or `<directory…>` for a clipped directory. No
other text, styles or rows are changed; the redacted path's width is not
preserved. Original QA directories are neutral fixtures.

| Port capture | Observed | Original comparison |
| --- | --- | --- |
| `unit5-starting-*` | `Starting fake…`, dim, hint on row 3; held by separate owned gates | `original-starting-*`: centred splash, same wording, elapsed time and splash key hints |
| `unit5-connected-*` | Released gate leads to `Connected`, identity not drawn | `original-connected-*`: full header, model and prompt, no connected receipt |
| `unit5-runner-connected-*` | Prescribed developer runner leads to the same Connected shell | Same original connected captures |
| `unit5-failed-*` | Error-coloured headline, fixed quit hint, dim stderr heading, cut marker and six lines | `original-failed-*`: same fixture, stderr heading, cut count and tail |
| `unit5-notacp-*` | Error-coloured `fake did not start: Method not found: session/new`, no empty stderr heading | Design's supplied-message fallback rather than original's richer structured classification |
| `unit5-gone-*` | `The agent exited.`, hint still visible | `original-gone-*`: screen after killing the connected idle original fake remains visually unchanged |
| `unit5-runner-gone-*` | Same exit receipt, confirmed error-coloured with colour enabled | Same original post-exit comparison |
| `unit5-no-option-*` | Original two-row interim window, no connection/status row | CTUI-11 shell and unit 4 no-option capture |

Starting, connected and the first gone captures inherited `NO_COLOR=1`.
The traceback, notacp and runner captures explicitly unset NO_COLOR and
set a colour-capable terminal. Error colour is visible in the latter ANSI
captures, while plain-mode failures remain understandable through words.

## Commands and actions

The developer-prescribed command was run from the worktree root:

```sh
dart run example/chord/tool/dev.dart chord --fake
```

The other port runs used `dart run example/chord/bin/chord.dart fake
--agent-command <command>`. Commands used the original fixture with
`--start-fails traceback`, `--start-fails notacp`, or no flags. A shell gate
held the no-flags command before initialize, then releasing the gate showed
Connected. Original runs used its developer runner with a fresh named QA
place, `--hang start` for the splash, the same traceback fixture for failure,
and `--fake` for idle connected/exit comparison. No prompt was sent.

Exit was induced only on fixture groups freshly identified as descendants
of the corresponding owned tmux pane, with the fixture command and group
leader identity checked before SIGKILL. The port transitioned to Gone.
The original's idle screen showed no new visible exit notice in this run;
these captures record that observation, not a claim of UI parity.

Ctrl+c closed the 120x40 port Gone run; ctrl+d closed the 80x24 run.
Other port runs and original runs were closed with ctrl+d. No failure
flashed during quit. Cleanup verified that all designer unit 5/original
tmux sessions were absent, no matching fixture processes remained, and
owned gate files were removed. The runner's documented shared fake-state
location was preserved.

## Judgment and staged differences

The full interim screen reads clearly. The status, then quit hint, then
bounded diagnostic block make the failure understandable while retaining
a visible way out. At 80 columns long tail lines end in ellipses on their
own rows; the hint stays on row 3. Empty rows remain blank and nothing
suggests an available prompt or retry.

Differences are the design's deliberate staging: no splash/elapsed timer,
mark, model, prompt, transcript decoration or retry actions; compact header;
minimal Connected and explicit Gone receipts; one-press quit; supplied
startup failure reason rather than the original's step-specific wording;
and ellipsized diagnostics rather than original wrapped transcript lines.
The original traceback headline says it exited with code 1 before answering
initialize, while the interim uses `The agent exited.` with stderr below.
The original wraps two traceback file lines at 80 columns; the interim
ellipsizes them as specified. The colour of the failure headline matches
the original error role. The lead requested the explicit Gone state, so
its visibility while idle is intentional even though the original did not
show a new visible idle exit notice in this run.

No blocking visual finding. Handed to reviewer with this evidence.

# CHD-120 QA

Checked current main 050811a, including af6135f. Designer-approved appearance was left settled.

## What ran

- `deno task check`: types, lint, format and fake-agent tests; 1,051 tests and 20 steps passed, zero failed.
- `deno task compile`: produced the macOS arm64 binary.
- Source TUI at 120x40 and compiled TUI at 80x24 in an isolated tmux server, driven only by keys. Additional compiled checks started at 120x40 and resized to 80x24.
- Temporary HOME and XDG directories, neutral scratch cwd, wrappers named `chord` and `fake-agent`; fake agent from `tests/fixtures/`, with 50 ms steps. No live agent or model used.
- Close-idle, busy turn close, permission close, close expiry/rearming, shell close with another tab's command preserved, Esc on a turn and shell, visible agent error, resize, quit expiry, `/exit`, ctrl+c warning, ctrl+d confirmation, two open with one working, and last-session close.
- Session-layer and UI regressions in the full suite include fake-agent PID assertions after `closeAll`, busy-close and busy-quit; an injected shell checks that close stops only the closing tab's command.

## What was seen

- Idle close removed one tab immediately and selected its neighbour; the single-tab strip disappeared. Busy close left the tab open on first press, and removed it on second. After the warning expired during a still-running slow turn, the next press armed again.
- Permission-close named the wait before closing. The fake agent's deliberate error appeared in the transcript. Esc interrupted a slow turn and subsequent prompts still worked.
- Two shell commands ran in separate tabs. Closing tab 2 stopped its command and preserved tab 1's transcript and command. At 80x24, process inspection after close found sleep 143 alive and sleep 149 gone. Esc then stopped sleep 143. The wide run likewise left sleep 137 displayed as running after sleep 139's tab closed, then Esc displayed `Stopped by the user`.
- Busy quit named both sessions at 120 columns and counted them at 80 columns, matching the required mock wording. `/exit` armed the same warning. ctrl+c counted busy sessions. Expiry removed the warning and did not resurrect the old Closed note.
- With two open and only one working, ctrl+d armed with `2 fake is working · ctrl+d again to quit`; a second press quit. Resize preserved the warning and the session states.
- Quit printed two resume commands in tab order and EXIT=0. At 80 columns a long command naturally wraps in the pane; the raw stream contains two complete command lines. Closing the final tab quit with one command and EXIT=0.
- All four before/after `stty -g` values were identical. Raw terminal output for the main wide and narrow runs contained cursor-show and alternate-screen-leave sequences. The shell returned.
- Every fake-agent PID logged by this run's wrapper and all four owned sleep PIDs were absent after quit. The isolated tmux session/server was removed. The pre-existing unrelated fake-agent orphan was left untouched.

Captures are plain text and ANSI (`capture-pane -e`). No private paths occur in this evidence. Existing unrelated untracked evidence was left alone.

Library first: QA added no component, renderer, parser, protocol helper or production code. The reviewed fix reuses Map, ShellProcess, OpenSessions and existing Ink/string-width; no new library trial is required for this ownership change.

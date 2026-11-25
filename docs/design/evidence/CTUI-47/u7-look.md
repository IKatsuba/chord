# CTUI-47 U7 visual pass and U6 integration recheck

Handed implementation: signed `04e7919`. No U8 implementation was inspected
or run. Designer used owned tmux sessions at 120x40 and 80x24 for the named
`dart run example/mouse.dart` fixture and the integrated service example.
Plain and ANSI u7-* captures are retained here.

## Mouse example

Result: pass. A literal ` typed draft` was appended to the focused sample.
Injected SGR reports at one-based position 1,1 produced exactly one new
report each: up, down, primary press and primary release. Their visible
position is zero-based (0,0), wheel deltas are (0,-1)/(0,1), and button
reports show primary with zero delta. The counter moves 0 through 4 at
120 columns and 4 through 8 after resizing to 80. No raw mouse bytes or
arrow-history text enters the draft.

The event log moves from sample row 5 to 4 on one up and back to 5 on one
down at both sizes. Shift+Up/Down demonstrates the same one-row movement
without increasing the pointer count; Ctrl+L leaves an empty log. The draft
`draft stays here typed draft` remains unchanged. Last-event status, framed
input and every help action fit and remain readable at both sizes, including
an empty log. No pointer-only app action is introduced.

## Integrated editor

Commands: `dart run example/terminal_services.dart --scripted-editor`, and
the same command with `--editor-fails`. The ready screens exactly match the
earlier passed U6 plain captures at both required sizes, preserving visible
service and Super help.

For success, Ctrl+G opens a scripted inherited-stdio self-child at 120x40;
its ownership marker remains unobscured after resize to 80x24. Enter is sent
in its own call. The app returns at the current 80x24 size with exited 0 and
`Edited by scripted child`, then reflows cleanly to 120x40. For code 7, the
child begins at 80x24 and is resized to 120x40 while it owns the terminal.
Enter returns to a complete current-size app with exited 7 and the original
two-line draft unchanged. Resizing back to 80x24 retains that result; typing
`!` immediately edits the draft, proving focus returned.

Neither child-owned resize paints app title, border or help over the marker.
No stale marker rows survive either app return. This closes the required
U6 visual integration recheck after mouse-mode and cleanup changes.

## Limits and cleanup

These are injected-report observations, not physical mouse/trackpad input
or host protocol acceptance. Mode byte balance, branch absorption/rebuild
semantics, clipping/overlay routes and actual signal ownership need the
handed tests and source review; screenshots cannot prove them. Developer's
handoff names owned PTY checks for HUP/INT/TERM startup/window/suspension,
port opt-outs, terminal restoration and process-group cleanup. Designer did
not rerun those signal tests, AOT or a full suite, and makes no VM-reserved
signal claim.

No clipboard/notification/title/bell acceptance action or real editor,
agent or model ran. All three owned sessions quit with Ctrl+Q and were
checked absent or killed. The scripted children completed before quitting.
Sample file/directory cleanup is supported by the developer's owned PTY
tests; their paths were not independently discovered by this visual look.
U8 port wheel behavior remains pending its explicit handoff and original
comparisons, including current overflow-panel exceptions and closing guards.

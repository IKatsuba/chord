# CTUI-9 U6 service example visual pass

Handed implementation: signed `034f8bf`. Designer ran
`dart run example/terminal_services.dart --scripted-editor` in owned tmux,
and separately the same command with `--editor-fails`. Both were checked
at 120x40 and 80x24. Plain and ANSI captures are retained as u6-*.

Result: pass for the handed demo. Every service binding and both Super
line-navigation bindings are visibly listed at both required sizes. The
help wraps to two rows at 120 and three at 80, without clipping the final
Quit action. This closes U5's intermediate visual help limitation. Source
review/tests establish that labels derive from the real active KeyHelp
snapshot; screenshots establish visibility and readability.

Ready, empty and long-draft states remain coherent at both sizes. The
empty sample was reached with normal editing keys. The long first line
was typed literally; its caption remains one ellipsized row while the full
text wraps in the editable area and all help stays visible. No clipboard
copy was invoked to test payload; fake-service tests cover the complete
payload. Input focus remains active after editor return, demonstrated by
typing the long sample after success and `!` after failure.

Success: Ctrl+G left the alternate screen for a scripted inherited-stdio
self-child. At 80x24 its normal screen was filled with a child marker; a
resize to 120x40 left the marker intact and did not paint app furniture over
it. Enter was sent in its own call. The returned app drew at 120x40 with
Editor: exited 0 and the added `Edited by scripted child` line, then
reflowed cleanly at 80x24.

Failure: the explicit code-7 child likewise retained the normal screen at
120x40 and after resizing to 80x24. Enter returned to a complete 80x24 app
with Editor: exited 7 and the two original sample lines unchanged. Resizing
back to 120x40 preserved that state. Literal `!` then appeared at the draft
cursor immediately, demonstrating restored typing focus. No error dialog,
stale child rows or partial app repaint obscured either result.

All sessions quit with Ctrl+Q. The two editor sessions and the empty-state
session were checked absent, and the recorded failure parent PID was no
longer running after quit. No real editor, model or agent was launched.
Temporary sample deletion is covered by developer's owned PTY tests; this
visual pass did not independently discover or inspect its filesystem path.

No host clipboard/notification/title/bell action was invoked for acceptance.
This does not prove host protocol acceptance, AOT execution, physical
Command-key delivery, or signal cleanup. HUP/INT/TERM integration and demo
beforeExit cleanup accompany U7 in a new explicit handoff; QUIT/ABRT/PIPE/BUS
are VM-reserved and have no native workaround in this slice. U6 editor
ownership and cleanup must be rechecked after U7 introduces mouse/signal
modes. Earlier captures do not waive that integration requirement.

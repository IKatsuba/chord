# U11 window visual look

Developer unit 4e3bafb, original 577b58167. Pass at 120x40 and 80x24 in
owned tmux panes: `dart run example/chord/tool/dev.dart chord --fake` beside
`(cd ../chord && bun dev chord --fake --qa ctui21-u11)`.
Literal prompts and Enter were sent in separate calls.

Checked idle, text, thought collapsed/ctrl+o expanded, completed plan,
active permission and resize. Live plan at 80x24 matches spinner, working
line and checklist placement; digit1 allows and a later Esc rejects, both
with matching transcript results. Home at80 restores header and reports
12 lines below in both; End restores latest content. Compact header scrolls
away, removing the previous pinned-row difference. No U11 visual finding.

Recorded/staged differences: port version, sanitized worktree vs original
QA directory, omitted /help until slash commands, status ? hint deferred to
U14 (and therefore a wider right-facts variant at80). Per lead ? remains
literal at this U11 checkpoint. This is no claim that U14 help is complete.
Paired captures u11-* and side-by-side comparison files are saved.

At20 columns, an incidental existing plan truncation difference is recorded
as the lead-approved CTUI-19 follow-up in the design. It does not block U11.
No code audit, additional tests, suite or AOT run. Session reused for the
handed-over U12/U13 checks, then both owned panes quit through empty Ctrl+D.

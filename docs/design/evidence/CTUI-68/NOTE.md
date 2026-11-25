# CTUI-68 captures

Plain `tmux capture-pane -p` text of the port (`*.port.txt`) and of the
original (`*.original.txt`) in the same state at the same size, both on the
original's fake agent (`dev.dart chord --fake` and `bun dev chord --fake`),
prompts typed as named. Checkout paths in the headers are relabelled
`~/chorded-tui` and `~/chord`. Styles were compared cell by cell from
`capture-pane -e`; differences are listed in the handovers, not here.

- `u4-*`: the question box, commit 61a455bd. `askclaude` multi-select at
  120x40, `askdroid` Submit step and `askdimcode` own answer at 80x24.
- `u5-*`: the answered record, commit 524de282. Answered (`askcodex` with a
  secret, `askclaude` under its tool call), skipped, cancelled, and the same
  session resumed. The tool call's result line above claude's record is the
  original's `asked` mark, not in this unit.
- `u4-note-fixed-*`: the Note row after 2187bec2 and 7232ee2e.
- `u2b-*`: the asked call, commit 66b969f1. `askclaudeone` with its box
  open, `askclaude` answered and skipped, `askcodexwait` timed out, and the
  same transcript expanded with ctrl+o, where the call's own lines show.
- `u8-*`: plans by id, commit a794021d (CTUI-69). `plan` with the fake's
  plan capability only (`CHORD_FAKE_PLAN_CAPABILITY_ONLY=1` on both sides):
  live checklist at 80x24, finished record at 120x40; `proposal` on the
  plain fake once the draft is dropped, at both sizes.

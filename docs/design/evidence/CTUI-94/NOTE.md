# CTUI-94 evidence: a team change's body diff drawn from its source

Commit c5da7bb5. The original and the port side by side in tmux at 120x40
and 80x24, on the fake with an isolated, empty XDG_STATE_HOME:

    (cd ../chord && bun dev chord --fake --qa prop94)
    dart run example/chord/tool/dev.dart chord --fake --qa prop94

Prompt `propose`, `1` to save bugfix for this project, then prompt
`proposeagain`, the fake's change to the saved team.

- `*-1-change.txt`: the change proposal with its body diff and the
  "Replace team bugfix?" box; long diff lines wrap under their code
  (`7 + 5. tester runs the whole suite once more, without asking, and the`
  / `lead reports to main.` at 80x24).
- `*-2-expanded*.txt`: after ctrl+o (`-scroll` holds the scrollback).

Every row matches the original at both sizes (header version, the qa
directory, relabelled `<project>`, and the working timer aside). Selection
itself is not shown here: a drag cannot be driven in tmux; the unit's
tests copy the text. Expanded team instructions were not captured: the
fake's saved team starts a real claude lead, which captures must not do.

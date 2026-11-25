# CTUI-85 evidence: Enter in a background detail goes to the call's own row

Commits 6cd9b859 (lib) and 2dea2ac2 (port). The original and the port
side by side in tmux, on the fake with `CHORD_FAKE_CHILD_RUNTIME=fake` and
an isolated, empty XDG_STATE_HOME (task agents on the fake runtime only):

    (cd ../chord && bun dev chord --fake --qa <name>)
    dart run example/chord/tool/dev.dart chord --fake --qa <name>

- `*-0-home` … `*-3-jumped` (120x40, 80x24): prompt `tasktwo`, three
  `text` prompts, Home, ↓ Enter (background view), ↓ Enter (Watch the
  deploy's detail), Enter. Too little to scroll far: both clamp the same.
- `*-4-long-deploy-jumped` (120x40, 80x24): ten `text` prompts, then the
  same: both put `└─ Agent(Watch the deploy) …` on the top line.
- `*-80x24-5-build-detail` / `-5-long-build-jumped`: the first task's
  detail, then Enter: both put `├─ Agent(Watch the build) …` on top.

Every capture matches the original's row for row (header version, the qa
directory, relabelled `<project>`, and timers aside).

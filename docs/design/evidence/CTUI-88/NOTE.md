# Captures

`../chord` (`bun dev chord --fake`) beside the port (`dart run
example/chord/tool/dev.dart chord --fake`) in tmux at the size in the file
name, one session each, in this order: the fake prompt `permission` (the
permission box), Esc, `/model` (a PickerList picker), Esc, `askclaude` (the
question box), Esc Esc, `monitors` then ↓ Enter (the background view).
`.ansi` is `capture-pane -p -e`. The focused `❯` row is drawn in the
permission colour with no bold in the permission box, the model picker and
the question box in both; the background view's focused name stays bold in
both. The header's working directory is relabelled `<working directory>`;
the version line differs and is not a finding.

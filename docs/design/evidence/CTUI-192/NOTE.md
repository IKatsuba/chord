# CTUI-192 U4: the by-hand note of `chord acp`

Captured at commit b368553e0 with `dart run bin/chord.dart acp x --agent-command true`
in a tmux pane whose stdin is a terminal, at 120x40 and 80x24. macOS ran on the
maintainer's host; Linux ran in the CI-like container (Ubuntu, x86_64). The
captures keep chord's two stderr lines only: the shell prompt and, on Linux,
the Dart tool's first-run telemetry banner printed above them are not chord's
and are left out.

- macOS: the second line names Ctrl-D or Ctrl-C. Ctrl-D left at 120x40, Ctrl-C
  left at 80x24.
- Linux: the second line names Ctrl-C alone. Ctrl-D at 120x40 did nothing and
  the note stayed; Ctrl-C then left at both sizes.

Both lines are 78 columns or fewer, no wrapping at 80x24, no escapes.

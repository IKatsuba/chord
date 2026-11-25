## 0.71.0

- Initial release of the chord_tui framework; requires Dart 3.11.0 or later.
- Widgets, layout in cells, keys and actions, rich text, Markdown, code,
  diffs, pickers, forms and a headless tester for terminal interfaces.
- `openSystemUrl` uses PowerShell `Start` on Windows and on WSL when
  available outside containers and SSH, otherwise the platform opener.
  It reports only failure to start the opener, ignoring its exit code.
  `open` and `xdg-open` run detached; PowerShell is awaited.
- `Terminal.setUserVariable`, `userVariableBytes` and `tmuxPassthrough`
  for OSC 1337 user variables and tmux forwarding.
- `TextArea` with OpenTUI's default editing keys, keyboard selection,
  `selectionStyle` and the `editingKeys` catalog. `TextAreaController` has
  `TextSelection`, selecting moves, word and line deletes, and logical-line
  and displayed-row movement; logical-line edges step over line breaks.

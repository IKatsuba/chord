# CTUI-65 captures

Text captures (`tmux capture-pane -p`) of the port beside `../chord` on the
fake agent, at 120x40 and 80x24, with isolated `XDG_CONFIG_HOME` and
`XDG_STATE_HOME`. The scratch directory the runs used is relabelled
`<scratch>`; the loopback port in chord's server row is whatever the run got.

## U3 (CTUI-75): /mcp's lost-servers note

- `u3-no-servers-port-*`: a `.mcp.json` holding `{`, no servers passed. The
  note follows the none line with no blank row, as `McpPanel` draws it with
  zero servers. The original always lists its own server, so its nearest
  state is `u3-no-mcp-servers-original-*` (`--no-mcp-servers`), which has a
  server row and so a gap before the note.
- `u3-three-files-*`: a bad `mcpServers` entry in the user settings, two in
  `.mcp.json` and one in `.chord/settings.json`. The note reads the same in
  both, with the comma before "and" (`Intl.ListFormat('en')`). The original
  wraps the note's last row out of its 80x24 panel; the port shows it whole
  because it has no chord row (see below).

Not part of U3: the port's `/mcp` lists no `chord` row ("chord itself") and
no "chord's server gives fake …" line, which the original shows on the fake,
with or without `--no-mcp-servers`.

## U10b (CTUI-78): the cursor while a chord waits

`u10b-*`: the fake, a draft typed, then ctrl+x (`chord-waits`), then `a`
with nothing waiting (`nothing-waits`). Each capture ends with tmux's
`cursor_flag` and position. The cursor is hidden while ctrl+x waits and is
back at the draft afterwards. Apart from the version, the port and the
original read the same at both sizes.

## U9 (CTUI-76): chord's commands while the agent starts

`u9-*`: the fake held at start (`CHORD_FAKE_HANG=start`), Esc from the
splash, then each command and Enter, in one session at 120x40 (so the
transcript builds up) and again at 80x24 for the held prompt, /help and
/status. The prompt `hello` stays in the box. /help, /cost, /clear, /theme,
/mcp and /resume read as the original's, and /model opens nothing in either.
/status lacks the original's `Title: not given` row, an older gap filed as
CTUI-113. After the fix in ab78d3b3, closing the terminal after /clear
during the start leaves no chord or fake process, as with the original.

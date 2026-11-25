# CTUI-34 captures

Each state is captured from the port (`*-port.txt`) and from the original
(`*-original.txt`), both on the original's fake agent, at the same size.
The working directory in the header is relabelled `~/work/project`. Each
run read a throwaway `XDG_CONFIG_HOME` whose `chord/settings.json` holds two
servers, `docs` (http) and `files` (stdio).

## U2: the held-back line at session start

- `u2-no-http-*`: the fake runs with `CHORD_FAKE_NO_HTTP=1`, so it takes no
  HTTP servers, and `docs` is held back.
- `u2-no-mcp-servers-*`: `--no-mcp-servers` holds back every server.

The one difference is chord's own server (`chord (http, chord's own)` and
its sentence), which the port leaves to M4. Otherwise the wording, the
wrap and the amber colour (`#ffc107`, checked with `capture-pane -e`) match.

## U4: --no-mcp-servers repeated in resume commands

Run from a clean `git archive` of the unit's commit, so no one's work in
progress is compiled in. Both chord's run from a scratch directory `here`,
with `--no-mcp-servers`, on their own state directories, each holding one
fake session recorded earlier in a sibling directory `elsewhere`. The agent
is the original's fake, started through a one-line script, `fast.sh`.

- `u4-picker-*`: `/resume`, Ctrl+a for every directory, the `elsewhere`
  session selected.
- `u4-refusal-*`: Enter on it: the refusal naming the directory, with the
  command that opens it there, `--no-mcp-servers` before `--resume`.
- `u4-quit-*`: a prompt, then Ctrl+D twice: the resume line on quit.

Paths are relabelled character for character, so every line keeps the
width it was drawn at: the scratch directory reads
`/var/configs/xx/neutral-throwaway-config-place/c/run.capture-01`.
Session ids and the relative times differ between runs. The original's
held-back line for its own server is M4's, as in U2.

## U3: the /mcp panel

Run from a clean `git archive` of 5678fc29, the unit with both of its
fixes. Both chord's run from the scratch directory `here`, on a config
whose `chord/settings.json` holds `docs` (http), `files` (stdio, `npx -y
@modelcontextprotocol/server-filesystem .`) and `bad` (`"command": 3`).
Paths are relabelled character for character, as in U4.

- `u3-no-http-*`: the fake with `CHORD_FAKE_NO_HTTP=1`, then `/mcp`:
  `docs` not passed, with its note and the ignored-server note.
- `u3-closed-*`: Esc on that panel.
- `u3-no-mcp-servers-*`: `--no-mcp-servers`, then `/mcp`.
- `u3-starting-*`: an agent that takes 15 seconds to start, Esc on the
  splash, then `/mcp`: the starting line, full width.

The differences are all chord's own server, left to M4: its row, its
line under the table and its part of the held-back line. With one row
and one line fewer, the port's panel has room for the ignored-server note
where the original's is cut at 80x24.

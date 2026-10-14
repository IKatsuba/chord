# CHD-173 build captures

Taken by the engineer for the designer. Only the fake agent ran. HOME, XDG
config, state and cache were fresh under a `mktemp -d /tmp/chd173.XXXX`
root, with `fake` and `fake2` defined in that HOME's settings file, both on
`tests/fixtures/fake_agent/main.ts`.

Three tabs from `proj`: `text` on fake, ctrl+x c then `tools` on fake,
`/new fake2` then `text` on fake2. Tab 2 brought to the front (tab 3 at
80x24), then ctrl+d.

- `*-quit.txt`: the shell after quitting — the one printed command,
  `Resume this window with:` / `chord --resume w-…`.
- `*-resumed.txt` / `.ansi`: that command run from another directory: the
  three tabs in order, the recorded front tab in front (inverse in the
  `.ansi`). The transcript in each tab is the fake agent's replay on load.
- `*-missing.txt` / `.ansi`: tab 2's session record deleted, the window
  opened again: the other two tabs, and the status line naming the one left
  out.
- `*-refuse-mixed.txt`: `--resume w-… -r <id>` refused, exit 2.

Quitting the window opened from its record rewrote that record: one file
under `windows/`, the same id, its front tab as it was at the second quit.

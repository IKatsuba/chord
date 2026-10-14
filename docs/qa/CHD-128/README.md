# CHD-128 — quit is bounded on a wedged agent

Independent QA of the return fix on main `f0594a7`, including starting mode,
retired/replacement sessions after `/clear`, resize, errors, interrupt recovery,
compiled launches and exact terminal restoration, is in
[independent/README.md](independent/README.md).

chord from source against the fake agent started with `CHORD_FAKE_HANG`, so
it never answers one step and ignores SIGTERM and its stdin closing, at
120×40 and 80×24, from a shell in the pane so what quitting leaves is seen.

- `config`: `/config` → Effort → High sent, never answered; then ctrl+d.
- `turn`: the prompt `text`, never ended; Esc (stays `Interrupting…`); then
  ctrl+d.
- `start`: `initialize` never answered (`Starting fake…`); then ctrl+d.
- `starting-model`: chord started with `--model fake-small` on
  `CHORD_FAKE_HANG=config`, so the session opens and the starting model is
  never answered (`Starting fake…`); then ctrl+d.

For each, `*-before-quit.txt` is the screen before ctrl+d, `*-stopping.txt`
one second after, and `*-after-quit.txt` the shell once chord exited, with
`stty`'s `icanon` and `echo` printed after it. `*-config-values.txt` is the
effort list just before High was chosen.

| case           | size   | quit took | alternate screen | cursor | agent left |
| -------------- | ------ | --------- | ---------------- | ------ | ---------- |
| config         | 120×40 | ~7 s      | off              | shown  | none       |
| turn           | 120×40 | ~4 s      | off              | shown  | none       |
| start          | 120×40 | ~3 s      | off              | shown  | none       |
| config         | 80×24  | ~7 s      | off              | shown  | none       |
| turn           | 80×24  | ~4 s      | off              | shown  | none       |
| start          | 80×24  | ~3 s      | off              | shown  | none       |
| starting-model | 120×40 | ~5 s      | off              | shown  | none       |
| starting-model | 80×24  | ~5 s      | off              | shown  | none       |

The times include the polling of the script that measured them (about 2.5 s);
the `starting-model` ones about 1.5 s. Its alternate screen and cursor were
read from tmux's `alternate_on` and `cursor_flag`, and the agent's pids were
taken from the pane's process tree before ctrl+d.
The repository's path in the printed resume command is written `<repo>`.

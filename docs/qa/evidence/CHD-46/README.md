# CHD-46 independent QA

Checked implementation `9bb9dfc` on 2026-10-05. Designer-approved appearance
was left accepted. These captures are independent of the designer's captures.

## Commands and setup

- `deno task check`: 267 tests, 20 steps, no failures. The initial sandboxed
  attempt failed in fixture/UI tests; the unchanged run with local process
  access passed.
- `deno task compile`: produced `dist/aarch64-apple-darwin/chord`.
- Source launch: `deno run --allow-all src/main.tsx fake -C <scratch>
  --agent-command <temporary-fixture-launcher>`.
- Compiled launch: `dist/aarch64-apple-darwin/chord` with the same arguments.
- The launcher executed the existing `tests/fixtures/fake_agent.ts` through
  Deno, with the repository's Deno config. The changed command added
  `--resume-only`, advertising non-replaying ACP `session/resume`.
- Each flag used separate temporary working and `XDG_STATE_HOME` directories.
  An isolated tmux socket hosted a plain shell, first at 120x40, then 80x24.
  All TUI actions were keys: literal text and Enter sent separately, Esc,
  and two Ctrl+C presses to quit. Captures waited for settled output.

## Observations

For each of `--continue` and `--resume <id>`:

1. Sent `tools`, then `text`, and quit. The terminal printed a resume command
   containing the agent's ACP session UUID.
2. Changed the agent command to include `--resume-only`. At 120x40 the first
   resume showed the earlier prompts, `Read(README.md)`, `Read it.`, and the
   text reply. Sent `/echo NEW-TURN`; it was answered in place.
3. Quit and resumed a second time with the compiled binary at 80x24. All
   earlier turns and `NEW-TURN` remained, once each. Sent `/echo OK` and got
   `OK`. Original and migrated records, read through the session-store API,
   retained the UUID printed on quit.
4. Resized that resumed binary to 120x40; the earlier transcript and new
   answers remained. `error` showed the fake agent's failure reason. Esc
   interrupted `slow`, and `/echo AFTER-INTERRUPT` was answered afterwards.
5. Reopened the saved session with `CHORD_FAKE_REFUSE_LOAD=1`; the next prompt
   showed `could not be resumed` and `Resource not found`, without crashing.

An external UUID with no chord record exercised ACP `session/load`: its
replayed prompts, tool output and replies appeared at 80x24; a new prompt
was answered, and quit printed the same UUID. `no-such-session` produced a
clear start failure. Empty `--continue` produced a CLI error and exit 2.
The empty-directory capture contains only the error/exit excerpt.

Every TUI quit returned to the shell with `alternate_on=0`, `cursor_flag=1`,
and no remaining QA-owned fake agent in `/bin/ps`. Terminal modes matched
apart from macOS PENDIN; dimensions changed intentionally during the resize.
The isolated tmux server and temporary work/state were removed. A final
process scan found no QA-owned agent or tmux server. `verification.txt`
records the per-run readbacks.

The acceptance captures are `120x40-{continue,resume}-answered.txt` and
`80x24-{continue,resume}-answered.txt`. Other files show the second opening,
resize, errors, interruption, recovery and quit hints.

No live model or live agent was used. QA added evidence only: no component,
parser, protocol helper, dependency or production change. Existing acpx
runtime/store APIs and the ACP SDK fake fixture supplied the session work.
No new findings were filed; CHD-55 already tracks start-failure input behavior.

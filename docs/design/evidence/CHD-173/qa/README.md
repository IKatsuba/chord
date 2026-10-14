# CHD-173 independent QA

Checked current main at `6e43e9b`, including the window implementation
`5c8d0e5` and wording fix `5e8fa93`. Approved appearance was not reopened.
Only the fake ACP agent ran, named `fake` and `fake2`; no real agent or
model ran. HOME and all XDG directories were fresh under a temporary
`/tmp/chd173-qa-*` root. The original Deno dependency cache was reused.

## What ran

- `deno task check` in the foreground with process-query access.
- `deno task compile`, then the local compiled binary in the narrow matrix.
- Source at 120x40; compiled binary at 80x24. Each was also resized to the
  other size and back. An owned tmux server used the socket `chd173-qa`.
- A scratch `chord` launcher selected the source or binary. Settings defined
  both fake agents using the repository fixture and config. The single-session
  fallback was retaken with a temporary executable wrapper under `/tmp`, so
  the command it prints is public-ready too.
- All interaction used `tmux send-keys`: literal text and Enter in separate
  calls, with a pause between, and captures after redraws settled.

For each width, from `proj`: start `chord fake`, send `text`, ctrl+x c,
`tools`, `/new fake2`, `text`, ctrl+x 2, ctrl+d. Read the saved JSON.
From `elsewhere`, run the exact printed `chord --resume w-...` command.
Use ctrl+x 1/3/2 and `/status` to verify each session and directory, then quit.
Delete only the second tab's session JSONL file in this scratch state, run
that command again, and capture before any key clears the note. Resize and
restore, send `error`, send `slow`, Esc, then `text`, and quit.

Reopen, add a tab with ctrl+x c and send `text`, quit, reopen, close the
front tab with ctrl+x k, and quit. Read the record after each quit. Try a
window mixed with a session ID. Separately, open a fresh `fake` window, send
`text`, add an unprompted tab, and quit. Compare the existing window record
byte-for-byte. Capture `stty -a` and tmux terminal flags before and after.
Source and binary CLI probes tried mixed IDs in both repeated-option orders
and an absent window, checking exit status. Finally, inspect `ps` for the
unique `--qa-owner chd173-120` and `chd173-80` fake process tags and remove
the owned tmux server.

## What was observed

At both sizes, the three-tab quit printed one window command without an
agent name. The command restored `fake`, `fake`, `fake2` in order, with
recorded tab 2 in front. Its strip is inverse in `*-resumed.ansi`; its
header's first prompt is `tools`. Each `/status` had the expected session
ID, agent and recorded `proj` directory, despite launching from `elsewhere`.

One deleted session left the other two tabs open, in order, with the approved
short-ID note whole at both sizes. The absent front tab fell back to the
first remaining tab. The note cleared on a key, as other status notes do.
The partial quit rewrote the same record with two tabs. Growth to three and
shrink to two retained the same ID; only one window file remained. The
single-resumable-tab quit printed the existing session message and left
that window record byte-for-byte unchanged.

The deliberate agent error appeared as `The fake agent failed on purpose.`
Esc ended `slow` with `Interrupted by user`; the next `text` succeeded.
Resizing retained a usable prompt and the remaining tabs. Mixed IDs in
both orders and an absent window refused with exit 2, before TUI startup.

Quits returned to an interactive shell: `alternate_on=0`, `cursor_flag=1`,
`pane_dead=0`, canonical input, echo and signal handling restored. The
before/after termios flags are captured. No tagged fake-agent process
remained after the matrices, and the owned tmux server was removed.
Pre-existing processes were not signalled. See `cleanup.txt`.

## Evidence

- `*-quit.txt`, `*-resumed.txt/.ansi`, `*-missing.txt/.ansi`: acceptance screens.
- `*-record.json`, `*-rewritten.json`, `*-partial-record.json`,
  `*-grown-record.json`, `*-shrunk-record.json`, `*-window-files.txt`:
  ordered persistence and same-ID rewrite evidence.
- `*-tab-*-status.txt/.ansi`: each restored agent, session ID and directory.
- `*-error`, `*-interrupt`, `*-recovered`, `*-resized`: behaviour and recovery.
- `*-single-resumable-quit`, `*-before-terminal.txt`, `*-final-terminal.txt`:
  single-session fallback and terminal restoration.
- `*-mixed-*-exit.txt`, `*-absent-window-exit.txt`: source/binary exit probes.

Captures are raw tmux text and ANSI, not normalized. Fake `session/load`
replays its canned past, as in CHD-172; no claim is made about live-agent
history fidelity. `--continue` was not changed by CHD-173; its automated
coverage ran in the full check. No live-agent hand check was needed.

No implementation was added during QA. The existing Cliffy collect option,
zod schema validation and platform JSON/crypto were exercised. The earlier
Cliffy variadic trial and owner's repeated-option choice are documented in
`docs/decisions.md`; QA wrote no parser, renderer or protocol helper.
The known duplicated why comment is already filed as CHD-236. No additional
finding was filed in this run.

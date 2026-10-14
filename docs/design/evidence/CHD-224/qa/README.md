# CHD-224 independent QA

Tested `81f7a52` on `main` after the designer and reviewer passes. These are
independent whole-screen tmux text captures. The fake ACP agent is the only
agent used. Its step duration was 40 ms; config and state were isolated in
temporary XDG directories, with `/tmp/chd224-qa/work` as the session directory.

## What ran

- `deno task check`, in the foreground with process access for fixture cleanup.
- `deno task compile`, then the compiled macOS arm64 binary in tmux.
- Source and parent commit (`81f7a52^`) with identical fake-agent commands and
  session directory, at 120x40 and 80x24; fresh source also at 44 columns.
- Fresh single session; ctrl+x c to two sessions; ctrl+x k back to one;
  resize; 16 text turns; Home and End; error; slow plus Esc; recovery; /status.
- Explicit `-r` resume of a session created during QA, source and compiled,
  at both required sizes; source two-to-one closure after resume at both sizes.
- Compiled error, interruption and recovery at 80x24.
- Ctrl+d quit, tmux terminal flags, before/after `stty -g`, shell input, and
  `ps` checks of observed app and fake-agent descendants.

## What was seen

- One fresh session starts with `chord v0.0.0` on row 1, followed by agent,
  model, directory and help. No duplicate row exists at 120, 80 or 44 columns.
- Two-session whole frames match the parent commit byte for byte at 120x40
  and 80x24: strip on row 1, header on row 2. Strip source files are unchanged.
- Closing back to one session immediately removes the strip; the header moves
  to row 1 without a blank or stale row, including after resume and in the binary.
- Overflow starts with transcript on row 1. Home restores the header; End
  follows the latest reply. The recovered row is visible in the paired Home
  captures: 50 versus 51 hidden rows at 80x24, 34 versus 35 at 120x40.
- Resumed source and compiled sessions show the header on row 1, then the
  resumed first-prompt wording and replayed tools/text. `/status` still names
  agent, model, mode, session and directory. No wording refers to a title bar.
- The fake error says `The fake agent failed on purpose.` Esc says
  `Interrupted by user`; subsequent prompts complete successfully.
- Quits return exit code 0, leave the alternate screen (`alternate=0`), restore
  cursor visibility (`cursor=1`) and exactly restore `stty -g`. Resumed source
  and compiled shells accept and execute a command after quit.
- All observed QA app/agent PIDs are absent after quit. The isolated tmux server
  and temporary parent checkout were removed; owner sessions were untouched.
- `deno task check` passed: 1200 tests, 20 steps, 0 failures (6m18s). Compilation
  passed. All 51 text captures have their expected row counts and pass a scan
  for private home paths and names. `git diff --check` passed.

Layout/scroll inspection agrees with runtime proof: entry positions are measured
relative to content, viewport height is measured after layout, and mouse clicks
have no entry-selection mapping to offset. No new library was tried because
the product change removes code and introduces no component, parser or helper.

Appearance was already passed by the designer and was not reopened. No live-agent
compatibility claim is made. No new minor task was needed: CHD-226 already tracks
the pre-existing CLAUDE.md placement prose. CHD-211 should close as moot with
CHD-224. Unrelated untracked evidence was left alone.

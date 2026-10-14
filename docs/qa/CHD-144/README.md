# CHD-144 QA

Checked `ec10742` on `main`. The designer-approved appearance is settled.

## Commands run

- `deno task check` with process access for fake-agent cleanup.
- `deno task compile` for the host target.
- The resulting `dist/aarch64-apple-darwin/chord` in an isolated tmux server,
  at 120×40 and 80×24, with separate scratch working, config and state directories.
- Keyboard-only prompts: `plan`, `proposal` twice, `error`, `plan` interrupted
  with Esc, then `text`; ctrl+d to quit. The wide run also resized a running
  plan to 80×24 and back to 120×40.
- A temporary Deno probe using the real fake session with `openSession`, `Reply`
  and `resultJson`, asserting every proposal markdown snapshot, streamed output,
  and the final removal. Then the compiled CLI's `-p proposal` with text and
  JSON output, asserting output, exit code 0 and empty stderr.
- `stty -g` before and after; tmux alternate-screen and cursor flags after quit;
  raw terminal bytes for alternate-screen exit and cursor restoration; `ps` for
  agent cleanup; `git diff --check`; evidence privacy scan.

The TUI used `CHORD_FAKE_PLAN_CAPABILITY_ONLY=1`. Its agent command was:

```sh
deno run --quiet --allow-env --config "$PWD/deno.json" "$PWD/tests/fixtures/fake_agent.ts"
```

For reproduction, create a scratch directory and pass `-C` to the binary;
set `XDG_CONFIG_HOME` and `XDG_STATE_HOME` to separate directories there.
Send literal prompt text and Enter separately through tmux. The normal fake
step delay was kept for TUI captures. The headless probe used
`CHORD_FAKE_STEP_MS=0.1` to shorten the deterministic scenario.

## Observations

- Full check passed: 856 tests (20 steps), 0 failed.
- The staged evidence privacy suite passed: 7 tests, 0 failed. Its first
  focused invocation omitted the required write permission; the corrected
  command used all permissions from the repository test task.
- Compile succeeded and the compiled TUI started at both sizes.
- The capability-gated items plan showed ☒, ◐ and ☐ directly above the prompt,
  progressed through its steps, and became a completed Plan transcript block.
- At both sizes, the proposed markdown plan changed from `1. Read the code` to
  `1. Inspect the code` in one block, then gained `2. Write the change`.
  Removal dropped only that draft; `I'll look first.`, the file URI and
  `Plan written. Draft dropped.` remained.
- Two proposal turns had separate file entries. The second draft's rewrites and
  removal left the first turn's replies and file entry intact.
- Resizing during a plan preserved the list and usable prompt at both sizes.
- `error` displayed `The fake agent failed on purpose.`. Esc during a plan
  displayed `Interrupted by user`; the following `text` turn completed.
- JSON followed the latest markdown snapshot after both rewrite and growth,
  independently of append-only stdout. Withdrawal removed the draft from the
  final result. See `headless-snapshots.json`, `headless-result.json` and
  `headless-text.txt`. The existing headless regression also covers a final
  rewritten-and-growing plan that is not removed.
- After both quits, the shell returned, alternate screen was off and cursor
  visible. `stty -g` matched its baseline exactly; raw terminal output also
  contained alternate-screen exit and cursor restoration. See `cleanup.txt`.

No production code, fixture or dependency was changed by QA. No component,
renderer, parser or protocol helper was written, so no new library trial was
required; checks exercised the existing SDK transport, Ink and reducer.
No live Claude or Codex check was performed. Fake evidence proves capability
negotiation and rendering, not current live Codex integration.
No separate minor findings were identified.

# CHD-145 QA

Checked `8e9f934` over `703f0db` on `main`. Appearance remains settled.

## Commands run

- `deno task check`, with process access for fake-agent cleanup.
- `deno task compile`; the resulting host binary in a dedicated tmux session
  at 120×40 and 80×24, with scratch work, config and state directories.
- Fake command: `deno run --quiet --allow-env --config "$PWD/deno.json"
  "$PWD/tests/fixtures/fake_agent.ts" --resume-only` (absolute paths at launch).
- Keyboard prompts: `look at @src/a.ts @docs @nope.ts and @"my notes.md"
  @src/a.ts`, `check @docs @missing.ts done`, `error`, `slow` then Esc.
  Ctrl+D quit; `--continue` reopened the record; Home inspected its beginning.
  Resized both ways, sent `text` and `again @src/a.ts @"my notes.md" done`,
  then quit with Ctrl+C twice.
- Inspected the JSONL prompt entries, `stty -g` before/after, tmux
  alternate-screen/cursor flags, raw terminal bytes and owned processes with
  `ps`. Removed the tmux session after the shell returned.
- Read SDK 1.7.0's `PromptRequest` and `PromptCapabilities` type documentation.

## Observations

- Full check passed: 864 tests, 20 steps, 0 failed (4m23s), including the
  fake-backed link, sent-record, cancelled-unsent-record and replay cases.
- The staged public-evidence privacy check passed: 7 tests, 0 failed.
- Compile succeeded and the binary started and accepted keys.
- SDK v1 explicitly requires Text and ResourceLink as baseline blocks;
  `embeddedContext` enables Resource alone. The fake takes links without
  advertising embedded context.
- Exactly two links arrived in typed order: `src/a.ts` and `my notes.md`.
  Their URIs were absolute file URLs, with the space encoded as `%20`.
  The repeated file mention produced no duplicate; directories and missing
  paths produced no link. The original prompt stayed as typed.
- At 80×24 the links reflowed, and the prompt remained usable. A prompt
  without mentions produced no Received link lines.
- The record retained unchanged text and both resolved link names/URIs.
  Reopening through the fake's `session/resume` drew the typed prompt once,
  with no URI appended to it. A follow-up mention prompt sent both links.
- `error` displayed `The fake agent failed on purpose.`; Esc during `slow`
  displayed `Interrupted by user`; the later `text` turn completed.
- Both quits returned to the shell with alternate screen off and cursor
  visible. Raw bytes contain alternate-screen exit and cursor-show sequences.
  The first `stty -g` comparison matched exactly; the second differed only in
  macOS PENDIN. Canonical input, echo and signals were restored.
- Final process inspection found no remaining QA binary, test runner or fake
  agent. The dedicated tmux session was removed.

No production code, fixture or dependency changed. QA wrote no component,
parser, renderer or protocol helper. The engineer's documented parser trials
rejected linkifyjs/plugin, twitter-text and shell-quote for concrete prose/path
parsing failures; QA did not rerun those trials. Walking and URL creation use
globby and `@std/path`. No live agent was used. No minor findings were found.
The documented `-p` exclusion and trailing-comma behavior remain lead choices.

# CHD-265 independent QA

Change: `6398108`, on `main`. Designer-approved appearance was preserved.

## What ran

- `deno task check`, in the foreground with process-inspection access for
  fake-agent cleanup.
- `deno task compile`, producing `dist/aarch64-apple-darwin/chord`.
- Source TUI against `tests/fixtures/fake_agent/main.ts`, driven only by
  tmux keys, at 120×40 and resized to 80×24. Selected `fake-small`, completed
  81 ordinary fake turns, and ran `/context` at 1%, 80% and 81%.
- Compiled TUI at 80×24: the default long fake model name, `/vim`, then
  shift+tab to accept-edits mode, a prompt and `/context`.
- Compiled TUI with `--tokens-only` at 120×40 and resized to 80×24;
  compiled TUI with `--no-usage` at 80×24. Prompt and `/context` in each.
- Source TUI at 80×24: `error`, `slow`, Escape, then `text` to recover.
- Ctrl+d to quit all four windows; tmux terminal flags, before/after
  `stty -g`, shell readiness, owned tmux-server removal and `ps` inspection.
- Capture privacy scan, terminal-cell width checks using existing
  `string-width`, and explicit ANSI checks at the warning boundary.

All manual runs used a neutral scratch working directory and isolated
`XDG_CONFIG_HOME` and `XDG_STATE_HOME`. No real model or live agent ran.

## What was observed

| Check | Result and evidence |
| --- | --- |
| Ordinary wide and narrow line | `Fake Small · 1% context used` fits without wrapping: `qa-source-120-used.txt`, `qa-source-80-used.txt`. |
| Shared percentage | `/context` shows Used 2,000/200,000 (1%), Free 198,000 (99%): `qa-source-120-context.txt`. |
| Exact warning boundary | 160,000/200,000 is 80% used, dim/plain; 162,000 is 81% used, yellow `38;2;255;193;7`: `qa-source-120-80-plain.ansi.txt`, `qa-source-120-81-yellow.ansi.txt`. |
| High usage after resize | 81% remains yellow at 80×24: `qa-source-80-81-yellow.ansi.txt`. |
| Boundary reports | `/context` agrees with the current status figure at 80% and 81%; Free is 20% and 19%: `qa-source-120-80-context.txt`, `qa-source-120-81-context.txt`. Earlier report entries retain their historical values. |
| Short form at 80 columns | Vim's insert mark plus accept-edits mode constrains the line to `Fake Large with a 1M context win… · 1% used`. The cycle hint disappears before the model is shortened. `/context` agrees: `qa-compiled-80-short.txt`, `qa-compiled-80-short-context.txt`. |
| Estimates | Compiled tokens-only fixture shows `GPT-5.3 Codex · ~1% context used`; `/context` reports 2,000/400,000 (1%) with the estimate note. Both widths fit: `qa-estimate-*.txt`. |
| Missing usage | Compiled no-usage fixture draws the model with no percentage; `/context` says the agent has not reported fullness: `qa-unknown-*.txt`. Explicit size-zero omission is covered by the existing pure status/report tests in the full suite. |
| Error and interrupt | The deliberate agent error is visible, Escape produces `Interrupted by user`, and the next prompt succeeds with 82% used: `qa-source-80-error.txt`, `qa-source-80-interrupt.txt`, `qa-source-80-recovery.txt`. |
| Terminal cleanup | Every window returned to a usable shell with `alternate=0`, `cursor=1`, and exactly matching before/after `stty -g`. The owned tmux server was removed; no manual QA agent remained. |
| Evidence hygiene | All captures fit their terminal width and contain no private home path. |

No task-owned defect was found. The already-filed CHD-267 documentation
wording and CHD-268 intermittent permission-test helper issue remain separate.
No new component, parser, renderer, protocol helper or dependency was added;
this wording/arithmetic change requires no library trial.

## Final validation

`deno task check` passed: 1,398 tests, 20 steps, zero failures, 7m45s.
`deno task compile` passed and its binary ran the three compiled scenarios
above. The staged-evidence privacy test passed all seven tests;
`git diff --cached --check` passed. Final process inspection found no check,
manual QA agent or QA tmux server left running.

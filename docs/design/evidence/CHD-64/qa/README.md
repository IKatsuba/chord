# CHD-64 independent QA

Product revision: `a5c4773` on `main`. These are QA's own tmux captures,
separate from the engineer's captures in the parent directory. `.ansi` keeps
the terminal colours; `.txt` is the same capture through strip-ansi, with
trailing padding removed. `.ansi` retains the background's full padding.

## Runs

- `deno task check`, with inherited `NO_COLOR=1`: 361 tests and 20 steps passed.
  The first sandbox-limited run was stopped before rerunning unchanged with
  process-query access for the suite's `/bin/ps` cleanup assertions.
- `deno task compile`: the local macOS arm64 binary built successfully.
- Source: `deno task chord:fake -C /tmp/chd64-qa/work`, with isolated
  `XDG_STATE_HOME`, `NO_COLOR` unset and `COLORTERM=truecolor`. In an isolated
  tmux server at 120x40, sent `markdown`, then `edit`; PgUp showed the quote.
  Resized to 80x24, End showed shell and edit, and PgUp twice showed TypeScript
  and quoted code. Literal text and Enter were separate sends.
- Source at 80x24: sent `error`, then `slow`, Esc, and Ctrl+D.
- Compiled binary: same isolated work directory and its own state directory,
  using `--agent-command` for a scratch copy of `tests/fixtures/fake_agent.ts`.
  Sent `markdown` at 120x40, resized to 80x24, then sent `edit` and `rewrite`;
  Ctrl+O expanded the latter. Ctrl+C twice quit.
- Source under `NO_COLOR=1`: repeated `markdown` and `edit` at 120x40,
  PgUp to the quote, then resized to 80x24 and End. Ctrl+D quit.

The compiled run's scratch copy of the fake markdown reply appends this input:

~~~~markdown
- Quoted multiline code:
  > ```ts
  > /* first comment line
  > second comment line */
  > const longName = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz";
  > ```

```unknown-language
const plainUnknown = 123;
```

```
const plainMissing = 456;
```
~~~~

Only the copied fixture's relative import of `src/session/context.ts` was
redirected to the original module. The first attempt with that import still
relative failed during initialization and displayed the error in the TUI;
the captures here are from the corrected scratch fixture. Repository fixtures
and product code were unchanged.

## Observations

- TypeScript and shell tokens are coloured, including quoted code. Both lines
  of the nested comment and both wrapped string fragments retain their colours.
  Missing and unknown labels remain plain.
- Changed diff rows use the light token sheet on red/green tints, while context
  uses the terminal sheet. Signs, numbers and content match the fixture;
  the expanded rewrite preserves separate hunks, deletions and narrow clipping.
- Captures have at most their terminal's width in cells. Tinted rows reach the
  transcript's right content boundary (column 79 or 119); the existing outer
  one-cell padding remains. Colours stay inside the boxes and diff rows.
- NO_COLOR adds no syntax colours or diff backgrounds. The existing inline-code
  blue remains, as documented and accepted earlier in the task.
- The intentional agent failure is shown as `The fake agent failed on purpose.`
  Esc produces `Interrupted by user` and returns control to the prompt.
- All three panes returned to their shell with `alternate_on=0` and
  `cursor_flag=1`. Before/after `stty -g` differs only by macOS's PENDIN bit;
  canonical input, echo, controls and speeds are restored. Final `ps` found no
  fake-agent or check processes. The QA-only tmux server was removed.
- No live agent or model was used. The approved design was not reconsidered.

emphasize 7 and wrap-ansi were exercised under source and compiled runs.
The library choice and earlier markdansi-hook, shiki and cli-highlight trials
are recorded in `docs/decisions.md`; QA added no tokenizer or renderer.

# CHD-266 QA

Tested implementation b1c8e6d on main 0d71913. The owner's option-A decision
and the designer's approval are the acceptance; appearance was not reopened.
The owner explicitly left CHD-279's dim-after-bold limitation for later.

## Commands and keys run

- `deno task check`, unchanged, with process-inspection access, in the
  foreground. Final ordinary run passed types, lint, formatting and 1488
  tests (20 steps), zero failed, in 9m2s. No dimension or colour overrides,
  test fixes or skips were used for this passing run.
- `deno task compile`; the resulting `dist/aarch64-apple-darwin/chord` started
  and ran the same fake-agent scenarios as source.
- Source: `deno task chord fake --agent-command "deno run --quiet --allow-env
  --allow-net=127.0.0.1 --config '$PWD/deno.json'
  '$PWD/tests/fixtures/fake_agent/main.ts'" -C /tmp/chd266-qa/work`.
  Compiled: replace `deno task chord` with the compiled binary.
- Four sessions on an isolated tmux server: source dark, source light,
  compiled dark, compiled light. Each used temporary XDG config/state,
  explicit theme settings, and `FORCE_COLOR=3`. No real agent or model ran.
- Start at 120x40. Type `agentlong`, then Enter in a separate send. Down,
  Down, Enter picks parser. Capture folded; ctrl+o expands; resize to 80x24;
  capture expanded and folded. Down, Up, Enter returns to main.
- `/clear`, then `task`: Down, Enter denies the task child's edit; wait for
  the failed report. Resize to 120x40. `/clear`, then `task`, Enter allows
  its edit; wait for the message and report; resize to 80x24.
- `/clear`, `monitorexit`: capture at both sizes. `/clear`, `monitorflood`:
  capture folded at both sizes; ctrl+o and Home inspect expanded output.
- In source light and compiled dark, `/clear`, `agents` captures queued
  incoming lines and outgoing rows. Down, Down, Enter picks parser; capture
  both sizes; Down, Up, Enter returns to main.
- `/clear`, `agentfail`, then `/clear`, `agentexit` proves chord's error and
  stderr messages. `/clear`, `long`, Esc interrupts; `text` proves recovery.
  The Esc/recovery captures are source light and compiled dark. The initial
  ctrl+c probe in the other two sessions armed quit, as designed; it is not
  counted as interrupt evidence.
- ctrl+d quits. Capture terminal state with tmux, compare `stty -g` before
  and after, inspect raw output for alternate-screen leave/cursor show, kill
  each owned tmux session, and inspect `/bin/ps -axo pid,ppid,pgid,command`.

## What was seen

Every incoming body is under the existing tool-result glyph at the body's
indent, distinct from the agent's reply. The long child instruction folds
with `+2 lines` at 120 columns and `+3 lines` at 80; expansion includes
`Tell me only what failed, if anything.` Markdown lists, code colours and
bold remain rendered. Width follows the shared tool-result gutter.

A denied task edit becomes `Fix the tokenizer · fake · failed`, with its
ACP error visible under the glyph. ANSI captures show the body in the error
colour: RGB 255/107/128 dark, 196/22/42 light. The glyph remains dim, without
a sender colour. Successful reports and intermediate task messages are dim.
Headers retain their runtime/report/failed labels. Outgoing rows keep their
existing shape and truncation; the queued incoming lines remain single lines
above the prompt box.

Monitor lines remain verbatim. The nonzero exit ends with `Exited with code
1 after 1s.` Flooding folds at `+95 lines`; chord's closing sentence remains
visible below the fold and wraps at the body indent. Expanded output has no
fold marker. Child turn failures and agent exits reach main as `← chord`,
with the failure/stderr reason visible in the indented dim body.

Esc stops a streaming turn, shows `Interrupted by user`, and a subsequent
`text` prompt receives `Hello, world. This reply came in chunks.` Resizing
preserves the messages and usable keys. All four quit checks returned to the
shell with tmux `alternate_on=0`, `cursor_flag=1`, and `pane_current_command=zsh`.
The before/after `stty` strings match exactly, and raw terminal output contains
both alternate-screen leave and cursor-show sequences. Recorded owned
agent/application PIDs are absent from the final process snapshot; no process
command names the QA temporary directory. Pre-existing processes were left
alone. See `cleanup.txt`; raw quit captures stay outside the repository because
the resume command contains the local fake-agent command path.

No component, renderer, parser, protocol helper, or dependency was written.
The library trial for this QA was the existing Ink Under/Folded and markdansi
path in the actual source and compiled terminal runs.

## Separate findings

CHD-280 records the repeated early wrap before an inline-code span at 80
columns (see `source-dark-report-80.txt` and `compiled-light-report-80.txt`).
The markdown module is unchanged by CHD-266; the approved narrower gutter
exposes this existing wrapping behaviour. It does not return this change.
CHD-279 remains owner-accepted. The known sandbox process-query hang is already
tracked as CHD-273; this check was run with the necessary access from the start.
The first full check reproduced CHD-268: the MCP permission test missed its
transient submitted-prompt row, while its expected dialog was already visible.
It ended with 1487 passing tests and one failure in 9m16s. The unchanged isolated
test then passed in 646 ms. The reproduction was added to CHD-268, without a
duplicate task or a test-helper change; the full check was rerun unchanged.
The second non-TTY run repeated the same lone failure (9m5s). Terminal probes
showed two harness assumptions: a short terminal can scroll the submitted row
away, and ANSI styles break the literal gutter assertion. The unchanged
isolated test passed in a 120x40 terminal with `FORCE_COLOR=0` (514 ms); the
full check was then run in that explicit plain-text terminal environment.
That environment is unsuitable for the whole suite: the permission test
passed, but two NO_COLOR subprocess tests inherited FORCE_COLOR and failed
(1486 passing, two failing, 9m3s). No passing full-check claim is based on it.
Ink's existing terminal-size library supports COLUMNS/LINES for piped output,
so a dimension-only full-run probe supplied those without colour variables.
That full run passed the permission and NO_COLOR checks but exposed a separate
splash-test resize race: its initial larger frame satisfies the text wait
before the explicitly requested 80x24 frame settles (1487 passing, one failing,
8m46s). Filed separately as CHD-281. The ordinary unchanged full check was
then run again; none of the environment probes are counted as a green gate.
The next ordinary run passed those UI checks but reproduced existing CHD-79's
shell-stop observation race (1487 passing, one failing, 9m5s). Its sleep was
absent in the subsequent process query. The reproduction was added to CHD-79;
duplicate CHD-282 was cancelled. The isolated unchanged shell test passed,
and the ordinary full check was rerun with no code changes.
The final ordinary `deno task check` passed all 1488 tests (20 steps), zero
failed, in 9m2s. Every prior failure remains recorded above; no partial or
environment-probe run is substituted for this passing full gate.

## Captures

File prefixes identify source/compiled and theme. Suffixes identify scenario,
size and folded/expanded state. `-ansi.txt` preserves terminal styles for
representative bodies. Plain captures are the actual tmux screen text;
no screen text was rewritten or normalized.

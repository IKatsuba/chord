# CHD-66 independent QA

Checked the reviewed eaeae33 implementation and designer evidence bed48e2 on
main. Appearance was already approved; these captures prove behaviour.

## Commands run

- Read CLAUDE.md, README.md, FEATURES.md, decisions.md and the quarry and
  chord-tui skills.
- `deno task check`: 393 tests, 20 steps, zero failures.
- `deno task compile`: produced the local macOS arm64 binary.
- Source (`deno run --allow-all src/main.tsx`) and compiled binary in isolated
  tmux servers, with scratch `-C` directories and isolated `XDG_STATE_HOME`.
  The agent override ran `tests/fixtures/fake_agent.ts` through Deno with the
  repository's deno.json. All input was literal tmux text followed separately
  by Enter, or named keys. No live agent/model was started.
- At 120x40 and 80x24 in both builds: `text`, `tools`, `/cost`, `/context`,
  `/status`; `/co` and `/st`; `error`; `slow`, Esc; resize to 80x24 and
  `/cost`; `/exit`. Repeat the two turns with `--no-usage` and both reports.
- 101 `text` turns in one source window, with `/cost` after turn 100 and 101.
  Save an isolated copy of the state after 100 turns, then resume each record
  by its session id at both terminal sizes and run `/cost`.
- A temporary copy of the SDK fixture's `slow` scenario sent a usage_update
  with cost USD 0.0375, used 6,000, size 1,000,000 before streaming. After two
  completed turns and `/cost`, send `slow`, `/cost` during the turn, resize,
  Esc, `/cost`, and double Ctrl+C.
- Read captures back and verify values and terminal dimensions; compare
  `stty -g` before/after each standard run, read tmux alternate-screen/cursor
  flags, and check the process table after cleanup. Scan these captures for
  private paths. `git diff --check` passed.

## Observed

- Two-turn cost is $0.0250; input 2,000, output 400, cache read 1,600.
  Context is 4,000 of 1,000,000 used and 996,000 free (99%), agreeing with
  the status line. Status contains agent fake, the advertised model and
  Default mode, the session UUID and scratch directory. All hold in source
  and compiled builds at both sizes.
- Completion offers /context and /cost for /co and /status first for /st.
  Each full command executes locally and draws its transcript report.
- With no usage, cost/context state plainly that the agent has not reported;
  cost still includes session time and neither report invents zeros.
- Agent failure is visible as “The fake agent failed on purpose.” Esc leaves
  “Interrupted by user”; a report still works after interrupt and resize.
- After 101 observed turns, tokens are 101,000 / 20,200 / 80,800 and cost
  $1.26. The earlier 100-turn report remains $1.25 and
  100,000 / 20,000 / 80,000, proving report snapshots remain unchanged.
- On resume, both 100 and 101 turn records show 100,000 / 20,000 / 80,000
  and the approved note: “Tokens count the last 100 turns; any earlier ones
  are not included.” Cost remains $1.25 or $1.26 respectively. The 100-turn
  record was copied from a real keyboard-driven run, without modifying its
  usage. No note appeared in the continuously observed window.
- During the subsequent slow turn, /cost uses $0.0375 while the preceding
  report stays $0.0250. Tokens still reflect the two completed turns. The
  report survives resize and interruption; double Ctrl+C quits.
- Every standard run restored the same stty state. All 14 completed windows
  (including the live-update fixture) returned alternate=0 and cursor=1.
  Shells were usable again, all QA tmux servers exited, and final ps readback
  found no QA-created fixture processes. Existing unrelated processes were
  left alone.

## Separate finding and limits

CHD-73 records a pre-existing resume defect: a trailing space in the agent
command differs from acpx's trimmed stored command and opens a new record.
The initial resume harness included that space; the corrected checks used
identical canonical commands and the original isolated records. This does
not return CHD-66. CHD-52 already tracks the unrelated CHD-32 captures, which
were left untouched.

The idle detector initially matched reply text “Working”; it was corrected
and the standard matrix rerun. Raw quit screens are not committed because
resume instructions contain the absolute fixture command. Terminal checks
are recorded here instead. A final-check attempt passed 392 tests but failed
the existing SIGTERM-resistant shell cleanup test at its immediate PID check.
The test's PID was absent on readback; all four shell tests passed unchanged
in isolation, and the full check was rerun before committing.
No live agent check was made. No component,
parser or protocol helper was written, and no new library was tried or added;
QA reused Deno, tmux, the existing ACP SDK fake and the compiled application.

# U5 explicit team choice screen check

Screen code: `223849eecfc05aa26fa6e66f89e8ac70bdf6131a`.
Captured 2026-10-27, 20:08-20:11 UTC. The later signed evidence commit
contains only this note and captures, not a different screen implementation.

Visual PASS at 120x40 and 80x24, with no blocking visual findings.

## Method and provenance

Each session ran from an immutable archive of the exact handed commit,
with only dependencies linked from the checkout and preserved during QA.
No original Git directory/index or worktree was linked. The archived lockfile
specifies dependencies. No later source work or uncommitted test migration
was included in the app snapshot.

The tracked launcher was
`nice -n 19 bun tests/fixtures/selected_team_qa.ts choose`.
Each own tmux session used its isolated fixed named QA directory, explicit
fake commands for all candidates and fixture-only resource sources. The
unavailable-MCP case additionally used the documented fake-agent setting
`CHORD_FAKE_NO_HTTP=1`. No real provider/model, auth-source, credential or
login calls were made.

Text was sent using `send-keys -l`, then Enter separately. Captures use
`capture-pane -p` and matching `-e` variants. Every saved capture was
inspected as terminal text, including Home/PageDown positions and ANSI
styling. ANSI variants differ only by styling and, in the unavailable-MCP
startup warning, a trailing space at a wrap boundary. No images were made.

All own sessions were killed. Final tmux query found no server; process
query found no matching QA or fixture helper processes.

## Observations

- `choose-*-completion`: `/team ch` exposes
  `choose  Ask main to select a run (uses a model turn)` at both sizes.
  Tab completes the command and offers the saved team name.
- `choose-*-help`: `/help` includes `/team choose uses a model turn`.
  The 80x24 shortcuts panel uses its existing scrollable two-column layout;
  this disclosure is visible before scrolling.
- Missing name, missing job and unknown-team captures show local actionable
  refusals before any selection report or Team launch appears.
- A valid `/team choose fixture selectedidle` appears once as an ordinary
  visible main prompt, followed by Resources and the selected Team report.
  The complete reason, uncertainty warnings, planned settings, actual lead
  settings and unopened reviewer remain available in ordinary scrollback.
  ctrl+o shows saved choices and changes. The selected fake-small model
  differs visibly from the saved fake-large model.
- `direct-*`: typed `/team run fixture selectedidle` shows the saved
  fake-large configuration, without the Resources/selection report.
- `picker-*`: Enter on the saved fixture prepares `/team run fixture` in
  the prompt. Adding the job and submitting produces the same saved path,
  without a main selection report.
- `queue-*-queued`: during `costwait`, choose appears in the ordinary
  waiting queue. Esc interrupts and restores the choose command to the
  draft; no Team row appears. A second queued choice followed by `/clear`
  clears the transcript and leaves the command as an editable draft,
  without a Team row in the resulting screen.
- `nomcp-*`: without chord's MCP tools, valid choose says no selection turn
  was sent; no alternate direct-run or provider fallback appears.

Screens establish the visible interaction and layout, not the number of
protocol calls or lifecycle guarantees after arbitrary delays. Developer's
reached tests provide separate behavioral evidence for exact turn counts,
generation/lease isolation and cancellation. Designer did not rerun those
checks, compile, release checks, real providers or the full suite.

The developer's final composite checks included a separately pending
count-only test migration that is excluded from this code commit. Running
the app does not execute or validate that migration; reviewer/tester own
its separate handoff. Earlier visual evidence retains its original SHAs.

Prose formatting and diff checks passed. Required privacy scan initially
exceeded Bun's default five-second timeout (7 passed, 1 timed out); rerunning
the same file under `nice -n 19` with `--timeout=60000` passed all eight
tests, including the tracked capture scan.

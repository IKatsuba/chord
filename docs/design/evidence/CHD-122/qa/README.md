# CHD-122 independent QA

Implementation: `7744c57`. Validated on main at `fbd9e4f`.
Appearance was already approved by the designer; this pass checks behaviour.

## What ran

- `deno task check`, foreground, with process access for fixture cleanup.
- `deno task compile`, macOS arm64, then the resulting binary in tmux.
- Source at 120x40 and compiled binary at 80x24, each with a temporary HOME,
  XDG config/state directories and a separate `/tmp` working directory.
- Keys only: `mode`, `/new codx`, `/new fake2`, `/status`, `permission`,
  `form`, `link`, tab switching, bare `/new`, ctrl+x c, `error`, `slow`,
  resize, Esc, `text`, `/new broken`, ctrl+x k, opening nine sessions,
  rejecting a tenth with both commands, and ctrl+d to quit.
- `stty -g` before and after; tmux alternate-screen/cursor inspection;
  `ps` before and after; removal of the owned isolated tmux server.

User settings made the original fake command deliberately invalid and set
Fake Small/plan. Invocation flags supplied the working fake command and
Fake Large/plan. For fake2, user settings supplied the working fake command
and Fake Large/default; project settings overrode only its model and mode
with Fake Small/acceptEdits. This proves command-flag isolation and the
project-over-user merge through the running CLI. Both commands ran only
`tests/fixtures/fake_agent/main.ts`; no real agent or model was used.

## What was observed

- Original fake starts and answers `Mode: plan.` on Fake Large; named fake2
  starts on Fake Small and answers `Mode: acceptEdits.`. Its `/status`
  names fake2 and the window's directory. Switching to fake restores its
  original model and mode.
- Unknown codx is refused in the transcript without opening a tab.
- With three sessions, `/status` shows `3 open (1 waits)` for permission,
  `3 open (2 wait)` for permission plus form, and `3 open (1 waits)` for
  a link. Answering/cancelling removes the wait suffix. An unseen completed
  reply does not count as a request waiting for the person.
- Bare `/new` and ctrl+x c from fake2 retain that agent's model and mode.
- An agent turn failure and a configured command that cannot start are both
  visible. A new prompt succeeds after the failed turn and after interrupt.
- Source survives resizing from 120x40 to 80x24 while streaming; compiled
  survives 80x24 to 120x40. Esc records `Interrupted by user`.
- Both `/new` and ctrl+x c refuse a tenth tab with the prescribed message.
- Both quit with exit code 0. The restored shell accepts a command;
  tmux reports alternate screen 0, cursor visible 1, and shell active.
  `stty -g` is identical before and after each run.

Capture names starting `source-` use 120x40 until `resized-working`, then
80x24. Names starting `binary-` use 80x24 until `resized-working`, then
120x40. ANSI captures accompany the named-agent and three-session states.
Restored-shell captures were taken after clearing the shell through keys.
All committed captures were scanned for private home paths.

Library first: QA adds evidence only. No component, renderer, parser,
protocol helper or dependency was written or needed; the implementation
reuses existing Ink, settings, command and tab machinery.

## Final validation

`deno task check` passed: types, lint, formatting, 1,140 tests and 20 steps,
zero failures (5m49s). `deno task compile` succeeded and that binary was
used above. The staged-evidence privacy check passed all seven tests;
`git diff --cached --check` passed.

Final `ps` inspection found no QA-owned test or fake-agent process. Only
pre-existing orphan fixture PID 78189 (`--hang config`), present before
this run, remained untouched. The owned tmux socket had no running server.
There were no blocking findings and no incidental tasks to file.

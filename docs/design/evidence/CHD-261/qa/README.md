# CHD-261 independent QA

Checked main at e984804 after the designer's round-2 pass and reviewer approval.
The approved appearance and unreleased-record policy are preserved.

## What ran

- Foreground `deno task check`, with process inspection available: types,
  lint, format and 1453 tests (20 steps), zero failures, 8m42s.
- `deno task compile`: standalone aarch64-apple-darwin binary built and
  started in tmux against the repository fake ACP agent.
- Source `deno task chord:fake` at 120x40, resized to 80x24 and back:
  `/team new fix bugs`, project save with 1, a change request, ctrl+o,
  Esc rejection, another proposal, ctrl+c's quit arming and ctrl+d quit.
- Compiled binary at both sizes: proposal, rejection with 3, the next words
  producing a changed proposal, Down/Up/Down and Enter to save globally,
  proposal of an existing global team and replacement with 1, and `error`.
  All application actions used keys. Configuration, records and projects
  were isolated under `/tmp/chd261-qa/`.
- Temporary scenario using the repository's `chordClient`, `callChord` and
  `PROPOSED_TEAM`: `members` as a string, then reserved name `main`.
  For write failure, a directory was placed at the scratch target only
  after a valid save box opened; 1 then exercised the writer's refusal.
- A temporary Deno probe opened fake-agent conversations and asked chord's
  save question during `slow`. Request abort, natural turn end, interrupt,
  clear and close each withdrew it. After clear a fresh session accepted a
  prompt. Each conversation was closed in `finally`.
- Actual scratch records replayed through `recordActions` and the transcript
  reducer retained three saved and two not-saved outcomes. Four additional
  current-format probes passed: saved/not saved, tool before/after both
  served events. No legacy-shape compatibility was required.
- A truecolour compiled run captured the changed modes at both sizes.
  Closing its last session used ctrl+x k while the save box waited.
- Terminal and process cleanup: tmux state, before/after `stty -g`, and
  `ps` comparison against a baseline taken before QA.

## What was seen

- Proposals and changed proposals kept all four mode rows above the save box
  at 80x24. Old modes stayed whole. At 120x40 the changed body showed its
  four-line diff; at 80x24 the count and fold line remained above the box.
  ctrl+o exposed instructions and the full body diff. These match the
  designer-approved captures, allowing scratch paths, prompt text and time.
- Only `bypassPermissions` carried RGB 255,193,7; its old-mode suffix was dim.
- 1 saved the project file. Arrows and Enter saved the isolated global file,
  with no project file created there. Replacement wrote back to that global
  file. Esc and 3 showed `Not saved` and retained the existing file; the next
  prompt opened a new proposal. Outcomes appeared on the call itself.
- The wrong-type input and reserved name were refused without a save box.
  `main` showed `the name main is taken` under the call. The write conflict
  showed `.chord/teams/bugfix.md was not saved: Is a directory` under the
  call; the conflicting directory remained and no temporary writer file
  remained. The fake's failed turn displayed its deliberate error.
- Source and compiled quits returned to a usable shell with alternate=0
  and cursor=1. Source and compiled termios matched their before snapshots.
  The final last-session close also restored alternate=0/cursor=1.
  All three QA tmux sessions were removed. Final `ps` comparison found no
  newly started fake or live agents or fake-task wrappers. Pre-existing
  processes were left untouched.

## Separate finding and limits

CHD-274 records the pre-existing shared tool renderer truncating long error
lines even under ctrl+o. At 80 columns the MCP SDK prefix hides the zod issue;
at 120 only its beginning is visible. The same truncation occurs for ordinary
tool errors and long write errors. It exists at fa10608 and is not a CHD-261
regression. The refusals and save behavior pass; full error text visibility
is left to that separate task under the minor-findings rule.

No live agent/model was used. No implementation was changed. No push,
publish or PR was performed. CHD-268 and CHD-273 were left separate.

Library-first: verified the recorded trial and actual use of @cliffy/table
with cli-truncate, ink-select-input through ChoiceList, zod/MCP SDK, jsdiff
and the part-1 @std/yaml writer. Source and compiled flows exercised them;
QA added no renderer, parser, component, protocol helper or dependency.

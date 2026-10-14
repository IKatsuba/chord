# CHD-311 independent QA

Implementation: `d4ac52ec` on `main`. Merge baseline: `d8a69df5`.
Designer-approved option C is the appearance boundary. This is behavior QA.

## What ran

- `bun run check`, unchanged tree, foreground with process access: types,
  ESLint, Prettier, lint-policy tests and all repository tests.
- `bun run compile`: host `bun-darwin-arm64/chord`.
- Source (`bun src/main.tsx`), host binary and merge-baseline source in
  an isolated tmux server, each at 120x40 and 80x24. All use
  `tests/fixtures/fake_agent/main.ts`. Settings, records and working directory
  are isolated under `/tmp/chd311-qa`; baseline uses an archived merge tree
  and the same installed dependencies. No real agent or model was contacted.
- Literal prompt text and Enter sent separately, with settled captures;
  Ctrl+O opens and closes transcript details. Captured empty window, markdown,
  tools, calls, edit, plan, subagent, thought, shell, shellcut, compact, error,
  bash, status, agentlong, agents and rewrite. Text captures are grouped by
  scenario; selected ANSI captures retain terminal colours.
- Source and binary, both sizes: 200-line stream while following and scrolled
  back; PgUp, Shift-Up (`ESC [ 1 ; 2 A`), wheel (`ESC [ < 64 ; 20 ; 5 M`),
  End, resize to the other size and back. Two tabs scrolled to the same numeric
  offset in different transcripts, switching back and forth with Ctrl+X 1/2.
- Esc during `slow`, then `error`, then `text`. Startup splash with fake
  initialization deliberately hung, then Ctrl+C twice.
- Ordinary exits by Ctrl+C twice, Ctrl+D and `/exit`. Before/after `stty -g`,
  tmux cursor/alternate-screen flags, terminal exit bytes and `ps` ownership
  checks before destroying the isolated tmux server.

## What was seen

`bun run check` passed: 51 lint-policy tests, 1510 repository tests,
0 failures, 17994 repository assertions; repository tests took 508.04s.
Compile succeeded and the binary drew, accepted keys and quit at both sizes.
The full suite includes fake-agent session coverage, stream/PgUp/Shift-Up/wheel/
two-session tests, and the folded/expanded Tool, monitor-list and message-sender
ANSI regression tests (SGR/reset retained, line erase/hyperlink escapes removed).

Source and binary follow the stream's newest numbered line. PgUp holds the view
while the new-output count grows. Shift-Up and wheel each move the view; their
captures here are taken after the stream settles for deterministic one-row
checks. The `stream-` filename prefix groups the long-stream probe, not a claim
that those two captures are mid-stream. End reaches line 200. Resize out and back
keeps the top entry; each tab restores its own entry despite equal offsets.

Esc shows `Interrupted by user`, ends the working spinner and returns the
prompt. The next turn displays `The fake agent failed on purpose.`; the next
successful turn displays `Hello, world. This reply came in chunks.`. A reply's
literal `Working` text was distinguished from the `Working…` spinner when
checking completion. Named tmux Shift-Up was replaced with the explicit key
sequence used by the repository's harness.

Settled comparison captures match the baseline and source/binary agree, except
for the four approved fitting differences below. Colour captures match too;
elapsed times, spinner/blink frames and asynchronous stream positions are
excluded. The `agents` comparison was retaken after message delivery settled
and scrolled to the same row. The splash mark drifts between animation frames;
all three versions draw the mark and `Starting fake…` at both sizes.

| Scenario | Baseline row | Current source and binary row |
| --- | --- | --- |
| calls, 120 columns, folded/open | `Bash(deno test --allow-read --allow-write --allow-env --allow-run --allow-sys lint/ tests/ --filter "tool calls dra…` | `Bash(deno test --allow-read --allow-write --allow-env --...sys lint/ tests/ --filter "tool calls draw their status")` |
| calls, 80 columns, folded/open | `Bash(deno test --allow-read --allow-write --allow-env --allow-run --allow-s…` | `Bash(deno test --allow-read --allow-...ilter "tool calls draw their status")` |
| agents, 80 columns | `I changed how a string at the end of a line is read. Run the parser test…` | `I changed how a string at the end o...ts now and tell me only what fails.` |
| rewrite, open, 80 columns | `32 +   { id: 31, name: 'a row whose name runs well past the edge of a na…` | `32 +   { id: 31, name: 'a row whose ...ge of a narrow terminal window' },` |

All 16 panes returned to their shell with identical before/after `stty`, cursor
visible (`cursor_flag=1`) and alternate screen left (`alternate_on=0`). Ordinary
source/binary exits also include `ESC [?1049l` and `ESC [?25h` in the recorded
terminal bytes. All 37 application descendants recorded before ordinary quit
had exited at the `ps` check, before tmux teardown. Only the owned isolated tmux
server was destroyed. No agent from this QA run remained.

## Scope and existing findings

No code change, new parser or component was written. Library trials remain as
recorded in `docs/decisions.md`: selected `@ansi-tools/parser`, rejected
ansi-sequence-parser and anser; opentui-spinner 0.0.7 tried and rejected on
OpenTUI 0.6.0. Existing library-backed Ansi is reused.

CHD-336 (pre-existing header colour at chalk level 2) and CHD-337 (resume notice
ANSI descriptions, separately filed after the two-return bound) remain their
own tasks. This run filed no new finding and does not reopen those tasks or the
designer-approved appearance. No live-agent check was needed for this component
migration. QA passes for handover to chd-lead to close.

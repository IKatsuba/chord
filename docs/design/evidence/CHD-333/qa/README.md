# CHD-333 acceptance QA

Implementation d75718f9, tested at db03ebd9 on main. The designer-approved
appearance is settled. These captures prove behaviour with only the repository's
fake ACP agent; no live agent was started.

## What ran

- `bun run check`, in the foreground, with process/socket access for fixture
  lifecycle tests: static gates and 51 lint tests pass; 1,502 repository tests
  pass, 0 fail, 17,882 assertions across 108 files in 505.45 seconds. React act
  warnings were emitted; the command exited 0.
- `bun run compile`, producing the host darwin-arm64 binary.
- `bun test ./tests/ui/transcript/tools/proposal_test.ts`: 14 pass, 0 fail.
- Source and host binary in an isolated tmux server, with separate scratch
  working, configuration and state directories; every interaction used keys.
- `capture-pane -p` and `capture-pane -p -e`, `stty -g` before/after and `ps`.
- Staged evidence privacy: 7 pass, 0 fail. `bun run check:static` on the
  evidence tree passes, including 51 lint tests.

Source command: `bun /tmp/chd333-qa/repo/src/main.tsx fake -C <scratch>`.
Binary command: `/tmp/chd333-qa/repo/dist/bun-darwin-arm64/chord fake -C <scratch>`.
Both used `--agent-command "bun /tmp/chd333-qa/repo/tests/fixtures/fake_agent/main.ts"`.
The neutral repository symlink keeps private paths out of terminal output.

## What was seen

New proposal: `propose`, Ctrl+O, PgUp through the table at 80x24 and 120x40.
Every role reads whole on its own dim row under the runtime column. Folded,
the roles remain cut as permitted. Enter saves the project file.

Long-model change: after saving, only the scratch team's reviewer was changed
to security-review, claude / claude-sonnet-4-5-20250929, bypassPermissions,
with role "Reviews the diff for security problems and edits nothing". Then
`propose`, Esc, "make the tester bypass", Ctrl+O and PgUp. At 80x24 the actual
table has 70 cells: tester's mode wraps `was acceptEdits` below the new mode;
security-review's model id stays unbroken below `claude ·`. Every role is
reachable by paging, with no table ellipsis. At 120x40 the runtime and mode
fit on one line. Resizing the opened view in both directions preserves the
content. Folded truncation remains permitted. Enter replaces the scratch file;
the saved tester has bypassPermissions and the reviewer has the proposed model.

The ANSI captures show tester's bypassPermissions in RGB 255;193;7 and
`was acceptEdits` in SGR 2 on the continuation line. Role rows are SGR 2.
The removed security-review row, including its model, is dim as a removed row.
Saved `/team show bugfix` opened at both sizes uses the same shape and keeps
its long model whole.

`error` displays "The fake agent failed on purpose.". `slow`, a resize and Esc
leave "Interrupted by user"; `text` afterward returns "Hello, world. This reply
came in chunks.". Source Ctrl+D and binary Ctrl+C twice exit 0. An additional
source Ctrl+C while a save is pending cancels without writing a team file,
then quits cleanly. Before/after stty values match. Raw source and binary output
end the alternate screen and show the cursor; the shell accepts further input.
`cleanup.txt` records those assertions. No TUI-owned chord or fake process
remains, and the isolated tmux server was removed. Existing live-agent processes
were left alone.

The first source launch reopened `/dev/tty` in a wrapper and did not accept
keys; those captures were discarded. Direct foreground launch accepted input.
Source's first successful matrix ran with inherited NO_COLOR; the later source
new-proposal and binary matrices removed it to verify colour.

## Scope and library

The existing @cliffy/table supplies Cell.colSpan and minColWidth/maxColWidth
wrapping. QA exercised that implementation and its focused tests; no component,
parser, workaround or dependency was added. The recorded library trials and
reviewed source pass the role/runtime input directly to Cliffy.

No new findings or side tasks. CHD-335, the pre-existing missing previous-model
annotation, remains separate. Below-80-column appearance, other platforms and
live-agent interoperability were not judged by this acceptance run.

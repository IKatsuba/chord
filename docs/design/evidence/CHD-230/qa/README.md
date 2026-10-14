# CHD-230 QA

Tested source revision `2110243` on `main`, including the reviewer-approved
folded-arrow fix `4f0b888`. Appearance remains the designer-approved one.

## What ran

- `deno task check`: types, lint, format and all fake-agent tests; 1266 passed
  (20 steps), 0 failed, 6m59s on the source revision. Repeated after staging
  this evidence; its result is recorded on CHD-230.
- `deno task compile`: produced `dist/aarch64-apple-darwin/chord`.
- `deno test --allow-read --allow-env --allow-run --allow-sys --allow-write
  --allow-net=127.0.0.1 tests/ui/transcript/message_test.tsx
  tests/session/tasks_test.ts`: 14 passed, 0 failed. These include dark/light
  folded/opened pending, in_progress, refused (completed plus chord.error),
  delivered and coloured-recipient ANSI assertions, and task relay/state
  assertions against a stub session. The full suite and tmux checks reach the
  fake ACP agent over stdio.
- Source TUI in a private tmux server, `deno task chord:fake -C
  /tmp/chd230-qa/work`, isolated XDG config/state, `CHORD_FAKE_STEP_MS=30`,
  `FORCE_COLOR=3`, separate dark/light settings. Keyboard-only `agents`,
  child selection, `x` twice on docs, `agentclose`, `task` with Allow and
  Deny, ctrl+o, `error`, `slow`, Escape, and ctrl+d. Resized between 120x40
  and 80x24 in both themes. Settings and state remained under the QA fixture.
- Compiled TUI with the same fake command, isolated state, dark 120x40 and
  light 80x24: start, `agents`, child selection, `agentclose`, ctrl+d.
- `tmux capture-pane -p` and `-p -e`; `tmux list-panes` for alternate-screen
  and cursor state; `stty -a` before/after; `ps` before/after quit against
  the recorded process tree; removed only the QA-owned tmux server.
- Public-path and envelope-glyph scan of the saved evidence; no matches.

## What was seen

The parent's sent rows are `→ parser`, with text under `⎿` and dim
`· queued`; received rows are `← parser · fake`. Arrow and name both use
parser's colour (dark RGB 108/182/255; light 10/91/196). The child's view
shows plain `← main` and `→ main`; its prompt has the named coloured border.
The list displays `← message from main`. `Open(parser)` and
`Agent(Fix the tokenizer)` remain tool calls.

Incoming queued messages are dim `←` rows at both widths, including a
queued report. ctrl+o opens the task block and its delivered `→ main · queued`
row; folding keeps the arrow and queued suffix. A task's message and report
have plain arrows; a denied task produces `← Fix the tokenizer · fake · failed`
with a red arrow (dark RGB 255/107/128, light 196/22/42) and the error text.
A keyboard close of docs produces dim `← chord`.

`agentclose` produces a red `→ parser` with the refusal under `⎿`, rather
than swallowing the error. The `error` scenario says it failed on purpose.
Escape during `slow` produces `Interrupted by user` and restores the prompt.
Resize keeps the message rows reachable and the prompt usable at 80x24.
No envelope appears in these captures or in active source/tests and requested
docs. Row direction, gutters, agent names and queue placement agree with
CHD-225's A parent/child text mocks; runtime names and scenario text differ.

The compiled binary starts and reproduces parent/child exchanges and refusal.
All four original runs exited 0. After quit, tmux reported alternate=0 and
cursor=1; the shell returned. All 16 recorded QA subprocesses were absent
from `ps` after quit. A second clean start/quit recorded the exact stty flags:
only macOS PENDIN clears, with canonical input, echo, signals and control
characters unchanged. The isolated tmux server was removed. No live agent
was used.

## Scope and separate findings

Pending/in_progress and refused folded sends, and a task send to a coloured
recipient, are independently verified by rendered ANSI tests. The stock fake
scenario produces a delivered child send to main; no claim is made of a
terminal capture for the other folded states. Parent refused sends were
exercised through the real UI/server/fake-session path.

CHD-238 is a separate colour-lifecycle task: after closing parser, earlier
parser rows lose their blue and the refused recipient name is plain. This
comes from CHD-170's `App.tsx` AgentColours context, built only from open list
rows. The parent captures precede closing; the refusal captures demonstrate
this limitation. It is not a regression from CHD-230's arrow-state fix. No
CHD-170 lifecycle approval is implied by this message QA. Existing wrapping
is already tracked as CHD-222; it was not reopened.

No source code, protocol wrapper, key or dependency changed during QA. The
rendering uses the existing Ink Text/Box/gutter spans and shared tone helpers;
no new component or renderer was written and no new library trial was needed.
All captures are public-ready text from a neutral scratch directory.

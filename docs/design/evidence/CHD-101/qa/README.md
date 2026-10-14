# CHD-101 independent QA

Checked on main at 3d0e3ed with `deno task compile` and its macOS arm64
binary. The fake agent was compiled from `tests/fixtures/fake_agent.ts`
with `deno compile --allow-env`, named `fake-agent` on a temporary PATH.
No live agent was used. HOME, XDG_STATE_HOME and XDG_CONFIG_HOME were isolated
under a temporary directory; HOME's final segment was `u`.

## Commands run

- `deno task check` (types, lint, formatting, fake-agent tests).
- `deno task compile`.
- `chord fake --agent-command fake-agent -C <temporary HOME>/src/api`,
  then `/echo api transcript`, then ctrl+d.
- The same in `src/app`, with `/echo app transcript`, then ctrl+d.
- A fresh app session: `/echo active unchanged`, `/status`, `/resume`,
  ctrl+a, Down, ctrl+a, ctrl+a, Down, Enter, `/status`.
- Resized the open picker from 120x40 to 80x24 and repeated the scope and
  selection checks.
- From app: `chord fake --agent-command fake-agent --resume
  4f9a6735-6d25-4f1b-ac57-222548b8ad74`; resized to both widths, then
  `/echo resumed continuation`, `error`, `slow`, `/resume`, Esc.
- Repeated `error`, `slow`, Esc at 80x24; ctrl+c twice to quit.
- From `src/empty`: `/resume`, Enter, ctrl+a, ctrl+a, resize, ctrl+a,
  Esc, ctrl+d.
- From app: `/resume`, Enter, `/status`, ctrl+d.
- With `CHORD_FAKE_REFUSE_LOAD=1`, resumed api from app, sent
  `/echo refused load`, captured at both widths, then ctrl+d.
- Inspected tmux's `alternate_on` and `cursor_flag`, `stty -a`, and `ps`;
  killed the isolated tmux server and checked it was gone.

Literal prompt text and Enter were sent separately, with a pause between.
All interaction with chord was through keys. Captures are text and ANSI from
`tmux capture-pane`; filename suffixes name the terminal dimensions.

## Observations

The narrow scope contains only app's earlier session, excluding the active
session. The wide scope contains app and api, newest first, with `~/src/`
directories. Toggling back from api resets the highlight to app's valid row.
Resizing preserves a usable picker and both scope hints.

Selecting api refuses it plainly and puts its command on a separate line.
The two `/status` reports prove the session remains
`608cdb21-5a47-40df-bc27-db7cd9f254fe` in app. Running the displayed resume
command from app opens api and replays its prompt and reply. A further
prompt succeeds. Choosing the local app row also replays its transcript
and restores that session id.

The empty directory opens a picker with no Enter hint; Enter does nothing.
The wide scope still lists all saved app/api sessions at both sizes.
Agent errors and a refused load are visible; `/resume` during a turn says
it is busy; Esc ends the turn with `Interrupted by user` at both sizes.

Every exit returned code 0 to a working shell. tmux reported
`alternate=0 cursor=1`. `stty -a` shows `icanon isig echo` restored.
Before/after encoded terminal flags differed only in macOS PENDIN, a shell
input bookkeeping flag; no raw-mode flags remained. The owned tmux server,
compiled chord process and fake agent were absent from `ps` after cleanup.

Captures were scanned for private paths before staging; the repository's
privacy test also checks the staged evidence. Appearance was already approved
by the designer and was not reassessed.

No implementation was added in QA. The engineer's recorded library trial was
`tildify` 3.0.0 under Deno; its fixed system home cannot take the UI's injected
home. Directory cutting reuses `cutPath` over the existing cli-truncate.

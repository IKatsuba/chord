# CHD-254 independent QA

Checked `475aa7f` on `main`, including engineer change `d300693` and the
designer's approved evidence. Appearance was not reconsidered.

## Ran

- Source `deno task chord:fake`, in a dedicated tmux server at 120x40,
  with separate scratch work, XDG state and XDG config directories.
  Keys only: `task`, Enter on Allow, `agents`, `task` left waiting on its
  Edit, then ctrl+c twice.
- Copied only the parent record into a second isolated records directory.
  Kept its first 56 lines, ending immediately after the second task's
  `subagent_update` with `state.state = running`; removed that line's `at`.
  The next omitted line was the served `spawn_task` answer. Copied no task
  records. `fixture-proof.json` preserves the cut boundary.
- Resumed that parent under source `deno task chord:fake --resume <id>`.
  Captured 120x40 folded and ctrl+o, resized to 80x24 and captured expanded
  and folded. Delayed ANSI captures were taken 0.7 seconds apart.
- Separate source fake session with `CHORD_FAKE_STEP_MS=60`: `calls` while
  running at both widths, Esc to interrupt, `permission` and Esc to reject,
  `error`, then `calls` allowed to complete and fail its missing-file call.
- `deno task compile`; the resulting macOS arm64 binary at 80x24 with the
  existing fake ACP command and a `text` prompt.
- Quitted every session, inspected tmux terminal flags and `stty -g`, checked
  the process table with `ps`, then killed the dedicated tmux server.
- Supplementary Deno assertions verified the actual crash record's boundary,
  captures' dimensions and ended status, delayed dim markers, and terminal
  flag restoration excluding PENDIN.
- `deno task check` on the evidence-staged tree (result recorded below).

## Saw

- The unfinished historical parent call is a bare
  `Tool(mcp__chord__spawn_task)` headline at both widths, folded and expanded.
  It has no `Waiting…` or `Running…` line. Its ANSI marker is consistently
  dim (`CSI 2 m`), unchanged in delayed captures; no pulse remains.
- The task still says `Disconnected`. ctrl+o shows `taskchild` and
  `Its work was not kept: the task's record is gone.` Resize preserves this.
  `Waiting on parser.` in the wider captures is the fake's historical reply,
  not an unfinished tool status.
- Live `calls` shows `Running…` at both widths. A current-turn permission
  call shows `Waiting…`. After Esc the running status disappears and
  `Interrupted by user` remains. Rejected permission and agent errors are
  visible. The completed call retains its output, and the failed call shows
  `Error: File does not exist.`
- The compiled binary starts, connects to the fake and renders its streamed
  `Hello, world. This reply came in chunks.` response.
- All four quits restore `alternate=0`, `cursor=1`, a shell prompt and
  canonical input/echo. `stty` differs only by macOS's `PENDIN` bit, the shell's
  pending-input flag. The owned binary and fake agent are gone in `ps` after
  quit; the isolated tmux server is removed. The old orphan PID 78189 was
  present before and after QA, belongs to existing CHD-158, and was untouched.
- Full check passed on the first run with process access: types, lint, fmt,
  and 1367 tests (20 steps), zero failed, 7m56s. The fake-only test
  `a call its turn left unfinished waits on nothing once the turn has ended`
  passed, as did the session/replay and live rendering coverage. The staged
  evidence passed the repository privacy test. Compilation exited zero.

No real agent or model was used. No implementation or dependency was added;
the change reuses Tool/Ink's existing ended behavior, so no new library trial
applies. No new separate finding was discovered. Pre-existing untracked
evidence was left alone.

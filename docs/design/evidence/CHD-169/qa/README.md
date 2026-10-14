# CHD-169 independent QA

Checked source main `f86452b`, including reviewed fix `aad0baf`. The task lifecycle modules are unchanged between those commits. The approved message arrows from CHD-225 (`1f909e7`) supersede the original envelope glyph. Designer-approved appearance was kept settled.

## Ran

- Read binding CLAUDE.md, README.md, FEATURES.md, decisions.md, CHD-167 and the board's chord-tui skill.
- `deno task check`, foreground, with process access: **1221 passed (20 steps), 0 failed, 6m23s**. `checks.txt` preserves the result.
- `deno test --allow-read --allow-write --allow-env --allow-run --allow-sys --allow-net=127.0.0.1 --filter task tests/session/conversation_test.ts tests/session/tasks_test.ts`: **14 passed, 0 failed**.
- `deno task compile`: produced `dist/aarch64-apple-darwin/chord`; started that binary in tmux with the repository fake-agent command.
- Fresh `deno task chord:fake -C /tmp/chd169-qa/work` runs in an isolated tmux server, with isolated XDG config and state, `CHORD_FAKE_STEP_MS=30`. All TUI actions used keys, with text, Enter and chord keys sent separately. Captures were opened as text before reporting observations.
- Scenarios `task`, `chordcalls`, `text`; child permission allowed with `1` and denied with `2`; `/mcp`, `/clear`, ctrl+o, Esc, ctrl+x k, ctrl+d; resize between 120x40 and 80x24. Additional source run with `CHORD_FAKE_NO_HTTP=1`; additional source run with `CHORD_FAKE_HANG=config` to hold the child's required starting model.
- Read actual parent/child JSONL records and asserted their relationship, selected model, relayed start/end and served message, two wrapped parent message prompts, and exactly one child job turn. Public record evidence is included.
- Compared terminal settings before/after source and compiled quit; queried tmux alternate-screen/cursor flags and `ps` for owned processes. No live agent or model was run.

## Saw

At both acceptance sizes, the task block replaces the spawn call and runs inside the parent's turn with no child tab. The child's permission appears in the parent tab; `1` lets it proceed. Its message queues while the parent runs, then starts a separate parent turn. Its last agent message arrives as a report and starts the next parent turn. Captures `a`, `d`, `b-message-queued`, `b-message-sent`, `b-report-queued` and `c` show these states. Repeated runs account for different tab numbers across captures.

Denying the edit ends the child Failed, queues a failed report, then shows its error and the parent's next turn. The failure was captured at 80 columns and resized to 120. ANSI captures show the failed arrow and body in `38;2;255;107;128`.

The close line names a running task; the second ctrl+x k closes its parent tab. Busy ctrl+d arms with the same task count; confirmation exits. `/mcp` lists chord first, names the tools, and shows `not passed` plus the HTTP explanation when capability is absent. A `task` prompt without HTTP replies `No chord server in this session.` `chordcalls` draws List agents, List agents(fake), List sessions, and the refused runtime with the offered runtimes.

`/clear` while the child runs and its message is queued removes both. Its old parent PID 3655 and child PID 5434 were absent from the next process snapshot; replacement PID 5529 was present. The new session answers `text` alone. The focused session tests additionally exercise two children, late chunks/results/report callbacks, held lines, and the new prompt's isolation.

With two tasks, B's nested permission reaches B only in the focused deterministic session test. The focused delayed-open/model tests prevent any job prompt after startup cancellation. The listed-but-refused, unlisted and no-list refusal tests fail startup without sending the job. The real fake process held in starting-model setup was cancelled with Esc: its block ends Cancelled with zero tool uses; child PID 11284 was gone afterwards and no report arrived. The parent's fake PID 11235 remained until quit, then was gone.

During work, resizing preserves the task and queued message. Esc ends the task Cancelled and retains its queued message; `/clear` then removes held state and a new `text` turn succeeds. The compiled binary also answers the child's permission, queues its message, expands its work with ctrl+o, survives resize and interruption, and quits.

Source and compiled quit yielded `alternate=0 cursor=1`. `stty -g` matched exactly before/after both. The source shell accepted a command after quitting (terminal-restored capture). All sampled owned parent/child PIDs were gone on exit, and the isolated tmux server was removed. Other people's processes were left alone.

## Scope and handover

Pass to chd-lead. No blocking or new minor findings. Existing CHD-222 covers markdown line breaking and CHD-223 covers blank rows after folding; neither was reopened. Resume drawing (CHD-171), long-lived agents (CHD-170), live-agent compatibility and unrelated later commits are outside this QA judgment.

Library first: CHD-169 reuses ACP/MCP SDKs and CHD-149's reducer/renderer. The existing @std/assert/equal Deno and compiled trial is recorded in decisions.md. This QA adds evidence only, with no component, renderer, parser, protocol helper or dependency.

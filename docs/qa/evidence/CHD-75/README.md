# CHD-75 independent QA

Checked `d5360a4` on main. The designer-approved appearance was kept.

## Commands run

- `deno task check`: 430 tests, 20 steps, zero failures (4m30s).
- `deno task compile`: produced the host aarch64-apple-darwin binary.
- Source and compiled binary in an isolated tmux server, driven with keys
  only, at 120x40 and 80x24. Each run used a temporary working directory
  and its own `XDG_STATE_HOME`.
- Source also ran with `CHORD_FAKE_NO_CONFIG=1` and
  `CHORD_FAKE_REFUSE_CONFIG=1` at both sizes: eight terminal runs in all.
- Before/after `stty -a`, raw output, tmux `alternate_on` and `cursor_flag`,
  a shell command after quitting, and final `ps -axo pid,ppid,command`.
- Privacy scan of these captures and `git diff --check`.

## Observations

At both sizes, `/conf`, Tab, Enter opens Settings. Effort starts at Medium;
mode and model do not appear in this list. Enter opens Low, Medium and High,
with Medium selected and marked. Esc returns to Settings; a second Esc
closes it. Enter, Down, Enter selects High, closes the picker and writes:

```text
 › /config
   ⎿  Effort set to High
```

The result line is dim in the ANSI captures. Reopening shows High. Selecting
High again sends no change and adds no note. High remains after a completed
`text` turn and after an interrupted `slow` turn. The `error` scenario's
“The fake agent failed on purpose.” remains visible. Esc interrupts the
slow turn and the prompt can immediately open `/config` again.

The no-config fake shows its plain sentence and Esc closes the picker.
The refusing fake shows its red error under a `/config` echo, and reopening
still shows Medium. These paths pass at both sizes.

The compiled binary starts and exercises the same successful flow at both
sizes. Resizing its 120x40 window to 80x24 while High is highlighted keeps
the value picker operable; resizing back and Enter sets High.

All eight runs quit with Ctrl+D and exit 0. Terminal modes match exactly
before and after; raw output emits alternate-screen exit and cursor show;
tmux reports alternate screen off and cursor visible; the shell accepts a
command. `terminal-restoration.json` records these checks. Final process
inspection found no remaining fake-agent, check, or QA tmux process.
Quit captures stay outside the repository because the fake adapter's resume
command includes its local absolute fixture path.

The full check includes fake-agent session tests for filtering, successful
set/readback, refusal and no-options, and the deterministic delayed-read
regression test. Multiple-option Esc highlight retention has unit-test
coverage; the running fake offers only one option. No live agent was used.
No separate minor findings were filed.

## Library first

QA wrote no component, renderer, parser or protocol helper. The runs exercise
the existing PickerList/picker.ts and acpx setConfigOption in source and in a
compiled binary. The implementation's library trials of ink-select-input
and @inkjs/ui Select, and why their key handling did not fit this picker,
are recorded in decisions.md; no dependency was added for this change.

## Captures

Each screen has plain `.txt` and colour-preserving `.ansi` versions.
`source-<size>-normal-*` covers completion, options, values, Esc back,
success, readback, agent error and interruption. `none-options` covers the
empty list; `refuse-changed` and `refuse-readback` cover the refusal and
unchanged value. `binary-*-changed` proves the compiled flow; the binary
resize capture proves the narrow value list after a live resize.

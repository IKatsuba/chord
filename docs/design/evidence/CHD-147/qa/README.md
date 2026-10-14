# CHD-147 independent QA

Implementation checked: `1b6431d`, on `main`, after review return 1.
Designer-approved appearance was kept.

## Commands run

- `deno task check`: 888 passed, 20 steps, 0 failed, 4m44s. Types, lint and
  formatting also passed. Run with process-query access for fixture cleanup,
  without concurrent tmux captures. Includes the fake session-layer tests,
  terminal sanitizer tests, frame-by-frame split-escape regression and
  24-column rendering test. No test reached a real agent or model.
- `deno task compile`: succeeded for `aarch64-apple-darwin`.
- `dist/aarch64-apple-darwin/chord --version`: `chord 0.0.0`.
- Source and the compiled binary, each against `tests/fixtures/fake_agent.ts`,
  in a separate tmux server at 120x40 and 80x24. Scratch cwd and XDG config/state
  were isolated under `/tmp/chd147-qa`. `CHORD_FAKE_STEP_MS=10` gave each shell
  piece a one-second pause for capturing, and `FORCE_COLOR=3` preserved tones.
  Literal prompt text and Enter were separate sends. No application state was
  injected: all actions were keys.
- `tmux capture-pane -p`, with `-e` for exit colours; `resize-window`,
  `display-message` for alternate-screen/cursor flags; `stty -g` before/after;
  `/bin/ps -axo pid,ppid,pgid,lstart,command` before, during and after.
- Captures were checked for their exact row count and maximum display width
  with the existing `string-width` library, and scanned for private paths.
  ANSI exit frames were checked for dim output and the error colour.

## Observations

Both source and binary behaved identically:

- `shell` began with `Running…`, then showed a first line, partial `1/3`,
  rewritten `3/3`, and the succeeding output as it grew under its call.
- While CSI and OSC sequences were incomplete, no escape fragment or
  hyperlink address appeared. Completing them restored `ok | 2 passed` and
  `FAILED | 1 failed`.
- After exit 1, the fold showed the last three lines, its `+2 lines` hint
  beneath them, and `Exit code 1`. Output was dim; the exit was
  `38;2;255;107;128`, the approved error tone. There was no doubled `Failed`.
- Ctrl+o showed all five output lines and the exit; another Ctrl+o folded
  them back without typing into the prompt.
- At 24 columns, expanded `Task test deno test` became `Task test deno t…`,
  and the next row remained `running 3 tests`. Resizing back restored it.
- Claude-shaped `bash` at 120x40 kept `Running…` with no premature output,
  then displayed both git-status lines at once, including the leading space.
- Resizing a running shell from 120x40 to 80x24 preserved its output and
  controls. Esc interrupted it. The agent's deliberately failed next prompt
  showed `The fake agent failed on purpose.`; a subsequent `text` prompt
  streamed its reply normally.
- Ctrl+d returned to zsh. Both runs reported `alternate=0 cursor=1`, with
  identical `stty -g` before/after. The app and fixture PIDs recorded during
  each run were absent after quit; see `cleanup.txt`. The isolated tmux server
  was then removed.

No live agent was used. No source, dependency or agent configuration was
changed. The implementation's trials of `@xterm/headless` 5.5 and
`@alcalzone/ansi-tokenize` 0.2, and why they did not fit, are recorded in
`docs/decisions.md`; QA added no renderer or parser.

No new findings were filed. Existing CHD-155 (reducer truncation), CHD-157
(emoji/tab alignment) and CHD-158 (the older orphan fixture) remain separate.
The pre-existing PID 78189 was identity-checked as the fixture started at
07:00:36 with `--hang config`, and was left to CHD-158. Unrelated untracked
evidence was left alone.

The `.txt` files are independently captured terminal screens. Only exit
frames retain a companion `.ansi` file for colour evidence. The final
mandatory check was rerun with this evidence staged before committing.

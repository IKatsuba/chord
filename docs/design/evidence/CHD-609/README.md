# CHD-609 U4 screen evidence

Screen unit: `7909a848c5402f4f68a65adb1dc1e68065098a73`.
Baseline: origin/main `0e5929134bac36826cd44c1163629c0f6b0b4325`.
Design: `docs/design/CHD-485.md`, "The auto review".

These are whole-window captures of the running fake riff TUI at 120x40
and 80x24, using an owned tmux server and separate fixed QA directories.
The command was `bun dev chord --fake --qa <name> riff`, with inherited
`NO_COLOR` cleared and `FORCE_COLOR=1`. No live provider, model, sign-in
or credential store was used. Developer held U5 runtime edits until the
U4 captures finished.

Each `.txt` is `tmux capture-pane -p`; each `.ansi` adds `-e`. PNGs render
the captured terminal cells through installed `ansi_up` and
`puppeteer-core`, following the repository screenshot approach, without
cropping controls or adding decorative window chrome. Input used literal
`send-keys -l`, with Enter in a separate call.

- `u4-direct-*`: `call shell {"command":"printf '%s' 'direct admission' | wc -c"}`.
  The output `16` appears beneath the call, with no permission box.
- `u4-safe-git-*`: after initializing the QA repository with system git,
  `call shell {"command":"git status --short | wc -l"}` displays `0`
  without a permission box.
- `u4-reversible-review-*`: `call shell {"command":"node --version"}`
  still reaches the safety review in U4. Reversible admission belongs to
  U5 and was not judged as implemented here.
- `u4-review-*`: `call shell {"command":"printf reviewed; pwd"}` reaches
  the caution box. The warning, rationale, countdown, Allow once / Deny
  choices, Esc hint, draft and auto status fit at both sizes. `2` denied
  both review asks without running their commands.
- `u4-safe-git-refusal-*`: setting the QA repository's `filter.a=b.clean`
  to `harmless-sentinel`, then sending
  `call shell {"command":"git status --ignored"}`, fails the call without
  a permission box. The fake model echoes the explanation that chord did
  not run git and offers read/list/search or asking the person. The tool
  preview is shortened; the complete explanation is visible in the reply.
- `u4-empty-80x24`: the initial narrow window, prompt and mode status.
- `origin-main-direct-*`: the same direct pipeline against the baseline
  in an owned source archive. It opens the existing review box at both
  sizes; U4 removes that interruption for the admitted pipeline while
  keeping the existing transcript and prompt layout.

Screen judgment: pass, with no blocking visual findings. This was a
screen look, not code review or a repetition of developer's tests. The
short commands completed before capture; these captures establish output
placement and completed states, not a sustained streaming interval.
Reversible admission awaits U5. All four owned tmux sessions were killed
after capture.

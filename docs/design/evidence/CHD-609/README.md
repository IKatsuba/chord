# CHD-609 screen evidence

## U4: direct admission

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

## U5: reversible admission and captured names

Screen unit: `cf9f1f384e68b44d0f8f38e51d973a0755b9cfb1`.
The source head stayed fixed for the complete live capture session.

The U5 launchers used `/bin/zsh`, owned fixture HOME and ZDOTDIR values,
fixture XDG config/state directories, and PATH limited to the known Bun
executable directory plus `/usr/bin:/bin`. They started the fake riff
TUI directly with argv, without reading the owner's shell startup files.
Each fixed QA directory held a fixture package with a `stream` script
running `bun stream.ts`. That file printed `Fixture stream N/8` once per
second for eight ticks, with no network or provider access.

All U5 frames use the exact prompt
`call shell {"command":"bun run stream"}` at both 120x40 and 80x24:

- `u5-streaming-*`: with an empty fixture `.zshenv`, reversible admission
  runs the script without a permission box. Numbered output appears in
  the live terminal block while the working line and Esc hint remain
  visible. The output's expansion hint, draft and auto status fit narrow.
- `u5-completed-*`: the same call finishes with tick 8/8 and exit code 0.
- `u5-alias-review-*`: after adding `alias stream='false'` to the fixture
  `.zshenv`, the same command reaches the caution review. The alias names
  an argument, rather than the executable. The complete reason, countdown,
  Allow once / Deny choices and Esc hint fit at both sizes. `2` denied
  these calls; the aliased command was not run.
- `u5-restored-*`: after removing that alias, the next identical call
  streams without a permission box again. Captured names are refreshed
  rather than keeping the prior alias hold.

An initial `node -v` attempt with inherited PATH emitted Bun run help.
Those setup-attempt captures were discarded and reported to developer;
the final captures above use developer's bounded PATH and fixture script
recipe. No node behavior conclusion is drawn from that attempt.

Screen judgment: pass, with no blocking visual findings. Unlike U4's short
commands, U5 has mid-run streaming evidence at both sizes. This remains a
screen look, not code review or an independent application test run.
Both owned sessions were stopped after the scripts completed. The fixture
homes, QA directories and temporary capture/render helpers were removed.

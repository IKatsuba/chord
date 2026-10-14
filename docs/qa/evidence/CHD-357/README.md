# CHD-357 QA evidence

Behavior checked on main at `ad54c2fe`; implementation `1993116d`.
Designer approval stands. These are independent keyboard-only tmux captures,
from source and the host darwin-arm64 compiled binary, in isolated temporary
working, config and state directories. No live agent was used.

## What ran and what appeared

- A copied fake bugfix team with lead `high`, tester `low`, and coder effort
  omitted: `/team show` reads `high / low / —`; `team` starts the lead on
  `high` and tester on `low`. The live list reports coder's runtime `medium`.
- `proposeefforts`, project save, next prompt, Ctrl-O, change save and
  `/team show`: efforts survive saving and the changed values appear. A new
  fake session's `propose` removes the effort fields from the saved team.
- Binary with lead and tester `max`: both transcripts say the refusal and
  `set by team bugfix`; tester's `effort` prompt answers `medium`.
- Separate fake runtime commands with `--refuse-config` and `--no-config`:
  lead and tester keep running; each transcript says the refusal or
  `the agent offers no efforts`, respectively. The initial fake runtime
  stays separate so its command-line override cannot mask these fixtures.
- `/team run bugfix text` with a separate runtime on `--hang start`: its
  row appears immediately; `/team show` and resize still work. At 80 columns
  the running effort column gives way to the headline as approved.
- Member permission rejection, `error`, `slow` and Escape: rejection,
  `The fake agent failed on purpose.` and `Interrupted by user` are visible.

Source and binary were resized between 120x40 and 80x24. Ctrl-O content was
also captured at 80x90 to show the whole change. No appearance was redesigned.

Six temporary independent fake-only probes used the real ACP session and
chord server: accepted, unsupported, explicit set refusal, no-effort runtime,
omitted effort and hung startup. They asserted lead/member `effort` and
`note` answers, team source attribution, `run_team` waiting when effort is
set, omitted-effort immediacy and `/team run` immediacy. All six passed. The harness asserted initialized agent PIDs gone. A broader
process audit caught four wedged startup fixtures after the temporary harness
ended too early; those identified PIDs were stopped. Repeating the hung-start
probe with five seconds for shutdown to settle passed, and process inspection
found no probe-owned fixture left.

## Terminal and process restoration

Completed source and binary Ctrl-D quits, source Ctrl-C quit, and a hung-start
quit returned to the shell with `alternate_on=0`, `cursor_flag=1` and
`pane_current_command=zsh`. Each before/after `stty -g` matched. The hung-start
shutdown needed longer than the first three-second harness capture; it then
completed with exit 0 and identical terminal settings. Final process cleanup
and the full check result are recorded on the task board.

No live adapter, light-terminal appearance, or child-record effort persistence
was judged. CHD-350 tracks the existing permission-clock test timing failure;
CHD-373 and CHD-375 remain separate follow-ups. No new library or product code
was written. Existing @cliffy/table, cli-truncate and string-width behavior is
covered by the opened and narrowed table captures and repository tests.

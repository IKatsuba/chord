# CHD-119 independent QA

Feature: `f0594a7`. Checked on `main` at `35f7ca2` before adding this evidence.
Appearance was already approved by the designer.

## Commands and setup

- Read the project rules, CHD-114 and the board's `chord-tui` skill.
- Run `deno task check` and `deno task compile`.
- Start an isolated tmux server, temporary HOME/config/state directories and
  scratch working directories under `/tmp/chd119-qa`.
- At 120x40, run the source with `deno run --allow-all src/main.tsx`; at
  80x24, run `dist/aarch64-apple-darwin/chord`. Both use only
  `tests/fixtures/fake_agent.ts` through `--agent-command`, with `-C` a scratch
  directory. Settings explicitly choose dark or light and the bell channel.
- Send literal text and Enter separately. Create three sessions with ctrl+x c;
  send `permission` in tab 2 and `slow` in tab 3, then ctrl+x 1.
- Capture with `tmux capture-pane -p` and `-p -e`, pipe raw pane output locally
  for byte counts, resize between 120x40 and 80x24, quit with ctrl+d, and inspect
  tmux terminal flags, raw restoration sequences, `stty -g` and `ps`.

## Observations

Each size/theme pair has `waits`, `typed`, `attended`, `answered` and `resized`
captures. Tab 1 stays front while tab 2 has `●` and tab 3 is working. The
permission notice remains on the left. Typing `1` goes into tab 1's draft;
tab 2 remains parked. ctrl+x a opens tab 2's permission box with an 8-second
wait, counted from its arrival. `1` there allows it, records
`Allowed Write notes.txt · Allow`, and the agent replies `Permission: allow.`
The other tab can finish independently and gets `✓` and its reply notice.

ANSI captures retain the front tab's bold inverse (`1;7`) and the warning
colour: RGB 255,193,7 in dark and 138,90,0 in light. This verifies the approved
roles; the designer's accepted 80-column model truncation remains as built.

Each raw run has exactly one BEL before the permission is answered and three
over the whole run: permission, permission turn end and slow turn end. The
startup OSC 11 query's BEL terminator is excluded. Raw output is kept outside
the repository because the launch and resume commands name local executables.

The compiled `extra` run at 80x24 uses OSC 9 to inspect notification messages.
A permission in tab 2 and a later form in tab 3 give `● 2 sessions wait`.
Attention visits tab 2, then tab 3, then wraps to tab 2 while both stay parked.
The form's notice reads `● 3 fake asks for input`; notifications name
`fake (2)` and `fake (3)` once for each wait. The `long` turn is interrupted
while working, records `Interrupted by user`, and adds no notification (5/5).

The compiled `errors` run queues `error` after `slow` in tab 3, then starts
`slow` in tab 2 and returns to tab 1. It shows tab 2 `✓`, tab 3 `✗`, and
`✗ 2 sessions ended`. Attention reaches the older failure in tab 3, where
`The fake agent failed on purpose.` is visible, then the reply in tab 2.
The next press says `No session waits`.

Every quit returns to the shell with alternate_on=0 and cursor_flag=1.
The four size/theme runs and both additional runs restore `stty -g` exactly.
The raw streams end with alternate-screen exit and cursor-show sequences.
The isolated tmux server is gone. `cleanup.txt` records the sampled owned
processes and their absence after the UI runs; the final board handover also
records the process check after the automated suite ends.

No live agent was used. No product code or dependency was added: library first
for this slice reuses Ink, cli-truncate/string-width and existing tab/watch
state; sentence selection needs no new component, parser or protocol helper.
The earlier strip work records its unsuccessful ink-tab trial in decisions.
No new minor findings. The reviewer's separate documentation task CHD-141 and
the existing CHD-52 for untracked CHD-32 captures with private header paths
remain outside this feature's acceptance. Those untracked captures were left
alone and were not staged; this QA evidence has no private-path matches.

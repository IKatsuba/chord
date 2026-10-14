# CHD-263 QA after the owner's edit removal

Checked main at `0d2e78b`: removal `45e1600`, broken-row hint `15dcec9`.
The task discussion confirms the owner's decision and designer/reviewer approval.

## Ran

- `deno task check` on the current tree, with process access for fake-agent
  cleanup assertions: types, lint and format passed; 1488 tests passed
  (20 steps), 0 failed, in 9m0s.
- `deno task compile`, then the resulting macOS arm64 binary.
- Keyboard-only source and binary tmux in an isolated server at 120x40 and
  80x24, with separate scratch HOME, state and project directories.
- Both removed forms: `/team edit bugfix` and `/team edit bugfix <words>`.
  Compared the scratch file against the original UTF-8 bugfix fixture with
  `cmp`; configured an editor sentinel which would record any invocation.
- Broken-row Down/Enter/Up/Esc, runnable-row Enter, resize, `/team ed`
  completion, saved-name completion and `/help`/shortcuts.
- Typed team run, latest-message running show and immediate stop in both
  executables. Fresh-session `/team new`, save, a plain-language change,
  replacement approval and verification of the saved member fields.
- Deliberate fake-agent `error`, `slow` followed by Esc, keyboard quit,
  tmux terminal flags, before/after stty and `ps`.
- Staged-evidence `tests/privacy_test.ts`: 7 passed, 0 failed.

## Saw

Both removed forms refuse with
`/team has no edit; it takes list, new, show, run or stop`. The original
UTF-8 fixture remains byte-identical in both source and binary and neither
editor sentinel is invoked. The refusal does not start an agent turn.
No edit completion is offered; help retains ctrl+g for the draft, with no
team-edit action.

Broken-row Enter keeps the picker open and draft empty. At 120 columns its
hint says `Fix the file, or ask main to fix triage · Esc to close`; at 80 it
says `Ask main to fix triage · Esc to close`. Up restores the Enter hint.
Runnable Enter fills `/team run bugfix ` and closes the picker. Esc leaves
no stray `/team` or `/team list` transcript row. Broken run reports its
problem without directing the person to edit.

Typed jobs appear under the Team row; running show includes the newer
incoming `← @tester · fake` headline. Stop closes the team immediately and
draws its report before the chord note. Both fresh-session new requests
reach the proposal/replacement box. The original fixture stays identical
while approval is pending. A subsequent plain-language request reaches
`Team(bugfix) · change`, with the replacement choice. After approval, both
saved files contain reviewer on codex, model gpt-5.3-codex, mode read-only.
No real runtime starts: all runtime commands are mapped to the fake fixture,
and this proposal path starts only main's fake agent.

The deliberate error is visible as `The fake agent failed on purpose.`;
Esc produces `Interrupted by user`. Both quits return to a working shell:
`alternate_on=0`, `cursor_flag=1`, and stty is exactly equal before and after.
After bounded shutdown, `ps` shows no descendants of either returned shell.
The isolated tmux server and owned shell processes are removed.

## Separate findings and scope

- Existing CHD-277 still reproduces: an open picker keeps its opening-width
  row layout after resize. The hint follows width, and reopening restores
  narrow rows. It remains usable and does not return this change.
- Filed CHD-283: the fake agent recognizes the new-team preface only at the
  prompt's start. A held run note before that preface makes `/team new` play
  its default text scenario. A fresh `/clear` session exercises the proposal
  correctly. This is a fixture coverage limitation, not a product failure;
  both pieces are present in the recorded prompt.

Prior CHD-263 QA coverage stands where removal did not change behavior.
Designer-approved appearance, CHD-264 resume, physical kitty negotiation
and ctrl+g's encoding issue are outside this pass. No live agent/model was
used and no implementation was repaired by QA.

Library reuse exercised: existing PickerList movement/selection, proposal
and @cliffy/table rendering, Tool's run_team row and transcript messageHeader,
under source Deno and the compiled binary. No dependency or replacement
editor was added. No push, publish or PR.

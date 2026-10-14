# CHD-118 QA at 0153338

Result: Return 2. Switching away from a partially filled elicitation form
and returning discards the entered values. Designer approval stands.

## Commands and checks run

- Read CLAUDE.md, README.md, FEATURES.md, decisions.md, CHD-114 and the
  quarry and chord-tui board skills.
- `deno task check`, rerun unchanged with process access after the sandbox
  denied `ps`, which the fake-agent lifecycle checks need.
- `deno task compile`; drove the resulting macOS arm64 binary in an isolated
  tmux server by keys only, with temporary HOME, config, state and working
  directories and `tests/fixtures/fake_agent.ts` as the only agent.
- Captured text and ANSI at 120x40 and 80x24; compared two-session, leader
  and many-tab structure with CHD-114's mocks, accepting the designer's
  documented differences. Resized the same running window between sizes.
- Temporary fake-only delayed-image probes at both sizes: hold tab 1's
  typed-path read after Enter, open tab 2, send its independent prompt,
  release the read, switch back and inspect both transcripts. Tab 1 had
  shell output held for its prompt.
- Temporary fake-only form-switch probes at both sizes: type a form value,
  open tab 2, return to tab 1 and assert the original value remains.
- Quit with ctrl+d, run `stty -g` again in the restored shell, read tmux's
  `alternate_on` and `cursor_flag`, destroy the isolated tmux server and
  inspect owned processes with `ps`.
- Scan every captured artifact added here for private paths before commit.

## Observations

The unchanged full `deno task check` rerun passes: 780 tests, 20 steps,
zero failures (6m46s). Compile succeeds. The staged evidence privacy test
passes all seven tests.

The compiled binary starts. The two-session strip appears only after the
second session opens. The front tab is bold and inverse in ANSI captures.
The directory appears once. At 80 columns the directory shortens first;
when glyphs require more room, tabs behind drop their names while the front
keeps its name. The leader line fits both sizes and Esc dismisses it.
Forward/back switching, including ctrl+n/ctrl+p as second keys, shows each
session's own transcript. The 80x24 help panel has all 19 rows, including
the session line and merged quit line.

A pending leader digit does not answer the permission list: ctrl+x 2 while
tab 2 asks permission leaves the same request pending. A same-tab leader
digit does not type into a form. Agent failures show their message. Esc on
an active fake turn records `Interrupted by user`, and another prompt works.

Both temporary delayed-image probes pass. Tab 2 can submit while tab 1's
read is held. Tab 1 alone receives its image and held shell context, while
tab 2 retains its distinct prompt and has neither image nor shell context.
The committed typed-path and clipboard switch tests are also in the full
check. The reviewer's separate pasted-path probe and CHD-131 coverage task
remain recorded on the board; they are not claimed as a new QA probe here.

Both temporary form-switch probes fail with
`switching away and back discarded the form value keep`. The failure was
also reproduced twice in the compiled keyboard-only TUI at 80x24. Compare
`80-form-repro-typed` and `80-form-repro-same` with
`80-form-repro-lost`: the first two retain `keep`, the last is empty.

Reproduction from a fresh window:

1. Type `form`, press Enter, wait for Project name.
2. Type `keep` into Project name.
3. Press ctrl+x, then c; wait for tab 2 to connect.
4. Press ctrl+x, then 1.
5. The original form is still pending but Project name is empty.

`ElicitationForm` keeps its reducer state in component-local `useState`
(App.tsx:2743). The front-only form render (App.tsx:1779) unmounts when
switching to a tab without a form. Preserve form values, selection and
cursor by session/request and add a fake-only delayed-switch regression.
This is a defect in the newly introduced switch action and the design's
per-session form state, so it returns to the engineer.

Quitting restored the shell, identical before/after `stty -g`,
`alternate=0` and `cursor=1`. The isolated tmux server was destroyed.
Temporary probe teardown proved all probe agent PIDs stopped. No live
agent, owner configuration write, push, publish or PR was used. Temporary
probes were kept outside the repository and removed after use.

No new component, parser, renderer, protocol helper or dependency was
written in QA. The engineer tried ink-tab 5.2.0 and rejected its fixed
format, key ownership and lack of shrinking/directory support, recorded in
decisions.md.

The first full check reported 779 passed (20 steps) and one failure in the
unchanged shell lifecycle test: `the sleep (96213) outlived the stop`. The
immediate unchanged isolated shell test rerun passed all four tests. This
existing flake is CHD-79; QA added this occurrence there rather than filing
a duplicate. Final process inspection found no leftover PID 96213.

No new unrelated tasks were filed by QA; CHD-131 already tracks
the reviewer's non-blocking pasted-path regression coverage.

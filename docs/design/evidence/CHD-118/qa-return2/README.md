# CHD-118 Return 2 QA

Validated the form fix at `39f89bd` in HEAD `7c9a210`. Designer approval stands.
The earlier QA captures remain in `../qa/`; this round checks the returned fix.

## Ran

- `deno task check` on the current tree: 791 tests, 20 steps, zero failures
  (6m51s), with process inspection access.
- `deno task compile`; the resulting binary started in isolated tmux.
- Keyboard-only compiled TUI checks against `tests/fixtures/fake_agent.ts`, with
  temporary HOME, config, state and working directory, at 120x40 and 80x24.
- Resize from 120x40 to 80x24, agent error, active Esc interruption, another
  prompt, shortcuts, quit, stty comparison and final process inspection.
- Staged evidence privacy tests: 7 passed. New evidence privacy scan and
  `git diff --check` passed. Pre-existing untracked evidence was left alone.

## Saw

At each width, send `form` in tab 1, type `keep`, Tab, type `a@b`, Left.
Switch to tab 2 and back with ctrl+x keys, then type `.dev`. Project name stays
`keep`; Contact email stays focused and becomes `a@.devb`, proving the middle
cursor survived. See `*-form-before` and `*-form-restored`.

Tab four times to Region, Right to open its list, Down to United States.
Switch to tab 2 and back. The list stays open with United States highlighted;
Enter selects it. Leader digits neither pick a choice nor enter the form.
See `*-choice-before`, `*-choice-restored` and `*-choice-selected`.

Cancel that request, send `form` again. The later request starts blank, with
Replicas 2 and Public No, focused on Project name. Typing `fresh` fills that
field. See `*-fresh-form` and `*-fresh-focus`.

Agent failure is visible. Esc interrupts `slow`; a later `text` prompt receives
its reply. The 80x24 shortcuts panel contains all 19 rows. Quit restores the
shell, identical stty state, alternate=0 and cursor=1. The isolated tmux server
was destroyed; no run-owned fake-agent processes remain. See `cleanup.txt`.

The first harness attempt used Enter instead of Right to open Region's list;
that navigation error was corrected and the checks repeated. No product defect
was found. Captures are plain text and tmux ANSI (`capture-pane -e`).

CHD-131 (pasted-path regression coverage) and CHD-132 (permission highlight reset)
remain separate non-blocking tasks under the two-return bound. No new finding
was filed. Earlier strip, leader, permission-digit and delayed-image acceptance
stands; the full suite reruns the committed image/form switch regressions.

Library first: the engineer tried ink-tab 5.2.0 for the strip and rejected its
format, key ownership and absent shrinking/directory support, as recorded in
`docs/decisions.md`. Return 2 reuses FormState/formKey; QA adds only evidence.
No live agent, production source edit, dependency, push, publish or PR.

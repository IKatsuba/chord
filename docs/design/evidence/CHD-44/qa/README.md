# CHD-44 independent QA

Checked implementation `24aa142` and corrected evidence `768d9e2` on
`main` at `82e3e4b`. The designer-approved appearance was kept.

## Commands run

- `deno task check`: types, lint, formatting, 242 tests and 20 steps passed.
  The restricted attempt could not inspect processes; it was stopped and
  its fake agents cleaned up. The unchanged command passed with process access.
- `deno task compile`: produced the macOS arm64 binary, which started in tmux
  against `tests/fixtures/fake_agent.ts` through `--agent-command`.
- `deno task chord:fake -C "$W"`, with `W` created by
  `mktemp -d /tmp/chord-qa.XXXX`, isolated XDG state/config directories and a
  QA-owned tmux server. Input was keys only, with literal text and Enter sent
  separately. Captures were taken after redraws settled.
- `tmux resize-window`: source at 120x40 and 80x24; binary at both sizes.
- `stty -g` before/after, tmux cursor/alternate-screen flags, and `ps` for
  run-owned current and retired agents after quitting.
- `git diff --check` and a private-path scan of evidence before committing.

## Observations

- `/` lists `/clear`, `/echo`, `/exit`, `/greet`, `/help` with descriptions.
  Up wraps from clear to help; Down wraps back. `/gr` filters to greet.
  Tab completes `/greet `; adding `there` and Enter sends `/greet there` and
  returns `Hello from the fake agent.` Enter on `/gr` sends `/greet` too.
- Esc hides the list without erasing the draft.
  `/zzq` has no matches and restores the status line. `/echo two words`
  closes the list and returns `two words`.
- `/help` opens the shortcuts panel, including slash-menu keys; Esc closes it.
- `/clear` starts a **new session**, empties the transcript and restores the
  advertised commands. Up recalls `/clear` without opening the menu.
  Independent session records confirm new sessions rather than a screen reset.
- During the streaming `long` scenario, `/cl` then Enter followed immediately
  by `/clear` then Enter leaves an empty transcript. Five records cover the
  initial session and four clears. The old agent PID disappears, and the new
  session accepts `/greet` without late old-turn output in its transcript.
- `error` displays `The fake agent failed on purpose.` in the transcript.
  Resize during `long`, then Esc, shows `Interrupted by user` and a usable prompt.
- Source `/exit` and binary Ctrl+C twice (after Ctrl+C clears the draft) exit
  successfully. Both restore identical `stty -g` values; tmux reports cursor=1,
  alternate=0. The source shell responds to a command. No current or retired
  QA agent remains in `ps`; the QA-owned tmux server was killed.
- No live agent or model was run. The full check proves session and conversation
  behavior against the repository's fake agent. No code or appearance changes.

The eight ANSI captures are independent QA evidence: open and filtered menus,
empty transcript after clear, and an agent command/reply at each required size.
Read them with `cat` to retain the highlight colour. The 120-column agent
capture follows Tab completion with arguments; the 80-column one follows Enter
on the filtered command. Narrow captures were made after resizing the same TUI.

Library-first evidence remains in `docs/decisions.md`: fzf 0.5 accepted;
Fuse.js 7 tried and rejected for its matching; ink-select-input tried and
rejected for consuming filter letters/digits and rotating limited lists.
QA wrote no component, parser, renderer or protocol helper.

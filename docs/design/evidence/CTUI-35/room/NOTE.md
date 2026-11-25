# The room: a plan with three children, the original at 80x24

Captured from `../chord` (v0.71.0) for unit 20 (design section 6, "The
room"): how the plan box's Note and the agents list share a short window.

Run, in tmux at 80x24, from `../chord`:

```sh
CHORD_FAKE_CHILD_RUNTIME=fake bun dev chord --fake --qa <name>
```

then the prompts `agentsquiet` (opens `parser` and `docs`; `docs` asks
permission), `agentother` (opens `other`) and `cursorplan` (main asks the
plan). `CHORD_FAKE_CHILD_RUNTIME=fake` is needed: without it `other`
opens on codex.

- `original-80x24-plan-three-children.*`: the plan box as asked, Note
  empty (one row), the list whole: `main` and three children.
- `original-80x24-plan-note-N-lines.*`: ↓ ↓ to the Note, then a note of
  `word word …` that wraps to N lines (13 words a line) in the Note's
  width. N = 2, 3, 5, 6, 7, 10.

What they show:

| Note lines | Note rows drawn | List rows drawn |
| --- | --- | --- |
| 1 (empty) | 1 | 4 agents |
| 2 | 2 | 4 agents |
| 3 | 2 (scroll row + 1) | 4 agents |
| 5 | 3 (scroll row + 2) | 2 agents + `… +2 more` |
| 6 | 3 | 2 agents + `… +2 more` |
| 7 | 3 | 2 agents + `… +2 more` |
| 10 | 3 | 2 agents + `… +2 more` |

The hint wraps to two rows once the Note is focused. With the Note focused the transcript has given way to no rows: only the
blank row and the working line stay above the box.
`.txt` is `capture-pane -p`, `.ansi` the same with `-e`. Paths shown by
the original's header are scrolled out of every capture.

## The port at unit 20, commit cc0fc996

`port-unit20-window-tests.txt`: each screen of
`test/ui/app/agents_room_window_test.dart` at the moment it asserts, at
120x40 and 80x24 (three children, the fake's session still starting; the
timer's fake-clock hours shown as `(…)`). The port cannot open the fake's
children by hand at this commit, so the tests' screens are the evidence.

Row for row against the captures above: an empty Note leaves the list
whole; a 3-line Note shows the rule and one line, the list whole; a
5-line Note shows the rule and two lines, the list `main`, `parser`,
`… +2 more`. `original-80x24-form-three-children.*` (`form` after
`agentsquiet`, `agentother`) matches the port's form-with-the-keys screen
row for row: no prompt, the list down to two agents and `… +2 more`.

Two differences inside the Note, both older than this unit: the port's
rule drops ` · pageup to scroll` (`plan_box.dart` passes no key to
`requestRule`; the original passes `pageUp` while the Note has the keys),
and the Note wraps by cells, not words.

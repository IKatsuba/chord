# Children: the fake's scenarios and the fixture, unit 34 (interface I12)

How they were taken:

- `orig-<size>-<name>.*`: `../chord`, unchanged, in a tmux window of the
  size, `CHORD_FAKE_CHILD_RUNTIME=fake bun dev chord --fake --qa <name>`,
  each run in its own fresh QA directory and state, then the prompt.
- `port-<size>-<name>.*`: the port's runner from the repository's root,
  `CHORD_FAKE_CHILD_RUNTIME=fake dart run example/chord/tool/dev.dart chord
  --fake`, the same prompt. The runner keeps the fake's state in its one
  fixed place, so every port run of this capture shares it (see `/resume`).
- `fixture-<size>-<flag>.*`: `dart run example/chord/tool/children.dart
  --<flag>`, no agent.
- `.txt` is `tmux capture-pane -p`, `.ansi` the same with `-e`. The QA
  directory and the repository's path in the header are relabelled
  `<project>`, which shortens that one row; nothing else is edited.
- Times (`idle 13s`, `Session time`) and the version in the header differ
  by run and are not differences.

The port opens the fake's children on `fake` (commit 7dc1d9b2): no capture
shows `No agent named fake`.

## Per capture

- `*-120x40-agents.*`: prompt `agents`. Matches row for row (the list,
  `✓ new reply`, `● permission`, `← new message`, the status notice), but
  for the second message to parser: the original's `→ to @parser`, the
  port's `→ to @parser · queued`.
- `*-120x40-agents-attend.*`: then ctrl+x a, docs' permission in front.
  Matches but for the box's first line: the original's box opens with
  `docs asks`, the port's has no such line (and the port's transcript sits
  one row lower for it).
- `*-<size>-agentsquiet.*`: prompt `agentsquiet`. Match at both sizes. At
  80x24 this stands for `agents` too: the two scenarios rest on the same
  screen, so `agents` was taken at 120x40 only.
- `*-<size>-agentexit.*`: `✗ parser exited · ctrl+x a`, `✗ exited`, chord's
  `parser's agent exited: …` message. Match at both sizes.
- `*-<size>-agentfail.*`: `✗ parser's turn failed`, `◦ idle  ✗ turn
  failed`. Match at both sizes.
- `*-<size>-agentlong.*`: the long markdown instruction folded under
  `Open(parser)`. Match at both sizes.
- `*-<size>-task.*`: the task's permission between turns. The box, the
  heading `Agent(Fix the tokenizer) · fake asks · between turns` and
  `ctrl+x a to answer` match. Differences: the port draws the `spawn_task`
  call as a block of its own, `⏺ Agent(Fix the tokenizer) · fake ·
  fake-small ⎿ taskchild`, above the task's block, where the original
  draws the task's block alone; the original's `background  ● 1 task
  asking` row under the status line is absent in the port (CTUI-36, as
  the owner decided).
- `*-<size>-tasktwo.*`: the original groups the two tasks, `⏺ Running 2
  agents… (ctrl+o to expand)` with `├─`/`└─` rows `· 0 tool uses`, above
  `The build and the deploy are being watched.`; the port draws four
  blocks, each task's `spawn_task` call (`⎿ taskwait`) and then its
  block, no group, and the reply after them. `2 agents still running`
  matches; `background  2 tasks running` is CTUI-36's. The fixture's
  `--tasks`, which hears no call rows, groups them as the original does.
- `*-<size>-taskcost.*`: the same extra call block (`⎿ costwait`) above
  `Agent(Count the cost) · fake`; `background  1 task running` absent.
- `*-<size>-taskcost-cost.*`: then `/cost`: the table matches at both
  sizes (`Count the cost … task agent, running: counted when it ends`,
  `1 running`, the note wrapping at 80 columns).
- `*-<size>-agentclear.*`: chord's refusals for `parser` and `nobody` and
  the reply. Match at both sizes.
- `*-<size>-agentmentions.*`: parser and docs open and their rows match.
  The scenario then calls `run_team` twice: the original answers `No team
  named bugfix · list_teams lists them` on a `Team(bugfix)` row each time
  and ends `Agent completion sessions opened.`; the port shows the raw
  call, `⏺ chord - run_team (MCP)(team: "bugfix", job: "First completion
  team.")`, and the turn ends `⏺ Internal error`, so its status line has
  no `1% context used`. Teams are CTUI-37's.
- `*-<size>-agentmentions-at.*`: then `@@`: `parser` and `docs` offered in
  the same order. Match (the 80x24 transcript stands at another scroll
  line because of the lines above).
- `*-<size>-agentmentions-resume.*`: then `/resume`. The children's rows
  read `open now  parser · text` and `open now  docs · text` in both. The
  port's list also has every earlier port run of this capture (its
  runner's one state place, no `--qa`), so its numbers take two columns
  and its first row is another run's docs; not a parity difference.

## The /cost set

Under `../cost/` as `*-<size>-run-live`, `-run-closed` and `-run-retired`;
`../cost/NOTE.md` says what they show.

## The fixture

`fixture-<size>-<flag>.*` for `--asking`, `--unseen`, `--exited`,
`--failed`, `--tall`, `--many`, `--held` and `--tasks`, each at 120x40 and
80x24. `--light` and `--plain` change only the theme and were not
captured.

## What the differences come to

As the lead settled them after these captures:

- The `spawn_task` call drawn as a block of its own (`task`, `tasktwo`,
  `taskcost`): a difference of the port's, fixed after this commit.
- `/clear` keeping a child open (`../cost/*-run-retired`): a difference
  of the port's, fixed after this commit.
- The permission box from ctrl+x a without its `docs asks` line
  (`agents-attend`): a difference of the port's, fixed after this
  commit.
- The close note naming the model (`../cost/*-run-closed`): kept, as
  `../cost/NOTE.md` says.
- `· queued` on the second `→ to @parser` (`agents`): timing. The fake
  takes no steering by default, so the message goes in as a turn, queued
  while parser's turn runs; the scenario sends it as parser's turn for the
  first begins, and the original's capture caught that turn already over.
  Given the same state the port answers as the original
  (`test/session/message_queued_timing_test.dart`).
- `run_team` unserved (`agentmentions`): expected; teams are CTUI-37's.
- The `background` row under the list (`task`, `tasktwo`, `taskcost`):
  expected; the owner left it to CTUI-36.


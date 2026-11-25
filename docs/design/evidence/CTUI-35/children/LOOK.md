# Designer's look at unit 34, commit 5e6e7e9d

The fixture (`tool/children.dart`), run live at 80x24 and 120x40 with no
flag and with `--asking`, `--unseen`, `--exited`, `--failed`, `--many`,
`--tall`, `--held` and `--tasks`, reads as the original's list does:
words as `status.ts` has them, `… +6 more`, a tall row cut with `↓`
beside its last line in sight (`agents.ts`), the held rows with
`after the running calls:`, the task group under `Running 2 agents…`.

The side-by-side captures here, compared with times and the version
masked: `agentsquiet`, `agentexit`, `agentfail`, `agentlong` and
`agentclear` are equal at both sizes. The differences that read badly,
each in a unit before this one:

- `tasktwo` (live): each `spawn_task` call is drawn as an
  `Agent(…) · fake ⎿ taskwait` block of its own above the task's block,
  four blocks where the original draws one `⏺ Running 2 agents…` group;
  `taskcost` and `task` show the same extra call block. The fixture's
  `--tasks` groups, so the live path does not.
- `agents-attend`: the permission box ctrl+x a opens lacks its
  `docs asks` line.
- `/clear` with a child open keeps the child (see `../cost/`); the
  original closes it.

Nits: `· queued` on the second `→ to @parser` (`agents`), the close
note's model. Decided: no background row (CTUI-36), `run_team` (CTUI-37).

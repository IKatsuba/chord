# CTUI-37 brief: teams, chord's team tools and get_budgets

The original's M5 (`../chord` `docs/FEATURES.md` M5, `docs/design/M5-teams.md`,
`docs/guide.md` "Teams" (about lines 1489-1600), "Resource facts and team
selection", "Children, teams and commands" (about 805-900) and the settings
table's `teamSelection`), ported to the window and to `chord acp`. Board
comments on CTUI-37 add: `/team` in `chord acp`'s `upstream_commands`
(CTUI-56 split), `get_budgets` on chord's MCP server with M5's resource facts
(CHD-533, CHD-548), and the `teamSelection` settings, already checked and
merged in `example/chord/lib/settings.dart` by CTUI-79 (used as they are).

The design builds on CTUI-35 (`docs/design/CTUI-35.md`: the server, the
host of many sessions, `toolsOf`, `WindowAgents`, records; its section 9
lists the seams CTUI-37 fills: lead and member branches of `toolsOf` and
`messageRecipients`, `Caller.team`, team rows and folding, team clauses in
the left-open note, `team` in `chord acp`'s commands, `get_budgets`) and
CTUI-36 (monitors, the background view; members and leads have monitors as
children do).

**M5-teams.md is the first design; `src/` and `tests/` are the
specification where they moved on** (efforts on rows, `"` and control
characters refused in names, `list_teams`'s `runs`, selected runs and their
receipts, `/team show <run ID>`, `/team choose` removed, CHD-548's
`get_budgets`). Where the design and the source disagree, the source holds
and the draft says so.

## The problem

M4 gave the window long-lived children. M5 lets a person keep a team in a
file (a lead and up to eight members, each with runtime, model, effort,
mode and instructions, plus a markdown body every agent reads), hand it a
job by words to main (`run_team`) or by `/team run`, and watch it in the
agents list, one level deeper than M4. The lead opens only the file's
members; everyone may `spawn_task`. CHD-533/548 add `get_budgets`, which
reads Claude Code's and Codex's usage windows when called, and per-run
selection overrides on `run_team` (`selection: {reason, lead?, members?}`)
checked against `teamSelection` constraints, frozen for the run and
recorded as a receipt.

## What a person sees and presses

- `/team` (`/team list`): the teams picker, `/resume`'s panel shape; Enter
  puts `/team run <name> ` in the draft; a broken file shows its first
  problem and Enter does nothing; empty: `No teams yet. …`.
- `/team new <words>`: a prompt to main naming `propose_team`.
- `propose_team`'s `Team(<name>) · proposal` / `· change` rows (table of
  agents with runtime, model, effort, mode in warning colour when it skips
  the person's ok, role; body as markdown or diff), and the save box shaped
  like the permission box: `Save team <name>?` 1 this project / 2 every
  project / 3 tell the agent what to change (Esc); `Replace team <name>?`
  for a change. Saved / not saved / write failed rows.
- `/team show <name>` (and its running form with each agent's state, unseen
  mark and latest headline), `/team show <run ID>` for a recorded selected
  run's receipt; `/team run <name> <job>` drawn as `Team(<name>) · …` with
  no turn of main's, main told with the next prompt; `/team stop <run>`.
- Completion of team names after `show`, `run`, `stop`; `/team` in the
  slash list and `/help`.
- The agents list: lead row `team · claude · Opus`, members nested `├─`
  `└─`, folding a team to its lead's row with its size and most urgent
  state naming the member, the team under the `❯` unfolded; `bugfix 2`
  runs; member box `tester · bugfix`; header `bugfix's member · opened by
  @bugfix`; the instructions line `bugfix's instructions for tester · N
  lines (ctrl+o to expand)`; status line and notification wording naming
  the run; `x` on a lead closes the team, armed while any of it works;
  `ctrl+x a` unfolding to a waiting member.
- `← chord` notes: member closed (to lead), member exited / turn failed (to
  lead, and the M4 parent rule), lead exited (members closed, to main),
  team closed by the person (to main).
- `Resources` block for `get_budgets`; `List teams`, `Run team` rows and a
  selected run's receipt (`RecordedReceipt`).
- Resume: past drawn, teams not reopened, the left-open note names each run
  with its count and `/team run <name> starts the team again`.
- `chord acp`: `/team` forms answered as text, `team` in the command list,
  refusals worded as the guide's list.

No new key (M5's "Keys" table).

## What an agent calls

`list_teams`, `run_team {team, job, selection?}`, `propose_team`,
`get_budgets {agents?}`; a lead's `open_agent {member, prompt}`,
`send_message` (main, its members, other runs' leads), `close_agent` (its
members); a member's `send_message` (its lead, its team's open members);
`spawn_task` and `list_agents` for every long-lived agent; `list_agents`
gains each runtime's modes. Per-role tool sets as `src/server/tools.ts`'s
`toolsOf`, forks' refusals for the team tools (guide line ~632).

## Constraints

- AGENTS.md binds. Files named after the original's: `lib/teams.dart`,
  `lib/session/{team_command,team_selection,budgets,resource_normalization,
  resource_access,codex_resources}.dart`, `lib/platform/resource_*.dart`,
  `lib/ui/teams/`, `lib/ui/transcript/tools/{proposal,resource_lines,
  selection_lines}.dart`, and the existing files extended.
- The repository's own `.chord/teams/architects.md` and `ship.md` must load
  in the port exactly as the original loads them (a test reads both).
- Packages before our own code for what is not the terminal: YAML reading
  (`yaml`), YAML writing that matches `@std/yaml`'s `stringify` closely
  enough that a file saved by the port reads back the same in both
  programs, diffing (`dartdiff`, CTUI-6, and the framework's diff view, CTUI-16;
  reuse it), JSON-RPC to Codex's app-server (`json_rpc_2`, pinned). Problems
  in zod's words, by the port's own checker (CTUI-29's decision).
- The framework stays chord-free: only what a terminal app generally needs
  goes to `lib/` of the framework (likely nothing new: the picker, the
  permission-box shape, the table and folding exist; say if not).
- Tests never reach a real agent or a real provider's usage endpoint: pure
  modules, the tester, in-memory/scripted ACP, the original's fake (its
  `team`, `team2`, `teamlead`, `teamtester`, `teamcoder`, `teamtask`,
  `propose`, `selectedteam`, `budgetawareteam`, `savedteamplain`
  scenarios) and the original's resource fixture source
  (`src/platform/resource_fixture.ts`), plus a test that a real reader is
  never resolved under test.
- Owner's priority: features first, polish later; nothing beyond the
  original.

## Non-goals

`/team choose` (removed by the owner in the original), any scheduler,
reservation or quota enforcement, reopening teams on resume, worktrees,
locks on files, a chord-side check of the body's sections.

## Open questions, per architect

**framework**
1. Does any part need a new framework widget or change (the proposal table
   with columns cut and wrapped by priority, a diff of the body folded with
   context, folding rows in the agents list)? Name the existing widgets
   used, or the smallest addition with its tests.
2. The proposal table: what the original does with `@cliffy/table` vs the
   source's actual layout (`src/ui/transcript/tools/proposal.ts`), and how
   the port draws it at 120x40 and 80x24 with the existing text layout.

**interface**
1. Every screen and word: picker (rows, hints, narrow forms), save box,
   proposal/change rows (folded and ctrl+o), `/team show` both forms and the
   receipt, `Team(…)` rows and refusals, `List teams`, `Resources`, the
   list's team rows, folding, member header, box title, status line,
   notifications, `x` arming words, `← chord` notes, the resume note, and
   `chord acp`'s `/team` answers. Verbatim, with the source line for each;
   where M5-teams.md and `src/` differ, say which and why.
2. Where each piece sits in the port's existing UI (pickers, dialogs,
   transcript tools, agents view, prompt commands) and what the shortcuts
   panel line becomes.
3. The capture plan: which fake scenarios give each state at 120x40 and
   80x24, original beside port.

**runtime**
1. Team files: discovery, read, check (zod's words and order, including
   the source's later rules), write (atomic rename) and the YAML packages:
   try `yaml` for reading and at least two writers (`yaml_writer`,
   `yaml_edit`, others) against `@std/yaml`'s output for the original's
   tests and this repository's two team files. Say what fits; if none does,
   that is an owner question with options.
2. The host: runs, leads, members, naming (`bugfix 2`, numbers not reused),
   frozen run snapshot and selection (`team_selection.ts`: validation,
   freezing, receipts, cleanup warning), `toolsOf` and `messageRecipients`
   branches, closing rules (parent closes children, lead exit), the team
   part of first prompts (`teamPart`), records (`team`, member names,
   receipts) and replay, `chord acp`'s `/team`.
3. `get_budgets`: the readers. Codex through its app-server over JSON-RPC
   is plain Dart. Claude's reader runs the TypeScript Agent SDK's
   experimental getter in an isolated worker of chord's own binary; Dart has
   no Agent SDK. Find what the SDK actually sends to the `claude`
   executable for that getter and lay out the options (speak that protocol
   from Dart, run the SDK through a JS runtime, report Claude unavailable,
   …) with costs; this is likely an owner question. Executable resolution,
   process groups and cleanup, the 10 s bound, `darwin-arm64` only, the
   fixture source for tests.
4. Failure modes and tests per unit; performance of folding many runs in
   the list and of `/team show`'s running form.

Each draft ends with its proposed units for ship (ordered, each with its
tests) and the questions it thinks are the owner's.

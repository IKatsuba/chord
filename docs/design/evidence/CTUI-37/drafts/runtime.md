# CTUI-37 runtime draft: team files, runs, get_budgets

Runtime architect's answer to the brief's runtime questions. Line
references are to `../chord` as it stands; where `docs/design/M5-teams.md`
or CHD-533 differ from `src/`, the source holds and the difference is named
(section 9).

## 0. Findings that change the brief

- **The original does not write with `@std/yaml`.** `src/teams.ts` reads
  frontmatter through `vfile-matter` (which calls npm `yaml` 2.9.1's
  `parse`) and writes with npm `yaml` 2.9.1's `stringify`, default options.
  The writer trial (section 1.4) is against that.
- **Codex's app-server speaks JSON-RPC without the `"jsonrpc": "2.0"`
  member**, both ways (`codex-app-server-client` 0.1.5 never writes it; the
  original's fake `tests/fixtures/resource_provider.ts` answers `{id,
  result}`). `json_rpc_2` 4.1.0's `Client._isResponseValid` drops any
  response without it, so the `Client` as it is never sees an answer. That
  is an owner question (Q2).
- **The Claude usage getter is a stream-json control request**, which the
  original's own test fixture `tests/fixtures/claude_resource_provider.ts`
  already speaks. Captured in a scratch run of SDK 0.3.325 against a fake
  executable (section 3.2). Speaking it from Dart is plain process I/O
  (Q1).
- **No pub package detects Mach-O/ELF under `dart compile exe`** (section
  3.4): a four-byte check of our own (Q4b).

## 1. Team files

### 1.1 Module layout

| Original | Port | Kind |
| --- | --- | --- |
| `src/teams.ts` | `lib/teams.dart` | pure check, text and changes; file effects (`findTeams`, `saveTeam`) over `dart:io`, tested on temporary directories |
| `src/agent_name.ts` | `lib/agent_name.dart` (exists) | `"` and control characters refused, reused by member names |
| `src/session/team_command.ts` | `lib/session/team_command.dart` | pure: `teamCommand`, `ranNote`, `teamRefusal`, `stoppedLine`, `NO_TEAMS`, `LEAD_ROLE`, `newTeamPrompt`, `teamsSaved`, `briefly` |
| `src/session/team_selection.ts` | `lib/session/team_selection.dart` | pure: `RunChoice`/`RunSelection` checks, `freezeSelection`, `validateSelectedRole`, `selectionReceipt`, `confirmSelectionRole`, `withSelectionCleanupWarning`, `recordedSelection` |
| `src/session/budgets.ts` | `lib/session/budgets.dart` | pure: `ResourceWindow`, `ProviderLimits`, `Budgets` checks; `TeamSelection` reuses `lib/settings.dart`'s checker and `mergeTeamSelection` (CTUI-79) |

Tests mirror: `test/teams_test.dart`, `test/session/team_command_test.dart`,
`team_selection_test.dart`, `budgets_test.dart`.

### 1.2 Discovery and read

As `findTeams`: `teamDirs` gives `<cwd>/.chord/teams` and `teams/` beside
the user settings file (none without a config home); each `*.md` that is
not a directory; project wins a shared name and marks `hides`; sorted by
name with code-unit order (`<`, not locale); every file read in parallel
(`Future.wait`), a read error giving `cannot be read (<OS message>)`, the
OS's words inside as CTUI-29 already accepted for settings. A missing
directory is no teams; any other listing error throws, as the original.

Files are read whenever needed (picker, completion, `list_teams`,
`run_team`, `/team run`, `/team show`, `propose_team`), never cached, so a
file saved elsewhere counts at once. Window-side reads are async results
and carry `(key, launch)` (CTUI-35 section 3): a picker or completion
answer whose key or launch moved is dropped.

`parseTeam`: the bytes decoded as UTF-8 with a leading BOM dropped (as
vfile's decoder); vfile-matter's regex verbatim
(`^---(?:\r?\n|\r)(?:([\s\S]*?)(?:\r?\n|\r))?---(?:\r?\n|\r|$)`); no match →
`no frontmatter between --- lines`; `loadYaml` on the group, a `null`,
`false`, `0` or `''` document reading as `{}` (vfile-matter's `|| {}`), so
an empty frontmatter says `description is missing`; a YAML error →
`the frontmatter is not valid YAML (<first line of Dart yaml's message>)`.
The message inside the parentheses is the Dart parser's (`Duplicate
mapping key.` where npm yaml says `Map keys must be unique`), the same
accepted difference as CTUI-29's `not valid JSON (…)`.

(**Revised after review**) `package:yaml` 3.1.4, the version the port's
`pubspec.lock` pins and the one the trial resolved (pub `yaml`, Dart team), reads every input of the
trial as npm `yaml` does (section 1.4), including `yes`/`on` as strings,
`0o17`, `0x1F`, `.inf`, `~`, anchors and aliases, dates as strings and
duplicate keys refused. The `YamlMap` is converted to plain `Map`/`List`
before checking, so the checked team holds no `YamlNode`.

### 1.3 The check, in zod's words and order

Our own checker, as CTUI-29 decided for settings, in `lib/teams.dart`. It
reports only the first issue, so what matters is which issue zod reaches
first. The order, from the schema and zod v4's object walk:

1. The name: `agentNameProblem` first, then `TEAM_NAME`
   (`^[a-z][a-z0-9-]{0,23}$`), then `main`/`chord` taken.
2. Root not a mapping → `the frontmatter is not a YAML mapping`.
3. Shape keys in order: `description`, `lead`, `members`; inside each,
   its keys in declaration order (lead: `agent`, `model`, `effort`,
   `mode`, `instructions`; member: `name`, `role`, `agent`, `model`,
   `effort`, `mode`, `instructions`); array items by index; then the
   object's unknown keys (`<path>.<key> is not a key a team has`; at the
   root `unrecognized key: "x"`, lowered as `problemOf` does).
4. Per string: type (`invalid input: expected string, received number`),
   then `min` (`too small: expected string to have >=1 characters`),
   `max`, then refinements (`must be one line`, `chord knows no runtime
   named x`, the member name's regex message, then `x is taken`). zod v4
   runs continuable checks in sequence, so with only the first issue kept
   the first failing check names it.
5. A missing key → `<path> is missing` (the custom `MISSING` map).
6. Members array: type, `min(1)`, `max(8)`, items, then `superRefine`'s
   `members.<i>.name: <n> is named twice` at the second occurrence.
7. The body trimmed; empty → `the body is empty`.

Problem text is `problemOf`'s: `<path>: <message with first letter
lowered>`. The test reads every case of `tests/teams_test.ts` (its
problem table at about line 300 and the effort cases) as a table, so the
port and the original are checked on the same inputs; any case whose
exact zod wording is not obvious from the source is run once in the
original under bun by the ship developer and pinned.

`checkProposal` and `teamChanges` (deep equality over the plain maps,
`DeepCollectionEquality` from `collection`, already a dependency) as the
original.

### 1.4 Writing, and the YAML writer trial

`saveTeam`: create the directory recursively; write
`<file>.<uuid>.tmp`; rename over `<file>`; on any error delete the
temporary (ignoring a delete failure) and rethrow. `teamText` is
`---\n<yaml>---\n\n<body>\n`.

Trial, in a scratch Dart project outside the repository, against npm
`yaml` 2.9.1's `stringify` run under deno, on: `tests/fixtures/teams/bugfix.md`,
this repository's `.chord/teams/architects.md` and `ship.md`, and two edge
sets (strings that need quotes: `yes`, `123`, `null`, `true`, `0x1F`, `~`,
`: `, ` #`, `@`, `- `, brackets, quotes; multi-line strings with no final
newline, two final newlines, leading spaces, blank lines, tabs, trailing
spaces; a long single line).

| Writer | Byte-identical to `stringify` | Dart `yaml` reads back equal | npm `yaml` reads back equal | Notes |
| --- | --- | --- | --- | --- |
| `yaml_writer` 2.1.0 | no (5/5) | no (edge) | no (edge) | quotes every string; `|` with no indentation indicator loses leading spaces; `|+` written as `|`, so a second final newline is lost. **Does not fit.** |
| `yaml_edit` 2.2.4, default style | no (5/5) | yes (5/5) | yes (5/5) | every multi-line string double-quoted on one line with `\n`; no folding at 80 columns |
| `yaml_edit` 2.2.4, `ScalarStyle.LITERAL` on multi-line strings | no (5/5) | yes | yes | falls back to double quotes for strings ending in one newline (the usual `instructions`), literal with 4-space indent otherwise: mixed and unlike either program |

What `stringify` does that none of them does: plain scalars when safe,
double quotes otherwise; block literals `|`, `|-`, `|+` and `|2` as
needed; long plain or quoted lines folded at 80 columns
(`description:` and `role:` lines in the repository's own files fold);
`>` for a long single line ending in a newline.

So: no package writes what the original writes. Both `yaml_edit` styles
satisfy the brief's bar, "a file saved by the port reads back the same in
both programs", and the original's round-trip test (`teamText(teamOf(saved))
== saved`) passes with any deterministic writer. What is lost is the look
of a saved file a person then edits by hand. Owner question Q3
(**Revised after review**: recommendation `yaml_edit` alone; trials ran
with Dart `yaml` 3.1.4, the version the port pins).

The repository's two team files load in the port (both programs read
them to the same data in the trial); a test reads both with the runtime
list `claude`, `codex` and expects a team each.

## 2. The host: runs, leads and members

### 2.1 Where things live

| Original | Port |
| --- | --- |
| `window_agents.ts` team parts | `lib/session/window_agents.dart`: `isLead`, `membersOf`, `ownChildren` (no `lead`, no `forkedFrom`), `runName` with `agents.runs`, `messageRecipients` lead and member branches, `childEnded`'s lead clause, `namedChild` (`tester · bugfix 2`), `notifiedName` (`tester (bugfix)`) |
| `agents_host.ts` | `lib/session/agents_host.dart`: `runs` map, `runTeamAt`, `runSelectedTeamAt`, `openMember`, `teamTell`, `dropChild`'s members-first, `tellEnded`, `closeAgent`'s lead branch, `closeByPerson`'s team clause, `runTyped`, `stopTyped`, `showTyped`, `teams`, `budgets` on `WindowView` |
| `server/tools.ts` | `lib/server/tools.dart`: `list_teams`, `run_team`, `propose_team`, `get_budgets`, the lead's `open_agent`, `tellTeam`, `toolsOf`'s lead and member branches, `FORK_REFUSED` on `run_team` and `propose_team` |
| `teams.ts` `teamPart` | `lib/teams.dart`; `teamBlock` already parsed by `record.dart`'s `_teamLabel`; written by `lib/session/tasks.dart` |
| `ui/agents/agents.ts` `teamRows`, `teamState`, `leftOpenLine` | `lib/ui/agents/` (interface owns the drawing; the fold computation is pure and tested here) |

### 2.2 State

- `runs: Map<leadId, Run>` with `Run = FoundTeam + team (frozen) + job +
  selected?`. The team is the file **as read at run start**; `openMember`
  reads only `run.team`, never the file again (original 464-471, 2229).
  A selected run's `team` is `freezeSelection`'s deep copy; Dart has no
  `Object.freeze`, so the frozen run holds unmodifiable copies
  (`Map.unmodifiable`, `List.unmodifiable`, recursively) built once, and a
  test mutating the source map after the run starts sees no change.
- `agents.runs`: closed leads' names, kept across `/clear` and `/resume`
  (`forgetClosed` keeps it), so `bugfix 2` is never reused while the
  window is open. `runName` is `numbered(team, taken)` over `main`,
  `chord`, every open child's name and `runs`.
- `parts: key → TeamPart` and `early` (exists) carry the team part to the
  first `deliver`.

### 2.3 Counting

`MAX_CHILDREN = 8` counts main's own children: a lead is one, members are
none, forks none (`openChild` refuses only `lead == null && forkedFrom ==
null && ownChildren >= 8`). Members are bounded by the file (`max(8)`)
and by `${member} is open; send_message reaches it`. Worst case in one
window: 8 runs × (1 + 8) + 8 forks + tasks of each long-lived agent. That
bound is what the performance section uses.

### 2.4 `run_team`, direct

`runTeamAt` in the original's order (`agents_host.ts` 2123-2208):
launch valid → read teams now → not found
(`No team named X · list_teams lists them` for the tool, `· /team lists
them` for `/team run`) → file problem → `startRefusal(name = team)` then
`fullRefusal` → launch valid again → `runName` → `startChild` with
`team: {name}`, the lead's `teamPart` (`others` = other open leads' names)
and `asked: set by team X` → launch moved after start → `Team launch <id>
was cancelled before its first job; the attempted lead is closing.` →
`runs[id] = run`. The run is registered after `startChild` returns and
before `connected` delivers the first prompt (that delivery is a later
event), so a lead cannot call `open_agent` before its run exists. The
port's `startChild` delivers on the host's ordered event path, which
keeps that ordering; a test drives a scripted lead that calls
`open_agent` in its first turn's first update.

The view wrapper awaits `started` (effort settled) and answers `{id,
name, agent, model?, mode?, team, effort?}`.

### 2.5 `run_team` with `selection`

`runSelectedTeamAt` in order: launch → teams → `The saved team is
invalid. No run started.` → `policyNow()` (merged user + project
`teamSelection`, re-checked; a throw gives `Team selection settings could
not be validated. …`) → `freezeSelection` without capabilities → each
distinct runtime's capabilities **one after another**, launch checked
after each (`Runtimes.read`, which may probe; bounded by its 60 s) →
`freezeSelection` with capabilities → admission (`The selected lead
cannot be admitted. No run started.`) → id `uuid().substring(0, 8)` →
`runs[id]` **before** `startChild` → receipt published `planned` → await
`validated`.

Receipt updates (**Revised after review**). The original never rewrites a
recorded call: it **appends** each update as a new `served` line to the
record captured when the launch was admitted (`agents_host.ts`
2017-2053, `conversation.ts` 2208-2228, `record.ts` 1300-1317). The port
ports that capture:

- `Recording.captureServed()` on the file recording: returns null when no
  record was genuinely opened (never a replacement's path); otherwise
  marks the record begun and flushes (an admitted attempt is history even
  when the caller sent no prompt, so a no-prompt refused attempt keeps the
  record), and returns a writer `(turnId, call)` that queues a `served`
  line to **that path** through the existing record worker.
- `Conversation.captureServed()`: null without a session; else captures
  the recording's writer and the current turn stamp, and returns a writer
  that goes through `served(call)` while the same session is current and
  through the captured writer otherwise. Today's `served` drops writes
  during close and stamps the current session (`conversation.dart`
  1502-1504); the captured writer is what lets a late update land after
  `/clear`, during close and after the window moved on.
- `publish` builds the `run_team` call (`asked: runId`, `answer: {id, name,
  team, agent, receipt}`, plus `error: Team launch <id>: <note>` when the
  lead is refused) and writes it through main's captured writer and the
  lead's (captured in `checkStarted`, once the lead opened).
- Updates: planned at launch; lead confirmed or refused (`confirmSelected`
  reads actual agent/model/mode/effort, each 1-128 characters or null;
  effort only a soft note); each member refused, confirmed or not
  admitted; `withSelectionCleanupWarning` when a close fails
  (`dropChild`'s `closed.catch`, for a lead or a member of a selected run).
- On read, replay folds `served` `run_team` lines by `asked` (= runId):
  the last line for a run is its receipt, drawn at the position of the
  first. No rewrite mechanism is added.

Tests (record, isolated `XDG_STATE_HOME`): a receipt updated after
`/clear` of main lands in the record admitted, not the fresh one; an
update during main's close and after the window closed is appended; resume
shows the latest state only; a refused attempt with no prompt keeps the
record (it is listed by `/resume`); a member's cleanup failure leaves the
warning in the latest receipt after resume.

The receipt check is `SelectionReceipt` in our checker; `recordedSelection`
accepts a receipt only when `asked == runId == answer.id`.

### 2.6 A lead's `open_agent {member, prompt}`

`openMember` with its three `occupied()` checks (before admission, after
`startRefusal`, after the selected run's capability read): two calls for
one member that both passed the first look start one member, the second
answered `<member> is open; send_message reaches it`; a lead closed
meanwhile answers `You are closed; you open no members`. A selected run
re-reads policy and capabilities at admission (`This member was not
started.` suffix). Parent is the lead's `Conversation`; `from: {name:
lead.name, reachable: true}`; `team: {name: run.name, lead: lead.id}`.

### 2.7 Messages

`messageRecipients`: main → its children; fork → none; plain child →
main; lead → main, its members, other leads; member → its lead and the
other members; lead gone → none. `teamTell`'s refusals verbatim from the
original (`Your lead has closed; nothing more reaches it`, `No agent X is
open for you; you reach a, b, and c`, …). The `and` list is `andList`,
`Intl.ListFormat('en', conjunction)`: `a`, `a and b`, `a, b, and c`
(checked under deno); the port writes it by hand, tested on 1, 2 and 3
names, as Dart's `intl` has no list format.

### 2.8 Closing

- `dropChild` (**Revised after review**), as `agents_host.ts` 614-655:
  members' drops are **started** first, recursively, each starting its own
  `closeChild` without awaiting it; then the lead's `runs` entry removed,
  pending clear settled `it was closed`, busy turn interrupted, `!` command
  stopped, spend kept, and the lead's `closeChild` started at once. Nothing
  awaits a member before the lead. Each close's failure is caught on its
  own (the cleanup warning for a selected run's role); `closeAll` joins all
  and reports one aggregate error. Test: a stubborn member and a stubborn
  lead (both ignore SIGTERM, scripted) close within the longest single
  `StopBounds`, not the sum, and both failures (if any) are in the
  aggregate.
- Lead `disconnected` (`tellEnded`): drop every member, then tell main
  `<run>'s lead exited: <stderr end>. Its members are closed; run_team
  starts the team again.` Member exit or failed turn: told to its lead
  (`parentOf` is the lead's conversation), the M4 wording.
- `close_agent`: a member's only its tasks (`No task X of yours;
  spawn_task's answer names them`); a lead's only its members (`No member
  X of yours is open`); main's a lead with its members.
- The person's `x` on a lead: `The person closed team <run>: its lead
  (<runtime · model>, id <id>) and its members a and b. It takes no more
  messages; run_team starts it again.` `/team stop <run>` shows
  `stoppedLine` first, then the same close.
- Bounds: every close is the existing `StopBounds` per process group, run
  concurrently by `closeAll`; a window closing with 8 runs of 8 waits the
  longest single bound, not the sum.

### 2.9 Records and replay

- Header: `team` on a lead only (the file's name); a member's header has
  `parent` = the lead's session id, `name`, `id`, no `team` (exists as a
  seam).
- `ran` line for `/team run`'s call, apart from `served`, so a resume does
  not answer a later `run_team` with it.
- `leftOpen` scans `served` and `ran` for `open_agent` and `run_team`; a
  `run_team` answer with `team` becomes `team <name> (<n> agents)` with `n =
  1 + members open in the lead's record`. Reading the lead's record is one
  more file per run on resume; with at most 8 runs that is bounded, and it
  goes through the existing record worker.
- A selected receipt reads back by `recordedSelection`; `/team show <run
  ID>` finds it in main's replayed calls. Older-format answers draw
  `Recorded in an older format; not shown.` (interface owns the words).
- Teams are not reopened on resume.

### 2.10 `chord acp`

`/team` through `upstream_commands`, with `ACP_TEAM_WORDS`; `list` →
`teamsText`, `new` → a turn of `newTeamPrompt`, `show` → `teamText` or
`runText`, a selected run's or recorded receipt's `show` refused (`… only
chord's window shows its receipt: …`), `run` → `startedText`, `stop` →
`stoppedLine`; a command with other blocks refused. (**Revised after
review**) chord's commands are `[team, new]`, `team` first, as
`upstream.ts` 126-139 (`CHORD_COMMANDS`), ahead of the agent's; a test
asserts the whole emitted list with agent commands present (`team`,
`new`, then the agent's in its order), and `commandsIfNone` sending both. The left-open note goes out in `_meta['chord/left_open']`
with team items. The resource readers' close is a leave step `resource
readers` that fails with the joined warnings (section 3.6).

## 3. `get_budgets`

### 3.1 Layout

| Original | Port | Kind |
| --- | --- | --- |
| `session/resource_access.ts` | `lib/session/resource_access.dart` | types: `LimitsPlace`, `ReadLimits` |
| `session/resource_normalization.ts` | `lib/session/resource_normalization.dart` | pure |
| `session/codex_resources.ts` | `lib/session/codex_resources.dart` | effect over a `GroupProcess` |
| `platform/resource_process.ts` | `lib/platform/resource_process.dart` | `withResourceProcess`, `ResourceReadError`, bounds, cleanup ladder |
| `platform/resource_executable.ts` | `lib/platform/resource_executable.dart` | resolve with an injected `ExecutableInspection` |
| `platform/resource_worker.ts` | `lib/platform/resource_worker.dart` (name kept, see Q1) | Claude's reader |
| `platform/resource_fixture.ts` | `lib/platform/resource_fixture.dart` | fixture cases |
| `platform/resources.ts` | `lib/platform/resources.dart` | `createResources`, `READ_TIMEOUT_MS` |

### 3.2 What the SDK sends `claude` for the usage getter

`usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({skipBehaviors:
true})` is `request({subtype: 'get_usage', skip_behaviors: true})`.
Captured by running SDK 0.3.325 with the original worker's options against
a fake executable that logs argv and stdin (no real `claude`, no network):

```text
argv: --output-format stream-json --verbose --input-format stream-json
      --tools= --setting-sources= --strict-mcp-config
      --no-session-persistence --settings {"disableAllHooks":true}
env:  CLAUDE_CODE_ENTRYPOINT=sdk-ts (when unset), CLAUDE_AGENT_SDK_VERSION=0.3.325;
      NODE_OPTIONS and DEBUG removed
stdin (one JSON per line):
  {"request_id":"<random>","type":"control_request","request":{"subtype":"initialize","systemPrompt":[""]}}
  {"request_id":"<random>","type":"control_request","request":{"subtype":"get_usage","skip_behaviors":true}}
stdout (one JSON per line, other message types ignored):
  {"type":"control_response","response":{"subtype":"success","request_id":"<id>","response":{…}}}
  {"type":"control_response","response":{"subtype":"error","request_id":"<id>","error":"…"}}
then: stdin closed, the process exits.
```

The `get_usage` response is `SDKControlGetUsageResponse`
(`rate_limits_available`, `rate_limits.{five_hour, seven_day,
seven_day_oauth_apps, seven_day_opus, seven_day_sonnet, model_scoped[]}`),
which `normalizeClaude` already reads. The original's fake
`tests/fixtures/claude_resource_provider.ts` answers exactly these two
subtypes, with scenarios `normal`, `unavailable`, `null-windows`,
`init-hang`, `getter-hang`, `stubborn`, `late`.

**Recording the wire (Revised after review).** So the pinned wire can be
reviewed and re-recorded for a later SDK, the recording is reproducible
with no real `claude` and no network, in any scratch directory outside the
repository:

1. `fake.ts`, run by deno: writes `{argv, env}` (the environment filtered
   to names matching `CLAUDE|SDK|NODE_OPTIONS|DEBUG`) as the first line of
   a log, then appends each stdin line; answers `initialize` with
   `{commands: [], agents: [], models: [], account: {}, output_style:
   'default', available_output_styles: ['default']}` and any other
   `control_request` with `{rate_limits_available: true, rate_limits:
   {five_hour: {utilization: 1, resets_at: null}}}`, each as
   `{type: 'control_response', response: {subtype: 'success', request_id,
   response}}`; writes `EOF` when stdin ends.
2. `fake-claude`, a shell script with no `.js`/`.ts` suffix (so the SDK
   runs it as a native binary): `exec deno run --allow-all fake.ts
   <log> "$@"`.
3. `run.ts`, run by `deno run --allow-all --node-modules-dir=auto`:
   `query()` from `npm:@anthropic-ai/claude-agent-sdk@0.3.325` with
   exactly `resource_worker.ts`'s options (`settingSources: []`,
   `persistSession: false`, `strictMcpConfig: true`, `mcpServers: {}`,
   `tools: []`, `settings: {disableAllHooks: true}`, an empty prompt
   iterable held open, `pathToClaudeCodeExecutable` the fake), then
   `initializationResult()`, then the getter with `skipBehaviors: true`,
   then close.

The environment captured also held variables inherited from the shell
the recording ran in; only the two the SDK sets are listed above. Ship
checks the recipe and its log into
`docs/design/evidence/CTUI-37/claude-usage-wire/` (the scripts and the log,
relabelled with no machine path), so the decision can point at it.

### 3.3 Options for Claude's reader (Q1)

| | What | Cost | Risk |
| --- | --- | --- | --- |
| A | Speak the protocol from Dart: spawn the verified native `claude` in its own group with the argv and env above, write the two requests, read stdout lines, close stdin | ~150 lines + tests; no new dependency | the getter is experimental: a `claude` that changes the request makes the read `unavailable` (the same exposure the original has, as it also drives PATH `claude` with SDK 0.3.325's messages) |
| B | Run the TypeScript SDK through bun or node as a helper | needs a JS runtime and the npm SDK installed beside the binary; breaks `dart compile exe`'s single file | high: install and version drift |
| C | Report Claude as not read (`unavailable`) | none | loses half the feature |
| D | Call the usage endpoint with the person's credentials | — | rejected: reads credentials, which the original refuses to do |

Recommendation A, pinned: the decision names SDK 0.3.325 as the source
of the wire, and a test asserts the exact argv, env and lines against a
recording fake.

**Bounds and failure words under A (Revised after review).** In the
original the 256 KiB bound is on the whole serialized, normalized result
the worker prints (`resource_worker.ts` 55-76), and the SDK's own reading
of `claude`'s stdout is unbounded inside the worker. With no worker, the
port bounds what it can see: **the accumulated bytes read from `claude`'s
stdout, 256 KiB in total**, counted across every line, `control_response`
or not, so a flood of short lines trips it as one long line does. Each
failure becomes the original's `ProviderLimits` words:

| Under A | Original's source of the words | Answer |
| --- | --- | --- |
| stdout past 256 KiB total | `collectClaudeResources`' bound | `The isolated worker result exceeds its output bound.` (via `ResourceReadError(protocol)`) |
| no `initialize` answer within 8 s, or no `get_usage` answer within 3 s, or the 20 s total | the worker's `deadline` / `TimeoutError` | `The isolated usage read exceeded its deadline.` |
| `subtype: error` answer, a line that is not JSON, stdout ending or `claude` exiting before the `get_usage` answer, a spawn failure after resolution | the worker's catch | `The experimental usage getter is unavailable or unsupported.` |
| `get_usage` answered but not the documented shape | `normalizeClaude` | `Malformed experimental usage snapshot.` / `Subscription limits unavailable: …` |
| group not verified gone after the ladder | `closeResourceGroup` | `Collector cleanup could not verify process-group exit.` (unless the 10 s answer went first), and `close()` reports it |
| 10 s per-provider bound or the caller's cancel | `resources.ts` | `Timed out after 10 s.` / the call cancelled |

The original's `The experimental usage query could not close cleanly.`
(an SDK `close()` that throws) and `The isolated Claude usage worker
failed.` (worker exit not 0) have no source under A and are not produced;
`Invalid isolated collector arguments.` neither, as there is no private
argument to check. Words naming "the isolated worker" are kept as the
original's text though no worker exists (Q1b).

Within A, the original's isolated worker (chord re-run with
`--chord-resource-worker <path>`) exists to keep the SDK's own exit
handlers and stderr away from the terminal; with no SDK in-process, the
port spawns `claude` directly in its own group with stderr drained and
ignored. The private flag is not ported (Q1b); the group cleanup and
bounds are unchanged.

### 3.4 Executable resolution

`resolveResourceExecutable` as the original, with `ExecutableInspection`
injected: custom ACP command → `Custom ACP command has no verified
association …`; not `darwin`/`arm64` (`Platform.operatingSystem`, and
the arch from `Abi.current() == Abi.macosArm64`) → `Resource collector
compatibility is not verified on this platform.`; `which` (process_run's
`whichSync`, already used) then `realpath`; native check on the first
4100 bytes; Claude non-native refused; Codex npm launcher needs `node` on
PATH; `--version` through `withResourceProcess`, 3 s, 4096-byte bound,
`^codex-cli (\S+)$` / `^(\S+) \(Claude Code\)$`.

Native check: `file-type` 22.3.0's rules for `elf` (`7F 45 4C 46`) and
`macho` (`FEEDFACE`, `FEEDFACF`, `CEFAEDFE`, `CFFAEDFE`, and `CAFEBABE`
with a big-endian architecture count 1-30). Tried on pub:
`file_magic_number` 2.1.0 and `file_signature` 1.0.1 depend on Flutter;
`file_type_plus` 1.1.0 and `mime` know neither format. So twelve lines of
our own, with a decision entry. File-type checks other signatures before
these; none of them starts with these bytes, so the outcome on a binary is
the same.

### 3.5 Codex's reader

`[path, 'app-server']` in its own group; newline-delimited JSON:
`initialize {capabilities: null, clientInfo: {name:
'chord-resource-reader', title: 'Chord resource facts', version: '1'}}`
(8 s), the `initialized` notification, `account/read {refreshToken:
false}` (3 s), and when `account.type == 'chatgpt'`
`account/rateLimits/read` (3 s); `normalizeCodex`. The framing is the
port's existing line framing (`lib/acp/wire.dart`); the request layer is
Q2.

### 3.6 Process ownership, bounds and close

`withResourceProcess` as the original: total 20 s, initialize 8 s,
request 3 s; on every exit path `closeResourceGroup`: library close and
stdin end and wait for the group up to 500 ms, then `SIGTERM`, 500 ms,
`SIGKILL`, 500 ms; still alive or no exit seen →
`ResourceReadError(cleanup, 'Collector cleanup could not verify
process-group exit.')`. Error classification: timeout (deadline or a
request timeout anywhere in the cause chain), cancelled, status 401/403,
429, else protocol. `GroupProcess.alive()` and `signal()` exist.

`createResources`: providers read in parallel, `claude`, `codex` by
default, `[]` none, others `No limits reader for this runtime.`; each
bounded by 10 s (`Timed out after 10 s.`), the caller's cancellation
propagating; the answer does not wait for a reader's cleanup, but
`close()` does, looping until no reader runs, and returns the cleanup
failures. Dart has no `AbortSignal`: the port uses the
`cancellation_token` package already in the pubspec (one token per read,
merged with a timer), as CTUI-12 does for ACP requests.

The window calls `close()` after the terminal is restored and writes the
failures to stderr, as `main.tsx`; the forced exit path does too. `chord
acp` runs it as the `resource readers` leave step. A window closing in the
middle of a read thus waits at most the read's own ladder (≤ 21.5 s worst
case, the 20 s total plus the ladder), never forever.

### 3.7 Never a real reader under test

The source is chosen once, by `createResources(collectors:
'official' | 'fixture' | ResourceCollectors)`. The window and `chord acp`
pass `official` unless the private capture flag
(`resourceSourceMode`) says `fixture`. The test catalog
(`test/fixtures/runtimes.dart`) builds hosts with `fixture` or an
injected `ResourceCollectors`; a test asserts that a host built by the
catalog with no collectors given throws before resolving any executable,
and a test of `official` uses an `ExecutableInspection` whose `lookup`
fails the test if called with no fake on `PATH`.

**The dev route (Revised after review).** The original's
`scripts/dev/tools.ts` 80-81 builds chord with
`CHORD_RESOURCE_FIXTURE="true"` defined at build time whenever it runs the
fake (or a capture asks for fixture resources), and `src/main.tsx` 697
reads only that define. The port: the flag is a compile-time
`bool.fromEnvironment('CHORD_RESOURCE_FIXTURE')`, never an environment
variable, so a shipped binary cannot be switched by its environment;
`example/chord/tool/dev.dart`'s `chordArgv` adds
`-DCHORD_RESOURCE_FIXTURE=true` to the `dart run` argv whenever `fake` is
set, or `fixtureResources` is asked. Today `dev.dart` 125-130 always runs
from the repository root with its own fixed `XDG_STATE_HOME` for the
fake; as the original's `chord(fake, args, run, fixtureResources, state)`,
the runner takes `fixtureResources`, `state` (made if missing, else the
fake's default) and a working directory (default the repository root), so
a capture runs in a staged directory with isolated state. Tests in
`test/tool/dev_test.dart`: `--fake` argv carries the define; without it
and without `fixtureResources` it does not; a run with `--fake` and a
`ResourceCollectors` probe that fails on `resolve` reads fixture windows
(the dev/CLI route cannot reach an official collector); `state` and the
working directory reach the child.

## 4. Concurrency and failure scenarios

| Scenario | Expected |
| --- | --- |
| Two `run_team` of one team at once | names `bugfix`, `bugfix 2` (the name is taken synchronously in `startChild`'s `openChild`) |
| A run closed, another started | `bugfix 3`, never `bugfix 2` again in that window, including after `/clear` |
| File edited while a run works | the run keeps its frozen team; the next run reads the new file |
| File deleted or broken during `open_agent` | no effect: members come from the frozen team |
| Two `open_agent tester` from one lead at once | one member; the other `tester is open; send_message reaches it` |
| Lead closes while its `open_agent` waits on capabilities | `You are closed; you open no members`; nothing starts |
| Lead process exits with 3 members open | members closed (concurrently), then main told once |
| Member exits | lead told; run goes on |
| Ninth run | `This session has 8 agents open; close_agent one first`; members never count |
| `/clear` on main while `run_team` starts | launch revoked: `This launch was cancelled; no run started.` or the attempted lead closing |
| Selected run, runtime does not confirm the model | lead refused, attempted lead closed, receipt `refused` with the note, published to main's record |
| Close of a member whose group outlives the ladder | receipt gains the cleanup warning; window close still bounded |
| `propose_team`: rename fails (disk full, permissions) | temporary removed; `<shown> was not saved: <message>`; old file intact |
| `propose_team`: person never answers, caller cancels | `The person was not asked to the end; nothing was saved` |
| Two `propose_team` saves of one name | last rename wins; each answer says where it saved |
| `get_budgets` while another reads | independent reads, each with its own processes |
| Provider floods stdout (Revised after review) | Claude: 256 KiB total of stdout bytes, short lines or one long → `The isolated worker result exceeds its output bound.`; Codex: the framing's line cap |
| Provider ignores SIGTERM | SIGKILL after 500 ms; a group that survives is reported, not waited on beyond the ladder |
| Window quits during a read | answer dropped; `close()` waits the ladder; warnings to stderr |
| Not `darwin-arm64` | each provider `unavailable`, no process started |

## 5. Performance

- **List folding.** Rows are at most 8 leads × 9 + forks + tasks, about
  100. `teamRows` is one pass over children grouped by lead (a map built
  once per frame, not `membersOf` per lead, which would be quadratic but
  still trivial at this size). The fold is pure and tested; a benchmark is
  not needed. The state used to pick the urgent member is already on each
  `ChildInfo`.
- **`/team show <running>`.** Reads the frozen run and each member's
  state and latest headline from the roster: O(members), no file read.
  The non-running form reads the team files once (async).
- **Team files.** Small, read in parallel, parsed on the main isolate:
  a file of a few KiB parses in well under a millisecond. The original
  sets no size bound and the port adds none; the risk of a huge file is
  a slow `/team` answer, not a stuck frame, as the read is async and the
  parse is the only synchronous part. No isolate.
- **Records.** A receipt rewrite is one line rewrite per update (at most
  10 roles + cleanup), through the existing record worker.
- **`get_budgets`.** Up to 10 s per provider, parallel, no spinner of its
  own (CHD-548); nothing on the frame path.

## 6. Test plan

Pure, directly:

- `teams_test.dart`: the original's cases; `bugfix.md` read; saved and
  read back equal and `teamText(teamOf(saved)) == saved`; a write failure
  leaves no temporary; both repository team files load; BOM; CRLF
  frontmatter; empty frontmatter; problems table.
- `team_command_test.dart`, `team_selection_test.dart` (freezing,
  inheritance across runtimes, allowlists, capabilities, receipt bounds,
  `recordedSelection`), `budgets_test.dart`,
  `resource_normalization_test.dart` (the original's inputs, including
  Claude's `+00:00` offset).
- `window_agents_test.dart`: `runName` numbering not reused,
  `messageRecipients` per role, counting, `childEnded` for a lead, fold.

Platform:

- `resource_executable_test.dart` with fake inspections, and one real
  inspection of a temp script and of the Dart executable (native).
- `resource_process_test.dart` on scripted Dart children: late answer after
  cancel not published, stubborn child killed, descendant reaped, cleanup
  failure classified.
- `resource_worker_test.dart`: the original's
  `claude_resource_provider.ts` built with bun (skipped with a reason when
  bun or `../chord` is missing, as the fake agent tests) through all its
  scenarios, plus a Dart scripted fake asserting the exact argv, env and
  lines of section 3.2.
- `codex_resources_test.dart`: the original's `resource_provider.ts`
  through bun (`normal`, `api-account`, `crash`, `timeout`, `stubborn`,
  `term`), and a compile-tagged test from an AOT build.
- `resources_test.dart`: parallel reads, 10 s timeout with a short
  injected bound, `close()` waits, fixture cases.

Host and server:

- Host with scripted sessions and a fake `ChordServer`: every scenario of
  section 4.
- Server over loopback HTTP: `tools/list` per role (main, plain child,
  lead, member, task, fork), schemas and descriptions verbatim, fork
  refusals.
- Through the original's fake agent: `team`, `team2`, `teamlead`,
  `teamtester`, `teamcoder`, `teamtask`, `propose` (and `proposeagain`),
  `selectedteam` with each `CHORD_FAKE_SELECTION_CASE`,
  `budgetawareteam`, `savedteamplain`, with `fixture` resources. No new
  scenario.
- Records on an isolated `XDG_STATE_HOME`: `ran`, receipts, left-open note
  with team items, resume of a selected run.
- `chord acp`: each `/team` form, the receipt refusal, the emitted command
  list `[team, new, …agent's]`, the leave step.
- (**Revised after review**) Records: receipt updates appended after
  `/clear`, during close and after the window closed; resume folds the
  latest; no-prompt refused attempt keeps its record; cleanup warning kept.
- (**Revised after review**) Closing: stubborn member and stubborn lead
  bounded by the longest single close.
- (**Revised after review**) Claude reader: short-line flood and one
  oversize response both trip the 256 KiB total; each failure row of
  section 3.3 answers its words.
- (**Revised after review**) `test/tool/dev_test.dart`: the dev route
  with `--fake` cannot resolve an official collector.

## 7. Proposed units for ship, in order

1. **Team files.** `lib/teams.dart` (read, check, text, save, changes,
   `teamPart`), `team_command.dart`. Tests: section 6's first two bullets.
   Needs Q3's answer for the writer.
2. **Runs in the host.** `window_agents` and `agents_host` team branches,
   `run_team` direct, lead's `open_agent`, `tellTeam`, closing, `toolsOf`
   lead and member, `list_teams`, records (`team`, `ran`, left-open).
   Tests: host scripted scenarios, including the concurrent close bound;
   fake `team`, `team2`, `teamlead`,
   `teamtester`, `teamcoder`, `teamtask`, `savedteamplain`.
3. **`/team` in the window.** picker, `show`, `run`, `stop`, completion,
   list rows and folding, notes (interface's unit; runtime's part is the
   pure fold and the async reads' `(key, launch)` drop).
4. **`propose_team` and the save box.** Fake `propose`; write failure.
5. **`get_budgets` with fixtures, and the dev route** (**Revised after
   review**). `budgets`, normalization, `Resources` with `fixture` and
   injected collectors, the tool, the `Resources` block; the compile-time
   `CHORD_RESOURCE_FIXTURE` and `tool/dev.dart` forcing it with `--fake`,
   with `state` and a working directory for staged captures (section 3.7).
   Tests: pure and `resources_test`; fake `budgetawareteam` with fixture;
   `dev_test` proving the `--fake` route never resolves an official
   collector.
6. **Readers.** process ownership, executable resolution, Codex reader,
   Claude reader with the stdout total bound, the recording evidence.
   Tests: platform tests through the original's fixture providers, the
   flood and oversize tests; compile tag. Needs Q1 and Q2.
7. **Selected runs.** `team_selection`, `runSelectedTeamAt`, the
   `captureServed` API on `Recording` and `Conversation` with appended
   receipt updates and replay folding by runId (**Revised after review**),
   `/team show <run ID>`, `RecordedReceipt`. Fake `selectedteam` cases and
   the record tests of section 2.5.
8. **`chord acp`'s `/team`** and the readers' leave step.

## 8. Questions for the owner

**Q1. Claude's usage reader** (**Revised after review**). Options in
section 3.3. Recommendation: A, speaking SDK 0.3.325's two control
requests to the verified native `claude` from Dart, tested against the
original's fake provider and a recording Dart fake, with the recording
recipe and log kept as evidence (section 3.2). Under A the port bounds
**the accumulated bytes of `claude`'s stdout, 256 KiB in total** (short
lines count as one long line does), where the original bounds the
worker's serialized result; init over 8 s, getter over 3 s or 20 s total
answer `The isolated usage read exceeded its deadline.`; an error
answer, bad JSON, or `claude` ending before the getter's answer answer
`The experimental usage getter is unavailable or unsupported.`; an
oversize stdout answers `The isolated worker result exceeds its output
bound.`; an unverified group exit answers the cleanup words and is
reported at close (table in section 3.3).

Q1b, within A: (i) drop the worker re-exec and spawn `claude` directly in
its own group, keeping the original's words though they name a worker,
and never producing the three worker-only words (`could not close
cleanly`, `worker failed`, `Invalid isolated collector arguments.`)
(recommended); (ii) keep the re-exec shape (`--chord-resource-worker
<path>` on chord's own binary, the bound then on the worker's printed
result as the original) for parity, at the cost of a private CLI flag and
a second process per read.

**Q2. Codex's JSON-RPC without `"jsonrpc"`.** `json_rpc_2`'s `Client`
drops every answer from Codex's app-server. Options: (a) the `Client`
over a channel of ours that adds `"jsonrpc": "2.0"` to what Codex sends
and removes it from what chord sends (about 20 lines in the existing
router layer, CTUI-12's precedent of laying fixes over `json_rpc_2`);
(b) a sequential reader of our own for three requests and one
notification, by id, about 60 lines; (c) Codex unavailable. Recommendation
(a): keeps `json_rpc_2` doing ids, timeouts and stream end. Whether Codex
accepts a request carrying `"jsonrpc"` is unverified, hence stripping it
outbound.

**Q3. Writing team files** (**Revised after review**). Options: (a)
`yaml_edit` 2.2.4, default style: a saved file reads back the same in
both programs and the original's round-trip test holds; multi-line
instructions are saved as one double-quoted line with `\n` and long lines
are not folded, so a saved file looks unlike one the original saves;
(b) our own emitter for the team file's narrow shape, byte-identical to
npm `yaml` 2.9.1's `stringify` on recorded fixtures, about 250 lines.
Recommendation (a), alone. Byte-identical output is the owner's option,
not a failing of the package against the brief's bar.

**Q4a. The YAML parse message** (**Revised after review**). A frontmatter
that is not YAML says `the frontmatter is not valid YAML (<first line of
Dart yaml 3.1.4's message>)`, e.g. `Duplicate mapping key.` where the
original says npm yaml's `Map keys must be unique at line 2, column 1:`.
This is a new difference (CTUI-29 accepted it for JSON settings, not for
team files). Options: accept and log it; or translate the few common
Dart messages into npm yaml's (an incomplete table of our own).
Recommendation: accept and log.

**Q4b. Native-signature check** (**Revised after review**). Our own
check of `file-type` 22.3.0's `elf` and `macho` rules (section 3.4), about
twelve lines, as no package fits. Trials, reproducible: `curl
https://pub.dev/api/search?q=file+type+magic` (and `q=mach-o`, `q=elf
parser`) for candidates; each candidate's archive from
`https://pub.dev/api/archives/<name>-<version>.tar.gz` and its pubspec from
`https://pub.dev/api/packages/<name>`, unpacked and searched for Mach-O and
ELF signatures:

| Package | Version | Mach-O / ELF | Fits `dart compile exe` |
| --- | --- | --- | --- |
| `file_magic_number` | 2.1.0 | ELF only | no: depends on `flutter` |
| `file_signature` | 1.0.1 | both (as a blocklist) | no: depends on `flutter` |
| `file_type_plus` | 1.1.0 | neither | yes |
| `mime` | 2.x (in the pubspec) | neither | yes |

Recommendation: our own check, logged in `docs/decisions.md`.

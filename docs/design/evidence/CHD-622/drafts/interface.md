# CHD-622 — interface draft: `cursor cloud` on chord's screen

The interface architect's answers to I1–I4 of the brief. The finding up
front: chord needs no new screen, state, component or key for this agent.
Everything below is drawn by what chord already has: the agent list
(`src/agents.ts`), the start picker and `/new` (`src/ui/pickers/`,
`src/ui/prompt/commands.ts`), CHD-435's sign-in block (`SignIn.tsx`),
CHD-454's start-failure block (`StartFailure.tsx`), the transcript's agent
message and tool rows, the status line's mode words and `/resume`. Two
small things in chord are wrong or missing for an agent that is not from
the ACP Registry and does not run on this machine, and those are named in
I4 as questions with a recommendation.

Today's screens were read from `bun dev chord --qa chd622-start` (the start
picker, no agent started), `bun dev chord --fake --qa chd622-turn`
(`greet`, `rawoutputs`) and `--qa chd622-res` (`/resume`), at 120×40 and
80×24. No live agent was started and no prompt reached one.

Colour roles named beside the mocks are those of `src/ui/theme/theme.ts`
and `src/ui/theme/text.ts`: `text` (the terminal's own foreground), `DIM`,
`BOLD`, `error`, `plan`, `link`, `accent` (the picker's `❯`), and `agents`
(the agents list's per-agent tones).

The adapter's words in the mocks (the first message, refusals, `request`
text, sign-in method) are placeholders: their wording is protocol's (P2,
P4). Where the screen needs something of those words, it is a `CROSS:` item.

## I1. How `cursor cloud` appears

### The command-line name

`KnownAgent.name` is one thing used as: the `chord <name>` argument, the
settings key `agents.<name>`, the `agent` and `offeredAgents` settings, the
record's agent (so `chord <name> --resume <id>` as chord prints on quit),
`/new <name>`, team files' runtime, `open_agent`'s agent, the header, the
agents list and `chord agents`/`--json`. `title` is the words for people
beside it.

Options:

- **(a) name `cursor-cloud`, title `Cursor Cloud Agents`.** One argv word;
  matches the registry's own form for multi-word ids (`github-copilot-cli`,
  `factory-droid`, `codebuddy-code`); `chord agents` piped stays one
  whitespace-split field for awk, which its doc comment promises; `/new
  cursor-cloud` completes as any other. The words "Cursor" and "Cloud" stand
  in the title, which is how the person reads the row.
- **(b) name `cursor cloud`, with the space.** `agentNameProblem` allows it,
  but every typed use needs quoting: `chord 'cursor cloud'`, chord's own
  quit line `Resume this session with: chord cursor cloud --resume <id>`
  would be wrong unquoted, `chord agents` piped breaks its columns, and
  `/new cursor cloud` would have to read two words as one name.
- **(c) name `cursor-cloud`, title `cursor cloud`.** As (a) but the title
  repeats the name; a title that is the name in other spelling says
  nothing (`agentChoices` already drops a title equal to the name).

**Choice: (a).** **OWNER:** the owner's decision 10 says "named `cursor
cloud` in chord". (a) reads that as the agent's words on screen, with
`cursor-cloud` as what is typed. If the owner meant the literal argv name,
(b) is possible but costs the quoting above in chord's own printed
commands. Recommendation: (a).

### Where the row sits

The catalog is riff, the registry's agents in id order, then the own-CLI
table (`src/agents.ts`, `AGENTS`). The new entry is neither registry nor
own CLI: runtime's R4 decides the table it lives in.

**Choice:** its row goes among the npx agents in name order. Sorted by
name, `cursor-cloud` falls right after `codex` (`claude`, `cline`,
`codebuddy-code`, `codex`, `cursor-cloud`, `deepagents`, …), which is
"beside claude and codex" with no special place and no rule of its own.
`/new`'s ranking (`readiness`) puts it with the npx agents (rank 3), so
`/new cu` lists the own `cursor` CLI first when PATH has `agent`, then
`cursor-cloud`. **CROSS (runtime, R4):** whichever table holds the entry,
`AGENTS` should merge it into the npx run by name rather than append it
after the registry's.

### Beside the existing `cursor`

`cursor · Cursor` (own CLI, local agent, shown only when PATH has `agent`)
and `cursor-cloud · Cursor Cloud Agents` (npx). The title tells them apart;
the existing `cursor` entry is left unchanged. **OWNER (minor):** retitle
`cursor` to `Cursor · local`? Recommendation: no — its title is Cursor's
product name, and "Cloud Agents" on the new row is enough.

### Everywhere it is shown

| Place | What it shows | Source |
| --- | --- | --- |
| start picker | `cursor-cloud · Cursor Cloud Agents` (title `DIM`) | `agentChoices` |
| `/new` completion | `cursor-cloud        Cursor Cloud Agents` | `agentItems`, `agentNote` |
| `chord agents` | `cursor-cloud  Cursor Cloud Agents  npx  npx -y @chorded/cursor-cloud-acp@0.1.0` | `agentTable` |
| `chord agents --json` | `{"name":"cursor-cloud","title":"Cursor Cloud Agents","via":"npx","found":null,…}` | `agentsJson` |
| header | `cursor-cloud · <model>` on line 2 | `header.ts` |
| status line (right) | `<model> · <effort if any> · N% context used` | `status.ts` |
| agents list | `main  cursor-cloud · <model>  ◦ idle 4s` | unchanged |
| settings | `"agents": { "cursor-cloud": { … } }` | unchanged |

`via: "npx"` is true: chord starts it with npx and the package is
downloaded, which `--json`'s doc says a client may confirm. No new `via`
value; `chord agents`' `from` column reads `npx` as for the registry's.

## I2. The screens

All mocks are the whole window. Dates, ids, the repository and the model
are made up. Line 2 of the header is `<agent> · <model>`; the model there is
whatever the adapter reports.

### Start: the picker, 120×40

```
                                ▀▀▄
                                ▀▀▀▀▄        ██████╗ ██╗  ██╗  ██████╗  ██████╗  ██████╗
                                ▀▀▀▀▀▀▄     ██╔════╝ ██║  ██║ ██╔═══██╗ ██╔══██╗ ██╔══██╗
                                 ▀▀▀▀▀▀▀▄   ██║      ███████║ ██║   ██║ ██████╔╝ ██║  ██║
                                 ▄▀▀▀▀▀▀▀   ██║      ██╔══██║ ██║   ██║ ██╔══██╗ ██║  ██║
                                ▀▀▀▀▀▀▀     ╚██████╗ ██║  ██║ ╚██████╔╝ ██║  ██║ ██████╔╝
                                ▀▀▀▀▀        ╚═════╝ ╚═╝  ╚═╝  ╚═════╝  ╚═╝  ╚═╝ ╚═════╝
                                ▀▀▀

                                          One terminal for every coding agent.
                                          v0.70.0 · ~/src/acme-web

                              Select agent

                                  1.  riff · chord's own agent · on a ChatGPT or Grok plan
                                  2.  agoragentic-acp · Agoragentic
                                  3.  auggie · Auggie CLI
                                  4.  autohand · Autohand Code
                                  5.  bob · Bob
                                  6.  claude · Claude Agent
                                  7.  cline · Cline
                                  8.  codebuddy-code · Codebuddy Code
                                  9.  codex · Codex
                              ❯   10. cursor-cloud · Cursor Cloud Agents
                                  11. deepagents · DeepAgents
                                  12. dimcode · DimCode
                                  13. dirac · Dirac
                                ↓ 14. factory-droid · Factory Droid
                                  … +16 more

                              ↑↓ or j/k to move · Enter or 1–9 to select · Esc to cancel
```

Roles: mark and wordmark in the mark gradient; tagline `text`; version line
`DIM`; `❯` and the highlighted row `accent`; titles after ` · ` `DIM`.
Unchanged from today but for one more row; the own `cursor` row is at the
list's end as now.

### Start: the picker, 80×24

```
                            ▀▄
                            ▀▀▀▄  █▀▀ █ █ █▀█ █▀█ █▀▄
                            ▄▀▀▀  █▄▄ █▀█ █▄█ █▀▄ █▄▀
                            ▀▀
                      v0.70.0 · ~/src/acme-web

          Select agent

              3.  auggie · Auggie CLI
              4.  autohand · Autohand Code
              5.  bob · Bob
              6.  claude · Claude Agent
              7.  cline · Cline
              8.  codebuddy-code · Codebuddy Code
              9.  codex · Codex
          ❯   10. cursor-cloud · Cursor Cloud Agents
              11. deepagents · DeepAgents
              12. dimcode · DimCode
              13. dirac · Dirac
            ↓ 14. factory-droid · Factory Droid
              … +16 more

          ↑↓ or j/k to move · Enter or 1–9 to select · Esc to cancel
```

### Not signed in (CHD-435's block), 120×40

The adapter answers `authRequired` (-32000) to `session/new` with its own
message, and its `initialize` sent one `authMethods` entry. chord draws
CHD-435's block as it is; the first line under `⎿` is CHD-454's pin line,
which is wrong for this agent today (I4, item 1; drawn here with the
recommended words).

```
 ▀▄     chord v0.70.0
 ▀▀▀▄   cursor-cloud
 ▄▀▀▀   ~/src/acme-web
 ▀▀     ? for shortcuts · /help

 ⏺ cursor-cloud did not start: Not signed in to Cursor.
   ⎿  chord ran @chorded/cursor-cloud-acp@0.1.0, the version this chord pins.
      cursor-cloud offers this sign-in:
        Cursor login · Run `npx -y @chorded/cursor-cloud-acp@0.1.0 login` in a terminal, or set CURSOR_API_KEY
      chord does not sign agents in. Sign in with cursor-cloud's own CLI in a terminal, or set its API key where it offers
      one.
































╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Roles: `⏺` and the headline `error`; `⎿` `DIM`; the block `text`; the
method name `Cursor login` `BOLD`; backticks drawn as they are, through
`Ansi`. CHD-435's fixed line fits this agent as written: the package is its
own CLI, `CURSOR_API_KEY` its API key.

**CROSS (protocol, P1/P4):** the method's `description` should name the
exact pinned version the adapter is (`@chorded/cursor-cloud-acp@<its own
version>`), not the bare package: bare `npx @chorded/cursor-cloud-acp login`
runs npm's latest, which may be a different adapter than the one chord
pins. The adapter knows its own version, so no chord code is needed.

### Not signed in, 80×24

```
 ▀▄     chord v0.70.0
 ▀▀▀▄   cursor-cloud
 ▄▀▀▀   ~/src/acme-web
 ▀▀     ? for shortcuts · /help

 ⏺ cursor-cloud did not start: Not signed in to Cursor.
   ⎿  chord ran @chorded/cursor-cloud-acp@0.1.0, the version this chord pins.
      cursor-cloud offers this sign-in:
        Cursor login · Run `npx -y @chorded/cursor-cloud-acp@0.1.0 login` in a
        terminal, or set CURSOR_API_KEY
      chord does not sign agents in. Sign in with cursor-cloud's own CLI in a
      terminal, or set its API key where it offers one.









╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Nothing is cut: the block is 6 rows, the window keeps 9 empty.

### Refused start: branch not pushed, 120×40

Not `authRequired`, so no sign-in block: today's failure row, then CHD-454's
block (pin line, and the stderr tail only if the adapter wrote one). The
headline wraps `stepWords`' `it refused session/new: <message>` around the
adapter's message.

```
 ▀▄     chord v0.70.0
 ▀▀▀▄   cursor-cloud
 ▄▀▀▀   ~/src/acme-web
 ▀▀     ? for shortcuts · /help

 ⏺ cursor-cloud did not start: it refused session/new: Branch login-page is not on origin
   (github.com/acme/web). A cloud agent starts from a pushed branch: run git push -u origin login-page, then start
   again.
   ⎿  chord ran @chorded/cursor-cloud-acp@0.1.0, the version this chord pins.
```

The same row for no remote (`… refused session/new: ~/src/acme-web has no
git remote. A cloud agent works on a repository Cursor can clone: add a
remote and push.`) and for a cwd that is not a git repository. At 80×24 the
headline takes four rows, the pin line two; the prompt stays.

**CROSS (protocol, P4):** the refusal's message carries the way on itself
(the command to push, or what is missing): chord adds no way on for this
agent (`wayOnFor` keeps zeroclaw alone). **CROSS (protocol):** the code —
`-32602` invalid params would read the same through `stepWords`; avoid
`-32601`, which `stepWords` turns into "it does not serve ACP sessions".

### Refused start: Node too old, 80×24

The adapter exits before `initialize` (runtime's R6). chord's existing
row: `it exited with code 1 before answering initialize.`, then the stderr
tail, which is where the adapter's own refusal shows.

```
 ⏺ cursor-cloud did not start: it exited with code 1 before answering
   initialize.
   ⎿  chord ran @chorded/cursor-cloud-acp@0.1.0, the version this chord pins.
      The end of its stderr:
        @chorded/cursor-cloud-acp needs Node 22.13 or newer; this is Node
        20.11.1. Install a newer Node: https://nodejs.org/en/download
```

**CROSS (runtime, R6):** that refusal goes to stderr as one or two lines
(the tail shows the last lines only) and nothing to stdout.

### Session open: the first message, 120×40

The adapter's first message names the repository, the branch and the
agent's link (decision 5). It is an ordinary agent message, drawn as one.

```
 ▀▄     chord v0.70.0
 ▀▀▀▄   cursor-cloud · Composer 2
 ▄▀▀▀   ~/src/acme-web
 ▀▀     ? for shortcuts · /help

 ⏺ Cursor cloud agent on github.com/acme/web, starting from branch login-page (3f2a9c1, pushed). It runs in Cursor's VM,
   not on this machine, and pushes its work to a branch of its own.
   https://cursor.com/agents?id=bc-5e1f0a7c-2d4b-4e8a-9c1f-7b2e6d3a9f10































╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                          Composer 2
```

Roles: `⏺` and text `text`; the URL `link` where markdown marks it (a bare
URL as plain text if not). The terminal's own URL detection makes it
clickable; chord adds no key for it.

**CROSS (protocol, P1/P2):** when the first message arrives decides
whether it does its job. The person should read "this is remote" before
the first prompt, not after it. Options: (a) as `agent_message_chunk`s
right after `session/new` answers, before any prompt — it needs the cloud
agent's id, so the agent is created at `session/new`, or the message gives
repository and branch then and the link with the first prompt's turn;
(b) as the first chunks of the first prompt's turn. Interface
recommends (a). **CROSS (runtime, R7):** chord's handling of agent
messages that arrive between `session/new` and the first prompt (no turn,
no cycle mark) is not pinned by a test today; a test that such a message
draws as `⏺` text and does not start `Working…` belongs to this task.

### Session open, 80×24

```
 ▀▄     chord v0.70.0
 ▀▀▀▄   cursor-cloud · Composer 2
 ▄▀▀▀   ~/src/acme-web
 ▀▀     ? for shortcuts · /help

 ⏺ Cursor cloud agent on github.com/acme/web, starting from branch login-page
   (3f2a9c1, pushed). It runs in Cursor's VM, not on this machine, and pushes
   its work to a branch of its own.
   https://cursor.com/agents?id=bc-5e1f0a7c-2d4b-4e8a-9c1f-7b2e6d3a9f10











╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                   Composer 2
```

A link longer than the row breaks at `/`, `-`, `.` as rows do today; a
break inside the URL defeats a terminal's click. **CROSS (protocol):** keep
the link on a line of its own and as short as the SDK gives it.

### A streaming turn with tool calls of unknown shape, 120×40

What chord draws depends only on what the adapter sends: a `title`, a
`kind`, `rawInput`, and content or `rawOutput`. Three shapes, all drawn by
today's tool rows (as `rawoutputs` showed):

1. A call the adapter maps to an ACP kind with a short title
   (`Read src/routes.ts`, `kind: read`) → `⏺ Read(src/routes.ts)`.
2. A call it does not know, sent as `kind: other`, the SDK's tool name as
   title, `args` as `rawInput`, `result` as `rawOutput` → `⏺ <name>` and the
   result as JSON under `⎿`, cut to chord's usual rows with ctrl+o for all.
3. A call with no result yet → the row alone, its `⏺` blinking as running.

```
 ▀▄     chord v0.70.0
 ▀▀▀▄   cursor-cloud · Composer 2
 ▄▀▀▀   ~/src/acme-web
 ▀▀     ? for shortcuts · /help

 ⏺ Cursor cloud agent on github.com/acme/web, starting from branch login-page (3f2a9c1, pushed). It runs in Cursor's VM,
   not on this machine, and pushes its work to a branch of its own.
   https://cursor.com/agents?id=bc-5e1f0a7c-2d4b-4e8a-9c1f-7b2e6d3a9f10

 › add a login page with email and password, tests included

 ✻ Looking at how routes are laid out and where forms live…

 ⏺ Read(src/routes.ts)
   ⎿  Read 84 lines

 ⏺ codebase_search
   ⎿  {
        "query": "form validation",
        "results": [
          "src/forms/validate.ts",
          "src/forms/Field.tsx"
        ]
      }

 ⏺ Edit(src/pages/Login.tsx)
   ⎿  Added 62 lines

 ⏺ run_terminal_cmd
   ⎿  … +38 lines (ctrl+o to expand)
      Tests  41 passed (41)
      Time   6.2s

 ⏺ The login page is in src/pages/Login.tsx with its route in src/routes.ts; its tests pass in the cloud VM.

 ⏺ edit_file

 ››› Working… (2m 14s · esc to interrupt)

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                    Composer 2 · 12% context used
```

Roles: `›` prompt rows `DIM` marker and `text`; thinking `✻` and its text
`DIM`; tool `⏺` by status as today (running blinks, done `success`, failed
`error`); names `BOLD`; results `text`; `… +38 lines (ctrl+o to expand)`
`DIM`; the working line `accent` spinner and `DIM` words.

No guessing in chord: chord already draws an unknown call as its title and
its raw result; nothing here asks chord to read Cursor's shapes.
**CROSS (protocol, P2):** a title that is the SDK's tool name
(`codebase_search`) reads as code; mapping the few stable, documented names
to ACP kinds and short titles is protocol's call, and every unknown one
must still get a non-empty title, or chord's row has nothing to show.

**CROSS (protocol, P2):** SDK `status` events. chord has no slot for an
agent's free-text status (the working line is chord's own). Each one sent
as a message would fill the transcript with `CREATING`/`RUNNING` rows.
Interface recommends: none shown while the run goes, the working line
covers it; only a status that ends the run abnormally (error, expired)
reaches the transcript, as the turn's `stopReason` or a short message.

### A streaming turn, 80×24

```
 ⏺ Read(src/routes.ts)
   ⎿  Read 84 lines

 ⏺ codebase_search
   ⎿  {
        "query": "form validation",
        "results": [
          "src/forms/validate.ts",
      … +3 lines (ctrl+o to expand)

 ⏺ Edit(src/pages/Login.tsx)
   ⎿  Added 62 lines

 ⏺ edit_file

 ››› Working… (2m 14s · esc to interrupt)

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                Composer 2 · 12% context used
```

The header and the first message have scrolled away, as any transcript's
do; `home` brings them back.

### A `request` event as text, 120×40

Decision 6: shown as text, never answered by guessing. It is an agent
message like any other, so it is drawn as one; the turn goes on or ends as
the adapter says.

```
 ⏺ Edit(src/pages/Login.tsx)
   ⎿  Added 62 lines

 ⏺ Cursor's agent is waiting for input: "Should the login form also offer sign-in with a magic link, or only email and
   password?" chord cannot answer this from here; send your answer as your next prompt.

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                    Composer 2 · 12% context used
```

At 80×24 the message wraps to four rows under `⏺`.

Not a permission prompt, not a dialog, no key: decision 6 rules out an
answer from chord, so nothing on screen waits on a key of chord's.
**CROSS (protocol, P2):** what the text says about the way on must be true.
"Send your answer as your next prompt" is only right if the turn ends at
the `request` (`end_turn`) and the next `agent.send()` reaches the waiting
agent; if the run keeps waiting with the turn open, the person sees
`Working…` forever. Interface recommends: the adapter ends the turn at a
`request` with the text above; protocol confirms against the SDK types.
If the SDK cannot deliver an answer, the text must say so instead and
point to the agent's link.

### Cancel, 120×40

Esc while a turn runs: chord's `chat:cancel`, ACP `session/cancel`, the
adapter's `run.cancel()`. Today's outcome row, no change:

```
 › add a login page with email and password, tests included

 ⏺ Read(src/routes.ts)
   ⎿  Read 84 lines

 ⏺ codebase_search
   ⎿  Interrupted by user

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                    Composer 2 · 12% context used
```

`Interrupted by user` in `error`, as today. **CROSS (runtime, R6):** chord
draws the outcome when the turn answers `cancelled`; if `run.cancel()` is
slow, `Working…` stays until it does, as with any agent. Whatever the cloud
agent already pushed to its branch stays pushed; that is not chord's to
say, and if it is to be said the adapter says it.

### `/resume` with cloud sessions, 120×40

`/resume` and `chord --resume` read chord's own records
(`~/.local/state/chord/records/`), not the agent's `session/list`: chord as
a client never calls `session/list` today. So the list holds the
`cursor-cloud` sessions a prompt was sent in from chord, in this
directory (ctrl+a for all), drawn as any agent's:

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Resume a session                                                                                                     │
│ cursor-cloud's earlier sessions in this directory.                                                                   │
│                                                                                                                      │
│ ❯ 1. 2h ago     add a login page with email and password, tests included                                             │
│   2. yesterday  fix the flaky checkout test                                                                          │
│                                                                                                                      │
│ Enter to resume · Ctrl+a for all directories · Esc to close                                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                          Composer 2
```

At 80×24 the frame is 78 wide and the prompts cut with `…` as today.

A cloud agent started elsewhere (cursor.com, another machine) is not in
this list. It opens by id: `chord cursor-cloud --resume bc-…` reopens it if
the adapter serves `session/load` or `session/resume`, its past as the
adapter replays it — chord's existing path for a session it never saw
(docs/guide.md: "`--resume <id>` also opens a session chord never saw").

**OWNER:** should `/resume` also list sessions the agent's `session/list`
offers? Options: (a) no — by id only, as above, in this task; (b) yes, for
every agent that offers `session/list`: a chord-wide change to `/resume`
(merge the agent's list with chord's records, mark ones chord has no record
of), its own design. Recommendation: (a). (b) changes `/resume` for claude
and codex too, which is not this task.

### A run that ended remotely

Two cases, both drawn by what exists:

1. **While chord is open, between turns** (the cloud agent finished after
   the turn ended, or the person ended the turn and the run went on): if
   the adapter sends updates with no turn running, chord draws them as it
   draws an agent's own work today, with no cycle mark as plain rows; with a
   cycle mark (CHD-426) as `Working…` until the mark ends it. **CROSS
   (protocol/runtime):** whether the adapter keeps a run's stream after the
   turn ends; interface recommends one turn = one run, so nothing arrives
   between turns.
2. **While chord was closed, then resumed:** the header says
   `resumed · 3h ago · <title>`, the past replays from chord's record and
   the adapter's replay, and the adapter's message on load says how the run
   ended:

```
 ▀▄     chord v0.70.0
 ▀▀▀▄   cursor-cloud · Composer 2
 ▄▀▀▀   ~/src/acme-web
 ▀▀     resumed · 3h ago · Add login page
        ? for shortcuts · /help

 › add a login page with email and password, tests included

 ⏺ Read(src/routes.ts)
   ⎿  Read 84 lines

 ⏺ The login page is in src/pages/Login.tsx with its route in src/routes.ts; its tests pass in the cloud VM.

 ⏺ This cloud agent finished 2h 51m ago. Its work is on branch cursor/login-page-5e1f, pushed to github.com/acme/web.
   https://cursor.com/agents?id=bc-5e1f0a7c-2d4b-4e8a-9c1f-7b2e6d3a9f10
```

**CROSS (protocol, P1/P4):** that closing message is the adapter's, sent
on `session/load`/`session/resume` after the replay; chord adds nothing.

### What chord prints on quit

Unchanged: `Resume this session with: chord cursor-cloud --resume bc-…`.
**CROSS (runtime, R6):** if a run keeps going in Cursor's VM after chord
quits (or after `session/cancel` fails), chord's quit line says nothing of
it. Whether the person must be told is runtime's R6; if yes, interface
recommends the adapter's first message say it once ("It keeps running if
chord closes"), rather than a chord line for this agent.

## I3. Keys

**No new action, so no new key.** Every action on the screens above is one
chord has:

| Action | Key | Rebindable | Shortcuts panel |
| --- | --- | --- | --- |
| pick the agent | ↑↓/j/k, Enter, 1–9 | no (picker keys) | unchanged |
| cancel the run | Esc | yes, `chat:cancel` | unchanged |
| cycle `agent`/`plan` | shift+tab | yes, `chat:cycleMode` | unchanged |
| choose a model | `/model` | — (command) | unchanged |
| expand a tool result | ctrl+o | yes, `app:toggleTranscript` | unchanged |
| resume | `/resume`, ctrl+a for scope | as today | unchanged |
| open the link | the terminal's own click | — | — |

Opening the cursor.com link is the terminal's, as every link in a reply
is; chord has no "open link" action today and this task is no reason to
add one. A `request` has no key by decision 6. Sign-in happens outside
chord (CHD-435's "Keys": nothing to bind).

**CROSS (protocol, P3):** the status line names a mode by its id:
`MODES` has words for `plan` (`⏸ plan mode on`, `plan` tone) and
`QUIET_MODES` hides `default`. If the adapter's modes are `agent` and
`plan`, the default reads `⏵⏵ agent mode on` all the time. Interface
recommends ids `default` (name `Agent`) and `plan` (name `Plan`), so chord's
existing words apply with no chord change. shift+tab then shows:

```
  ⏸ plan mode on (shift+tab to cycle)                                                Composer 2 · 12% context used
```

## I4. Changes in chord beyond the agent-list entry

The owner's "no change in chord" holds for the first message, the
`request` text, tool calls, cancel and resume. Two things are not right
today and are generic, not for this agent by name.

1. **The pin line says "the ACP Registry".** `pinLine` in
   `src/session/start_failure.ts` prints `chord ran <pkg>@<v>, the version
   the ACP Registry names.` above every start failure and sign-in block of
   an agent with `pinned`. If runtime's entry sets `pinned` (it should: the
   version is what a person reports), the line is false for
   `@chorded/cursor-cloud-acp`, which is not in the registry. Options:
   (a) the line takes where the pin comes from: `the version the ACP
   Registry names` for the registry's, `the version this chord pins` for
   chord's own table; (b) the entry leaves `pinned` unset, and failures
   show no version; (c) one word for both: `the version this chord pins`.
   **OWNER:** recommendation (a): pure logic in `start_failure.ts` and its
   test, `KnownAgent` gains the source (runtime's R4 decides the field),
   `-p`'s and `open_agent`'s plain lines follow as `failureLines` already
   shares `pinLine`.
2. **chord's MCP servers.** chord gives every session its own MCP server
   (and the person's), which run on this machine; a cloud agent in Cursor's
   VM cannot reach a local stdio or loopback server. Not an interface change
   if handled at the entry, but the screen differs: team tools, `@@`
   messages and `open_agent` from a `cursor-cloud` session cannot work.
   **CROSS (protocol/runtime):** options: (a) the entry sets
   `mcpServers: false` as `openclaw`'s does (CHD-441), and the agent gets
   none; (b) the adapter takes them and ignores them, so chord believes its
   tools are there; (c) the adapter forwards them to the SDK. Interface
   recommends (a): what chord shows then matches what works.

Not proposed, listed so the owner can say otherwise:

- **A remote marker** (`☁` or `remote` in the header line 2 or the status
  line). **OWNER:** decision 5 chose the first message instead, "to be
  tried". Recommendation: none now; if the try shows the message scrolls
  away too soon, a marker driven by a generic signal from the agent (an
  `agentInfo` or `_meta` field, never the agent's name) is the follow-up,
  with its own design.
- **A `request` drawn differently** (warning tone, a `?` gutter):
  recommendation no; it is the agent's message and decision 6 says text.

## State, logic and components

- **No new state slice.** The start picker and `/new` read `ListedAgent`s
  (`pickers/state.ts`, `prompt/commands.ts`); the sign-in and failure blocks
  read `state.connection` (`app/state.ts`: `signIn`, `failure`); the
  transcript's entries, the status line's mode and model, and `/resume`'s
  records are unchanged.
- **Pure logic:** the catalog order (`src/agents.ts`, runtime's R4), and
  `pinLine`'s source if I4.1(a) is taken (`src/session/start_failure.ts`).
  Both have tests at their mirrored paths (`tests/agents_test.ts`,
  `tests/session/start_failure_test.ts`).
- **Components:** none new. `AgentPicker` (`pickers/Pickers.tsx`),
  `SignInBlock` (`app/SignIn.tsx`), `StartFailureBlock`
  (`app/StartFailure.tsx`), `Failure`, `Reply` and the tool rows
  (`transcript/`) on OpenTUI's `box`/`text`/`span`, as today.
- **Tests for the screen:** through `tests/ui/harness.tsx`, the picker
  lists `cursor-cloud · Cursor Cloud Agents` after `codex`; a fake agent
  answering `authRequired` with this package's `authMethods` draws the
  block with the pinned command; an agent message before the first prompt
  draws as `⏺` text and starts no `Working…` (I2's CROSS to runtime).
  Checked by hand in tmux at 120×40 and 80×24 with `--fake --qa` and an
  `--agent-command` running the adapter on its fake SDK (runtime's R4/R7).

## Summary of flags

- **OWNER:** I1 name `cursor-cloud` with title `Cursor Cloud Agents` vs the
  literal `cursor cloud` (recommend the former); I1 retitle `cursor`
  (recommend no); I2 `/resume` from `session/list` (recommend no, by id);
  I4.1 pin line's source (recommend (a)); I4 remote marker (recommend
  none now).
- **CROSS protocol:** sign-in description names the pinned version; refusal
  messages carry their way on and avoid -32601; first message before the
  first prompt; link on its own line; non-empty titles for unknown tools;
  `status` events not as rows; `request` ends the turn with true words;
  closing message on load; mode ids `default`/`plan`; MCP servers.
- **CROSS runtime:** the entry merged into the npx run by name; Node
  refusal on stderr; a test for a message before the first prompt; what
  the person is told of a run that outlives chord; MCP servers at the entry.

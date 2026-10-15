# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) and any other agent
working in this repository. It is binding.

## What this is

chord is a full-screen terminal client for coding agents that speak the Agent
Client Protocol. `README.md` is the pitch, `docs/guide.md` the whole of what it
does, `docs/FEATURES.md` is the map of what gets built and in which order,
`docs/decisions.md` is why the stack is what it is. Read the README,
`FEATURES.md` and `decisions.md` before the first change.

The repository is public-ready from the first commit: everything in it — code,
comments, docs, commit messages, test names — is in English, and nothing in it
names a private path, a key, or a person's machine. `tests/privacy_test.ts`
fails `bun run check` on any file git tracks that names a home directory,
the name of the home of whoever runs it, or a path in Claude Code's own
directory there other than its public settings files.

## The one rule

**Take a library before writing one.** Below the interface, chord's own ACP
layer (`src/acp/` and `src/session/`) on `@agentclientprotocol/sdk` is the ACP
client; on screen, OpenTUI (`@opentui/core` and its React bindings,
`@opentui/react`) and its components are the widgets.
Before writing a component, a parser, a renderer or a protocol helper, look for
a maintained one that runs under Bun and survives `bun build --compile`, try it, and
say in the handover what you tried. Writing our own is the answer only when the
library is shown not to fit, and that finding goes into `docs/decisions.md`.

When a library does not do directly what the task asks, do not write a
workaround around it on your own call: no rewriting its input, no guessing at
ambiguous input, no patching its behaviour. Stop and hand the owner the
question with the options, including changing what the task asks so the
library fits as it is. A trial recorded in `docs/decisions.md` is not the
owner's consent.

## Commands

```sh
bun install                 # the dependencies, as bun.lock pins them
bun run chord [agent]       # run from source
bun run chord:fake          # run from source against the fake agent in tests/fixtures/
bun run check               # types, lint, fmt, tests — passes before every commit
bun run check:static        # tsc, ESLint, Prettier and lint/'s own test; check runs it too
bun run test                # tests only
bun test ./tests/shell_test.ts -t 'a stop'   # one file, the tests whose names match
bun run lint --fix          # what ESLint can fix, then bun run fmt lays it out
```

The binary is built by `bun build --compile`, Bun 1.4.2 or newer. The
installer is `compile --install`, not a script named `install`, which
`bun install` would run as the package's own install step:

```sh
bun run compile             # this machine's binary into dist/<target>/chord
bun run compile --all       # every release target
bun run compile --install   # this machine's binary into ~/.local/bin/chord
bun run npm                 # lay out npm/ from dist/
scripts/release.sh --dry-run  # the owner's release, short of publishing
bun run registry            # refetch the ACP Registry into src/registry.ts
bun run mark                # rasterise scripts/mark.svg into src/ui/header/mark.ts
bun run screenshots         # retake docs/images/ from chord on the fake agent
```

## Layout

Folder by folder, as the tree is. `tests/` mirrors `src/`, so where a
module's tests are follows from where it is.

- `src/` — the command line and what the window and `-p` share outside the
  sessions:
  - `cli.ts` — chord's Cliffy flags, apart from what is done with them, so
    a test parses argv through the declarations chord runs on.
  - `main.tsx` — runs the command line; with `--resume` and no id, draws
    the start picker first (`ui/app/Start.tsx`) on the renderer the window
    then takes over, and quits on its Esc; finds the session `--continue`
    names or the sessions `--resume` does, a window's by its record, reads the settings files and
    the MCP servers for each directory they work in, starts chord's MCP
    server for the
    window, renders the app full-screen, and on quit stops the server and,
    with two or more sessions a prompt went to, saves the window's record
    (the one it was opened from, again) and prints the one command that
    resumes it, or else the command that resumes the one session; with
    `-p`, reads piped stdin and hands over to `headless.ts` instead.
  - `headless.ts` — `chord -p`: the prompt with piped input joined to it,
    the reply as stdout carries it, the `--output-format json` object, the
    stderr lines for a refused effort or mode, each permission refused or allowed
    and each question of a form skipped, and the exit code; no OpenTUI.
  - `agents.ts` — the agents chord starts by name: `registry.ts`'s,
    `claude` and `codex` for the registry's `claude-acp` and `codex-acp`,
    each started as `npx -y <package>@<version> <args…>` or
    `uvx <package>@<version> <args…>` with its entry's env, then `clis.ts`'s
    by their own argv, a name in both the registry's; or the command that
    overrides the name; and the line chord refuses an agent with, before the
    window and `-p`, when the command it runs is not on PATH (@david/which);
    and `chord agents`' list: every one of them on the settings files'
    command where they give one, each own CLI marked by whether PATH has it,
    then the names only the settings files define, in columns
    (@cliffy/table), the start wrapped within its column on a terminal
    (wrap-ansi); and how `/new` describes an agent, the same marks.
  - `registry.ts` — generated by `bun run registry`, never edited: the
    ACP Registry's agents that npx or uvx starts, each at the exact version
    fetched with its website and repository, and the date it was fetched.
  - `clis.ts` — written by hand: the agents started by a CLI the person
    installs themselves, each with the argv its docs give for ACP and where
    they say to install it.
  - `settings.ts` — the user's and the project's settings files: where
    they are, each read and checked by zod, merged with the project's on
    top, and weighed against the flags into what chord starts with, and
    what a session of any other agent `/new` opens starts with, from the
    files alone, and each agent's command they give; the
    problems found, which `main.tsx` prints on stderr before the window and
    hands the window as warnings; paths as the window shows them, from the
    working directory or `~`, or from `~` alone; `theme`, `editorMode` and
    `mouse`, read only from the user's file, the first two of which
    `saveTheme` and `saveEditorMode` write back atomically with its other
    keys kept — the only writes chord makes to a settings file; and the
    keybindings file beside the user's settings file, read once.
  - `teams.ts` — the team files: `.chord/teams/<name>.md` in the project
    and `teams/` beside the user's settings file, the project's winning a
    name both have, read whenever asked for, never at start; each read
    (vfile-matter, its YAML through `yaml`) and checked by zod (the name, the
    description, the lead, 1–8 members, each agent's optional model,
    effort and mode, a body), a file that fails listed
    with its first problem in zod's path words; `propose_team`'s input
    shape and a proposal checked as its file would be; each agent's change
    against the team saved before; a team written back,
    its frontmatter through `yaml`'s `stringify`, to a file beside the
    target renamed over it; and the team part a run's lead or a member gets
    ahead of its first message: chord's standing words (its tools, who it
    reaches, the directory, the other runs open), then the file's.
  - `mcp.ts` — the MCP servers each session gets: `mcpServers` in the
    settings files and the working directory's `.mcp.json`, each server
    checked by zod on its own, merged by name (user's file, `.mcp.json`,
    then the project's file), and turned into ACP's `McpServer` values that
    go with `session/new` and `session/load`; read only, never written.
  - `notify.ts` — telling the terminal chord waits on the person: which
    events start a wait (a turn ending unless it was cancelled or a
    monitor's event started it, a permission request, a form or link the agent asks for), and the BEL,
    OSC 9 or OSC 777 bytes for it, from the settings' channel and the
    terminal the environment names; `ui/app/terminal.ts` writes them to
    stdout between frames, once the renderer is idle.
  - `files.ts` — the working directory's files that `@` offers, walked by
    globby with every `.gitignore` read and `.git` left out, and the
    `resource_link` blocks a prompt's mentions of them send.
  - `links.ts` — opens a link an agent asked the person to open, in the
    system's browser through the `open` package, only once they chose to.
  - `shell.ts` — runs a bash-mode command, or a monitor's, through the
    user's shell in the session's directory, in a process group of its own
    (`platform/process.ts`) so Esc or a monitor's stop stops what it
    started too, and is over only once the group is reaped; a monitor's
    stdout line by line through split2, its stderr not read, the
    signal it died by, and, once the shell exits on its own (`exited`, even
    with a child still holding stdout), what it left in its group stopped
    too (`reap`), the shell's code kept as the end.
  - `editor.ts` — ctrl+g: the draft in `$VISUAL`, `$EDITOR` or vi, through
    the user's shell, on @inquirer/external-editor's temporary file, and
    back as a draft, or what the status line says of an editor that failed;
    `ui/app/terminal.ts` runs it inside the renderer's suspension, which
    leaves the alternate screen and raw mode around it and redraws after.
  - `upgrade.ts` — `chord upgrade`: cliffy's upgrade command over the
    package manager that installed the running binary, read off its real
    path (npm, bun, pnpm or yarn), installing the exact version globally,
    or a refusal that names each manager's command where none is found.
  - `not_found.ts` — whether a `node:fs` call failed because nothing is at
    the path, which every reader of a file that may be absent (settings,
    `.mcp.json`, teams, records, windows) takes as none there.
  - `images.ts` — the images a prompt takes: ctrl+v's, from the system
    clipboard through @mariozechner/clipboard, loaded on the first ctrl+v,
    and the file a path names; file-type says from the bytes what each is,
    and only PNG, JPEG, GIF and WebP go.
- `src/server/` — chord's own MCP server, which every session the window
  opens gets beside the user's servers, where its agent takes HTTP.
  - `server.ts` — serves it on the loopback at a port the system picks,
    through @modelcontextprotocol/sdk's Streamable HTTP transport on
    `platform/serve.ts`; gives each session a bearer token, refuses a request
    without one it gave, and gives each MCP session an `McpServer` with its
    caller's tools.
  - `tools.ts` — the tools by the caller's role (a session the person
    opened: `list_agents`, `list_sessions` with each session's long-lived
    agents, `list_teams` with each team's open runs, `spawn_task`,
    `open_agent`, `run_team`, `propose_team`, which draws the team and
    waits on the person's save box, and writes the file they pick,
    `send_message` to a child of its by id or
    name, `close_agent`, `monitor`, `stop_monitor` and `list_monitors`; a
    long-lived child: `list_agents`, `spawn_task` for task agents of its
    own, `send_message`, to its parent alone, and the three monitor tools,
    its own monitors only; a team's lead: the same, but `open_agent`
    `{member, prompt}` for its file's members, `send_message` `{to}` to
    main, its members and the other runs' leads, and `close_agent` for a
    member; a member: the same as a child, but `send_message` `{to}` to its
    lead and its team's other open members; a task: `send_message` alone,
    as it ends with its first turn) and their
    answers, each monitor tool's said for the model with its value as
    `structuredContent`, worked out from
    what the window reads of itself, each call told to the caller's session
    as it is served, so its call draws by what chord served.
  - `runtimes.ts` — each runtime's models, modes and efforts for
    `list_agents` (the efforts on the model they were read for): an open
    session's, or one opened to read them and closed, within a bound, kept
    for the window.
- `src/platform/` — what is not a plain `node:` call, so moving runtime is
  this folder's change. Nothing else in `src/` calls `Bun.*`: files, the
  environment, the terminal and timers are `node:` built-ins.
  - `process.ts` — a child leading a process group of its own on
    `node:child_process`, its group signalled and probed, its exit with the
    signal and the code a shell's `$?` reads, and the binary's own path.
  - `serve.ts` — HTTP on the loopback, on `Bun.serve`.
  - `heap.ts` — `kill -USR2 <pid>`: a heap snapshot of chord as it runs,
    in V8's format (`Bun.generateHeapSnapshot`), with `bun:jsc`'s counts
    beside it, into `heaps/` in chord's state directory, nothing on screen
    (`docs/memory.md`).
- `src/acp/` — chord's own ACP transport on `@agentclientprotocol/sdk`,
  which every session, the window's and `-p`'s, runs on.
  - `connection.ts` — `openAgent` starts an agent, connects on its stdio
    and initialises ACP v1 (forms and links, plans and compactions by id,
    subagents as sessions of their own, no files or terminals, and
    commands' output as tool calls' `_meta`), keeps the agent's answer, and
    offers `session/new`, `load`, `resume` and `list` (the last three only
    where the agent offers them), prompts, cancel, config options, modes
    and models, and `_session/steering` (only where the answer to
    `initialize` advertises it under `_meta.steering.supported`, through
    the SDK's request for a method its schema lacks), each with an
    `AbortSignal`; it answers permission requests
    and forms through the caller's handlers, `cancelled` once a cancel (the
    session's, or its subagents' with it) or a close withdraws them.
  - `traffic.ts` — runs a relay, when the caller gives one, between the
    agent's stdio and everything else, as an ACP proxy would stand; hands
    every message either way, as the relay left it and in wire order, and
    the agent's stderr, to one subscriber; and keeps the agent's
    notifications from the SDK's schema.
  - `process.ts` — starts the agent in a process group of its own from a
    command line (shell-quote) or an argv, and stops it within its bounds:
    stdin's end, SIGTERM, SIGKILL, the exit seen.
- `src/session/` — sessions on chord's transport, below the interface and
  shared with `-p`.
  - `session.ts` — opens a session (new, or an earlier one through
    `session/load` or `session/resume`), sends prompts with images after
    their text, then a `resource_link` for each file the prompt's `@`
    mentions name, and cancels them, reads whether the agent takes images,
    hands every `session/update` for the session to its listeners as the
    agent sent it, and those for the subagents it announced, at any depth,
    with the subagent's id, and cancels their work with the session's turn,
    reads and sets its model, mode, effort and other config options, says once its
    agent has gone what it left on stderr, and closes without leaving an
    agent.
  - `permissions.ts` answers permission requests by the option picked, and
    `elicitations.ts` the forms and links the agent asks for, both parked
    until a key answers.
  - `agent_state.ts` — what the agent says of the session besides its
    turns: its config options, its efforts among them, its modes and models the older way, its
    slash commands, from `session/new`'s answer, the updates and the
    answers to `set_*` calls.
  - `modes.ts` — the agent's modes as its `mode` config option lists them,
    or the older `modes` field, and which one shift+tab goes to next.
    `models.ts` — the agent's models as its `model` config option lists
    them, or the older `models` field, and the name the status line gives
    the one in use. `efforts.ts` — the agent's efforts for the model it is
    on, as its config option of ACP's `thought_level` category lists them,
    found by that category alone. `config.ts` — the agent's other select config options,
    such as effort, with each one's values and the one in use, as `/config`
    lists them.
  - `conversation.ts` — drives one session for the interface: opens it and
    puts it on the starting model, effort and mode, saying a refusal with
    where the value was set and what the agent offers (an effort's refusal
    never failing the start), says first to the window alone
    that a session is a resumed one, when it was last used and its first
    prompt as its record has them, plays a resumed session's past
    out before `connected`, hands what it reports to the session's record,
    plays each prompt, the agent's updates (in a turn, after its answer and
    outside any turn) and the turn's result out as reducer actions, holds a
    prompt sent during a turn and sends it once the turn ahead ends and the
    agent has gone quiet after it (late updates belong to the turn they
    follow; the turn ahead ends on screen only then), takes the person's
    queued prompts back on an interrupt, the wait included, and sends the
    queued messages once the interrupted turn ends, delivers a message from
    another agent as a turn, wrapped `<message from="…">`, queued as a
    prompt is, or, set aside, ahead of the person's next prompt with no
    turn of its own (chord's note of a `/team run`), and one an agent sent
    with `send_message` into the turn running, at once, on an agent that
    takes steering (asking one with no turn to answer `promptRequired`),
    once the turn's prompt has gone (one with mentions waits on their walk,
    and a message before then is queued behind the turn), drawn and
    recorded in that turn once the agent took it, held in the queue while
    the turn waits on a permission, a form or a link until the person
    answers, as is one behind a steer still out when one is asked, and queued as the next turn when the agent refuses it,
    the turn ends or an interrupt comes first, or when the agent starts a
    turn of its own with it (Codex's adapter, a steer that missed the turn),
    which is cancelled at once, what it sends folded under an id of its
    own and closed by chord's `self_started` line, no prompt of chord's going while a steer is
    unanswered or until the agent goes quiet after that cancel, steers
    going one at a time and none into a turn a steer found over, runs the session's task agents (`tasks.ts`), relaying their
    work into the session's stream and their requests' answers back,
    stopping them with the turn and closing them with the session and on
    `/clear`, runs the monitors its agent starts (`monitors.ts`), each
    batch of lines a message queued as one is, joined into that monitor's
    message while it is still queued, its end the last, ids going on from
    the past's, and stops them without a word on `/clear`, on close and
    when the agent goes, the close waiting for their process groups to
    go, tells the
    session of each of chord's tools served to it, reports the models, modes, other
    config options and slash commands before `connected` and whenever an
    update or the answer to a change it asked for moves them (a change to a
    config option goes into the transcript as a note), whether the agent
    takes images before `connected`, and each turn's tokens once it is
    answered; answers the forms and links a turn asks for, and cancels
    those its turn ended under; asks the person chord's own question in the
    permission box during a turn (`propose_team`'s save box), withdrawn with
    the turn, an interrupt, `/clear` or the close; cancels; lets the session go for a new one
    on `/clear`; and closes the agent.
  - `oneshot.ts` — `-p`'s one turn in a session of its own, on the
    starting effort and in the starting mode when the agent takes them,
    every permission refused or,
    under `--dangerously-skip-permissions`, allowed, every form declined and
    every link cancelled, with the turn's tokens
    and the last cost the agent reported, or chord's estimate of it.
  - `starting.ts` — asks for a starting model, effort or mode and words a
    refusal,
    for the window and `-p` alike; a required value's refusal fails the
    session's start, as a task agent's model does.
  - `tasks.ts` — a task agent, from `spawn_task` to its report: its own
    session's events relayed into its parent's as a subagent's under the
    task's id, its permission requests, forms and links the parent's to
    answer, its first turn's last message delivered to the parent as a
    message (`· report`, or `· failed` with the error), a task the parent
    stopped sending a line ahead of the person's next prompt instead, one
    stopped while it starts never sending its job, and the effort it
    started on, asked for in `spawn_task`, said to its block once it is up; and a
    message's wrapper, written and read back, a team agent's first with its
    team part in `<team>` ahead of it, and its sender as its row names it,
    `@name` for one `send_message` reaches.
  - `record.ts` — chord's own session record, one JSON Lines file per
    session under `records/` in chord's state directory (`state_dir.ts`):
    what the reducer was handed, from the session's start (each prompt as
    the agent got it, with the links its mentions sent, every update whole,
    with the subagent it was for and, for a subagent's start and end, when
    it came, each request chord's server served, a message as the wrapped
    prompt the agent got with its sender beside it, whose `@` the wrapper
    does not say, read back as its row, and the running turn it went into
    when it was steered, drawn there again, or, in a record kept before the
    sender was, told by the record's own `open_agent` and `spawn_task`
    answers, the session that started a
    task agent's or a long-lived one's (a member's, its lead's), chord's id
    for a long-lived one, a lead's team, and a task's id, as its parent's
    record keeps only the task's start and end and draws its work from the
    task's own, or none once that has gone, each long-lived agent closed while
    the session went on, a run the person's `/team run` started as the
    `run_team` call it was, each form or link answered, with the questions
    chord read in it and the answer, each interrupt, each turn the agent started on
    its own and chord cancelled, and the agent's exit, each turn's
    result and tokens, the model, mode and config values in use, and the
    agent's id for the session), appended as the session goes once a prompt
    is sent, and drawn again as the reducer's actions, however the agent
    reopens the session, closing with the long-lived agents that were open
    when it was left, which are not reopened, each team run one of them
    with the members its lead's record had open, and the monitors that were
    running, which are not restarted; the window's sessions are
    recorded, `-p`'s are not.
  - `sessions.ts` — finds the session `--continue` opens again among those
    records, and the tabs `--resume <id> …` does, in order, each on its
    record's agent, refusing a tenth id, one named twice or, among several,
    one with no record, and the earlier sessions `/resume` and the start
    picker offer, this directory's or every one's, and what it says of one from another
    directory, and the command printed on quit that resumes each (by id,
    which works for every session).
  - `windows.ts` — chord's window records, one JSON file per window under
    `windows/` in chord's state directory: a `w-` id, when it quit, its
    tabs in order (each session's id, agent and directory) and the one in
    front, written whole on a quit with two or more resumable tabs; the
    command printed for it; and the tabs `--resume w-…` opens from it,
    each from its session's record, one whose record is gone left out and
    named on the status line, and a window id among session ids refused;
    and the windows `/resume` lists: every record read, those with a
    session left newest first, merged with the sessions by time, a window
    this directory's only when every tab is, its row's summary (`▣ 3
    sessions, 2 open · claude, codex, claude`, the agents counted and then
    cut at a `, ` past 30 columns) and directory (`~/src/app +1`), the
    cap's arithmetic and refusal, and the refusal of one with a tab
    elsewhere.
  - `monitors.ts` — a monitor: CHD-243's numbers, a line as an event
    carries it (strip-ansi, cut at 1,000 characters), an event's caps of
    100 lines and 16 KiB, the rest counted, the flood watch over a sliding
    10 s, the word and the sentence each end gets, what a resumed past
    says of its monitors (from the `monitor` and `stop_monitor` calls
    served and the end messages: the next id, how each ended, those left
    running), and `MonitorRun`, which runs one command through `shell.ts`
    and batches its lines on a fixed 200 ms window, keeping its timeout.
    `window_monitors.ts` is whose monitors a call to chord's MCP server
    reaches (the tab's session or the child's own; a task's none) and the
    limit of 8 the tab's session and its children share.
    `elapsed.ts` is how long something took in words, for the spinner, the
    agent list and a monitor's end alike.
  - `replay.ts` — turns the past an agent replays in `session/load` into
    the reducer's actions, so it draws as its turns did live.
  - `enrich.ts` — the enricher chain every session's traffic runs through,
    on the transport's relay, so the session's state, its record, the
    window and `-p` read only what it leaves: each enricher pure, from a
    message the agent sent and what the chain has folded of its sessions to
    the messages in its place, ACP's shape both sides, with what chord
    filled in named under `_meta`'s `chord/filled`. `enrichers.ts` is
    them: the adapters' `subagent_spawned` and `subagent_state_update` read
    as ACP's `subagent_update`, the rest of their shape under `_meta`'s
    `chord/subagent_draft`, a cost from a turn's tokens for an agent that
    gives none, the context window from the model for a `usage_update` with
    none, a tool call's title and kind carried onto its updates and
    permission requests, a mode change read back from an answer that
    says nothing, as Codex's, and the question forms of claude, codex,
    factory-droid, opencode and dimcode, each read by its adapter's own
    marks into `questions.ts`'s one shape under `_meta`'s
    `chord/questions`, the form left as sent so the answer goes back under
    its own field ids. `prices.ts` is a model's price and window
    from @pydantic/genai-prices' data.
  - `subagents.ts` — which sessions are the session's own and its
    subagents', and what the window reads of the subagents: how many still
    run, the way down to one, and the request a call waits on.
  - `tabs.ts` — the sessions open in one window, pure: their tabs in the
    order they were opened, at most nine, the one in front, what open,
    close, next, previous and a tab's number do to them, each tab's wait
    state (what it asks the person for and since when, a reply or failure
    not yet seen, the turn running) folded from the events `notify.ts`
    classes as waits, the order `ctrl+x a` goes through them in, and the
    tab `ctrl+x w`'s list opens on; and each tab's long-lived agents, which
    get no tab: the children `open_agent` opened, each keyed from the tabs'
    own keys, named and coloured in the order it opened, at most eight of
    the session's own, a team's lead among them, with a lead's members
    after it, which the cap does not count, and a run named after its team,
    numbered past the first (`bugfix 2`) with no closed run's number given
    again, the one picked, which the window shows and the prompt goes to, those it
    closed, what a notification calls each (a member with its run,
    `tester (bugfix)`), each child's wait folded as a tab's is (a message not yet seen
    among them, which marks no tab), a tab's waits merged into its
    glyph's, and what chord tells a parent when a child's agent exits or
    its turn fails, a lead's exit saying its members are closed.
    `open_sessions.ts` gives each tab and each child its own
    `Conversation`, and so its own agent, closes a tab's children with it,
    and closes them all at once.
  - `usage.ts` — what the session has spent, each turn's tokens as the
    agent's answer to its prompt gave them.
  - `context.ts` — a bash-mode command's output as it goes to the agent
    ahead of the next prompt, in Claude Code's `<bash-input>` tags, and
    read back from a resumed session's prompts.
  - `terminal_text.ts` — a command's output as plain text: each delta
    written as a terminal would, `\r`, backspace, tabs, erase in line and
    cursor moves applied, every other escape dropped, one a delta ends
    inside held as the parser state it left, within a constant, and the
    last of it kept from a line's start.
- `src/session/transcript/` — the pure reducer from a session's
  `session/update`s, prompts, permissions, forms, cancels, results and the
  agent's exit to the transcript state every visible slice draws, one
  module per kind of update. `reducer.ts`'s `reduceTranscript` composes
  them, and folds itself what is the session's and no entry's: usage, the
  mode, the slash commands, the older `plan` update, the entries
  chord's own commands add, and the line closing a turn the agent started
  on its own, which chord cancelled, kept under what that turn sends after
  it and standing alone while the turn sent nothing. `types.ts` is the shapes they share, and the
  empty transcript. `messages.ts` is replies and thoughts, a chunk running
  on into its block. `tools.ts` is a tool call through its updates, and its
  terminals: what the commands it ran wrote, their directory and exit,
  folded from its `_meta`, the output as `terminal_text.ts` keeps it.
  `plans.ts` is a plan by id: its entries the live list, its markdown or
  file the reply it rewrites. `compactions.ts` is each compaction the agent
  ran, by its id, with the summary it kept. `subagents.ts` is each
  subagent, an entry where its first update came among its parent's,
  holding its own messages, calls, plan and subagents apart from the
  parent's, folded through the reducer's own fold, its state (ended
  `cancelled` with a cancelled turn, `disconnected` with the agent, left
  running by a turn that ends on its own) and when it started and ended, on
  chord's clock. `permissions.ts` is a permission waited on in the turn's
  status and a form or link waited on beside it, each answer's record.
  `turn.ts` is the turn: its prompt, or a message, which draws as a row of
  its own, a cancel, the result that settles it (a
  finished plan into the transcript, a form left open recorded cancelled,
  an ending other than `end_turn` said, a running task agent's requests
  left waiting between turns), and the agent's exit. `chord.ts` is chord's
  own calls: a request its server served tied to the tool call with the
  same arguments, now or once that call comes, and a `spawn_task` call
  replaced by the task it started, which stands where the call stood and
  takes its updates; a task is a subagent with its runtime and model under
  `_meta`'s `chord/task`. `shell.ts`
  is a bash-mode run, which no turn asked for.
- `src/ui/` — the interface, split by feature, one folder each, as
  `docs/decisions.md` ("The interface split by feature") lays out. Pure
  logic is a snake_case `.ts` beside its feature's components; there is no
  `index.ts`, so an import names the file it needs. A feature's components
  are in a PascalCase `.tsx` in its folder; `app/App.tsx` defines no
  component but the window. Every component draws on OpenTUI's own
  `<box>`, `<text>` and `<span>` (`theme/text.ts`) and hears the terminal
  through OpenTUI's hooks; there is no layer between them and OpenTUI
  (docs/decisions.md, "OpenTUI part 8b").
- `src/ui/app/` — the window. `App.tsx` is the whole window, and only
  assembles it and routes keys: each key, Enter and edit in the box goes
  through `keys.ts` and the steps it returns are played in order.
  `keys.ts` is pure: from the front session's state, history and a key
  press to the steps it asks for — actions for the reducer, the box
  redrawn, history moved, and the ones that reach past the state, named
  for the hooks to do — and so tested without a terminal. `sessions.ts`'s
  `useSessions` drives the sessions through `open_sessions.ts`: each opened
  with its own `Conversation`, whose events go into the reducer under its
  tab's key, on its own agent's command, model and mode, in its own
  place (the directory it works in, and that directory's starting values
  and MCP servers, which `@`, bash mode, `/mcp`, `/status` and the header
  read from the tab in front), with a token for chord's MCP server, whose
  tools read the window through it; the tabs `--resume` opens with, in
  order, the first in front or the one a window record had, and the note a
  window record's missing tab leaves on the status line; opening one beside the rest, where the front
  one works, of the front session's agent or the one `/new` names, an
  agent chord cannot start refused, switching between them on the
  `session:` keys, closing them, quitting, `ctrl+x w`'s rows and its pick,
  `/resume`'s list, the front session's agent's sessions and every saved
  window, and its pick, which goes to the tab a session is open in rather
  than load it twice, and opens a window's tabs beside the open ones, none
  twice, an empty front tab giving its place, or none at all past the cap,
  `/model`'s and `/config`'s picks, sending a prompt, and the header's
  strip and the status line's waits and armed lines read from the tabs;
  and the long-lived agents: `open_agent`'s child where its parent's tab
  works, on the effort asked for, `spawn_task`'s and `open_agent`'s answer
  waiting, when one was, until the child is up to say the effort it is on
  and a refusal's line, the messages both ways (the first, and any sent while it starts,
  held until it is up), `close_agent`, the pick moved through the list,
  `x` on the picked child and chord's message to the parent after it,
  a child's own task agents, chord's message to the parent when a child's
  agent exits or its turn fails, `/clear` refused with a child picked, a closing tab's children closed
  with it, and the list's rows; and teams: `list_teams` and `run_team` from
  the team files where the tab works, the run's lead opened with its team
  part and kept beside the file as read, a lead's members opened by name
  on the file's runtime, model, effort and mode, the messages between a lead, its
  members, main and the other runs' leads, routed by who sends them and
  never through the lead, and a lead closed, by the person, by main or by
  its agent's exit, closing its members, with chord's sentence to main or
  to a member's lead; and `/team`'s side of them, for the front tab's
  `main` whatever is picked: the teams and runs its picker and names read,
  `/team run`'s run with chord's note to main held for its next prompt,
  `/team show`'s team and its running run caught as it stands, `/team
  stop`'s close, and `/team new`'s words sent to main as typed, with what its agent gets ahead of them.
  `renderer.tsx` is the terminal chord draws on: taken once
  (`openTerminal`: the alternate screen, raw keys, the mouse unless
  `mouse` is off, the kitty keyboard protocol where the terminal speaks
  it), the window drawn on it through OpenTUI's React root (`render`), and
  given back on every way out, a signal and an uncaught error included,
  those two waiting first for what the window asked `closeOnForcedExit` to
  close, its agents; and the window's quit, the terminal given up for a
  while, and bytes of chord's own written between frames, as hooks.
  `input.ts` is what the person does, as hooks on OpenTUI's `useKeyboard`
  and `usePaste`: each press as chord's own `Press` (`usePress`, through
  which every component hears keys; `shortcuts/press.ts` reads it, its
  base-layout key included), each bracketed paste (`usePasted`), a key or
  paste a listener claims kept from the textarea, a listener turned on
  hearing the next press and not the one that turned it on, what each sets
  off drawn before the next is read, and a wheel step or a drag anywhere
  over the window (`useMouse`). `Clip.tsx` is a clipping `<box>` that draws
  nothing while it is laid out to no rows, as OpenTUI draws every box at
  least a row high; `layout.ts` reads the transcript's boxes after each
  frame for the scroll and moves the view in the frame that laid it out.
  `terminal.ts` is the other side effects as hooks: the bytes that tell the
  terminal chord waits, ctrl+g's editor, the clipboard ctrl+v and an empty
  paste read (the latter quietly) and the image files a draft names, bash
  mode's commands, a link opened, and the files `@` walks. `commands.ts` runs chord's own slash
  commands, `/team`'s forms among them, and saves `/theme`'s and `/vim`'s
  choice; `timers.ts` runs out
  an armed quit or close, the drag's hint and a chord's first keys.
  `drag.ts` is what makes a drag, the left button let go on another cell
  than it went down on, and the modifier its hint names for the terminal.
  `layout.ts` measures the transcript in each frame OpenTUI lays out, for
  the scroll, and holds the view on the entry at its top while scrolled
  back, moving it in that same frame, which is also what keeps the view
  still as older entries mount above it; within a view of the top of what
  is mounted it asks for the next older chunk (`backfilled`). It also has
  OpenTUI's native scene cull the transcript to its area
  (`nativeScene.setViewport`), so entries off screen are not painted. The
  window draws only the entries `transcript/mount.ts` says are mounted,
  and the header or a child's line only with the first.
  `Start.tsx` is the window before the window: `chord --resume` with no
  id's picker, alone on the screen with no prompt box or status line, Esc
  and ctrl+c quitting.
  `state.ts` is its pure state, each
  feature's slice from its folder's `state.ts` put together, with what more
  than one feature writes (the connection, the transcript, the agent's
  models, options and modes, the armed quit and close, the note of the
  sessions, the drag's hint, `/clear`, quitting, and an update's effect on
  the scroll, the queue, the held output and the search), and what each key
  asks for, read across them all. It is split in
  two. Each session's own (the connection, the agent's id for the session,
  when it came up and what it has spent, the transcript, the scroll
  position and the first entry held mounted while scrolled back, the agent's models and the one the header names, whether it was
  resumed and from when, its other config options, its modes and the
  one still being asked for, the monitors its agent started that still
  run, the prompts queued behind the turn, bash mode
  and the command output held for the next prompt, the draft and its
  cursor, the images the draft holds and whether the agent takes any) is
  kept by the tab's key, and an event from a session behind changes only
  its own, as is each long-lived child's, by its key; the window's (the
  armed ctrl+c, ctrl+d or `/exit`, the armed `ctrl+x k` and the session it
  closes, whether the list of agents has the keys and the child an armed
  `x` closes, ctrl+o's expanded view, the open
  shortcuts panel, the open model picker, whether `ctrl+x w`'s sessions
  picker is open, the sessions and windows `/resume` lists and
  whether every directory's are shown, `/config`'s picker, on the options
  or one's values, the theme in use and the one `/theme` previews, whether
  `/mcp`'s list is open, the slash command list's highlight, the files `@`
  found and the finder's highlight, ctrl+r's search while it is open, what
  the status line says of an editor ctrl+g opened that failed or a ctrl+v
  that found no image, vim mode's state while `/vim` has it on, the keymap,
  a chord's first keys while the next is waited for, and the keybindings
  file's problems counted) is one for every session. The session in front
  and the window together are what is drawn and
  what each key does to it. `closing.ts` is what makes a
  session busy (a permission or
  form asked, the person's prompts queued, task agents running, those and
  its long-lived agents at work, a turn or a bash-mode command running), so
  closing or quitting it
  asks for a second press, and the armed lines that say so;
  `strip.ts` is the header's tabs once two or more sessions are
  open: each tab's number, agent and glyph, the one in front, the
  directory once on the right, and the order they shorten in to fit, and
  `Strip.tsx` draws them;
  `context.ts` is the React contexts every component reads, the palette,
  the keymap and the colours of the session's agents by name, with `paint`
  and the hint helpers.
- `src/ui/agents/` — the list under the status line of a session's
  long-lived agents, drawn while it has a child, and the monitors it and
  its children run, after them in the order they started. `agents.ts` is
  pure: each agent row's name, runtime, model and the effort it is on, and state
  (`● permission 12s`, `✗ failed`, `← message from @main`,
  `✓ replied 2m ago`, `✻ working 41s`), a team's members nested under its
  lead with `├─` and `└─`, and, where the whole list does not fit its rows,
  each team but the picked agent's folded to its lead's row
  (`team · claude · 4 agents  ● tester: permission 12s`), each monitor row's description,
  `$ command` and `running 6m · 3 events`, a child's ending `· parser`, at
  most `max(2, rows / 6)` rows then `… +N more`, moved to keep the `❯` in
  view, cutting a command first, then dropping the effort, the model, a monitor's
  running time and the state's words to fit; where ↑ ↓ take the `❯` (an
  agent's row picks it, a monitor's picks nothing) and where it goes when
  `x` stops a monitor; the status line's hint while it has the keys, an
  agent's or a monitor's; the line a child's transcript opens with; and the
  line a resumed session's closes with, naming the long-lived agents open
  when it was left.
  `Agents.tsx` draws the list and that line; the box's border takes the
  picked child's colour and name in `prompt/Prompt.tsx`.
- `src/ui/transcript/` — the transcript. `Transcript.tsx` draws its
  entries, each drawn again only when its props change (`React.memo`), as
  the reducer keeps an entry a chunk did not touch: a prompt, a message from another agent (`←`), a reply, a
  thought, a note, a report, a shell run, a
  compaction, the long-lived agents a resumed session left open, and the rule below it while scrolled back. `message.ts` is
  what a message reads as: its header, its text folded after six lines, a
  monitor's event as its lines printed verbatim with chord's sentence for
  its end last and never folded, its arrow's colour, and its row in the
  queue. `reports.ts` is what `/cost`,
  `/context` and `/status` put in the transcript, and the plain sentence
  each says when the agent has not reported; `scroll.ts` is where the
  transcript's view is: following the
  bottom or scrolled back, what pgup, pgdn, shift+↑/↓, home and end do, and the
  rule that says what is below;
  `mount.ts` is which entries are mounted: only the tail's while
  following (40 by weight, at least the view's rows), the window held from
  where the view left the bottom, 60 more above it at a time as the view
  nears its top, all of them for home, and the tail again back at the
  bottom; a folded subagent group costs one, an opened one its agents'
  work too;
  `compaction.ts` is what a compaction reads as: `Compacting conversation…`
  while it runs, in the spinner within a turn, then compacted, failed or
  cancelled;
  `markdown.ts` is a reply as terminal markdown, laid out to its width;
  `highlight.ts` is code coloured by its language (emphasize), for a reply
  and a diff.
- `src/ui/transcript/tools/` — a tool call. `Tool.tsx` draws one, its
  terminal output and its diff, and the gutter, `⎿` lines and outcomes the
  other entries hang theirs from. `tools.ts` is what
  a tool call reads as: its `Read(path)` headline, its status, its `⎿` lines;
  `chord.ts` is what chord's own calls read as, from what chord served:
  `List agents(codex)`, `List sessions`, `→ @main · queued`, a
  refused `Agent(name) · runtime`, and what was said or answered;
  `proposal.ts` is `propose_team`'s `Team(bugfix) · proposal` or `· change`:
  its agents as a table (@cliffy/table) cut to the width, an effort
  column only where an agent sets one, the role first, then a changed
  effort's old one, then the model, never the effort or mode, or opened,
  every cell whole and each role on lines of its own under its row, a
  changed cell that wraps broken before `was`, a mode that skips the
  person's ok told
  apart, a change's rows marked `+`, `~` or `-` and a changed effort's and
  mode's old one, the body folded to its first lines where the window has the rows, a
  change's body as a diff cut to its changed lines under the line that
  counts it, and the `Saved to …` or `Not saved` line;
  `terminal.ts` is what a command an agent ran wrote, under its call: its
  latest lines while folded, drawn as the reducer keeps them, and a failing
  exit with its code;
  `diff.ts` is an edit's diff as numbered, marked rows, folded to a few.
- `src/ui/transcript/agents/` — `Agents.tsx` draws subagent blocks and
  groups. `subagents.ts` is what a subagent reads as:
  its `Agent(<title>)` block, a task agent's with its runtime and model
  after, the model dropped first where it does not fit, its
  latest calls while it runs and its ending after, those spawned back to
  back as one `Running N agents…` tree, task agents never grouped with the
  runtime's own, with each row laid out to the width,
  its work in ctrl+o's view with its plan where it first came, the row a
  child's permission box opens with, and the status line's
  `1 agent still running`.
- `src/ui/prompt/` — the prompt and what it opens. `Prompt.tsx` draws the
  prompt box (and hands on each bracketed paste while its textarea hears
  them, the empty one the textarea drops included), ctrl+r's search line, the queue, the slash command list and
  the `@` file list. `TextArea.tsx` is OpenTUI's `<textarea>` in the
  terminal's own foreground, its cursor in the colour the terminal answers
  OSC 10 with, letting go of the keys as it unmounts, what each of its
  events sets off drawn at once.
  `prompt.ts` is what the prompt box adds to its textarea (its own keys
  turned off where the keybindings moved them, `\`+Enter, how
  tall it grows, which of the textarea's rows it shows and the gutter's
  `›`, `↑` and `↓` beside them); `history.ts` is the prompts
  sent, walked with ↑ and ↓; `search.ts` is ctrl+r's search through them:
  the newest prompt containing the query, the next older one on each
  ctrl+r, the `search prompts:` line, and where the match is in the
  textarea's cells, which it marks; `vim.ts` is vim mode: normal mode's keys
  played by @replit/codemirror-vim-core's engine on an editor of chord's
  over the draft and its cursor, `u`'s past and the register, and what Esc
  out of insert mode leaves; `images.ts` is the `[Image #N]` a pasted image
  puts at the cursor, the paths a draft names that are taken as images, and
  the images a prompt sends: those whose placeholders are in its text, a
  key that cuts into one, widened to the whole of it, and ctrl+w straight
  after one, which takes it whole with its space; `queue.ts` is the
  prompts queued behind the turn as the dim `›` rows under the working
  line, a message among them as a `←` row, `· after your answer` in its
  header when it waits for the person's answer to go into the turn, and
  the draft the person's go back to on Esc; `mentions.ts` is the `@` file finder: the
  `@` and part of a path at the cursor, the files it matches (fzf), the
  path a pick puts in its place, and the paths a prompt mentions; `bash.ts` is bash mode: the `!` that starts
  it, and a command's run as the transcript draws it; `commands.ts` is the slash
  command list: chord's `/clear`, `/config`, `/context`, `/cost`, `/help`, `/mcp`, `/model`,
  `/new`, `/resume`, `/status`, `/team`, `/theme`, `/vim` and `/exit` and the agent's commands, which a typed `/name`
  matches (fzf), and what Tab and Enter do, the words after a name of
  chord's going with it, as `/new` names an agent; `/new `'s list of
  the agents the window can start, by name, the one typed exactly first,
  those that will start on top and an own CLI PATH lacks marked; and the
  names `/team show `, `run ` and `stop ` offer, the saved teams' (not a
  broken file's) or the open runs', Enter on a run's
  putting it in the box for the job.
- `src/ui/dialogs/` — what the agent asks the person. `permission.ts` is the
  permission prompt's choices, the arguments it shows for a request with no
  content, one `key: value` per line, and what an answer reads as; `form.ts` is a
  form an agent asks for: the fields its schema asks for, what each key
  does to them, their problems as zod finds them in chord's words, the rows
  the box draws as they scroll, the hint line, the answer sent and its
  record, and the host a link opens; `questions.ts` is the question box a
  form the enrichers read questions in takes instead (layout A, one
  question a step, then Submit): what each key does, the rows a step
  keeps in view, the hint line, the summary and what Send gives back under
  the agent's own field ids; `saveChoices` is chord's own question's
  choices, each with the file it writes. `Permission.tsx` draws the permission
  prompt, and in its shape chord's own question, `propose_team`'s save box,
  `Form.tsx` a form and a form's or link's record in the
  transcript, `Questions.tsx` the question box, and `Link.tsx` a link the agent asks the person to open.
- `src/ui/pickers/` — `Pickers.tsx` draws the model, resume, sessions,
  config, theme and teams pickers and `/mcp`'s panel, with the list they share and
  the numbered choices the permission prompt and a link take. `picker.ts` is
  the pickers' list: `/model`'s models, the one in use marked, and
  `/resume`'s earlier sessions and saved windows, each as when it was last
  used, `open in 2` for a session open in a tab, and its first prompt, after
  the name of an agent another started (`parser · agentchild`), a
  window's after its `▣` summary, with its directory from `~`
  when every directory's are listed, `ctrl+x w`'s open sessions, each as
  its agent, where it stands (`here`, `● permission 41s`, `✓ replied 2m
  ago`…) and its first prompt, and `/config`'s options, each with its value, and one option's
  values, the one in use marked; `mcp.ts` is `/mcp`'s list of
  the MCP servers chord passed, in columns cut to the width.
- `src/ui/teams/` — `/team`. `teams.ts` is pure: the form typed and its
  refusals, the words main gets for `/team new` (one line naming
  `propose_team`, then the person's), chord's note of a run the person
  started, the lines `/team` says (a refusal, `/team stop`'s close), the teams picker's rows in columns (size and
  runtimes, where saved, `✻ working 6m` or `✻ 2 runs`, description; a
  broken file's problem and path), the runtimes and half the hint dropped
  below 100 columns, what Enter on a team puts in the box (nothing for a
  broken file), and `/team
  show`'s running form: its header and each agent's file's effort, given
  up where the latest headline would keep fewer than 12 cells, state and
  latest headline, cut to the width. `Teams.tsx` draws what a `/team` command left
  in the transcript: the command as typed, then a run's `Team(…)` row as
  `run_team`'s call draws it, the team shown as a proposal is (its file,
  description, agents and body folded) or running, or a line.
- `src/ui/plan/` — `Plan.tsx` draws the plan above the prompt and its
  record in the transcript. `plan.ts` is the agent's plan as the `☐ ◐ ☒`
  list above the prompt, the line it hangs from between turns and how a tall
  one folds (a finished one moves into the transcript when its turn ends).
- `src/ui/status/` — `Status.tsx` draws the working line, its spinner
  turning on a 140 ms timer, the status line and the leader line.
  `status.ts`
  is the working line's words and clock, the spinner's three `›` marks with
  the mark's light colour running along them, and the status line under the prompt: vim's `-- INSERT --` or `-- NORMAL --`,
  then the message, the notice of the sessions behind that want the person
  (`● 2 claude needs your permission · ctrl+x a`), bash mode, the agent's
  mode or the hint (or the subagents a finished turn left running) on the left, the model, the effort it is on and the context left on the right, shortened to fit
  the width, and, after a chord's first keys, the leader line in its place:
  the keys that can follow and what each does.
- `src/ui/shortcuts/` — `Shortcuts.tsx` draws the shortcuts panel.
  `keys.ts` is every key as the shortcuts panel lists
  it, and how many columns it takes, indented on the left alone, named as the
  keybindings file binds it; `bindings.ts` is every action a key can be
  bound to and its default keys, the keybindings file read over them with
  its problems, and a key press matched against the keys bound, chords
  included, and, where a press matches nothing, the US key in its place on
  a Russian layout (convert-layout's table, typed in `convert-layout.d.ts`)
  that `app/state.ts`'s `keyAnswer` tries after the press's base-layout key.
- `src/ui/header/` — the startup header, the first thing in each session's
  transcript, right under the bar while the transcript is short. `Header.tsx`
  draws it; `header.ts` is pure: the mark's width and the text's beside it,
  its colour level from chalk's and the theme's `mark` role, and the lines
  (version, agent and the model the session started on, directory, keys, and
  a resumed session's last use and first prompt). `mark.ts` is generated by
  `bun run mark`, never edited: Chorded's mark at 4 rows, and at 8 for the
  splash, each half cell
  filled or not and its place on the diagonal gradient (0..1), not a colour. `mark_rows.ts` is pure: a grid and a colour level (truecolor and
  256 with a stop set, 16 with one tone, none) to rows of styled runs, ready
  for `<Text>`, the gradient interpolated and the nearest xterm colour
  in OKLab found by culori at draw time.
- `src/ui/splash/` — the startup splash, alone on the screen from launch
  until the first session is up or fails, or Esc leaves it, with the window
  laid out but not drawn behind it, so keys pressed meanwhile land there;
  never on a stdout that is not a terminal. `Splash.tsx` draws it, dim, on
  one 300 ms timer; `splash.ts` is pure: the eight places the mark drifts
  through, the mark the screen fits (8 rows, 4, or none), its box at each
  step, the two lines under it, where each goes to be centred, and whether
  it holds the screen.
- `src/ui/theme/` — `theme.ts` is every colour chord paints, by role, in each of its themes,
  which theme `auto` comes to on the terminal's background (OSC 11, which
  OpenTUI asks as `app/renderer.tsx`'s `openTerminal` takes the terminal, then
  `COLORFGBG`), `/theme`'s choices and how
  much of the picker fits, and the `agents` role, the six colours a
  session's children take in turn; `app/App.tsx` hands the palette down through
  `app/context.ts`'s React context, so `/theme`'s preview reaches every component at once.
  `text.ts` is what a component hands OpenTUI's `<text>` and `<span>`: a
  palette colour as OpenTUI takes it (chalk's sixteen names as the
  terminal's own), the props every text takes (the terminal's foreground,
  no selection of OpenTUI's), one that takes the rest of its row, one cut
  at its edge, the dim border's grey, and a string's SGR read into runs by
  @ansi-tools/parser, every other escape left out; `Ansi.tsx` draws those
  runs as `<span>`s. OpenTUI's `<text>` draws an escape's bytes as text,
  so a string an agent sent (a call's title and output, a thought, a plan
  step, an error) goes through `Ansi` unless something cleaned it first.
- A feature's `state.ts` — its slice of the window's state and its reducer,
  knowing only that slice and importing nothing from `app/`:
  `prompt/state.ts` the draft, its cursor and images, bash mode and the
  output held, the queue, the slash command list, the `@` file finder,
  ctrl+r's search, vim mode and what ctrl+g and ctrl+v failed to do, with
  the list and the finder as the draft opens them; `pickers/state.ts` the
  model, resume, sessions, config and theme pickers, `/mcp`'s list and the theme in
  use, with whether each is on screen; `transcript/state.ts` the scroll,
  the first entry held mounted and ctrl+o's view; `shortcuts/state.ts` the panel, the keymap, a chord's first
  keys and the keybindings file's problems, with the key press and the
  commands a key asks for; `dialogs/state.ts` the form being filled in
  and the question box being answered,
  with whether a permission, form or link waits on the person.
- `tests/` — `bun test`; `*_test.ts` / `*_test.tsx`, each at the path that
  mirrors its module's: `tests/settings_test.ts` tests `src/settings.ts`,
  `tests/acp/connection_test.ts` tests `src/acp/` through
  `connection.ts`, `tests/ui/prompt/history_test.ts` tests
  `src/ui/prompt/history.ts`, and `tests/session/transcript/tools_test.ts`
  tests `src/session/transcript/tools.ts`. `tests/privacy_test.ts` tests
  the repository itself, as above. Helpers sit beside the tests that share
  them: `tests/session/transcript/fold.ts` folds actions through the
  reducer, and `tests/ui/app/states.ts` gives the state tests their
  starting states and key presses.
- `tests/ui/` — besides each module's own tests, the window's: chord's
  whole `App` on the fake agent, drawn through `harness.tsx`, each test
  in the folder of the feature it drives, in a `_test.tsx` named for the
  component it reaches there (`transcript/Transcript_test.tsx`,
  `transcript/tools/Tool_test.tsx`, `transcript/agents/Agents_test.tsx`,
  `prompt/Prompt_test.tsx`, `dialogs/Permission_test.tsx`,
  `dialogs/Form_test.tsx`, `dialogs/Link_test.tsx`,
  `pickers/Pickers_test.tsx`, `plan/Plan_test.tsx`,
  `status/Status_test.tsx` and `shortcuts/Shortcuts_test.tsx`).
  `harness.tsx` is the only test module that draws on OpenTUI's test
  renderer (`@opentui/react/test-utils`' `testRender`): every test that
  draws a component or the window renders, types raw bytes, pastes,
  resizes, reads the frame, asks whether a text is mounted at all (on
  screen or not, for the transcript's tail) and unmounts through its
  `draw`, the frame as
  Ink's test terminal kept it (each run's escapes while chalk has colour,
  trailing blanks left out), and, on a `Logged` terminal, every byte the
  renderer writes and raw mode turned on and off, for ctrl+g's editor.
  `app/render.tsx` renders the window for them all: `withWindow`, which
  unmounts it, stops the agent and proves every process it started gone
  whatever the test does, the keys as a terminal sends them, and the waits
  and steps more than one feature's tests take, `ready` among them: the
  status line's hint, since the header names the same keys from the first
  frame. `app/App_test.tsx` is the
  window's own: the header, interrupting, failing and quitting, the
  notifications, the terminal handed to the editor and back, tabs, a
  resumed session, `/clear`, `/help`, `/exit`, `/new` and the reports
  `/cost`, `/context` and `/status` add.
- `tests/fixtures/fake_agent/` — a scripted ACP agent on the SDK's agent side.
  `main.ts` is the agent, which `bun run chord:fake` and `tests/fixtures/fake.ts`'s
  `fakeAgentCommand` start: the scenario chosen, every request answered,
  sessions listed, loaded and resumed, and a turn's usage; it plays one
  table spread from a module per family under `scenarios/`: `text.ts`
  (`text`, `thought`, `todos`, `mcp`, `markdown`, `slow`, `long`),
  `tools.ts` (`tools`, `steps`, `calls`, `unordered`, `edit`, `rewrite`),
  `permissions.ts` (`permission`, `twins`, `mcpask`), `plans.ts` (`plan`,
  `proposal`), `forms.ts` (`form`, `link`), `shell.ts` (`shell`,
  `shellcut`, `bash`), `compaction.ts` (`compact`, `codexcompact`,
  `compactfail`), `modes.ts` (`status`, `exitplan`, `mode`, `lock`),
  `soak.ts` (`soak`, `soaklead`, `soakturn`),
  `subagents.ts` (`subagent`, `subagentupdate`), `chord_tools.ts`
  (`chordtools`) and `misbehaving.ts` (`error`, `late`, `unknown`). Beside it, what the scenarios read too:
  `options.ts` its flags and environment variables, `turn.ts` a turn and
  its call ids, `client.ts` what the client declared at `initialize`, and
  `sessions.ts` each session's directory, MCP servers, model, mode and
  effort with the config options that offer them.
  A prompt that is exactly a scenario name (`text`, `thought`, `tools`, `steps`, `calls`,
  `unordered`, `edit`, `rewrite`, `markdown`, `permission`, `plan`, `proposal`,
  `shell`, `shellcut`, `bash`, `compact`, `codexcompact`, `compactfail`, `status`,
  `error`, `slow`, `long`, `todos`, `exitplan`, `lock`, `mcp`, `form`, `link`,
  `mode`, `late`, `twins`, `mcpask`, `unknown`, `subagent`, `subagentupdate`,
  `chordtools`)
  plays that scenario; `steps` makes 150 calls, a transcript longer than
  its mounted tail in one turn; `form` asks for a form with a field of each kind and
  `link` for a link to open (`tests/fixtures/forms.ts`), `askclaude`,
  `askclaudeone`, `askcodex`, `askdroid`, `askopencode` and `askdimcode`
  each adapter's question form (`tests/fixtures/questions.ts`), claude's
  after AskUserQuestion's tool call as claude-agent-acp sends it,
  `askcodexwait` codex's with a wait of 300 ms, withdrawn 50 ms after it
  runs out, as codex-acp withdraws it once it does, and each says what came back, and
  an accepted link is followed by `elicitation/complete`; `twins` asks a
  permission with two `allow_once` options and says the id picked; `mcpask`
  asks for an MCP call as claude-agent-acp does, by the tool's name with the
  arguments only in `rawInput`; `late`
  sends a chunk after answering the prompt; `unknown` sends an update of a
  kind ACP does not have and a notification of its own;
  `mcp` answers with the MCP servers its session was opened with, as JSON;
  `chordtools` connects to chord's own, through the MCP SDK's client, calls
  `list_agents` and `list_sessions` and answers with what came back, as
  JSON; `chordcalls` makes the same calls as tool calls, titled as Claude's
  adapter titles them, then a `spawn_task` on a runtime chord does not
  know; `task` starts `taskchild` as a task agent on the fake runtime and
  works on a while; `taskchild` makes two calls, asks permission to edit,
  messages its parent through `send_message`, runs the tests and reports;
  `agents` opens `parser` on `agentchild` and `docs` on `permission`, both
  long-lived on the fake runtime, and messages `parser` twice;
  `agentchild` runs the tests twice, messaging its parent after each;
  `agentsheld` opens `docs` alone and messages it while it waits on its
  permission; `agentclose` closes `parser` and then messages it, which chord refuses;
  `agenttask`, `agentexit` and `agentfail` open `parser` on `task`, on
  `crash`, whose agent writes its last words to stderr and exits mid-turn,
  and on `error`; `taskeffort` and `agenteffort` start a task and open an
  agent on `text` on high effort, `taskmaxeffort` and `agentmaxeffort` on
  max, which the fake does not offer, and each says the effort chord's
  answer says it started on, and its note; `team` and `team2` call `list_teams`, then `run_team` on
  `bugfix` (`tests/fixtures/teams/fake/bugfix.md`, all on the fake runtime)
  with an issue's job; a team agent's first prompt plays its role, read off
  its team part, unless its message names a scenario, which it plays: `teamlead` opens `tester` and `coder`, asks the other runs'
  leads which files they hold and reports to main, `teamtester` writes a
  test, reports to its lead, messages `coder` directly and asks the person
  to run the suite, and `teamcoder` messages `tester`; `propose`, or the
  prompt `/team new` sends, proposes `bugfix` on claude and codex through
  `propose_team` and says where it was saved, and the next prompt after a
  proposal, whatever it says, is `proposeagain`: the same team with the
  reviewer on codex and tester in `bypassPermissions`; `soak` hands
  `bugfix` the job `soaklead`, whose lead opens `tester` and `coder` on
  `soakturn` and sends main `soakturn`, and each `soakturn` streams a
  30-line reply and a call, then sends `soakturn` back to its sender, so
  the four take turns until chord quits (`scripts/memory.ts`); a
  prompt that is a wrapped message is answered with who it was from, or,
  when what it says is a scenario's name, plays that scenario, as a child's
  first prompt is its parent's message; and `--no-http` or `CHORD_FAKE_NO_HTTP=1` leaves HTTP out of its
  `mcpCapabilities`, so chord gives it no server of its own; `long` streams 200
  numbered lines about 100 ms apart, to scroll back through by hand; `plan`
  moves its three steps along about 2 s apart, to see the list mid-turn;
  `proposal` sends Codex's proposed plan by id about 2 s a step: markdown
  rewritten then grown, a file plan, then the markdown one removed;
  `shell` runs a command as Codex's adapter does, to any client: its
  terminal named up front, its output (`tests/fixtures/terminals.ts`) in pieces about
  half a second apart, then a failing exit with the last piece, and
  `shellcut` the same with a hyperlink whose URL runs past the output bound
  and whose end comes in a later piece; `bash` as
  Claude's does: to a client that asks for terminal output in `_meta`, the
  terminal up front and the whole output, then the exit, once it is done
  about half a second later, and to any other a `console` code block;
  `compact` compacts as Claude's adapter does, to a client that declares
  `session.compaction`: a `compaction_update` in progress, its summary in
  chunks over about 2 s, then completed (cancelled when its turn is);
  `codexcompact` as Codex's does, with no summary, and `compactfail`
  fails with Claude's error; to any other client each is a `Compact
  conversation` tool call of kind `think`;
  `todos` says whether Claude's task list tools reached it turned on;
  `status` moves to plan mode by `current_mode_update` alone, reports a cost
  and answers with token usage of its own, and `exitplan`
  leaves a mode for the default as Claude does once a plan is approved;
  `lock` moves to plan the same way and refuses every mode asked for after;
  `mode` says the mode the turn runs in;
  `subagent` runs subagents as Claude's and Codex's adapters send them to a
  client that declares `clientCapabilities.subagents` (`subagent_spawned`,
  `subagent_state_update`, each subagent's work under its own session id):
  two spawned back to back, one with a plan, five calls, a subagent of its
  own and a write it asks permission for, the other failing, then, after a
  line of the parent's, a third alone that runs on about 2 s past the turn's
  answer; a cancel ends each still
  open `cancelled` before the answer; `subagentupdate` sends one in ACP's
  own `subagent_update`, running then idle. `--step-ms <ms>` or
  `CHORD_FAKE_STEP_MS` sets the pace of every scenario (5 ms a step by
  default). Every
  session offers two models, `Fake Large with a 1M context window` (in use
  until switched) and `Fake Small`, and three modes, `default`, `acceptEdits`
  and `plan`, and an effort, `low`, `medium` (until set) or `high`, through
  config options; `--no-config` or `CHORD_FAKE_NO_CONFIG=1` leaves the effort
  out and `--refuse-config` or `CHORD_FAKE_REFUSE_CONFIG=1` refuses every
  change to it; `--no-modes` or `CHORD_FAKE_NO_MODES=1` offers no modes and
  refuses `session/set_mode`. `--hang <step>` or `CHORD_FAKE_HANG=<step>`
  wedges it: `start` never answers `initialize`, `config` never answers a
  config, mode or model change, `turn` never ends a prompt, cancelled or not; it then
  ignores SIGTERM and outlives its stdin, so only SIGKILL ends it. It
  switches its model, mode and effort through
  `session/set_config_option` and answers `session/set_mode` as Claude's
  adapter does, or, with `--silent-set-mode` or
  `CHORD_FAKE_SILENT_SET_MODE=1`, answers both, for the mode, as Codex's
  does: an empty answer and no update, though the mode moves. With
  `--plan-capability-only` or `CHORD_FAKE_PLAN_CAPABILITY_ONLY=1`, the
  `plan` scenario sends its plan as Codex's adapter does: as a `plan_update`
  with an id to a client that declares `clientCapabilities.plan`, and as
  reply text to any other. Every session
  advertises two slash commands, `greet` and `echo` (`tests/fixtures/commands.ts`), just
  after `session/new`, as Claude's adapter does; a prompt starting with one
  plays it. Shell output sent ahead of a prompt is answered first with a
  `Received` line naming each command and its first line of output, and
  each image in a prompt with one naming its media type and size in bytes,
  and each `resource_link` with one naming it and its URI;
  `--no-images` or `CHORD_FAKE_NO_IMAGES=1` says in `promptCapabilities`
  that it takes none. Any
  other scenario's turn that ends on its own reports usage as Claude's adapter does: a
  `usage_update` with the context used so far (2,000 tokens a turn), the
  model's window and the session's cost ($0.0125 a turn), and the turn's
  tokens in its answer; `--no-usage` or `CHORD_FAKE_NO_USAGE=1` reports none,
  and `--tokens-only` or `CHORD_FAKE_TOKENS_ONLY=1` only the tokens, no cost
  and no window, on two real models chord's price data knows,
  `gpt-5.3-codex` (in use until switched) and `claude-haiku-4-5`. `session/list` gives the sessions the process created,
  newest first, and `session/set_model` takes either model. `session/load` takes any UUID and replays a short past (the
  `tools` and `text` scenarios) before it answers; any other id is not found,
  and `CHORD_FAKE_REFUSE_LOAD=1` refuses every load; `--resume-only` also
  offers `session/resume`, which takes the same ids and replays nothing.
  `--steering claude` or `--steering codex` (`CHORD_FAKE_STEERING`)
  advertises `_session/steering` and answers it as that adapter does: into
  the turn playing, `injected`, read at its next step or as it ends with
  `Read the message from <sender>.`; with none, Claude's `promptRequired`
  where the request asks for it, else, and always for Codex, a turn of the
  agent's own, `startedNewTurn`, answered before that turn says anything,
  as Codex's adapter answers once it has started. Without the flag it advertises nothing and
  refuses the method. `--steer-late` (`CHORD_FAKE_STEER_LATE=1`) lands a
  steer only once the turn playing has answered, as one that meets a turn's
  end does, Codex's answering a while after; as Codex's, a prompt that comes
  while a turn plays opens with `Started alongside a turn still playing.`.
  `tests/fixtures/recorder.ts`
  plays one through the session layer and returns what the interface would
  hand the transcript reducer, and `run` gathers a prompt's updates and its
  answer. `tests/fixtures/records.ts` leaves a session record as the window does, through a
  recording conversation, for the resume tests to find.
- `lint/style.ts` — the ESLint plugin for the layout the formatter cannot
  express; `lint/style_test.ts` runs it through ESLint's `RuleTester` under
  `bun test`, in `bun run check:static`. `lint/config_test.ts` lints one
  snippet per rule ESLint holds the tree to, so a rule that drops out of
  `eslint.config.ts` fails a test.
- `scripts/` — compile, npm packaging and the release. `release.sh` is
  the owner's, on an arm64 Mac (`docs/decisions.md`, "Releasing"): its
  steps are `release/`'s scripts, each runnable alone — `preflight.sh`,
  `natives.sh` (the macOS native libraries signed by the team before the
  build), `sign.sh` (`macos/chord.entitlements`), `selftest.sh` (a
  binary on the fake agent: `--version`, `-p`, and the window in tmux
  with ctrl+v), `notarise.sh` and `packages.sh`. `targets.ts` is the one list of
  release platforms: macOS and Linux, arm64 and x64 (Windows is not a target
  for now). `registry.ts` fetches the ACP Registry and writes
  `src/registry.ts`, refusing a package at anything but an exact version
  (npm-package-arg for npx, pip-requirements-js and @renovatebot/pep440 for
  uvx).
  `mark.ts` renders `mark.svg`, Chorded's mark copied from the brand, with
  resvg and writes `src/ui/header/mark.ts`, at 4 rows and at 8.
  `memory.ts` is the long-run memory check, too slow for `bun run check`:
  chord in tmux on the fake's `soak` team for minutes, its memory sampled,
  snapshots by `SIGUSR2`, the first and the last compared through memlab
  (`docs/memory.md`).
  `screenshots.ts` takes the README's screenshots: chord from source in
  tmux on the fake agent, in a home of its own where the settings name it
  `claude` and `codex`, each shot's scenario from `CHORD_FAKE_SCENARIO`
  under a person's prompt, the screen read back with `capture-pane -e`
  and drawn in a terminal window in Chrome (puppeteer-core, ansi_up) into
  `docs/images/`.
- `docs/` — features, decisions, `guide.md` (everything chord does, flag
  by flag and key by key, which the README links to), `memory.md`
  (snapshots and the memory check), and `images/`, the README's
  screenshots.

## How code is written

- **Bun runs chord.** chord runs from source and is tested on Bun, and
  `bun run check` is the check: `tsc`, ESLint, `prettier --check` and
  `bun test`. Tests are `test`, `describe`, `expect` and the fake timers
  of `bun:test`. Bun's `expect` narrows no type, so where a check must
  narrow one for the lines after it, the test asserts with `node:assert`'s
  `assert` instead. Code outside `src/platform/` calls `node:` built-ins, which
  Bun implements; `src/platform/` holds what Bun does its own way, such as
  serving on `Bun.serve`. A test that starts chord or the fake agent starts it
  under `process.execPath`, the `bun` running the test. The helper scripts
  in `scripts/` run on Bun too, and the binary is `bun build --compile`'s,
  with OpenTUI's native library for its target embedded.
  A dependency goes into `package.json`, where a jsr package comes from
  `npm.jsr.io` under its own name (`bunfig.toml`, `.npmrc`). No `node_modules`
  checked in, no `npx` in scripts.
- **Versions are pinned for things that move.** A pre-1.0 package is
  exact-pinned (`@replit/codemirror-vim-core`); the rest use caret ranges, and
  `bun.lock` is committed.
- **The style is what the tools hold.** `tsconfig.json` holds the strict
  compiler flags, `eslint.config.ts` the lint rules, `lint/style.ts` what
  Prettier cannot express (blank lines, imports first), and
  `.prettierrc.json` the layout (80 columns, single quotes, JSX's too).
  `bun run lint --fix` then `bun run fmt` lays code out.
- **Logic lives where a test reaches it.** Reducers from runtime events to
  transcript state, key handling, history, completion, settings merge — pure
  modules with tests. Components only draw state and dispatch.
- **Tests never reach a real model or a real agent.** Drive the UI through
  `tests/ui/harness.tsx`, on OpenTUI's `testRender`; drive the session layer with a fake ACP agent in
  `tests/fixtures/` speaking the protocol over stdio. A live agent is for a
  person checking by hand, not for `bun run check`.
- **Comments say why, not what.** A doc comment on a type says what it is for.
- **Every action has a key.** Nothing on screen needs a pointer. A new action
  names its key in the same change, and the shortcuts panel (`?` on an empty
  prompt) lists it: an entry in `src/ui/shortcuts/keys.ts`, and, if a person may
  rebind it, an action in `src/ui/shortcuts/bindings.ts` that `keyCommand` matches
  and the entry names. `tests/ui/shortcuts/keys_test.tsx` checks
  against it every key `keyCommand` answers and every key the prompt and the
  permission prompt widgets act on; a widget-owned key needs its test too.
- **Commit messages carry no trailers** — nothing after the body. Conventional
  prefixes (`feat:`, `fix:`, `docs:`, `chore:`) with a scope where it helps.

## Checking the interface by hand

chord is a terminal program, so a check runs it in a real terminal of a known
size and reads the screen back as text:

```sh
tmux new-session -d -s chord-qa -x 120 -y 40 'bun run chord'
tmux send-keys -t chord-qa 'hello' Enter
tmux capture-pane -t chord-qa -p        # the screen as text; -e keeps colours
tmux kill-session -t chord-qa
```

Use a session name of your own and always kill it afterwards. Check at least
one narrow size (80×24) as well as a wide one. A check against a live agent
spends the owner's account: keep prompts tiny and say in the handover that you
did it.

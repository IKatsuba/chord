# The chord guide

Everything chord does, flag by flag and key by key. The
[README](../README.md) is the short tour.

A full-screen terminal client for coding agents that speak the
[Agent Client Protocol](https://agentclientprotocol.com) — Claude Code, Codex,
Gemini CLI, Cursor, fx, OpenCode and the rest — with everything people reach for
in Claude Code's own interface: permission modes, slash commands, `@` file
mentions, `!` bash mode, plans, diffs, history, resume, and a keyboard for all
of it.

## Why

Claude Code's terminal interface is the best one there is for working with a
coding agent, and it only talks to Claude. ACP separates the agent from the
interface, so the interface can be one program and the agent anything. chord is
that program: open source, one binary, one window, any agent.

chord is the open sibling of [Chorded](https://chorded.app), a native macOS
workspace for agent sessions driven by key chords. The two share a belief —
every action has a key, and nothing needs a pointer — and a mark, which chord
draws when a session starts. They share no code, no licence and no account.

## Install

```sh
npm install -g @chorded/chord
```

The npm package is a small shim around a prebuilt standalone binary for your
platform (macOS and Linux; arm64 and x64). There is no Node build of chord.
The macOS binaries are signed and notarised.

`chord upgrade` installs the latest version through the package manager
that installed chord (npm, bun, pnpm or yarn); `chord upgrade --version
<version>` installs that one, and `chord upgrade -l` lists them.

Or build from source with [Bun](https://bun.sh) 1.4.4 or newer:

```sh
bun install
bun dev compile --install   # compiles into ~/.local/bin/chord
```

## Use

```sh
chord                 # choose an agent here
chord codex           # any agent `chord agents` lists
chord gemini -C ~/src/app
chord --continue      # the default agent's latest session here, again
chord --resume <id>   # a recorded session, on its own agent
chord --resume        # pick an earlier session first
chord agents          # the agents chord can start: name, what starts each, and whether PATH has its CLI
chord -p "Explain src/main.tsx"                # the reply on stdout, then exit
git diff | chord -p "Review this" --output-format json
```

Each chord process runs one main session with its children. For sessions
side by side, run chord in separate terminal panes.

A new interactive start with no agent named opens `Select agent` before any
agent or session starts. It uses the current `chord agents` listing,
including settings-defined names. Your configured agent is highlighted
initially, or Claude Code by default; if absent from the list, the first row
is highlighted. ↑/↓ or j/k moves, Enter or 1–9 selects. Esc or ctrl+c quits
without starting a session. The choice is for this run only and is not saved;
the next unnamed interactive start asks again.

The list marks missing own CLIs `not found` but keeps them selectable.
Other entries are not checked for installation, login or readiness; choosing
an entry still uses the usual startup checks. Naming an agent, supplying
`--agent-command`, using `-p`, `--continue` or any `--resume` form skips the
agent picker. It also stays out when stdin or stdout is not a terminal;
those routes keep their usual default-agent and resume behavior.

Inside chord, `/resume` lists this agent's earlier sessions in this
directory, newest first, with when each was last used and its title, or
first prompt if untitled, after a child's name. A recorded team attempt without
a prompt can appear as `Team attempt: <saved name>`; it uses real recorded
times and claims no startup or success. Looking at quota alone adds no entry.
Labels wrap, never cut; ↑ ↓ read a row taller than the picker a line per press before moving on.
`❯` stays on its first line; edge arrows mark more above or below. The
picker stays within its room. Enter replaces main with the highlighted
session; Esc leaves it alone. A child open now says `open now`; Enter picks
it instead. ctrl+a lists every directory's, with paths from `~`; ctrl+a
again returns here. Each list opens from the top. Settings, MCP servers
and files stay tied here, so chord gives a command to open another
directory's session where it works. For another agent's sessions, run
`chord <agent>` and use `/resume`.

`chord --resume` with no id opens the same picker before any agent starts,
as `claude --resume` does; Enter opens what it picks, from any directory,
as its own `--resume` would, and Esc quits with nothing started.

`/clear` starts a new main session with an empty transcript. `/new` opens
an idle child of main on main's runtime and goes to it; `/new <agent>`
uses the named runtime. It starts as `open_agent` would with no model,
effort or mode named: the runtime's own model and effort, the settings'
mode. Its first turn is your first prompt to it. Main hears of the child
ahead of its next prompt; its running turn continues. `/new` followed by
a space lists the agents chord can start; Tab completes one. The child
belongs to main even when opened from another child's view, and closes
with `x`, main's `close_agent` or `/clear`.

An agent asking for permission or a form, or ending its turn, never takes
the view by itself. The status line names what waits, and ctrl+x a goes to
the agent that has waited longest, then the next on each press. An unseen
exit is news even when the agent was idle. A failure names its agent, such
as `✗ parser's turn failed · ctrl+x a to go`. Several failures count each
state separately: `✗ 1 exited · 1 turn failed · ctrl+x a to go`. Seen
failures leave the status line.
An asking task is named as its box names it:
`● Agent(Fix the tokenizer) · fake needs your permission · ctrl+x a to go`,
or `● main's task needs your permission · ctrl+x a` where it will not fit.
Forms and links read `asks for input`. The hint names the oldest open
permission in that session, otherwise its oldest form or link. With several
asking, `● N agents wait` counts a task as one agent. ctrl+x a reaches its
box through its owner session; the background summary keeps `● 1 task asking`.

ctrl+d and `/exit` quit at once, closing the main session and its children
and waiting for their agents to exit. chord prints a
`chord <agent> --resume <id>` for the main session if a prompt went to it.
It repeats `--agent-command` only when given as a flag; settings commands
are read again from their files.

If chord fails while drawing the window, a crash screen shows the error
and as much of its stack as fits. Any key gives the terminal back, prints
the full error and stack to stderr, and exits with code 1. A modifier
alone, a paste or the mouse leaves the screen open.

A resumed session shows its earlier prompts, replies and tool calls, an
edit with its diff, and the next prompt goes on in the same session. chord
keeps a record of every session a prompt was sent in, in its state directory
(`~/.local/state/chord/records/`), which `--continue`, `--resume` and
`/resume` read, and the past is drawn from it whichever way the agent
reopens the session. The id is the agent's own: for Claude Code, the one
`claude --resume` takes, so `--resume <id>` also opens a session chord never
saw, its past as the agent replays it.

`--resume` (`-r`) takes one id, or none for the picker. Repeating the
option prints CLI help and a parse error, then exits 2 before any agent
starts. As the id is optional, a word after `--resume` that names one of
chord's own flags (`model`, `c`) is not read as an id.

`chord -r <id>` uses the record's agent when none is named on the command
line; an id with no record goes to the default agent. A named agent that
differs from the record's is refused. With no agent named,
`--agent-command` overrides the default agent alone, so a record for
another agent is refused too.

An old `chord --resume w-<id>` command passes its id to the agent as any id
chord has no record of; the agent's refusal shows. Legacy files under
`windows/` are ignored and left untouched.

`--continue`, `--resume` and `/resume` can open a session already open in
another chord process. Both processes then use it, and their turns
interleave in its record; close it in the other pane before resuming here.

Command and skill completions, `/new` and `/team` completions, `@` and `@@`,
history search and `?` appear above the prompt. Status, leader-key hints,
agents and the background summary stay below. Opening or closing a list
normally keeps the same draft's prompt borders and permanent rows fixed.
In the [recorded cramped resize case](design/CHD-525.md), with a running
plan, four queued prompts and an eight-line draft, resizing from 80×24 to
80×25, selecting the sixth file and closing completion moves the prompt up
one row as agents grow from three rows to four.

Completion lists shrink to the available space and scroll to the selection.
With no visible row, completion navigation and acceptance are disabled,
including a pick waiting for file matching. Enter still submits the draft
normally. Completion resumes when a row is available again.

`@` opens the file finder; fuzzy matching starts at the first character
after it. ↑/↓ moves the highlight, Enter or Tab adds the file, and Esc
closes the list. While matching, typing continues and the previous list
stays. After 150 ms, a dim `searching…` marks its last row, keeping the
highlight visible. Only results for the current mention replace the list.

During a match, Enter or Tab waits for its first result unless you moved
the highlight, in which case it picks that row at once. A waiting pick is
dropped if the mention changes or you switch sessions; keys typed while
waiting go into the draft as usual. If nothing matches, Enter sends the
draft as typed and Tab does nothing.

`@@` completes agent names, offering the open recipients `send_message`
reaches from the picked session (see below). Task agents and unopened
sessions are absent; equal names appear once. Fuzzy matching starts at the
first character. ↑/↓ picks; Tab or Enter inserts `@@name ` without sending,
quoting names with spaces as `@@"bugfix 2" `. Esc closes the list. With no
recipients it says `No agents to mention`; an unmatched query says
`No matching agents`. In either case, Enter sends the draft as typed and
Tab does nothing. A sent mention is plain text to the picked session: it routes
nothing and attaches no file link. Single `@` still finds files.

In the prompt, option+←/→ (alt+←/→) moves by word; cmd+←/→ moves to the
current displayed line's start or end, including when text wraps. alt+b/f
also moves by word, and ctrl+a/e goes to the line's start or end. `?` on
an empty prompt lists the arrow shortcuts. In vim mode these editing keys
apply in insert mode.

cmd+arrows work only where the terminal passes them to chord:

- **Ghostty:** its macOS defaults send word moves for option+arrows and
  line moves for cmd+arrows.
- **iTerm2:** its default profile sends option+arrows, but uses cmd+arrows
  to switch tabs. The **Natural Text Editing** key preset maps cmd+←/→
  to ctrl+a/e. Keep **Treat Option as Alt** on (the default); off,
  option+arrows act as cmd+arrows and move to the line's ends.
- **Terminal.app:** option+arrows move by word; cmd+arrows send nothing
  to chord. Use ctrl+a/e for the line's ends.
- **tmux:** option+arrows work, but tmux has no super/cmd modifier. Use
  ctrl+a/e for line moves, or a terminal preset that sends those keys.

ctrl+g opens the prompt in your editor (`$VISUAL`, then `$EDITOR`, then
`vi`), run through your shell; what it saves comes back as the prompt with
the cursor at its end, as when recalling a sent prompt with ↑/↓ or ctrl+r.
Control characters from the editor, history or a paste stay in the prompt
and are sent as held. The box shows them as `^L`, `^?` or `<85>`; the
transcript's prompt echo and ctrl+r's match show no notation. A paste
removes escape sequences; C1 CSI (0x9b) also takes the byte after it.
An editor that exits with an error or is killed leaves the prompt as it
was, and the status line says so.

ctrl+v puts the image on the clipboard into the prompt as `[Image #1]`, at
the cursor, and Enter sends it after the text. So does the terminal's own
paste (cmd+V) where the terminal sends an empty paste for a clipboard that
holds only an image, as Ghostty does; one with nothing on the clipboard
changes nothing. A path to a PNG, JPEG, GIF or WebP file pasted or typed
into the prompt (`/…`, `~/…`, `file://…`, as a terminal writes a dropped
file) is taken the same way. Backspace after
the placeholder, or delete before it, takes it whole, and the image stays
behind. An agent that takes no images gets none, and the status line says
so. While the agent starts, ctrl+v says `X has not started yet`. That notice
goes when the agent starts; if it fails, `X did not start: …` replaces it.
Other paste failures after startup stay until the next key.

`/config` lists the agent's own settings for the session other than its
model and mode, such as Claude's effort, each with its value; Enter on one
lists its values and Enter on a value sets it.

Each session's transcript opens with a header: Chorded's mark in its
gradient, drawn in half blocks, and beside it chord's version, the agent and
the model the session started on, its directory and the keys to `?` and
`/help`; a resumed session's adds `resumed · <age> · <title>`, a child's
name before the title, or its first prompt if untitled. Titles wrap without
cutting. The picker and header keep the title read when opened. The
conversation grows down from the header;
once it fills the window the header scrolls away, and `home` brings it back.

Claude's work after a background task and codebuddy's unasked turns show as
working: `››› Working… (Ns · esc to interrupt)`, timed from the cycle's
first update, with `✻ working` in the agents list.
Its end notifies as a turn's end does. Esc interrupts it; a prompt sent
meanwhile goes at once and takes it over. Requests inside it are held
between turns, with ctrl+x a to answer. Claude's cycle ends when it reports
autonomous model usage; without that update it stays working until Esc or
a prompt.

Replies and messages render as markdown, wrapped to the window. Rows can
break at spaces or after `/`, `-`, `.`, `,`, `:` and `(`. Outside quotes,
list continuations hang under their item's text, including nested items and
two-digit numbers. Code blocks wrap long lines at their box edge. Tables
and code inside quotes keep their drawn rows, as do proposal and saved-team
previews. Once a code block's fence closes, its top border has `[copy]`
on the right; `sh` and `bash` blocks also have `[run]`. A block inside a
quote has no buttons, but the keys below still reach it.

`[copy]` copies the block's text, without its border, label, display wraps
or trailing newline. The status line says `copied N chars to clipboard`,
`sent N chars to the terminal's clipboard` over OSC 52, or
`could not copy: <reason>`, for 3 seconds. `[run]` puts all the block's lines
into the prompt in bash mode, stripping a leading `$ ` from each line.
Enter runs them as one script in the session's directory, with the output
held for the agent's next prompt. An existing draft stays untouched;
the status line says `The prompt holds a draft · ctrl+c clears it`.

ctrl+x b picks the newest code block on screen, or the newest in the
transcript if none is visible. ↑/↓ move between blocks across replies,
scrolling to show the picked one, whose border turns accent and buttons
bold. `c` copies and ends picking; `r` fills the prompt and ends picking
on an `sh` or `bash` block. Esc ends picking; another key ends it and acts
as usual, except the wheel and pgup/pgdn scroll and keep the pick. The
status line names the bound keys, or says `No code block to pick` if none
is available. Blocks in replies and agents' messages remain reachable
however far back; code in tool output, expanded summaries or the plan box
is pickable only while on screen. An open fence cannot be picked.

Tool-call headlines show every line, wrapped to the width with no cap:
a Bash heredoc is visible in full in the transcript. Continuation rows
start under the name, at column 3, and `⎿` results follow the last row.
A call awaiting your permission has a still, dim `⏺` and `Waiting…` above
any output it already has. Otherwise its agent's status decides: `in_progress`
pulses with `Running…`, and `pending` stays still with `Waiting…`.
Claude's Bash stays `Waiting…` after approval until its adapter sends
`in_progress` or the result.
Results under `⎿` show every line, wrapped to the width: MCP results,
Bash output, your `!` shell output, Codex plans and subagent work. Diffs
show every row, with long lines wrapped under their code. Read shows its
first three source lines, each wrapped, then `… +N lines (ctrl+o to expand)`;
ctrl+o shows the rest. Terminal output keeps its last three lines, wrapped.
When a call has no content of its own, its `rawOutput` supplies the result:
a string as text; an object's string `stdout`, `stderr`, `output` and
`result` fields in that order; anything else as indented JSON. On an object
with those text fields, a non-zero `exitCode` makes a call reported as
completed read as failed. The agent's own content takes priority. A
non-empty refresh replaces the shown output; an empty one keeps the last
text. The session record and `-p` output carry the same result.

Codex Guardian reviews show one dim `Guardian reviewing…` line while in
progress. When the agent reports Approved in its structured review status,
the review disappears, including in ctrl+o and after `/resume`; the agent's
record keeps it. Approved and in-progress reviews are left out of subagent
tool-use counts and a team's latest headline. Denied, timed-out or aborted
reviews, or reviews with an unknown or missing structured status, keep the
full `Guardian(Review)` block. This behavior has no setting.

An Agent call shows its description; ctrl+o shows the subagent's whole task
and work, with later messages as `← from <sender>` rows. A Claude subagent
ends `Done`, `Failed` or `Cancelled` by the reason its agent reports;
`Ended` means no known reason, and `Untracked` means the agent lost sight of
it and it may still be working. ctrl+o shows any error or explanation.
After Esc, a subagent that announced it can be cancelled stays running on
screen until its agent reports its end.
An approved Claude plan appears once, as the plan.
cursor's `cursor/create_plan` and grok's `x.ai/exit_plan_mode` show under
`⏺ Plan(<name>)`, or `Plan` without a name: overview, markdown, then each
cursor phase with its todos, then the top-level Todos, both as sent even
when they repeat. With no plan from grok, it says `grok has written no plan.`
An `Approve Plan` box asks whether to proceed. cursor offers accept or keep
planning; grok offers start implementing, keep planning, or leave plan mode.
↓ past the choices reaches Note; Enter there keeps planning with the text,
and ↑ returns to the choices. The note also goes with keep planning picked
from the choices; accepting or leaving sends none. Esc keeps planning
without the note. A tall Note pages inside the box with pgup/pgdn while
selected; elsewhere those keys scroll the transcript. The call keeps its
plan and shows `Accepted`, `Kept planning: <note>`, `Left plan mode` or
`Cancelled`. Plans and permissions share the box in arrival order, before
forms, questions and links. An unanswered request is never accepted.
Cancellation, withdrawal, closing or an unreadable request gets `cancelled`.

In Claude and Codex sessions, an MCP call reads
`server - tool (MCP)(key: JSON, …)`, with its arguments whole and wrapped.
Strings are quoted, with newlines written as `\n`; arrays and objects are
compact JSON. Until arguments arrive, or with none, it shows the name
alone. Calls to chord's own server keep their own rows, such as
`List agents` and `→ to @reviewer`.

`/theme` chooses chord's colours: Auto, Dark, Light, each of those two
colour-blind friendly, or in the terminal's own 16 colours. Moving through
the list shows the whole window in the highlighted theme; Enter keeps it and
saves it to your settings file, and Esc goes back. Auto, the default, asks
the terminal for its background as chord starts. chord never colours plain
text, so it stays your terminal's own, and `NO_COLOR` turns every colour off
whatever the theme.

`/vim` turns vim mode on for the prompt, and off again; the choice is kept
for the next start. The box starts in insert mode, where it types as ever,
and `-- INSERT --` or `-- NORMAL --` under it says which mode it is in. Esc
goes to normal mode, which takes `h j k l`, `w b e`, `0 $ ^`, `x`, `dd`,
`dw`, `cw`, `yw`, `yy`, `yiw`, `D`, `C`, `i a I A o O`, `u`, `p` and
counts such as `3w`, `d2w` or `2yy`; `p` puts yanked or deleted text.
An `[Image #N]` goes whole under `x` and `dw`. Enter sends from
either mode. Esc in normal mode does what it does without vim mode, so
interrupting a turn takes Esc twice from insert mode; an open list, picker
or panel still closes on the first Esc.

Permission requests appear over the prompt box: 1–9 picks an answer,
↑/↓ moves the highlight, Enter picks it, and Esc rejects. A long request
scrolls under its pinned title; long lines wrap, and the choices and key
hint stay whole inside the box. The request takes the room left, at most
half the window's rows. The transcript gives way first, then the agents
list folds into `… +N more`, and only then does the request body shrink.
With three answers and no asker row, it gets 6 rows at 80×24 and 20 at
120×40.
A member's asker row reads `tester · bugfix asks`, the name bold in its
colour and the team dim; between turns, `tester · bugfix asks · between
turns`. A child's stays `docs asks`.

Question, form and link headings name who asks, wrapped without cutting.
In a turn, main uses its runtime: `claude asks you 2 questions`. A task
or subagent uses its call heading, such as `Agent(Fix the tokenizer) · fake`,
in the accent colour. A long-lived child uses its name, bold in its colour;
a team member adds its team, dim: `tester · bugfix asks…`. Between turns,
main uses `main` and the heading ends ` · between turns`.

In a question's non-secret Note beside choices, option+←/→ (alt+←/→)
moves by word; cmd+←/→ moves to the displayed line's start or end, where
the terminal passes those keys. Typing, backspace and paste edit at the
cursor; pasted line breaks become spaces. Bare ←/→ and Tab still move
between questions; ↑/↓ moves between rows. Returning to a question or agent
keeps its note and cursor.

A permission, form, question or link arriving with no turn running leaves
the keys and draft in the prompt. Its asker row ends ` · between turns`, and
`ctrl+x a to answer` moves the keys into the box. The front status line
reads `● permission asked between turns · ctrl+x a to answer`, or
`● input asked between turns · ctrl+x a to answer` for a form, question or
link.
If `session:attention` is unbound, the box takes the keys at once. The
request waits until answered; closing the session or quitting rejects it.
A request still open when its turn ends, including a task's, is held
the same way: the keys return to the prompt and the box stays between turns.
It keeps its asking mark in the status line and agents list, reachable by
ctrl+x a until answered or withdrawn. With children open, ↓ from a box's
last active row moves into the agents list: a form's buttons, a question
step's last row or Submit's Skip, a permission's last choice, a plan's
Note, or a link's Decline. Answers, selections, notes and focus stay with
the asking agent; returning gives its box the keys where you left it.
While the list has the keys, the box keeps its height but hides its
highlight and key hints; a held box keeps `ctrl+x a to answer`.
A prompt sent while it waits queues as `› after your answer: …`; messages
from other agents wait too. After the answer, they wait for one second
without an agent update, up to five seconds, before going to the agent.

Held forms, questions and links keep `››› Waiting for your input… (Ns)`,
timed from when they asked. On a short screen their bodies fold under
`… N more lines`, keeping `ctrl+x a to answer` visible; that key opens the
box whole. A held permission scrolls instead, its rules naming no key
until ctrl+x a gives it the keys.

Once a permission has the keys, pgup/pgdn scroll an overflowing request by
a page, shift+↑/↓ by a row, home/end to either end. The wheel over the box
scrolls it too.
Dim rules count wrapped lines out of view: `↑ N lines above` and
`↓ N lines below · pgdn to scroll`, with your bound key in the hint.
When one request row or none fits, the count sits beside the title. You can
allow at any time, without scrolling to the end. Resizing may move the
view; the counts still say what is hidden, and every row remains reachable.

`-p` draws no window: it sends one prompt, with anything piped in after it
on a line of its own, writes the reply to stdout as it streams, and exits 0
when the agent ends its turn, or 1 with the error on stderr. Nobody is there
to answer a permission, so each one is refused and stderr says so. Nor
is anybody there to answer an agent's questions: each form is skipped
(declined), which an agent reads as its questions left unanswered and goes
on, with a `chord: <agent> asked: <question> — skipped (no one to answer
under -p)` line on stderr for each question, or for the form; a link to
open is cancelled. cursor's and grok's plan requests are answered
`cancelled`, including with `--dangerously-skip-permissions`.
`--permission-mode`, or `permissionMode` in the settings files, starts the
turn in that mode, and `--effort`, or `effort`, on that effort; one the
agent does not take is a `chord: could not start in <mode> mode, …` or
`chord: could not start on <effort> effort, …` line on stderr, and the turn
runs as the agent chose. `--dangerously-skip-permissions`, only with `-p` and never a setting,
allows every permission instead, each with a `chord: allowed <title>.` line
on stderr; with both, the mode is asked for and whatever the agent still asks
is allowed.
`--output-format json` prints one object at the end instead: `result`,
`session_id` (which `--resume` takes), `stop_reason`, `is_error`, and `usage`
and `total_cost_usd` when the agent reports them. An agent that reports its
tokens but no cost, as Codex can, gets a cost chord works out from the
model's price, with `cost_estimated: true` beside it; `/cost` says
`(chord's estimate)` after such a cost, and a context window chord took from
the model's data is marked `~` on the status line.
Except for dirac, `/cost` totals the session's earlier turns from its record
and this window, each turn counted once. Older records show
`Before <date>: $… as last reported`; turns whose spend could not be counted
from cost or tokens show
`Not counted: N turns`. The order is `Total cost`, `Before`, `Not counted`,
`This turn`, tokens, then `Session time`, with absent parts left out.
While the reported session's turn runs with none of its spend received,
`This turn:     counted when it ends` follows those marks, or the sentence
saying nothing is reported yet. A permission held inside the agent's own
cycle counts as a running turn too.

dirac reports running session totals: `/cost` shows the last tokens and
cost it sent, with a line explaining that reading and no per-turn figure.
When its provider reports no cost, chord prices each answer's growth in
the token total at the model that answered, sums it, and marks the cost
`(chord's estimate)`. A note names the price used, or says several models
were priced. Answers on models with no price are left out of the cost and
counted under `Not counted`; the token rows still show the whole total.
With no price for any answer, the cost says the provider reports none and
chord has no price for the model.

With more than one session, a task included, `/cost` adds a table headed
`This session`: main, children and team runs with their members, then the
total. Tasks sit under whoever started them; a team's tasks have separate
rows. Each row shows its own spend. Names and full notes wrap inside their
cells; cost and tokens stay aligned. A note with fewer than 20 cells of
room moves under the row's figures. `~` marks estimates in the table and
task summaries. Closed children stay counted, as do sessions cleared or
resumed in place, under `before /clear`. The table also carries dirac's
no-cost and missing-price notes.

## Settings

chord reads two settings files before it starts: the user's,
`~/.config/chord/settings.json` (under `$XDG_CONFIG_HOME` when that is set),
and the project's, `.chord/settings.json` in the directory the session works
in. The project's file overrides the user's, and a command-line flag overrides
both.

```json
{
  "agent": "codex",
  "agents": {
    "claude": { "effort": "high", "permissionMode": "plan" },
    "my-agent": { "command": "my-agent --acp" }
  }
}
```

| Key                            | Sets                                                 | Flag                |
| ------------------------------ | ---------------------------------------------------- | ------------------- |
| `agent`                        | the default agent and startup picker's initial highlight | `[agent]`           |
| `agents.<name>.command`        | the command that starts that agent instead of chord's own   | `--agent-command` |
| `agents.<name>.model`          | the model each of its sessions starts on             | `-m, --model`       |
| `agents.<name>.effort`         | the effort each of its sessions starts on            | `--effort`          |
| `agents.<name>.permissionMode` | the mode each of its sessions starts in              | `--permission-mode` |
| `agents.<name>.mcpServers`    | `false` passes no MCP servers; `true` overrides openclaw's default of none |                     |
| `teamSelection`               | preferences and allowlists for agent-selected team runs; see below |                     |
| `preferredNotifChannel`        | how the terminal is told chord waits on you          |                     |
| `theme`                        | chord's colours, as `/theme` chooses them; user's file only | `/theme`     |
| `editorMode`                   | `vim` for vim mode in the prompt, as `/vim` leaves it; user's file only | `/vim` |
| `mouse`                        | `false` leaves the mouse to the terminal; user's file only |                     |
| `copyOnSelect`                 | `false` leaves a drag's selection for ctrl+c to copy (on by default); user's file only |                     |
| `mcpServers`                   | MCP servers configured for the agent, as `.mcp.json` writes them |             |

When a turn ends, a permission is asked or the agent asks you to fill in a form
or open a link, chord tells the terminal, so a window in the background can say
so. `preferredNotifChannel` is `auto` by default: OSC 9, a desktop
notification, in iTerm2, WezTerm, Ghostty and kitty;
OSC 777 in foot; the bell elsewhere and inside tmux. `bell`, `osc9`, `osc777`
choose one, and `off` turns it off. A turn you interrupt with Esc is not
announced. The notification names the agent:
`fake needs your permission: Write notes.txt`.

chord also reports the whole window's status through the
[Program Status Protocol](https://www.superlogical.com/rex/docs/build/program-status)
(OSC 7501), always on, independently of `preferredNotifChannel`. One root
record with `app=chord` covers main and its children.
Its `title` names the main session, even with a child picked:
the agent's own session title, updated when it renames the session and
restored on resume. Until the agent gives a title, it uses the first prompt
on one line (`!ls` for that shell command), as `/resume` does.
With neither, the title is absent; `/clear` resets it.
The title takes at most 192 UTF-8 bytes (256 in base64 on the wire).
The first state present wins: `blocked`, `error`, `working`, `done`, `idle`.
A permission, form or link makes it `blocked`, with kind `permission`,
`question` or `auth`; an exit, failed start or failed turn makes it `error`.
A running turn is `working`; a monitor or task between turns does not count.
A turn ending is `done`, except one cancelled with Esc or started by a
monitor's event.

Completed turns, failed turns and failed starts stay reported until you
visit their agent, press a key while it is shown, or start its next turn.
An exited agent stays `error` until it restarts or its session closes.
Only `blocked`, `done` and `error` carry a message, with the notification's
wording, such as
`fake needs your permission: Write notes.txt`,
`fake is waiting for your input` or `fake's turn failed`. Messages take at
most 2048 UTF-8 bytes. Both fields cut between graphemes, keeping joined
emoji and accented characters whole.
chord clears the status on quit, a signal or a crash, and while your editor
has the terminal, then reports it again on return.

Reports do not wait for a terminal capability reply and have no tmux
wrapping: inside tmux they do not reach the outer terminal. A terminal
without support shows nothing. Support includes
[iTerm2 3.7.5+](https://iterm2.com/downloads.html),
[cmux](https://cmux.com/docs/changelog) and Rex; kitty's support is in
0.50, not yet released. The Ghostty app does not yet show it.

chord sends the main session id to the terminal through OSC
1337 `SetUserVar=chord_session=<base64 id>`. The value is empty at start
and after `/clear`, until the first prompt is saved. A resumed or continued
session sends its id once open, as does a `/resume` pick. The value stays
when chord exits, including on a signal or crash. A launcher such as
Chorded can keep it and reopen with `chord --resume=<sessionId>`.
A named agent must match the record. Use `=`: a separate id starting with
`-` reads as options. An id spelling a chord option name (`-r`, `-c`, `-m`,
…) is not taken even with `=`.

iTerm2 and WezTerm keep this variable (`user.chord_session` in iTerm2);
other terminals ignore it. Inside tmux it reaches the outer terminal only
with `set -g allow-passthrough on`; several panes overwrite the same
variable, with the last write kept. This report is independent of
`preferredNotifChannel`.

`theme` takes Claude Code's ids: `auto` (the default), `dark`, `light`,
`dark-daltonized`, `light-daltonized`, `dark-ansi` and `light-ansi`. It is
about your terminal and your eyes rather than a project, so it is read only
from the user's file, and one in a project's file is reported and left out.
`/theme` writes it there, keeping the file's other keys. `editorMode`,
`normal` (the default) or `vim` as Claude Code names them, is read from the
user's file alone for the same reason, and `/vim` writes it there the same
way.

chord reads the mouse, so the wheel and the trackpad scroll the
transcript (or an overflowing permission request), and a drag selects text.
Release copies it through the system clipboard, or OSC 52 over SSH;
the highlight stays until a key or click. In replies and messages, a copied
paragraph, heading or list item joins its wrapped rows at any window width.
List markers and hanging indents do not copy; a list inside a quote keeps
its markers. Source soft breaks join with a space; hard breaks stay newlines.
Code outside quotes copies without its border, language label or padding;
a line wrapped at the box edge copies whole. Tables and code inside quotes
copy as drawn, borders included. Blank rows between blocks and loose-list
items copy as lines holding one space. When dragging from a nested item to
an outer one, move along the outer row before releasing so the selection
reaches it.
Clicking the prompt takes the keys back from the agents list or background
summary without changing which agent receives your typing. A picked child's
name and colour stay on the border. A permission, form, question, picker or
ctrl+r search keeps the keys when you click the prompt.
`"copyOnSelect": false` leaves the copy to ctrl+c. To use your
terminal's selection, hold its modifier while you drag: option in iTerm2,
fn in Terminal.app, shift in most others. Inside tmux, the wheel and drags
reach chord only with `set -g mouse on`, and over SSH a copy reaches
your clipboard only with `set -g allow-passthrough on`. `"mouse": false`,
read from the user's file only, leaves the mouse to the terminal.

### Keybindings

`~/.config/chord/keybindings.json`, beside the settings file, rebinds
chord's keys. It has the shape of Claude Code's `~/.claude/keybindings.json`
and shares its action names, so a block copied from there means the same
here; chord never reads Claude Code's file itself.

```json
{
  "bindings": [
    {
      "context": "Chat",
      "bindings": {
        "enter": "chat:newline",
        "ctrl+s": "chat:submit",
        "ctrl+g": null,
        "ctrl+x ctrl+e": "chat:externalEditor"
      }
    }
  ]
}
```

A key bound in a context replaces what it did there, `null` takes it away,
and a chord is keys separated by spaces, each within 3 seconds of the one
before. The actions are `chat:submit`, `chat:newline`, `chat:steer` (Tab),
`chat:cancel`, `chat:cycleMode`, `chat:externalEditor`, `chat:imagePaste`,
`history:previous`, `history:next` and `help:toggle` in `Chat`;
`app:toggleTranscript`, `history:search`, chord's own `session:attention`
and `codeBlock:pick` (ctrl+x b) in `Global`;
`codeBlock:copy`, `prompt`, `previous`, `next` and `cancel` in `CodeBlock`;
chord's own `agents:close` (`x`) in `Agents`, where it closes an agent
in the agents list or stops an item in the background view;
`autocomplete:accept`, `dismiss`, `previous` and `next` in `Autocomplete`;
`historySearch:next`, `accept` and `cancel` in `HistorySearch`;
`confirm:no` in `Confirmation`; `help:dismiss` in `Help`; `select:cancel`
and `select:toggleScope` (`/resume`'s ctrl+a, chord's own name) in `Select`; and `scroll:pageUp`, `pageDown`, `lineUp`, `lineDown`, `top`
and `bottom` in `Scroll`. ctrl+c and ctrl+d cannot be rebound, nor can the
keys inside lists, forms and vim mode. An unknown context, action or key,
and a key that would mean two actions at once, such as a key the
transcript scrolls on bound in `Chat`, is left out and named as a
warning in the transcript and on stderr, and the status line counts them; the
rest of the file still applies. The `?` panel and hints name the bound keys.
`session:new`, `session:next`, `session:previous`, `session:goto1` to
`session:goto9`, `session:list` and `session:close` went with tabs in
0.58.0. A binding to one is ignored with a warning saying so; the rest
of the file still applies.
The panel combines the newline keys as `shift or \ + enter`; after a
backslash, use the key bound to send. It also lists `any key` to quit the
crash screen; that key cannot be rebound. When the panel does not fit
above the prompt, a dim rule counts the lines above or below the view and
names the scroll key. pgup/pgdn page it, shift+↑/↓ move a row, home/end go
to either end, and the wheel over it scrolls it. Otherwise those keys
scroll the transcript. The panel opens at the top and keeps its place
across a resize. At very narrow widths, rows are cut rather than wrapped.

The keys work on a Russian layout too, the defaults and the file's alike: a
press that does nothing as typed is read as the US key in the same place,
so ctrl+ч is ctrl+x, `а` after it goes to what waits on you, and vim's
normal mode moves on р о л д. Text is never read again: Cyrillic typed in the prompt,
a form, the search line or vim's insert mode stays as typed, and a key the
file binds in Cyrillic is its own. Punctuation a US layout also types stays
itself, so on "Russian – PC", where the key in `?`'s place types `,`,
shift+7's `?` opens the panel. In a terminal speaking the kitty keyboard
protocol (kitty, Ghostty, WezTerm, iTerm2 with CSI u on), every key is
found on any layout, Greek, Ukrainian or Hebrew as well, by the key in its
place that the terminal names, so there the key in `?`'s place opens the
panel on an empty prompt too, and types its `,` after a draft.

chord hands the agent MCP servers for each session it opens, new or
resumed, from three places, each over the one before: `mcpServers` in the
user's settings file, the `.mcp.json` in the directory the session works in
(the file Claude Code and other tools share), and `mcpServers` in the
project's `.chord/settings.json`. A server named twice is the later one,
whole. Each is written the way `.mcp.json` writes it:

```json
{
  "mcpServers": {
    "filesystem": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "."], "env": { "DEBUG": "1" } },
    "docs": { "type": "http", "url": "https://mcp.example.com/mcp", "headers": { "Authorization": "Bearer …" } }
  }
}
```

A server started as a command has `command`, and may have `args` and `env`;
one reached over the network has `type` (`http` or `sse`), `url`, and may
have `headers`. Unless `agents.<name>.mcpServers` is `false`, an agent
gets stdio servers, and HTTP, SSE or ACP only when it advertises them. `false` sends none, chord's own included;
openclaw defaults to it because its bridge refuses per-session servers.
Set `agents.openclaw.mcpServers` to `true` to use the transport filter
instead. The rest are held back, chord's own among them, and each
session says at its start, in a warning line, which ones were not passed
to its agent and why; a task agent's line is in its parent's turn, named
as the task. While the agent starts, `/mcp` shows only
`<agent> is starting: chord has not passed it MCP servers yet.`
Once the session exists, it lists each server's name, its transport, its
command or URL, or `not passed` for one held back, with why under the
list, and the file that defined it; Esc closes it. It does not show `env`
or `headers`. Whether the agent then connected to the ones it was passed,
ACP does not say, and neither does `/mcp`. chord only reads these
files; it never writes `.mcp.json` or the agent's own configuration. A
server that is wrong is named with its file and left out, and the others
still count; a `.mcp.json` that is not a JSON object is named and ignored.
`/mcp` says under its list how many servers each file lost that way.
`-p` passes the same servers.

Beside them, every session the window opens gets an MCP server of chord's
own, named `chord` (or `chord-2`, … where a passed user server has that name),
when its agent takes MCP over HTTP and is not set to take none. chord serves
it on the loopback while the window is open, and each session reaches it with a
token of its own, so nothing else on the machine can call it. Its tools let
an agent see what it could start: `list_agents` names every agent chord can
start and the models and modes of those already read, or, given an agent's
name, that one's, starting it briefly to read them if no session of it is
open;
`list_sessions` names the main session, its id, runtime, model and open
long-lived agents. `spawn_task` starts a task agent: another agent, on any
runtime chord knows and a model it offers, does one job. Its caller's title
names it; its agent's session title is never shown, even resumed as main.
Its work draws in its parent's turn as a subagent's block does,
`Agent(<name>) · codex · gpt-5.3-codex`. Its ended block shows reported tokens and cost:
`Done (5 tool uses · 2.0k tokens · $0.0125 · 13s)`; unreported parts are
left out. In a group such as `Running 2 agents…`, a row that does not fit
wraps behind `│`, keeping its model, tokens, cost, tool uses and time.
Its permission requests, forms and links come to you
in the parent's view, and what it tells its parent with `send_message`, its
one tool, and the report its first turn ends with reach the parent as
messages, drawn as a `←` row: a turn of the parent's, or, while one runs,
what the task tells it goes into that turn, and the report waits behind it
the way a prompt does. Every agent chord opens but a task has `spawn_task` and
`list_agents`, so a long-lived child starts task agents of its own, drawn in
its own turn and closed with it; a task starts none. Esc stops the turn's
task agents with it, and they
send no report; `/clear` closes them with the session it lets go. A task
asked for a model its runtime refuses fails before it starts work. Asked
for an effort too, as `list_agents` lists them, it starts on it, and its
block says it after the model; one the runtime does not take leaves it on
the runtime's own, which the block says instead, and the refusal is a line
in the parent's transcript and in the answer, which waits for the task to
be up.

`open_agent` opens a long-lived agent the same way, with the prompt as its
first turn, a message from `main`. Its name cannot contain `"` or a control
character; a refusal names the character. Task names are unaffected.
While a session has children, a list of its agents sits under the status
line, `main` and each child in the order it opened, each child in a colour
of its own. Each agent has one row, with no session title, including team
leads and unfolded members.
Each row has its runtime, model, effort (`open_agent` takes one as
`spawn_task` does) and state: `● permission 17s`, `✻ working 41s`, `◦ idle 3m`,
`✗ exited` or `✗ failed to start`. Asking counts from the request, working
from the turn's start, idle from when it stopped. Unseen news is a separate
column: `✗ turn failed`, `✓ new reply` or `← new message`, cleared when
you open the agent. A failed turn leaves the agent open and idle;
`✗ failed to start` means it never came up, `✗ exited` that its process
is gone. Folded teams use the same words and clocks.
`working` uses the theme's accent, dimmed; in `dark-ansi` and `light-ansi`
it uses dimmed green, keeping it apart from the permission warning's
yellow. `idle`, `✓ new reply` and `← new message` are dim; a permission
keeps its warning colour. `/team show` uses the same colours.
As room narrows, effort, model and the mark's words give way in that order;
its glyph stays. Names and state words wrap without cutting, their
lines counted toward the list's limit. In a short window, the list folds
down to one agent row and `… +N more`, staying there until the transcript has rows
again. The background summary stays whole. ↑ ↓ scroll a row taller than
the list by line before moving on. ↓ on an empty prompt that is not walking
history moves into the list, where ↑ ↓ or j k pick; Enter, Esc or ↑ from
the first row returns the keys to the picked agent. Its chat fills the
window, the box takes its colour and name, and the status line its model,
effort and context: what you type goes to it as your own prompt.
↓ on the last line of a draft sets it aside with that agent: the field
empties, and ↑ brings back its text, images, bash mode and cursor. One more
↓ enters the list, so ↓ ↓ leaves an agent with its draft kept. On return
the field stays empty; ↑ shows the newest kept draft, then older ones,
then sent prompts. While walking history, ↓ steps toward the field before
it can set a draft aside. Editing a kept draft keeps the edit in its place;
sending it or clearing it with ctrl+c removes it. Sending another prompt
or using `/clear` leaves the kept drafts. In vim normal mode, j and k do
the same as ↓ and ↑ at the last and first lines.
The chat, status line, model and config pickers, image-paste refusals and
command reports name the picked agent's runtime, including while it starts,
stops or fails to start.
`send_message` from main reaches its open long-lived children and team
leads; from an ordinary child, its parent alone. Teams' recipients are
described below. Each message is a turn of the recipient's, as many as they
trade; `list_sessions` gives the main session's children. `@@` completes
these recipients' names in the prompt without sending them a message. A
message to a working Claude or Codex session goes into its running turn
through ACP's `_session/steering`, drawn among its calls. Claude waits for
the tool calls open when the message arrived to end, so steering does not
cut them off; calls opened later can still be running when it goes in.
In the recipient's view, each held message waits above the prompt as
`← from @main · after the running calls: …`, in arrival order, until it
goes into the turn and leaves the queue. The agents list marks a recipient
in the background with `← message from @main`, as for any queued message.
Codex takes it at once, since its steering does not cut calls. While the
turn waits on your answer to a permission, form or link, it waits under the
working line as `← from @main · after your answer: …`. After your answer,
it goes in or returns to `after the running calls` if those still run.
A runtime without steering takes it as the next turn, as the queue
under the working line shows. Should the message reach the agent just as
its turn ended, and the agent start a turn of its own with it, as Codex's
adapter does, chord cancels that turn at once, closes it with a dim
`Interrupted · the agent started this on its own` line, and sends the
message as the next turn. A monitor's events wait for the turn's end.

Enter during a turn queues your prompt until the turn ends. Tab sends the
whole message into the running turn where the agent supports it, without
stopping the agent: text, pasted images and `@path` links. Named image files
are read first, as with Enter. Earlier Enter-queued prompts stay queued.
The box clears, and your message appears as a plain `›` row among the
turn's steps. A held message waits as `› after the running calls: …` or
`› after your answer: …`, with an open question taking priority over calls.
Once sent to the agent, it shows `› into the running turn: …` if unanswered
for 500 ms, or at once if its held row was already showing. Esc takes held
messages back into the draft; one already sent to the agent stays. A
refused or late message becomes an ordinary queued prompt, including an
image Codex refuses on a model without image input. If it started its own
turn, chord cancels that turn with
`Interrupted · the agent started this on its own; your message goes as the next turn`.
On an agent without steering, Tab leaves the draft and sends nothing; the
status line says so for 3 seconds and names the key that queues it. Tab
does nothing with an empty box, no running turn or in bash mode; an open
`/`, `@` or `@@` list keeps Tab for completion. Rebind it with `chat:steer` in
`Chat`.

A child that waits on you is named on the status line, ctrl+x a picks it, and
its permission box opens there. `x` in the list closes the picked child, a
second time while it works or waits, and chord tells the parent so;
`close_agent` closes one from the parent, and a message to a closed one is
refused. A child whose agent exits, or whose turn fails, is news to its
parent too: a `← from chord` message, a turn of the parent's, says
`parser's agent exited: <the end of its stderr>. open_agent opens it
again.`, or that its turn failed and why, so a parent waiting on a report
does not wait for ever. A session holds eight children at most, a team's
lead counting as one and its members as none. `/clear` with a child
picked is refused; on `main` it closes the children with the session.
`/clear` and a `/resume` pick forget which children were closed, so a
message to a resumed session's former child is refused as closed when the
session was left. Team run numbers stay taken for this process, including
across `/clear` and `/resume`.

A team saved in `.chord/teams/<name>.md`, or in `teams/` beside your
settings file for every project, takes a job from the session you talk to:
say "hand it to bugfix" and the agent calls `run_team`, which chord draws
as `Team(bugfix) · claude · opus` with the job under it. `list_teams` names
the saved teams and their open runs, with known opaque IDs in its top-level
`runs` list; per-team run-name lists remain. It also exposes the saved shared
body, lead/member instructions and effort so the launching agent can read the
team's requirements before starting it. Team/member names cannot contain
`"` or control characters; a saved file with one appears with a problem
line in `list_teams`. The team's lead is a long-lived child
named after the team, on the lead's runtime, model, effort and mode; a second run
is `bugfix 2`, even if the first was closed. Its first prompt is the team's
instructions, drawn as one line (`bugfix's instructions for the lead · 58
lines`, ctrl+o for all of them), then the job as a message from `@main`.
The lead's `open_agent` takes a member's name and opens only the run's frozen
members, on their runtime, model, effort and mode (`Open(tester) ·
claude · sonnet · high · acceptEdits`); an effort the runtime does not take
leaves the agent on its own, which the answer and the agent's transcript
say; its `send_message` reaches main, its members and
the other runs' leads, and each message to main is a turn of main's. A
member messages its lead and the team's other open members by name,
directly. In the list the lead's row reads `team · claude · Opus` and its
open members are nested under it (`├─ tester`); when the list does not fit
its rows, each team folds to its lead's row, `team · claude · 4 agents` and
its most urgent state with the member's name (`● tester: permission 12s`)
in that state's colour, and the first unseen mark beside it. The team you
are in unfolds. A picked member's box reads `tester · bugfix`; its
permissions are yours to answer. The notification says
`tester (bugfix) needs your permission`, and with two
runs open the status line says which run's `tester` asks. `x` on a lead
closes the team, members and all, twice while any of it works, and chord
tells main; a member closed tells the lead, and a lead whose agent exits
closes its members and tells main.

A team is made by asking for one: the agent you talk to calls
`propose_team`, and chord draws its proposal as `Team(bugfix) · proposal`,
a row per agent with its runtime, model, effort where any agent sets one,
mode and role, with runtime, model and role wrapped under their columns,
a mode that skips your ok in the warning colour, then how the team works
in full. A box shaped like the permission box asks `Save team bugfix?`: for
this project (`.chord/teams/bugfix.md`), for every project
(`~/.config/chord/teams/bugfix.md`), or no, tell the agent what to change,
which Esc picks too. chord writes the file, never the agent; the call ends
`Saved to …` or `Not saved`, and your next words go to the agent. A
proposal under a saved team's name is `Team(bugfix) · change`, its changed
rows marked, a changed effort or mode with the one it had (`high was
medium`), and its body's change
counted and drawn as a whole, wrapped diff, and saves back in place.

`/team` is chord's own command for teams, and talks to the session you
opened whatever agent is picked. `/team` alone (or `/team list`) opens the
teams picker: each saved team with its size and runtimes, where it is
saved, `✻ working 6m` or `✻ 2 runs` while it runs in the window, and its
description, and a file that is not a team with its first problem. Enter
puts `/team run bugfix ` in the box for you to type the job. `/team new
<words>` asks the agent for a team through `propose_team`; to change one,
ask the agent in plain words, and it proposes the change against the saved
team through the same tool. `/team show bugfix` reports the team under the
command, and while it runs each agent's state, unseen mark and latest call or
message. `/team show <run ID>` inspects a recorded selected run's receipt
without a model turn or relaunch; its observations are historical, with current
state unknown. Cells wrap without cutting.
`/team run bugfix <job>` hands it your words as
they are, drawn as `run_team`'s `Team(bugfix)` row, with no turn of the
agent's; the agent hears of it with your next prompt.
Picker Enter prepares that same direct run, preserving saved composition.
`/team stop bugfix` closes the run and its members at once, and chord tells the
agent. A team's name is completed after `show`, `run` and `stop`.

### Resource facts and team selection

`get_budgets {agents?: string[]}` reads Claude Code and Codex usage limits
when called, in parallel, waiting up to 10 seconds per provider. Main and
long-lived agents can call it; task agents cannot. Omit `agents` to read both;
an explicit list filters by runtime IDs from `list_agents` (at most 128 IDs,
each 1–128 characters). `[]` reads none. A runtime with no reader returns an
unavailable reason without probing or installing it.

The answer is `{readAt, providers}`. Each provider has `agent` and either
`windows` or an `unavailable` reason. Each window has `name`, `usedPercent`,
`windowSeconds`, `resetsAt` and `models`; missing values are null. `readAt` is
the call's time, not proof of when the provider observed usage. Preferences,
active work, account identity and freshness states are not part of the answer.
Each call reads anew; there is no background collection or retained interest.
Old cache files under `~/.local/state/chord/resources/` are left untouched and
are no longer read or written.

The `Resources` block shows a `Read` line, then each provider's windows with
percent used, reset and models, or its unavailable reason. Unknown values stay
unknown; a provider with no windows says `no windows reported`. An empty answer
says `No providers read.` An answer recorded in the old format shows only
`Recorded in an older format; not shown.`, including with ctrl+o; its original
JSON remains in the session record.

Production readers try any installed version on `darwin-arm64`: Codex through
its unmodified official PATH npm launcher or native binary, and native Claude
Code through Agent SDK 0.3.311's experimental getter in an isolated worker.
The npm Codex launcher needs existing Node. Missing executables, unsupported
targets, custom ACP commands and failed or malformed reads return unavailable
reasons. Chord installs no provider and adds no login or credential reader.
Direct ACP remains supported on existing release targets.

The Claude getter may change or disappear. Readers send no inference prompt,
but provider-managed startup/auth/cache/hooks/telemetry effects can occur. A
read is not a zero-billing or capacity guarantee. Codex's client has uncapped
incomplete-frame buffering: a deadline does not cap memory. Subscription
percentages are never added to API dollars. There is no quota enforcement,
payment-source switch, paid fallback, scheduler or migration of running work.

Existing team instructions can request resource-aware selection. For example,
put ordinary text in the team's shared body:

```text
Before handing this team a job, read its role instructions and list_agents.
Pass this team's runtime IDs as agents to get_budgets. Consider each applicable
quota window and time to reset; missing capacity stays unknown. Choose
supported settings for this run, preserve every role and instruction, explain
uncertainty, and call run_team with selection.
```

The launching agent reads those instructions through `list_teams`, requests
facts when relevant, then uses normal `run_team` overrides. Chord does not
interpret or enforce this prose, require a quota read or add an opt-in field,
hidden prompt or extra selection turn. Without such instructions, selection is
not required. Human direct runs keep saved composition.

`teamSelection` optionally supplies preferences and selected-run allowlists in
the existing user/project settings, for example:

```json
{
  "teamSelection": {
    "intent": "balanced",
    "constraints": { "agents": ["claude", "codex"] }
  }
}
```

`intent` defaults to `fixed`, retaining saved choices. `balanced` asks the agent
to consider applicable windows and time to reset with reserve; `economy` prefers
lower known monetary spend, without converting quota to dollars. `prefer` uses
soft `prefer.agent` and nullable `prefer.model` fields. `constraints.agents`,
`constraints.models.<agent>` and `constraints.modes.<agent>` are exact
allowlists: omitted means no added restriction, empty means no allowed choice.
Preferences are not returned by `get_budgets`. Allowlists constrain every
effective role of calls carrying `selection`; direct
`/team run` and `run_team` without selection keep saved composition and existing
startup checks. They are selection policy, not global security controls.

Project settings override user settings: `intent` replaces, `prefer` merges by
key, `constraints.agents` replaces, and model/mode maps merge by runtime with
each runtime's list replaced. Selected admission rereads current policy; invalid
selection settings or unreadable/unparseable files refuse it. An unopened member
can therefore be refused after a policy edit; running work is untouched.

For a selected run, the agent calls normal `run_team` with optional
`selection: {reason, lead, members}` after reading the saved requirements and
applicable runtime facts. `reason` is required, nonblank and at most 500
characters; `lead` and each named member may
set `agent`, `model`, `effort` and `mode`. Unknown selected fields/member names
are refused. Same-runtime omissions inherit saved values. A runtime switch
requires explicit destination model/mode and effort if the saved role requested
it. The runtime must confirm the model/mode; no permission ordering or mode
equivalence is inferred. Effort remains a soft request, with actual value and
refusal note visible. The agent must preserve role instructions and hard prose
requirements; Chord checks structured choices, not arbitrary prose.

Selected runs freeze composition and instructions without rewriting team files.
Lead and later members must pass current policy and observed runtime/model/mode
checks before their first job. Preflight refusal starts nobody. A failed lead
attempt is closed without its first job; its safe ID/refused receipt may remain
in the caller's record even if no lead session record opened. Later member
refusal leaves existing work alone and updates that run's receipt. Cancellation
or caller replacement revokes pending launch authority; a timeout is not proof
nothing started. Inspect `list_teams` or the known run ID before retrying.

Receipts distinguish saved, planned and observed configuration, reason and
per-role planned/confirmed/refused state. `run_team` records no budget read or
budget warnings. Earlier receipts keep their recorded read and warnings; a
receipt without a read shows no `Read` line. Missing actual
runtime stays unknown in older receipts; runtime identity proves no account or
auth identity. Replay does not reopen work. An actual receipt without an ACP
call appears as `Recorded Team receipt (<name>)`, with Chord provenance and
current state unknown; inspection also labels it historical. Same-run revisions
show the latest valid receipt, and genuine ACP linkage replaces that fallback
with one ordinary Team row. No prompt or successful startup is invented.

`monitor` runs a command in the background for the agent that asks, a
session's or a long-lived child's, and each batch of lines it prints reaches
that agent later as a message: a turn of its own, drawn `← from dev server errors
· monitor` with the lines as printed, folded after six. Its end is one more,
`· exit code 1`, `· timed out`, `· flooded` or `· stopped`, with chord's
sentence last. A turn an event starts does not ring the terminal when it
ends. `timeout_ms` is a hard stop: set it longer than the whole command's
work, including a loop's whole length and a margin. `stop_monitor` and
`list_monitors` are the agent's own. A resumed session draws its events
again and names monitors left running. It also tells the agent at once,
in a turn of its own, each monitor's id and description, that it was stopped
and not restarted, and to start it again if still needed. A monitor
reaching its timeout is a stop:
`■ timed out after 1h`, dim, including its transcript message.

Monitors, `spawn_task` tasks and subagents from Claude, Codex and Cursor
share the `background` summary under the agents list, stoppable or not.
These subagents have kind `agent`; background Bash is not listed.
opencode, codebuddy, fast-agent, qwen and grok's subagent forms are not
covered by this view yet.
The summary names whose subagents they are: `main's 2 agents running` or
`main's 2 agents and tester's agent running`.
The summary counts the main session's items, including its children's and
team members', by state: asking, untracked and running, including stopping.
It wraps without cutting text. From an empty prompt, ↓ past the
agents reaches it; Enter opens the background view above the prompt, full
width in the pickers' rounded frame in the permission colour. It is as tall
as its rows, at most half the screen; the prompt, status line and summary
stay visible. Rows show name, kind, state with time and owner, oldest first.
A monitor's kind includes its id, `monitor · m25`, to tell same-named rows
apart. The kind and state cells wrap, keeping every part, including
monitor events.
↑ ↓ or j k move between rows. A row taller than the frame scrolls one line
at a time before moving to the next row. Its `❯` stays on its first line;
a dim `↑` in the gutter stands in when that line is out of sight. Resizing
or reopening starts it from its first line again.

An agent row reads `running`, `● permission` or `● input`; `● waiting`
means it needs action but no request reaches you. Every ended item leaves
the list at once. `? untracked` stays, even past the next prompt:
the agent lost sight of the subagent, which may still work. Its summary reads
`? main's agent untracked`.
`x` stops the focused item alone, without confirmation; an agent reads
`■ stopping` until its agent reports the end. A stop that cannot be sent
says `could not stop: …` in place of the hint; an agent without a stop says
`this agent offers no stop`. The hint and error wrap under the rows; the
whole error stays, with its line breaks kept. At the half-screen cap, rows
give way first, then pgup/pgdn scroll an error taller than its remaining
room. In a detail, a tall error leaves only the description line, and
pgup/pgdn and home/end page the error alone. Moving to another item clears
the error and restores the detail. An ended or stopping item ignores `x`.
Esc in the transcript leaves individually stoppable subagents running.

Enter on a monitor row opens its detail in place of the rows, titled
`Background · m2, 2 of 2`: its description, state and event count,
`started 3h 46m ago`, timeout and owner, then `$ ` and its command, and
`← ` and the last event batch with how long ago it came, or `← no events yet`.
Enter on an agent or task row opens its detail too: its name and state
stay under the title, then its whole task and work as ctrl+o draws it.
It opens at the end and follows live. pgup stops following; End resumes.
From one line above the end, new output or a resize starts following again.
A short room shows one work row with its hidden-line count, or only the
count when no work row fits. The name and state give way to keep that count.
pgup/pgdn and home/end scroll the detail; ↑ ↓ or j k step between items.
← or Esc returns to the list; a second Esc closes it.
Any item ending with its detail open stays shown until you leave it:
the title adds `· ended`, its end state appears, and `x` does nothing.
A monitor shows chord's end sentence. Enter in a detail picks the owner
and scrolls to its call or subagent block; a folded block stays
folded, and a missing call leaves the view open.
A new request taking the keys hides the frame until answered, then it
returns where you were reading. Over a held request, it takes that box's
place; ctrl+x a closes it and gives the request the keys. When a list row leaves,
`❯` moves to its replacement or the row above; the last row leaving closes
the view.
An agent ending after the turn that announced it leaves a line in its
owner's transcript: `✓ Run tests · agent · done in 4s`,
`✗ Run tests · agent · failed after 22s: tsc exited 2` or
`■ Run tests · agent · stopped with x after 43s`. A resumed transcript keeps
`stopped with x`; older records say `stopped after`. A task's `· report` or
`· failed` message is its end line. A task stopped after its announcing
turn ended gets a dim line instead: `■ Watch the build · task · stopped
with x after 3s`, `stopped with esc after …` or `stopped after …`.
A monitor's end message is its line. Closing an owner removes its items.

A session resumed after its agents ran draws them as they were. A subagent
left running when its agent process ended reads as ended at that point,
before any later resumed work. Each task keeps its block and, behind
ctrl+o, its work from the task's own record. If that record was deleted,
the block and elapsed time remain. A task left running reads
`Disconnected`. The transcript keeps every message both ways and the
`Open`, `Close` and `→` calls. Its long-lived agents are not reopened with
it; a closing line names those still open when it was left, which
`/resume` lists like any session, and a message the parent sends one is
refused. Opened from `/resume`, such a child is your own main session,
with no parent to message. A team run is one of them, named with how many of
its agents were open (`team bugfix (4 agents)`), and the line ends with
`/team run bugfix starts the team again`: a fresh run, with no memory of
the last but the working tree and what main was told. `/resume` lists its
lead and members like any child. A task agent gets no command on quit,
and past tasks do not appear in the resumed session's background view.
chord's own calls draw as `List agents`, `List sessions`, `Open(parser)`
and `Close(parser)`, and a message sent as `→ to @main` or `→ to @parser`,
in Claude and Codex sessions. Messages sent or received, from agents or
chord, show their whole text as markdown wrapped to the window, on resume
too, with no fold or ctrl+o hint. A pending send shows its text at once;
a refused send keeps it, then shows the refusal in the error colour.
Monitor events keep their six-line fold. Older Codex records keep their
earlier display.
If a call to chord is cut off before it reaches chord, its row ends in the
error colour: `Not delivered: cut off before it reached chord. chord tells
the agent at its next turn.` At that turn, chord names each cut call in a
note and asks the agent to send it again, on its own. A resumed record
shows the row without resending the note.
A name after an arrow takes `@` where `send_message` reaches
it, `main` and a long-lived child; a task, named by its title, and chord's
own `← from chord` stay bare. `/mcp` lists chord's server first,
and says what it gives the agent, or why it was not passed: the agent does
not take HTTP or is set to take no MCP servers. `-p` gets no such server.

Models, efforts and modes are set per agent because their ids are the
agent's own: `/model`, `/config` and shift+tab show what an agent offers, and
`chord agents` lists the names. An effort is one the model the session starts
on offers. A starting model, effort or mode the agent refuses is said in the
transcript, with where it was set and what the agent offers, and the session
goes on as the agent chose; an agent with no effort starts on its own, and
the line says it offers none. An unknown key or wrong-type value is named
with its file and left out; the rest still counts. A file that is not a
JSON object is named and ignored. A refused `agents.<name>.command`
instead prevents that agent from starting: main, child, task or team
member, and a session resumed alone in a directory that refuses it.
The warning names the cause and says `<agent> will not start`; stderr
reads `chord: <agent> not started: …`. chord never falls back to its own
command. Other settings problems appear on stderr and in yellow at the
transcript's top. `-p` takes `agent`, `command`, `effort`, `permissionMode`
and the agent's `mcpServers` setting from the files, and says a refused
effort or mode on stderr; `--model` is for the window. `--agent-command`,
`--model`, `--effort` and `--permission-mode` speak for the main agent;
children start on their own agent's settings or the values their caller gives.

chord knows the agents the [ACP Registry](https://agentclientprotocol.com/registry)
offers through npx or uvx, with all pins refreshed together: `claude` and
`codex` for Claude's and Codex's adapters, every other one by its registry
id, including `bob` and `github-copilot-cli` (Copilot). It starts one as
`npx -y <package>@<version>` or `uvx <package>@<version>`, so `npx` or `uvx`
must be on your `PATH`.

Some agents ship their own CLI, which speaks ACP itself: `cursor`, `devin`,
`fx`, `goose`, `junie`, `kimi`, `kiro`, `openclaw`, `opencode`, `poolside`
and `zeroclaw`. chord starts each by the command its docs give (Cursor's
`agent acp`, goose's `goose acp`, …), which you install yourself; when it is
not on your `PATH`, chord says which command it looked for and where the
agent says to install it, and exits before a session starts. chord downloads
nothing for them: the registry also offers most of these as archives to
unpack, but a CLI you installed and keep up to date is the one you already
signed in to. Any other ACP agent starts with `agents.<name>.command` or
`--agent-command`, which also replace the command chord knows for a name.
A settings command may be a string or a list such as `["my-agent", "--acp"]`:
the program, then its arguments as written, including empty arguments.
The program must be nonempty and every item a string. The last settings
file to give a command decides; `--agent-command` overrides all.
A name your settings files alone give a command starts as `chord <name>`.
`chord agents` lists them all: each one's name and title (`from settings` for a name only they define), `npx` or `uvx` for the
registry's, `own CLI · found` or `own CLI · not on PATH` for those that need
their own CLI, and `settings` where a settings file's command starts it, then
what starts it, that command in the table's or the registry's place, wrapped
within its column on a terminal and one line per agent when piped.
If an agent does not start, chord says which request it refused or was
answering when it exited or closed its connection, with its exit code or
signal when known. A Registry agent's failure also names the `package@version`
chord ran, including on a sign-in failure; an old Registry pin may be the
cause. Below it, when available, are stderr's last six non-empty lines,
with `… +N lines` for omitted lines and `…` on cut long lines. Plain stdout
messages are not shown. `-p` reports the same details on stderr; a lead's
failed-child note keeps the step, pin and stderr's last line.
For recorded fx `ResponseLanguageMismatch` turn failures, see the
[investigation and evidence limits](design/CHD-534.md).
A session request refused with `Method not found` means the program does not
serve ACP sessions: it is not an ACP agent, or not at this version. If
zeroclaw needs an agent alias, set `[acp] default_agent = "<alias>"` in
ZeroClaw's config, or start it with `zeroclaw acp --agent <alias>`.

chord does not sign agents in. If a new or resumed session needs a login,
its `did not start` row keeps the agent's words and lists any sign-in methods
it offers, each as `name · description`. Sign in with the agent's own CLI in
a terminal, or set its API key where it offers one, then start chord again.
The same guidance goes to `-p`'s stderr and to a lead whose child failed to
start. Sign-in guidance appears only for ACP's `authRequired` error.
For sigit, sign in from its own CLI: `/login <email> <password>` typed in
chord goes to the agent as prompt text and lands in chord's session record.

`dimcode` may start up to 18 other CLIs it finds on PATH through its own
`agent` tool, with their approvals bypassed and on your accounts. Their
actions do not reach chord's permission box. Its `/config` option
`permission` gates that tool: `read-only` refuses it, `workspace-write`
asks you first, and `full-access` runs it without asking. To disable a CLI,
set `externalAgents.<type>.enabled` to `false` in
`~/.dimcode/v2/config.json`, or use `/external-agents` (`/agents`) in
dimcode's own TUI. A missing entry is enabled. The types are `antigravity`,
`claude-code`, `codebuddy`, `codex`, `cursor`, `devin`, `droid`, `goose`,
`grok`, `hermes`, `kimi`, `kiro`, `mcode`, `mimo`, `opencode`, `pi`,
`qoder` and `zcode`. Disabled CLIs are still probed with `--version`.

When dimcode's `permission` is first seen at `workspace-write` or
`full-access`, chord shows `dimcode can start other agents` above the
prompt, with these facts and off switches. This includes children, tasks
and team members, shown at their parent or lead. `1. Got it, don't show
this again` records dismissal per machine in `notices.json` beside chord's
user settings file. `2. Show it again next time` or Esc records nothing.
↑ ↓ or j k move between choices; Enter picks. Permissions and forms hide
the notice until answered. With `-p`, its two paragraphs go once to stderr
and no dismissal is recorded.

## Development

```sh
bun install       # the dependencies
bun dev chord     # run from source
bun quality       # types, lint, format and tests
bun check         # native type checker
bun lint --fix    # what ESLint can fix
bun fmt           # native formatter
bun dev compile   # this machine's binary into dist/
bun dev registry  # refetch the ACP Registry's agents into src/registry.ts
```

`AGENTS.md` is binding for people and agents and says which checks a change
needs. `docs/decisions.md` records why the stack is what it is.

`bun dev --help` lists runtime, test and build commands: `chord` (`--fake`
for the test agent), `test`, `compile` (`--all` or `--install`), `npm`,
`registry`, `mark`, `screenshots` (optionally shot names), `memory`,
`selftest <binary>` and `release [version]`.

`bun quality` runs native type and format checks, tracked-file coverage,
ESLint and `lint/` tests, then the suite; `--static` leaves out the suite.
`bun lint` runs ESLint. Arguments after `bun dev chord`, `bun dev test`
and `bun lint` pass on as written; empty arguments need `--`
(`bun dev test -- -t ''`), as does the tool's help (`bun lint -- --help`
or `bun dev chord -- --help`).

`bun dev test` reports the tests' status. `tests/timings.json` only places
files: Bun uses it to balance shards and start each worker's slowest files
first; an unlisted file takes the median. No refresh is required.
CI runs `static` (`bun quality --static`), three `tests` shards
(`--shard=1/3`, `2/3`, `3/3`) and `compile`. The required `check` job
passes only when all of them succeed.

The owner's `bun dev release [version|major|minor|patch|fix]` releases
package.json's version when none is given. An exact version must equal it
or be above it, in canonical `X.Y.Z` form with no prefix or build metadata.
`fix` means `patch`. Pre-releases are refused, including a version argument
when package.json's current version is a pre-release. Give the command a
version or bump instead of editing package.json's version by hand.
A different version or bump is refused while package.json's version is not
on npm; `bun dev release` without a version finishes that release.

The release runs `install`, `check` (`bun quality`), `natives`, `compile`, `sign`,
`selftest`, `notarise`, `pack` and `publish` in order. `--skip` and `--only`
take comma-separated stages; `--from` and `--to` bound the run. `--only`
cannot combine with the other three. A new version needs `compile` among
the selected stages. `--package` selects one package to publish.
`--dry-run` stops before publishing but still submits to Apple;
`--dry-run --skip notarise` leaves out that submission.

Preflight checks a clean tree and the version. Publishing also needs `main`
equal to `origin/main` and no `v<version>` tag. After all eligibility guards,
every run requires successful `npm whoami`, including dry runs and runs
without `publish`; stage selection cannot skip authentication. Success
needs no terminal. On failure, stdin and stdout must both be terminals:
the release runs plain `npm login` once in that terminal, then requires a
successful `npm whoami` recheck. Without those terminals, or if login fails,
is cancelled or interrupted, or the recheck fails, the release stops before
release work. npm may open a browser and save credentials or registry
settings, even during a dry run.

A new version is then written into package.json and committed alone as
`chore: chord v<version>` before any stage. A publishing run pushes main
first. If the push fails, it drops the local commit and stops; a later
failure leaves the pushed commit on origin. Rerun with no version, or the
same one, to release package.json's version without another commit.

A dry run or a run without `publish` makes the version commit locally and
drops it at the end, on failure too. SIGINT, SIGTERM and SIGHUP also drop
an unpushed version commit. SIGKILL may leave it; drop that commit with
`git reset --keep HEAD~1`.

`natives`, `sign` and `notarise` require an arm64 Mac; signing and notary
credentials are checked before building when their stages are selected.
A stopped publish resumes only package.json's version from the packed
tarballs without rebuilding; a dry run or a run without `publish` refuses
that resume. Each tarball must match its recorded SHA-256 sum. The main
package waits for all four platform packages on npm, then all five must
answer before the annotated version tag is pushed to origin. Publishing
needs the owner at a terminal: npm gets the terminal for each authorisation
and the CLI waits. See `bun dev release --help` for examples.

A chord that has grown large: `kill -USR2 <pid>` writes a heap snapshot of
it, without stopping it, into `heaps/` in chord's state directory, for
Chrome's DevTools. `docs/memory.md` has how, and the long-run memory check
(`bun dev memory`).

## Built on

- [ACP Registry](https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json)
  — the agents chord knows by name, frozen into `src/registry.ts`, beside
  `src/clis.ts`'s agents started by their own CLI.
- [OpenTUI](https://github.com/anomalyco/opentui) — the terminal interface, through
  its React bindings.
- [Agent Client Protocol SDK](https://github.com/agentclientprotocol/typescript-sdk)
  — the connection to the agent, and the protocol types.
- [Cliffy](https://cliffy.io) — the command line.

## Licence

chord's code is [MIT](../LICENSE).

The Chorded name and the chevron mark, which chord draws at the top of a
session (`scripts/mark.svg`, and `src/ui/header/mark.ts` generated from it), are
trademarks of Igor Katsuba. The MIT licence does not cover them: a fork may
keep the code, but should take the mark out and draw its own. See
[TRADEMARKS.md](../TRADEMARKS.md).

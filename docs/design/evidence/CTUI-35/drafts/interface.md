# CTUI-35 interface draft: the window with many agents

The person's side of M4: what the window holds per agent and window-wide,
every key, every screen and its words, the `@@` roster, the seams, and the
units. Sources: `../chord` `docs/guide.md` (Use, lines ~130-175, ~245-255;
Keybindings; "chord's own server", ~1320-1480), `docs/design/CHD-493.md`
(one main per process, kept drafts), `docs/design/CHD-471.md` (state and
unseen columns, what gives way), `src/session/window_agents.ts`,
`src/ui/agents/{agents.ts,Agents.tsx,glyphs.ts}`, `src/ui/app/{state.ts,
keys.ts,closing.ts}`, `src/ui/status/status.ts`,
`src/ui/transcript/{message.ts,tools/chord.ts}`, `src/session/tasks.ts`.

Every screen below marked "captured" was taken from the original on
2026-11-19 with `(cd ../chord && bun dev chord --fake --qa <name>)` in tmux
at 120x40 and 80x24 (scenarios named per screen). Others are drawn from the
code and the guide and say so.

## 1. State: per agent and window-wide

### Today in the port

`example/chord/lib/ui/app/state.dart` has one `AppState` holding everything,
and `window.dart`'s `_TranscriptWindowState` owns one `StartConnection`, one
history, one prompt controller, one scroll. The original split this in
`src/ui/app/state.ts` long ago: `SessionState` (one per session key),
`WindowState` (one), `AppState = WindowState & SessionState` as the front
view, and `WindowedState { window, sessions: {key: SessionState}, front,
closing }` with `reduceWindowed`. The port follows it, file for file.

### The split (pure Dart, `lib/ui/app/state.dart`)

`SessionState`, one per agent key, swapped whole when another is picked:

| Field (port name today) | Why per agent |
| --- | --- |
| `start` (`StartState`), `agent` (`AgentState`), `resumed`, `omittedHistory` | each child starts, fails and reports on its own; the header/child line reads them |
| `transcript` (incl. turn, asking, planAsks), `spent`, `since` | its own chat and spend |
| `queue`, `held` | the queue and held `←` rows above its prompt |
| `attended`, `requestOverflows`, and the dialogs' `filling/answering/choosing/planning` | "answers, selections, notes and focus stay with the asking agent" (guide ~531) |
| `pendingMode` | mode asked of that agent |
| `draft`, `cursor`, `bash`, `images`, `imageCount` | its field (CHD-493 U2: each agent keeps its draft and cursor) |
| `kept` (new): `List<KeptDraft>` = text, images, bash, cursor | drafts set aside with ↓ (CHD-493 U10) |

`WindowState`, one per window:

| Field | Note |
| --- | --- |
| `shortcuts`, `quitArmed`, `closing`, `theme`, `themePreview`, `mcpPanel`, `resumeAsked`, `resumePicker`, pickers | as the original's `PickersState`, `ShortcutsState` |
| `expanded` | ctrl+o is the window's (`ViewWindow`) |
| `search`, `vim`, `editorFailed`, `pasteFailed`, `pasteFailedUntilStarted`, `keysFailed` | the original's `PromptWindow` |
| `notes`, `steerRefused`, `draftHeld`, `copied`, `selection` | notes and selection follow the front |
| `agentsFocus` (new) | the list has the keys |
| `agentsView` (new) | where a taller-than-list picked row's lines start |
| `agentCloseArmed` (new): key | the first `x` on a busy child |
| `sessionsNote` (new) | `Nothing waits on you` and the like, until the draft is touched |
| completion state (`menu`, `finder`, recipients snapshot) | the original's `PromptWindow`; the roster snapshot is recomputed per front (section 5) |

History: the sent prompts stay **window-wide** (one list), the **walk**
(index and the draft it began on) is **per agent**, keyed by session key, as
`App.tsx`'s `shared` + `walks[front]` (U10: another agent's walk never names
one of this agent's kept drafts). The port's `prompt/history.dart` gains
the `kept` stack in `older`/`newer`, as `../chord` `src/ui/prompt/history.ts`.

`WindowedState` (new): `window`, `sessions: Map<int, SessionState>`,
`front`, `closing: Map<int, Closing>`; `reduceWindowed` with the original's
actions: `InSession(key, action)`, `InSessionPast`, `AgentOpened(key)`,
`SessionShown(key)`, `SessionClosed(key, front)`, the spend-kept trio.
`frontState()` gives the widgets one `AppState`-shaped view so every widget
that draws today keeps its signature.

The roster is not window UI state: `lib/session/window_agents.dart`, the
original's `window_agents.ts` as pure Dart (`WindowAgents<C>`, `Child`,
`ChildInfo`, `MainAgent`, `MAX_CHILDREN = 8`, `messageRecipients`, `pick`,
`movePick`, `attentionOrder`, `attend`, `hear`, `closeChild`,
`forgetClosed`, `openChild`, `childName`, `takenNames`). Per agent it holds
the `AgentWait` (`lib/session/waits.dart`, already ported) the list draws.
Runtime owns how sessions are hosted; the window only reads `WindowAgents`
and dispatches `pick`/`attend`/close requests.

### Scroll: one authority

Scroll has one authority, the retained `ScrollController` per session
(framework draft F1). `SessionState` holds no scroll value; the port's
`AppState.scroll` (`ScrollState`) stays only as a projection of the front
session's controller, synced as today for key decisions (`ScrollChanged`),
and is never read to restore anything. `SessionShown(key)` attaches that
session's retained controller to the transcript view, which restores its
offset and follow mode as it was left; nothing copies a stored number back.

### Controllers, effects and projections

Owned per session, keyed by the session key and alive while the session is
open (created on `AgentOpened`, disposed on `SessionClosed`; `/clear` keeps
the key and the controllers, as the original keeps main's key):

| Live object | Why |
| --- | --- |
| its `Conversation` (runtime: fed by its own `StartConnection` through the host) | every intent goes to one session |
| its transcript `ScrollController` | scroll authority, above |
| its prompt text and cursor, as `SessionState.draft/cursor` | the `TextAreaController` itself stays one (below), loaded from these |
| its shell runs, its held-request timers, its kept-draft stack | effects that report into that session |

One per window, a **projection of the front** session, rebound on every
front change:

| Live object | Rebinding on `SessionShown(key)` |
| --- | --- |
| the `TextAreaController` (`_input`) | its text and cursor are written from the new front's `draft`/`cursor`; the old front's were saved by every edit already (`DraftEdited` lands in its own state) |
| the `CompletionController` | invalidated whole (section 5) |
| the `SelectionController` | cleared, as a selection belongs to what was drawn |
| the transcript list view | given the new front's entries and controller |
| the status line, the box title, the agents list | drawn from `frontState()` and `WindowAgents` |

Effects that outlive a key press carry a **target**: `(key, launch)`, where
`launch` is the session's launch identity (runtime's; a `/clear` or resume
pick under the same key starts a new launch). Their result is folded with
`InSession(key, …)` only if that target still exists and still has that
launch; otherwise it is dropped (the port's `_openEditor` already does this
for one connection with `identical(widget.connection, connection)`; this
generalises it). It is never applied to whoever is picked when it returns.
That covers:

- the external editor (ctrl+g): its text goes to the opening agent's draft
  (into `draft`/`cursor` of that `SessionState`, and to `_input` only if
  that agent is still front);
- the `/model`, `/effort`, `/config`, mode-cycle answers and refusals, and
  `/rename`'s note: to the agent asked;
- completion matches and an awaited `@`/`@@` pick: to the front they were
  started on, else dropped (section 5);
- the settings callback (`/theme` and settings saved): window-wide
  settings are not per agent, but a refusal note goes to the session that
  asked;
- image paste reads: to the asking agent's `images` and draft;
- `/clear` while that agent is hidden (by `clear_agent` or an agent's own
  path): its state resets under its key; the front is untouched, and its
  queued prompts return to its own draft.

Window intents target the front conversation. Today `window.dart` calls
`widget.connection.conversation` directly (send, clear, cancel, steer,
mode, model, config, rename, permission and form answers, shell context).
Each becomes `conversationOf(front)` taken **at the press**, and captured
for any `await` that follows, so a later answer still lands per the rule
above. This is real work in `window.dart` (every call site), so it has its
own unit (I2) and tests, not a free consequence of the split; `/rename` on
a picked child is one of its tests.

What the app passes in versus owns: the `AgentsList` widget is passed the
rows, the limit, the width, `focused` and the view; it holds nothing but the
one-second clock (the original's `useAgentsClock`, one timer shared with the
child line). Everything else is pure: `lib/ui/agents/agents.dart` (rows,
states, marks, layout, focus moves, hints, child line, left-open line) and
`lib/ui/agents/glyphs.dart`.

## 2. Keys

All ids and contexts as `../chord` `src/ui/shortcuts/bindings.ts`; the port
already has `agents:close` (`KeyContext.agents`, `x`) and
`session:attention` (`KeyContext.global`, `ctrl+x a`) declared (CTUI-31);
this task makes them do something.

| Key | Action id / context | Where it acts | What it does | Panel line |
| --- | --- | --- | --- | --- |
| ↓ | `history:next` / Chat | box, last line, no menu on screen | walk newer; else, from a non-empty draft not walking, set it aside (`draft_kept`); else, from an empty draft not walking, with children, enter the list (`agents_focused`) | `↑ ↓ for prompts, agents` (owner: trimmed until CTUI-36 adds `, background`) |
| ↑ | `history:previous` / Chat | box, first line | newest kept draft, then older kept, then sent prompts; the field's text is the walk's draft | same line |
| j / k | vim normal mode (not rebindable) | box in normal mode at last/first line | as ↓ / ↑ (they share `newerSteps`/`olderSteps`) | `/vim for vim mode` |
| ↑ ↓ j k | list keys (not rebindable) | list has keys | move `❯`, which **picks** at once (the view switches); a tall picked row scrolls by line first; ↑ from the first row returns the keys; ↓ on the last row stays | same `↑ ↓` line |
| Enter / Esc | list keys (not rebindable) | list has keys | return the keys to the picked agent's box (`agents_leave`) | none: the original's only Enter line, `enter for background, details, a call`, is CTUI-36's; ↑ ↓ and esc are named by the list's own hint |
| x | `agents:close` / Agents | list has keys, `❯` on a child | idle: close now; working, asking, queued or with tasks: arm (`agentCloseArmed`), status line `parser is working · x again to stop it and close`; second press closes; on `main` nothing | `x to close an agent` (owner: trimmed until CTUI-36 adds `, stop background`) |
| ctrl+x a | `session:attention` / Global | anywhere but the crash screen | pick the agent waiting longest (asking before unseen news), then the next on each press; its box gets the keys; none: `Nothing waits on you` | `ctrl + x a for what waits on you` (exists) |
| ctrl+o, pgup/pgdn, shift+↑↓, home/end | existing ids | list has keys | as in the box: verbose toggle and scrolling the picked transcript | existing |
| ctrl+c / ctrl+d | fixed | list has keys | arm quit / quit, as elsewhere | existing |

Conflicts and order, as `newerSteps` gates them: an open `/`, `@` or `@@`
list, history search, a picked code block (ctrl+x b), the shortcuts panel
and pickers keep their ↓/↑; ↓ reaches `newerSteps` only from the textarea's
last line (`onNewer`). A box holding the keys (permission, plan, form,
question, link): ↓ from its last active row enters the list (guide ~529:
a form's buttons, a question's last row or Skip, a permission's last choice,
a plan's Note, a link's Decline); the box keeps its height, hides its
highlight and hints while the list has the keys; returning gives the box the
keys where they were. Entering the list closes the `?` panel (`help:false`).
While the list has the keys, vim never acts (`listHasKeys`).

Every key above that is an action goes through the port's `Actions`/
`Binding` with the description the panel uses. The list keys that are not
rebindable are still bindings in the window's key map, with descriptions,
so the panel can list them; they are just not in `keymap.actions`.

Status-line hint while the list has the keys (`agentsHint`, short form when
the full one plus 40 cells does not fit):

```
↑ ↓ to pick · enter to write to it · x to close · esc to go back      [dim]
↑ ↓ pick · enter write · x close · esc back                           [dim]
```

`x to close` is left out when `agents:close` is unbound; it names the bound
key otherwise. The leader line after ctrl+x: `ctrl+x …  b a code block · a
the one that waits · esc never mind` (captured; the port's leader already
builds from bindings).

### Draft set aside (CHD-493 U10), exactly

- ↓ on a non-empty draft, last line, not walking, no menu: push `{text,
  images, bash, cursor}` onto the agent's `kept`; field empties. Applies with
  or without children (the original's `newerSteps` does not test
  `context.agents` for this step).
- ↓ again from the empty field enters the list when there are children; with
  none, nothing.
- ↑ from the empty field: newest kept, then older, then prompts; the kept
  draft comes back with its images, bash mode and cursor. History recall
  keeps the cursor at the end.
- Editing a kept draft shown by ↑ edits it in place (`kept_edited`); sending
  it or ctrl+c on it removes it (`kept_taken`); sending another prompt and
  `/clear` leave the stack.
- Nothing on screen says a draft is kept; no panel line.

## 3. Screens

Colour roles are the port's theme roles (`lib/ui/theme/`), as the original's
`theme.ts`: `agents[n]` for a child's colour by opening order, `warning`,
`error`, `success`, `accent`, `dim`. `working` is `accent`+dim; in the two
16-colour themes `success`+dim (CHD-483).

### 3.1 The agents list (captured, scenario `agents`)

Prompt has the keys, a child asking, 120x40:

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ● docs needs your permission · ctrl+x a to go · ? for shortcuts        Fake Large with a 1M context window · 1% used
    main    fake · Fake Large with a 1M context window · medium  ◦ idle 5s
    parser  fake · Fake Small · medium                           ◦ idle 7s        ✓ new reply
    docs    fake · Fake Large with a 1M context window · medium  ● permission 8s  ← new message
```

80x24, same moment (model and effort gave way on every row, as the column
is laid for the widest row with a mark):

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ● docs needs your permission · ctrl+x a  Fake Large with a 1M con… · 1% used
    main    fake  ◦ idle 5s
    parser  fake  ◦ idle 7s        ✓ new reply
    docs    fake  ● permission 8s  ← new message
```

Styles: status notice `● … ctrl+x a to go` [warning]; names [agents[n]],
`main` [text]; picked row's name **bold**; detail `fake · …` [dim]; `●
permission 8s` [warning]; `✻ working 41s` [accent dim]; `◦ idle 5s` [dim];
`✗ exited`, `✗ failed to start`, `✗ turn failed` [error]; `✓ new reply`, `←
new message` [dim]. Two left cells are the gutter: `❯ ` [permission colour]
on the picked row while focused, `↑ `/`↓ ` [dim] for lines out of sight.

List has the keys (↓ from an empty prompt), 120x40 and 80x24, captured:

```
  ↑ ↓ to pick · enter to write to it · x to close · esc to go back       Fake Large with a 1M context window · 1% used
  ❯ main    fake · Fake Large with a 1M context window · medium  ◦ idle 11s
    parser  fake · Fake Small · medium                           ◦ idle 13s        ✓ new reply
    docs    fake · Fake Large with a 1M context window · medium  ● permission 14s  ← new message
```

```
  ↑ ↓ pick · enter write · x close · esc back  Fake Large with a 1M… · 1% used
  ❯ main    fake  ◦ idle 11s
    parser  fake  ◦ idle 13s        ✓ new reply
    docs    fake  ● permission 14s  ← new message
```

`docs` picked (two ↓ more), 80x24, captured: the marks cleared on opening,
so the model came back; the box took the child's colour and name in its top
border; the status line's right side is docs' model:

```
╭─ docs ───────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ↑ ↓ pick · enter write · x close · esc back    Fake Large with a 1M context…
    main    fake · Fake Large with a 1M context window  ◦ idle 13s
    parser  fake · Fake Small                           ◦ idle 15s
  ❯ docs    fake · Fake Large with a 1M context window  ● permission 16s
```

Box title `─ docs ─` [agents[n]] on the border; with `main` picked the box
has no title (as today).

The other states (from CHD-471 mocks and `agentState`/`agentMark`):

- working: `✻ working 41s`; exited: `✗ exited`; never came up: `✗ failed to
  start`; failed turn: state `◦ idle 2s`, mark `✗ turn failed`.
- Asking for a form/question/link: `● input 17s`.
- Status line, others than the one shown: `● 2 agents wait · ctrl+x a to
  go`; `✗ parser exited · ctrl+x a to go`; `✗ 1 exited · 1 turn failed ·
  ctrl+x a to go`; a task asking: `● Agent(Fix the tokenizer) · fake needs
  your permission · ctrl+x a to go`, short `● main's task needs your
  permission · ctrl+x a`. At 80 columns `to go` drops (`ctrl+x a` bare).
- Narrow (43 columns, CHD-471): mark words drop to the glyph, then the state
  goes under the detail:

```
    main       fake  ◦ idle 4s
    parser     fake  ◦ idle 13s        ✓
    docs       fake  ● permission 17s  ←
```

- Tall row (title or long name; name column at most a third of the width,
  wraps under its first letter), 80x24 with the prompt holding the keys,
  then the list focused and read by line:

```
    main                       fake  ◦ idle 4s
    Summarise the release      fake  ✻ working 41s
  ↓ notes for 0.56.0 from the
    … +1 more
```

```
    main                       fake  ◦ idle 4s
  ❯ Summarise the release      fake  ✻ working 41s
    notes for 0.56.0 from the
  ↓ commits since 0.55.2,
```

- Limit: `agentsRowLimit(rows)` = the queue's own limit (4 lines at 24 rows,
  6 at 40); a wrapped row counts each line; past it `  … +N more` [dim]. In a
  short window the list folds to one agent row and `… +N more` while the
  transcript has no rows left, as the original (framework draft owns the
  arithmetic).
- `x` on a busy child, status line [plain]: `parser is working · x again to
  stop it and close`; `docs waits for your permission · x again …`; `has 2
  prompts queued`; `has 1 task agent running`.
- After a close, captured (parser idle, closed with one `x`), in main's
  transcript:

```
 ← from chord
   ⎿  The person closed parser (fake · fake-small, id 1efce421). It takes no
      more messages; open_agent starts another.
```

### 3.2 A child's view (captured, `agents`, `docs` and `parser` picked)

The header is replaced by the child line, `name` [agents[n] bold], rest
[dim]:

```
 docs · fake · Fake Large with a 1M context window · opened by main 17s ago

 ← from @main
   ⎿  permission

 ⏺ Write(notes.txt)
   ⎿  Waiting…
```

The permission box title names the child: `docs asks` (as captured), and
ctrl+x a gives it the keys (`❯ 3. Deny`, `Esc to reject`).

### 3.3 Messages: `←` and `→` rows (captured, `agents` and `task`)

In the sender's transcript, chord's own tool calls keep their rows
(`../chord` `src/ui/transcript/tools/chord.ts`), never `chord - send_message
(MCP)(…)`:

```
 ⏺ Open(parser) · fake · fake-small
   ⎿  agentchild

 → to @parser · queued
   ⎿  I changed how a string at the end of a line is read. Run the parser tests now and tell me only what fails.

 → to @parser
   ⎿  The printer is fixed too; run the whole parser suite once more.
```

In the recipient's:

```
 ← from @parser · fake
   ⎿  Ran bun dev test tests/parse: 2 failures, both in tests/parse/printer_test.ts.

 ← from Fix the tokenizer · fake · report
   ⎿  The tokenizer dropped a closing quote when a string ended the line. Fixed in src/parse/tokenize.ts, with two
      cases added to tests/parse/tokenize_test.ts. bun dev test passes.
```

`←`/`→` [text]; `from ` [dim]; sender **bold** (`@name` when
`send_message` reaches it, bare for a task and `chord`); the rest [dim]; a
failed report's arrow [error]; chord's own arrow [dim]. Message text whole
(no fold). The other verbs: `List agents(codex)`, `List sessions`,
`Agent(<name>) · codex · <model>`, `Close(<name>)`, `Clear(<name>)`; a call
cut off: `Not delivered: cut off before it reached chord. chord tells the
agent at its next turn.`

The port today has `ChildMessageEntry(from, text)` and the Claude
`AgentMessageEntry`; it gains the original's `MessageFrom {name, runtime?,
note?: report|failed, reachable?, monitor? (CTUI-36's)}` in place of the bare
string, and `fromLine`/`senderName` in `lib/session/tasks.dart`.

### 3.4 Held messages above the prompt (from `message.ts`'s `queuedMessage`; scenario `agentsheldgated`/`agentcallgated`)

In the recipient's view, each in arrival order, until it goes in:

```
 ← from @main · after the running calls: Then the docs, once the tests pass.
 ← from @main · after your answer: Then the docs, once the tests pass.
 ← from @parser · fake: All 214 parser tests pass now.
```

Header drawn whole, only the text cut to the width; a multi-line message's
first line with ` …`. The port's `queue.dart` `PromptQueueRow` already has
the `header` slot (`after the running calls: `); it gains the `← from …`
prefix for agent rows. The list marks a recipient in the background with `←
new message`. Self-started turn: `Interrupted · the agent started this on its
own` [dim] (port has `SelfStartedEntry`; it gains the `<sender>'s` form).

### 3.5 Task blocks (captured, `task`, `tasktwo`)

```
 ⏺ Agent(Fix the tokenizer) · fake · fake-small
   ⎿  Search(tokenize in src/parse)
      Read(src/parse/tokenize.ts)
      Edit(src/parse/tokenize.ts) · waiting for permission
```

Ended: `⎿  Done (5 tool uses · 2.0k tokens · $0.0125 · 12s)`. Group:

```
 ⏺ Running 2 agents… (ctrl+o to expand)
   ├─ Agent(Watch the build) · fake · 0 tool uses
   │  ⎿  Initializing…
   └─ Agent(Watch the deploy) · fake · 0 tool uses
      ⎿  Initializing…
```

These reuse the port's subagent block (`lib/ui/transcript/agents/`), with
runtime and model after the title. A task's permission box: `Agent(Fix the
tokenizer) · fake asks · between turns` with `ctrl+x a to answer`. In the
original, tasks outliving the turn show in the status line `2 agents still
running` and in the background summary under the list (`background  2
tasks running`, `● 1 task asking`). The owner decided: until CTUI-36 the
port shows them only in the status line and in their own block; no summary
row is drawn.

### 3.6 Resume

- Transcript end note, `⏺` [dim] + line [dim] (`leftOpenLine`): `parser
  (codex) was open when this session was left and is not reopened · /resume
  lists it`; plural `… were open … are not reopened · /resume lists them`.
  Team clauses are CTUI-37's.
- `/resume` rows: a child's session has its name before its title,
  `parser · agentchild`; one open now says `open now` and Enter picks it
  instead of resuming (CHD-493's screen, 120x40 and 80x24 identical inside
  the frame):

```
│ ❯ 1. 1 minute ago   open now  parser · agentchild                            │
│   2. 1 minute ago             docs · permission                              │
│   3. 2 hours ago              fix the tokenizer                              │
```

- Tasks' blocks and messages replay as they were; long-lived children are
  named, not reopened, and the list is absent.

### 3.7 Fixtures

Original captures: `bun dev chord --fake --qa <name>` with prompts `agents`
(list, asking, unseen, pick, x, ctrl+x a), `agentsquiet` (idle clocks),
`agentexit` (`✗ exited`, `← from chord … agent exited`), `agentfail` (failed
to start), `agentlong` / `agenttitled` (tall row), `agentsheldgated` and
`agentcallgated` (held rows; gate `<cwd>/.fake-gate/release`), `task`,
`tasktwo`, `taskcost`, `taskask`, `agentclear` (`/clear` on a child),
`agentmentions` (`@@`), then `/resume`.

Port captures: the same prompts through `dart run
example/chord/tool/dev.dart chord --fake` (the port's runner over the
original's fake). For states without an agent, a new standalone fixture
`example/chord/tool/children.dart` (no IO, in-memory roster): `--asking`,
`--unseen`, `--exited`, `--failed`, `--tall`, `--many` (fold and `… +N
more`), `--held`, `--tasks`, `--light`/`--plain`. `tool/agents.dart` stays
the Claude subagents fixture.

## 4. Wording index (verbatim, for tests)

`● <name> needs your permission`, `● <name> asks for input`, `● N agents
wait`, `<name> exited`, `<name> failed to start`, `<name>'s turn failed`,
`N exited`, `N turns failed`, ` · ctrl+x a to go`, `Nothing waits on you`,
`<name> is working · x again to stop it and close`, `waits for your
permission`, `asks for input`, `has N prompts queued`, `has N task agents
running`, `↑ ↓ to pick · enter to write to it · x to close · esc to go
back`, `opened by main 4m ago`, `◦ idle 3m`, `✻ working 41s`, `●
permission 17s`, `● input 17s`, `✗ exited`, `✗ failed to start`, `✗ turn
failed`, `✓ new reply`, `← new message`, `  … +N more`, `← from @main ·
after the running calls: `, `· after your answer`, `· queued`, `The person
closed <name> (<runtime> · <model>, id <id>). It takes no more messages;
open_agent starts another.`, `<name>'s agent exited: <stderr end>.
open_agent opens it again.`, `was open when this session was left and is
not reopened · /resume lists it`, `No agents to mention`, `No matching
agents`.

## 5. `@@`: the live roster

CTUI-24 left `TranscriptWindow.recipients` (immutable snapshot) and
`CompletionController.replaceRecipients(names)` which drops old matches and
a pending pick. M4 wires it:

- The roster is `messageRecipients(agents, front)` from
  `window_agents.dart`: from main its open long-lived children; from an
  ordinary child `main` alone; never tasks or unopened runtimes. Its team
  branches are not ported (section 6); a fork's empty answer arrives with
  CTUI-74.
- **Every front change and every launch change invalidates the completion
  session**, whether or not the names changed: two ordinary children both
  offer `[main]`, yet a match or awaited pick started in child A must never
  complete in child B, nor in A after a `/clear` or a reopen (a new launch
  under the same key). On such a change the window calls a new
  `CompletionController.resetSession(names)` (the generation bump that
  `replaceRecipients` does today, made unconditional), dropping matches,
  the awaited pick and the highlight.
- The identity shortcut (skip when the same name list comes again) holds
  only within one front and launch: a roster update for the same
  `(front, launch)` that leaves the names equal does not reset a match in
  progress; anything else resets.
- Colours come from each child's `colour` index through the theme, `main`
  [text]. Equal names appear once; matching starts at the first character;
  `No agents to mention` and `No matching agents` already exist.
- The constructor's `recipients` stays for fixtures (`tool/mentions.dart
  --agents`); production passes none and the live roster takes over once
  the first session opens.

## 6. Seams

The rule: no executable branch ships that nothing in this task can reach.

- **CTUI-36, background summary.** Nothing of it is drawn, focused or
  hinted. `moveListFocus(rows, by)` ships over agent rows only; its doc
  names the plug-in point (a trailing stop after the rows, which CTUI-36
  adds with its own tests). No `summaryFocus`, no `summaryHint`, no
  `summaryOnly` entry, no Enter-opens-background path, and no hint or panel
  line names the background. The list counts only its own rows; CTUI-36
  adds the summary row to the layout.
  Tasks after their turn: status line and block only (owner).
- **CTUI-74, forks.** `ChildInfo.forkedFrom` is carried as records carry
  it, and the roster's sort puts top-level forks after children (a pure
  ordering a test reaches with a constructed roster). No fork refusal code,
  no `fork ·` detail, no `forked from` child line, no fork branch in
  `messageRecipients`; CTUI-74 adds them.
- **CTUI-37, teams.** Only the fields records carry: `ChildInfo.team` and
  `ChildInfo.lead`. No `teamRows`, `folded`, `branch`, `teamState`, team
  folding in `listRows`, team branches in `messageRecipients`, or team
  clauses in `leftOpenLine`.

## 7. Where an exact copy is impossible, or the port departs

1. **Box title on the border** (`╭─ docs ─…╮`): needs a titled border on
   the prompt box; if the framework has none it is a `lib/` addition
   (framework draft). Not a departure once built.
2. **Panel wording (owner: trimmed until CTUI-36):** `↑ ↓ for prompts,
   agents` and `x to close an agent`; CTUI-36 restores `, background`, `,
   stop background` and adds `enter for background, details, a call`.
3. **Tasks after their turn (owner):** status line and their block only,
   until CTUI-36 draws the summary row.
4. **`/rename` and every window intent on the front agent**: in the
   original they act on the picked agent; the port's window calls main's
   conversation. Not free: unit I2 reroutes every call site.
5. **Clock**: one `Timer.periodic` shared by the list and the child line,
   running only while a row is timed (`listTimed`), so a list of exited
   rows does not redraw every second.

## 8. Units for ship (interface part, in order)

Each unit lists the tests that would fail without it. Runtime's hosting
reducer and event path land before I4.

**I1. Window state split.** `SessionState`, `WindowState`,
`WindowedState`, `reduceWindowed`, `frontState`; no scroll in
`SessionState`; per-session retained `ScrollController`s; the window holds
one session today.
Tests (`test/ui/app/state_test.dart`, `test/ui/app/window_switch_test.dart`):
`InSession(k2)` changes only k2's transcript; `SessionShown(k2)` brings
k2's draft, cursor and queue back as left and attaches k2's controller, so
a k2 scrolled 30 lines up shows that offset, not k1's; theme, `expanded`,
`vim` and `quitArmed` survive a switch; existing window tests pass through
`frontState` unchanged.

**I2. Front routing and targeted effects.** `conversationOf(front)` taken
at the press for send, clear, cancel, steer, mode, model, effort, config,
rename, answers and shell context; `(key, launch)` targets on the editor,
model/effort/config answers, completion, image paste, settings callbacks.
Tests (`test/ui/app/front_routing_test.dart`, scripted conversations):
`/rename x` with child A picked reaches A's conversation and A's note,
main untouched; ctrl+g opened on A, switch to B, editor returns: A's draft
holds the text, B's field is unchanged; `/model` asked on A, switch, answer
arrives: A's status shows it, B's does not; a refusal note lands on A; a
burst of typed keys split by a switch lands each key in the agent that was
front when it was pressed; `clear_agent` on hidden A resets A's state and
returns A's queued prompts to A's draft, B (front) unchanged; a result for
A after A's `/clear` (new launch) is dropped.

**I3. Kept drafts and per-agent walk.** `history.dart` `older/newer` with
`kept`; `KeptDraft`; `draft_kept`, `kept_taken`, `kept_edited`; vim j/k
share the steps.
Tests (`test/ui/prompt/history_test.dart`, `test/ui/app/keys_test.dart`): ↓
on a non-empty draft empties the field and ↑ returns text, images, bash and
cursor (`one X|two` → `one XYtwo`); ↓ from a recalled prompt steps to the
draft before setting it aside; a multi-line draft's ↓ moves the cursor until
the last line; an open `/` or `@` list keeps ↓; editing a shown kept draft
edits it in place; sending or ctrl+c removes it; another agent's ↑ does not
bring it; vim normal `j` on the last line sets aside, `k` brings back.

**I4. `window_agents.dart` and `agents.dart` pure modules.** Roster
(`openChild`, `closeChild`, `pick`, `movePick`, `attentionOrder`, `attend`,
`hear`, `forgetClosed`, `childName`, `takenNames`, `messageRecipients`
without team or fork branches), `agentState`, `agentMark`, `urgency`,
`listTimed`, `agentsRowLimit`, `listRows` (no teams), `moveListFocus`
(agents only), `agentsLayout` with the give-way order and line wrap,
`scrolledView`/`enteredView`, `agentsHint`, `childLine` (no fork or team
words), `leftOpenLine` (no team clauses), `agentCloseArmedLine`.
Tests (`test/ui/agents/agents_test.dart`,
`test/session/window_agents_test.dart`): each state's words and tone; mark
order failed > replied > message; a gone agent's failed turn is no mark; 120
and 80-column layouts equal the captured rows; effort, model, mark words
give way in that order; a name wraps inside a third of the width; a tall
row counts its lines; `… +N more`; ↑ from the first row returns none, ↓ on
the last stays; `messageRecipients` from main and from a child; a roster
with a `forkedFrom` child sorts it after children; `attentionOrder` asking
before unseen, oldest first, tie to main then opening order; a ninth child
refused.

**I5. `AgentsList` widget and the child line.** Drawn under the status line
while there is a child; the box's titled border and colour; the status
line's model of the picked agent; one shared clock.
Tests (`test/ui/agents/agents_list_test.dart`, tester at 120x40 and 80x24):
the captured screens of 3.1 and 3.2 cell for cell, styles by role; no list
with no child; `◦ idle 5s` becomes `6s` after a second of fake time; the
clock stops when only exited rows remain.

**I6. List keys and attention.** `agents_focused`, `agents_up/down`,
`agents_leave`, `close_agent` with arming, `attend_session`; bindings with
descriptions; trimmed panel lines; status notices of section 4.
Tests (`test/ui/app/agents_keys_test.dart`, fake window): ↓ ↓ from a draft
reaches the list with the draft kept; ↑ ↓ j k move and pick (the view
switches at once); Enter, Esc and ↑ at the top return the keys; `x` on idle
closes, on working arms with the note and closes on the second; `x` on
`main` does nothing; rebinding `agents:close` to `d` moves the hint and the
panel; ctrl+x a goes to the oldest asker then the next, `Nothing waits on
you` when none; a box holding the keys hands ↓ from its last row to the
list and gets its place back; the panel lists every list key and names no
background (keys test).

**I7. Messages and chord's tool rows.** `MessageFrom` (no monitor field
yet), `fromLine`, `senderName`, `←`/`→` rows, held `← from …` queue rows,
`← from chord` notes, `chord.dart` tool verbs for this task's seven tools,
cut-off sentence.
Tests (`test/ui/transcript/message_test.dart`,
`test/ui/transcript/tools/chord_test.dart`, `test/ui/prompt/queue_test.dart`):
each verb's row from its input and answer; `· queued`; header whole with the
text cut; a failed report's arrow in error; a held row's `after the running
calls` / `after your answer`.

**I8. Task blocks.** Runtime, model, effort after `Agent(<name>)`; ended
line with tokens and cost; group wrap behind `│`; the task box title; a
task after its turn counted in the status line only.
Tests (`test/ui/transcript/agents/tasks_test.dart`): the captured `task`
and `tasktwo` blocks; unreported parts left out; a refused effort names the
runtime's own; after the turn ends with a task running, the status line says
`1 agent still running` and no row is drawn under the list.

**I9. `@@` live roster.** `resetSession` on every front or launch change;
names from `messageRecipients`.
Tests (`test/ui/app/mentions_roster_test.dart`): main offers its children;
a child offers `main`; a pending `@@ma` pick awaited in child A, then the
pick moves to child B (both offering `[main]`): the pick is dropped and B's
draft is untouched; the same across A's `/clear` and across closing and
reopening A; a same-front roster update with equal names keeps the match; a
closed child disappears; a task never appears.

**I10. Window `/new` (owner: here, one parser with `chord acp`).**
`lib/session/new_args.dart` as `../chord` `src/session/new_args.ts`, shared
with runtime's `chord acp` `/new`; the window command opens an idle child
of main on main's runtime or the named one and picks it; `/new ` lists
agents for completion, Tab completes one, no `--name` completion.
Words: `--name needs a name · /new [agent] --name <name>`, `/new takes an
agent, then --name <name> · /new [agent] --name <name>`, `An agent name
<problem>`, `The name <name> is taken in this window`, `No agent named
<agent>; chord knows <list>`, `This session has closed`; refusals shown
where typed.
Tests (`test/session/new_args_test.dart`, `test/ui/app/new_test.dart`):
`codex --name code review` → agent `codex`, name `code review`; `--name
scout` → no agent; `codex --name` → `NO_NAME`; `codex --name=x` and `codex
extra` → `NOT_NAME`; a name with `"` refused naming the character; `main`,
`chord` and an open child's name refused unnumbered; `/new` opens a child
idle and picks it (box title, list row); the same parser's answers through
`chord acp` (runtime's test shares the cases).

**I11. Resume screens.** Left-open note, `/resume` child names and `open
now`.
Tests (`test/ui/transcript/left_open_test.dart`,
`test/ui/pickers/resume_test.dart`): singular and plural wording; an `open
now` row picks the child instead of resuming.

**I12. Fixture and captures.** `tool/children.dart`, its AGENTS.md command
lines, captures at 120x40 and 80x24 from the port beside the original's
under `docs/design/evidence/CTUI-35/`.
Test: each fixture flag renders in the tester without throwing.

## 9. Owner's answers (2026-11-19)

- Panel wording: trimmed until CTUI-36 (sections 2, 7.2).
- Window `/new`: in this task, one parser with `chord acp`'s (I10).
- Tasks after their turn: status line and their block only until CTUI-36
  (sections 3.5, 6, I8).

No open questions remain on the interface side.

# CHD-624 — interface draft: what the bump changes on screen

Answers I1–I4 of [the brief](brief.md). This PR adds no key, no command and
no component. Three things change on screen: the words of a compaction
Claude's adapter runs on its own, the mode a Claude session opens in, and
the rows of the agent list. A visual pass guards against the OpenTUI bump
moving anything else. Today's screens were read from
`bun dev chord --fake --qa chd624-ui` (and `--qa` without `--fake` for the
picker) in tmux 3.6a at 120x40 and 80x24, origin/main 49b4c650c.

Colour roles are `src/ui/theme/theme.ts`'s; "dim" is the `DIM` attribute on
the default foreground, as `Outcome` draws it.

## I1. "compacted while idle"

### Today

A compaction is drawn by `CompactionRecord` (`src/ui/transcript/Transcript.tsx`)
with words from the pure `compactionLine` (`src/ui/transcript/compaction.ts`):

- inside a turn, while it runs, the spinner says `Compacting conversation…`
  and the transcript draws nothing for it (`inSpinner`);
- outside a turn, while it runs, the transcript carries it as its own block:
  `✻ Compacting conversation…`, `✻` and words in `accent`, a gap row above;
- once over, one line hung under what came before it, as a tool's outcome:
  `⎿  Conversation compacted (ctrl+o for history)`, dim; failed and
  cancelled ones in `error`.

Captured at 80x24 after the fake agent's `compact`:

```
 › compact
   ⎿  Conversation compacted (ctrl+o for history)
```

### Proposed

The same shapes, the same colours, the same places; only the words gain
"while idle", at the end of the line's sense, so the line still starts with
what happened:

| Status | Today | Idle |
| --- | --- | --- |
| running, no turn | `✻ Compacting conversation…` (accent) | `✻ Compacting conversation while idle…` (accent) |
| completed, summary kept | `⎿  Conversation compacted (ctrl+o for history)` (dim) | `⎿  Conversation compacted while idle (ctrl+o for history)` (dim) |
| completed, no summary, or ctrl+o open | `⎿  Conversation compacted` | `⎿  Conversation compacted while idle` |
| failed | `⎿  Compaction failed: <error>` (error) | `⎿  Compaction failed while idle: <error>` (error) |
| cancelled | `⎿  Compaction cancelled` (error) | `⎿  Compaction cancelled while idle` (error) |

`ctrl+o` stays whatever key `app:toggleTranscript` is bound to, as
`useHintKey` names it today.

Which compaction is idle is decided once, at its first update, by the
session side (runtime R1, protocol P3), and handed to the screen as a flag:
no turn of the person's, no turn of chord's own, no agent cycle running, and
not part of a replay. A compaction that begins inside a turn and ends after
it is not idle. A person's `/compact` is a prompt, so a turn, so never idle.
The words do not depend on the agent's name: any agent's unasked compaction
outside a turn reads the same.

#### While it runs, nothing else on screen, 120x40

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help
 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.

 ✻ Compacting conversation while idle…
   ⋮  (27 empty rows)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                              Opus 5.5 · high effort · 41% context used
```

No spinner, no `Working…`, the status line keeps `? for shortcuts` (or the
mode), the prompt takes input. No OSC 7501 status, no notification, no bell,
no `✻ Worked for …` footer and no turn cost line after it: none of these
come from a compaction outside a turn (runtime R1 makes sure no cycle opens).
A child that compacts while idle keeps its row in the agents list as it was.

#### While it runs, 80x24

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help
 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.

 ✻ Compacting conversation while idle…











╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                     Opus 5.5 · high · 41% used
```

#### Over, 120x40

The running block goes; the line hangs under the last entry, as today's
does. The context figure on the right drops when the adapter's
`usage_update` arrives (41% → 9% here), as it does today.

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help
 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.
   ⎿  Conversation compacted while idle (ctrl+o for history)
   ⋮  (28 empty rows)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                               Opus 5.5 · high effort · 9% context used
```

#### Over, 80x24

The longest form, with the hint, is 60 columns with its indent; it fits one
row at 80. A failure's error wraps at the outcome's indent (6).

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help
 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.
   ⎿  Conversation compacted while idle (ctrl+o for history)












╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                      Opus 5.5 · high · 9% used
```

With ctrl+o's view open, the summary is drawn under the line, indented 5,
as today:

```
 ⏺ Done: three tests merged into one table, all green.
   ⎿  Conversation compacted while idle
     The person asked to tidy the parser tests. Three tests in
     tests/parser_test.ts were merged into one table…
```

#### The person sends a prompt while it runs

The prompt is free, so Enter sends at once; Claude's adapter queues the
prompt behind its own `/compact`. From then on the agent is compacting in
the person's turn, so the spinner says it, as for a compaction inside a turn:
`inSpinner` counts a running idle compaction as the turn's whatever turn
runs, and the `✻` block hides. When it ends, its line takes its place above
the new prompt:

```
 ⏺ Done: three tests merged into one table, all green.

 › and the lexer tests

✻ Compacting conversation… (4s · esc to interrupt)
```

then

```
 ⏺ Done: three tests merged into one table, all green.
   ⎿  Conversation compacted while idle (ctrl+o for history)

 › and the lexer tests

✻ Working… (9s · esc to interrupt)
```

Esc during that spinner cancels the person's turn as today; if the adapter
cancels the compaction with it, the line reads `Compaction cancelled while
idle`.

### Replay and resume

- **Resumed from chord's record.** The record must keep the flag with the
  compaction (protocol P3 says how: on chord's recorded action, not by
  rewriting the agent's update), so a resumed session draws
  `⎿  Conversation compacted while idle` where it was.
- **Replayed by the agent** (`session/load` with no record of chord's, and
  Claude 0.106+'s replay of the history before each compaction): nothing on
  v1 says a compaction was idle, so each is the plain completed line under
  the replayed turn before it. A replay never draws one running. Excerpt,
  120x40, a load that crossed two compactions:

```
 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.
   ⎿  Conversation compacted (ctrl+o for history)

 › and the lexer tests

 ⏺ Done: the lexer tests now use the same table.
   ⎿  Conversation compacted (ctrl+o for history)
```

  Guessing "idle" in a replay from the gap between turns would be chord
  guessing; it is left plain.

### Where it lives

- State: `Compaction` in `src/session/transcript/types.ts` gains
  `idle?: true`. This is the session's transcript, which the window reads as
  `state.transcript`; no feature `state.ts` under `src/ui/` changes
  (`transcript/state.ts` holds only scroll and ctrl+o).
- Pure logic: `compactionLine` reads `compaction.idle` for the words;
  `inSpinner` drops the same-turn condition for an idle compaction. Tests in
  `tests/ui/transcript/compaction_test.ts` (each row of the table above) and
  one harness test (`tests/ui/harness.tsx`) drawing the line at 80 columns.
- Drawn by today's `CompactionRecord` and `Outcome`
  (`src/ui/transcript/tools/Tool.tsx`): OpenTUI `box` and `text` through
  `theme/text.ts`. Nothing new.
- Keys: none new. ctrl+o (`app:toggleTranscript`, rebindable, already in the
  shortcuts panel) shows the summary. The panel is unchanged.

## I2. The status line and header at session start

### Today

While the session opens, the status line's left side is the notice
`Starting claude…` (`src/ui/status/Status.tsx`, `connection.status ===
'starting'`), which stands alone: no mode, no hint. A starting mode from
the settings is asked for after `session/new` "before anything is shown"
(`src/session/starting.ts`). Manual is Claude's name for the mode id
`default`, which the line leaves unsaid, as Claude Code does (`QUIET_MODES`),
so a Manual session shows `? for shortcuts`. The header names the agent and
model, never the mode.

Captured, fake agent, 80x24, `--permission-mode plan`:

```
  ⏸ plan mode on (shift+tab to cycle)      Fake Large with a 1M context window
```

and `--permission-mode yolo`, which the agent lacks:

```
 ⏺ Could not start in yolo mode, set by --permission-mode: the agent offers
   default, acceptEdits, plan
```

### Under D1

The screens are those of 0.99.1. The rule that keeps Auto from flashing:
the line draws a mode only once the session has left `starting`, and it
leaves `starting` only after `session/new` and, where the agent ignored the
initial option, the fallback set (runtime R2) have answered. Until then the
notice stands alone, so a `currentModeId: auto` in a response that ignored
the option is never painted.

**1. Opening**, any start mode. 120x40, bottom rows:

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  Starting claude…
```

80x24 the same, at 80. The model is not known yet, so the right side is
empty, as today.

**2. Open in Manual** (no mode named anywhere). 120x40:

```
  ? for shortcuts                                                                                 Opus 5.5 · high effort
```

80x24:

```
  ? for shortcuts                                         Opus 5.5 · high effort
```

**3. A mode named** by `permissionMode` in the settings,
`--permission-mode`, or a team member's mode. The first frame after
`Starting claude…` already shows it, in the mode's colour role (`edits`,
`plan`, `auto`), the cycle hint in the default foreground. 120x40:

```
  ⏵⏵ accept edits on (shift+tab to cycle)                                                         Opus 5.5 · high effort
```

80x24, where a longer model name would first lose the effort's word, as today:

```
  ⏵⏵ accept edits on (shift+tab to cycle)                 Opus 5.5 · high effort
```

A person who names `auto` gets `⏵⏵ auto mode on (shift+tab to cycle)` in
`auto`: chord sends what the person asked for.

**4. The agent did not end up in the asked mode** (it ignored the option
and refused the fallback, or reports another mode after both). The status
line tells the truth, the mode the agent reports, and the transcript says
why, with today's refusal words (`askStarting`, the `failed` entry, `⏺` and
text in `error`). Where the mode was chord's own default rather than a
setting, the "set by" part names that. 80x24:

```
 ⏺ Could not start in default mode, chord's start mode: the agent stays in
   auto
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)                    Opus 5.5 · high effort
```

The words after the colon are the agent's own where it gave a reason
(`agentMessageOf`), else `the agent stays in <id>`. The exact wording of
"chord's start mode" is protocol P1/P2's to settle with the lead; the shape
is today's.

shift+tab cycles from whatever mode the session is in, as today.

### Where it lives

- No new state. The mode is `state.transcript.mode` and the list
  `state.modes`, as today; `connection.status` holds `starting`.
- Pure logic: `statusLine` and `modePart` (`src/ui/status/status.ts`)
  unchanged. The requirement is on the session side: `starting` covers
  the initial option and its fallback. Test: a harness test where the fake
  agent answers `session/new` with `auto` and takes the fallback to
  `default`, asserting no frame shows `auto mode on`.
- Keys: shift+tab, `chat:cycleMode`, rebindable, already listed.
- The header is unchanged.

## I3. `chord agents` and the picker after D6

### `chord agents`

Today's columns (name, title, runner, start line) stay; the name column is
still set by `github-copilot-cli`. The rows that change, as a diff against
today's output (pins other than these move as the refresh brings them):

```
-autohand            Autohand Code        npx                    npx -y @autohandai/autohand-acp@0.2.1
-claude              Claude Agent         npx                    npx -y @agentclientprotocol/claude-agent-acp@0.99.1
+claude              Claude Agent         npx                    npx -y @agentclientprotocol/claude-agent-acp@0.107.0
-github-copilot-cli  Copilot              npx                    npx -y @github/copilot@1.0.105 --acp
+github-copilot-cli  GitHub Copilot       npx                    npx -y @github/copilot@1.0.111 --acp
+kimi-code           Kimi Code            npx                    npx -y @moonshot-ai/kimi-code@2.6.1 acp
 …
+autohand            Autohand Code        own CLI · not on PATH  autohand --acp
 cursor              Cursor               own CLI · found        agent acp
 …
-kimi                Kimi Code            own CLI · not on PATH  kimi acp
-kiro                Kiro                 own CLI · not on PATH  kiro-cli acp
+kiro                Kiro                 own CLI · not on PATH  kiro-cli acp --agent-engine=v3
```

`kimi-code` sorts among the registry's rows; `autohand` moves to the own
CLIs, in `src/clis.ts`'s order, and is marked `found` or `not on PATH` like
them. The runner column stays 21 wide.

### The picker (start screen and `/new`)

Rows are `<name> · <title>`, the registry's first, then the own CLIs found on
PATH (CHD-544). `kimi-code · Kimi Code` is always offered (npx).
`autohand · Autohand Code` is offered only where `autohand` is on PATH,
among the own CLIs; with `offeredAgents` naming it, it keeps its row and the
refusal says to install it, as for any own CLI. kiro's row is unchanged (the
picker shows no arguments). 80x24, scrolled to the change:

```
          Select agent

            ↑ 14. fast-agent
              15. gemini · Gemini CLI
              16. github-copilot-cli · GitHub Copilot
              17. glm-acp-agent · GLM Agent
              18. grok-build · Grok Build
              19. kilo · Kilo
              20. kimi-code · Kimi Code
              21. minimax-code · MiniMax Code
              22. minion-code · Minion Code
              23. nova · Nova
          ❯   24. pi-acp · pi ACP
            ↓ 25. qoder · Qoder CLI
              … +6 more

          ↑↓ or j/k to move · Enter or 1–9 to select · Esc to cancel
```

At 120x40 the same rows, 14 visible, as today.

### A session recorded under `kimi`

What it says depends on how protocol P5 keeps the old name, which is the
owner's (question below). Under the recommended answer nothing on screen
mentions the change: the session resumes on the npx program, which is the
same Kimi Code with the same session store, and `/resume` lists it as
before.

## I4. The OpenTUI 0.8.4 visual pass

### How

Each screen below at 120x40 and 80x24, on the branch and on origin/main, in
the same tmux, captured as text (`tmux capture-pane -p`) and diffed, and as
whole-window colour PNGs with origin/main beside for the owner. tmux 3.6
makes OpenTUI 0.8.3+ pick the unicode width method, where 0.8.1 may have
measured differently, so the branch is also run with
`OPENTUI_FORCE_WCWIDTH=1` and with `OPENTUI_FORCE_UNICODE=1`: chord's own
widths (string-width 8) must agree with OpenTUI's under both. All on
`--fake --qa <name>`; no live agent.

| Screen | How to reach it | What 0.8.2–0.8.4 can move |
| --- | --- | --- |
| Title page and picker | `--qa` without `--fake` | logo rows, centred column (text height) |
| Empty session | `--fake --qa` | header mark, status line |
| Markdown | `markdown`, `markdownwrap`, `markdowncode` | wrapped list items, code block frame |
| Wide graphemes | `graphemes`; type `naïve 日本語 👩‍💻 ok` in the prompt | right border, cursor column, wrap point |
| Permission | `permission`, `bigask`, `multidiffask` | reason, choices and timeout hint visible at 80x24, action scrolled above them |
| Forms | `form`, `requestform` | a row on the bottom border (text height) |
| Plan | `plan`, `todos`, `exitplan` | panel height, entries cut |
| Tools and diffs | `edit`, `tools`, `longresults` | `⎿` gutter, diff columns |
| Long transcript | `long`, then pgup, pgdn, home, end | culled rows blank or stale, follow lost (0.8.4 scrollHeight) |
| Subagents | `subagent`, `agents`, ↓ into the list | rows, names, states |
| Floats | `?`, `/`, `/resume`, ctrl+r | prompt, gap row and status line fixed (CHD-545) |
| Status line | `mode`, shift+tab through every mode | right side cut order at 80 |
| Compaction | `compact`, ctrl+o | outcome line, summary indent |
| `$EDITOR` | ctrl+g with `EDITOR=vi`, `:q` | no stray mouse or escape bytes in the prompt after return; full redraw (0.8.2 `suspend()`) |
| Colour | the empty session with `COLORTERM` unset | truecolor still detected (0.8.3 XTGETTCAP) |

### What counts as a regression

- A text row that differs from origin/main's at the same size and width
  method, other than the names and pins this PR changes.
- A dialog or panel border moved, overlapped, or carrying a content row.
- A right border, `│`, status right side or gutter off by a column on a line
  with wide graphemes, under either forced width method.
- The prompt, its gap row or the status line moving when a float opens or
  closes.
- The permission prompt at 80x24 losing its reason, a choice or the timeout
  hint.
- After scrolling a long transcript: blank or stale rows, pgup landing
  elsewhere than on origin/main, following not resumed at end.
- Anything left in the prompt after `$EDITOR` returns, or a frame not
  redrawn.
- Colours falling back from truecolor where origin/main had it.

Not a regression: a grapheme drawn at a different width under the two forced
methods, as long as chord's layout around it holds under each. A finding goes
to the lead; a fix that would mean working around OpenTUI goes to the owner
under the one rule.

## Open question for the owner

**Q. The name for Kimi Code after D6.** Records, settings (`agent`,
`offeredAgents`, `agents.<name>`), team files and `chord kimi` name `kimi`
today.

- a. Keep the name `kimi`, started from the registry's `kimi-code` entry,
  as `claude` is from `claude-acp` (`ALIASES` in `src/agents.ts`). The list
  shows `kimi  Kimi Code  npx  npx -y @moonshot-ai/kimi-code@2.6.1 acp`;
  everything that says `kimi` keeps working; nothing new on screen.
  *Recommended*: it is the precedent, and no person's file breaks.
- b. Name it `kimi-code`, and resolve `kimi` to it wherever an old name is
  read (records, settings, teams, `chord kimi`), silently.
- c. Name it `kimi-code`; `kimi` becomes unknown: a resumed record and a
  setting naming it get chord's unknown-agent refusals.

The brief's "lists `kimi-code`" reads as b or c; a changes that one line.

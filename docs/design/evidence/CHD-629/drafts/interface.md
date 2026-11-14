# CHD-629 — interface draft: `/rename`, the account, initial options, notices, subagent links

What a person sees and presses for F1–F5, the states, the keys, and where
the state and the pure logic live. Layout as `docs/design/CHD-624.md`:
`⋮  (n empty rows)` stands for that many blank rows, the screens were laid
out at their real widths with `string-width` and `wrap-ansi`, not by hand,
and the agent's words in them are illustrative where marked. Colour roles
are `src/ui/theme/theme.ts`'s `Palette` (`:73-119`) and the `DIM`
attribute; no new role.

## What I read

chord, at `CHD-629` (= origin/main `d82938bf5`):

- `src/ui/prompt/commands.ts:11-28` (`ChordCommand`), `:41-118` (the
  table), `:120-124` (an agent's command named like chord's is left out),
  `:362-405` (`submitted`: the rest of the line is `args`, trimmed, `:397`).
- `src/ui/app/commands.ts:122-149` (`/fork`'s note under the command as
  typed, on the agent it was typed on), `:166-194` (`/effort`, `/status`'s
  report from `reportFacts`).
- `src/ui/transcript/reports.ts:29-80` (`ReportFacts`, `reportFacts`),
  `:126-139` (`aligned`), `:385-397` (`statusReport`);
  `src/ui/transcript/Transcript.tsx:574-581` (report rows drawn as plain
  text, not through `Ansi`).
- `src/session/transcript/reducer.ts:222-252` (`reported`, `noted`; a note
  under the same id replaces a pending one), `src/session/transcript/types.ts:533-560`
  (`report`, `note` entries), `src/session/choice.ts:66-71` (pending words
  `Switching to …`).
- `src/session/record.ts:630-760` (`recordActions`: only `prompt`,
  `update`, `asked`, `answered` are recorded; notes and reports are not).
- `src/session/conversation.ts:761-784` (`title`, `#titled`),
  `:3344-3406` (`#applyStarting`, its `failed` line), `src/session/starting.ts:85-99`
  (the refusal's words).
- `src/ui/app/App.tsx:1100-1109` (the terminal's status named by the
  title), `:1541-1562` (the resumed header's title).
- `src/ui/app/state.ts:141-200` (`SessionState`), `:626-654` (`connected`,
  `connect_failed`), `:679-697` (`model`), `:1118-1140` (`SESSION_FIELDS`).
- `src/session/sign_in.ts` (whole), `src/ui/app/SignIn.tsx` (whole),
  `src/session/start_failure.ts:137-160`.
- `src/ui/transcript/tools/tools.ts:416-516` (`summary`), `:518-533`
  (`contentLines`: `session` falls to `default`, nothing), and
  `src/ui/transcript/agents/subagents.ts:131-153` (`agentHeadline`),
  `:689-711` (`askerRow`).
- `src/ui/agents/agents.ts:20-60` (`AgentRow`: long-lived children only),
  `src/ui/agents/glyphs.ts`, `src/ui/transcript/ended.ts:1-40`.
- `src/acp/connection.ts:228-234` (`CLIENT_CAPABILITIES`: no
  `session.notices` today), `src/session/cycles.ts:67-73` (`CYCLE_WORK`:
  no `notice`), `src/session/upstream.ts:59`.
- `src/ui/shortcuts/keys.ts:1-60`, `docs/design/CHD-626.md:154-156` (owner
  O6: no global keys for `/model`, `/effort`, `/fast`; the panel is full at
  40 lines), `docs/design/CHD-627.md:83-86` (no key for `/new`),
  `docs/design/CHD-445.md:20-60, 287-304, 491-530`, `docs/design/CHD-435.md`
  (the sign-in block).
- SDK 2.6 `dist/v1/unstable/schema/types.gen.d.ts`: `ToolCallContent` with
  `SessionReference` (`:220-228`, `:581-596`: `{sessionId, _meta}` only),
  `AuthStatusResponse` and `AuthState` (`:2447-2483`), `AuthAccount`
  (`:2498-2540`: `label`, `description`, `active`, `name`, `email`,
  `organization`; display only, "SHOULD NOT log them"), `Notice` and
  `NoticeSeverity` (`:3880-3920`: `severity` info/warning/error/string,
  `title`, `description`; "live events rather than session history").
- `@agentclientprotocol/claude-agent-acp@0.107.0` from npm, `dist/`:
  `session-notices.js` (`noticeUpdate`, `noticeTranscriptText`: today's bold
  blockquote), `session-mode.js:9-14` ("Auto mode unavailable"),
  `session-fast-mode.js:140-150` ("Fast mode turned off"),
  `v1/acp-agent.js:3495, 3694, 3726` (informational, API retry, model
  fallback), `async-tasks.js:324` ("Task stopped by user"),
  `subagent-replay.js:529-537` (a notice sent during a load), `auth-status.js`
  (`toAcpAuthStatus`: `unauthenticated` carries **no accounts**; a plan
  label such as "Claude Max"), `auth-status-reporter.js:107-115`
  (`auth/status` waits for a `claude auth status --json` probe, up to
  5 s, while no identity is known yet), `auth-methods.js:39-62`,
  `native-subagents.js:1194-1222, 1603-1624` (the `session` reference: on
  TaskStop and SendMessage calls naming a child, and on an Agent/Task call
  that stays shown because a permission request showed it; never before
  the child is announced), `v1/session-index.js:151-156` and
  `session-index/rename.js` (`set_title` answers `{title}`, the title as
  stored, publishes a `session_info_update`, refuses with -32600 "cannot
  change its title while it runs" on an old CLI).

Today's screens, `bun dev chord --fake --qa chd629-<name>` in tmux:
`/status` and a note at 120x40, the command list for `/re` at 80x24, a
refused `--permission-mode nope` at 80x24, `claudesubagents` at 120x40.

## Two rules over all five

- **Nothing the agent says is read for meaning.** A notice is drawn by its
  `severity` and its two strings; an account by its fields; a link by its
  `sessionId` against the subagents chord already tracks. No word is
  matched.
- **Every agent string is cleaned or goes through `theme/Ansi.tsx`**
  (`src/ui/AGENTS.md`). Report rows are drawn as plain text
  (`Transcript.tsx:581`), so the account's and the title's strings are
  cleaned in their pure formatter: escape sequences and control characters
  dropped (`strip-ansi`, already a dependency), whitespace runs folded to
  one space, as CHD-445 folds a title.

## F1 — `/rename <title>`

### The command

A new `ChordCommand`, `'rename'`, in `CHORD_COMMANDS` in its alphabetical
place, between `new` and `resume`:

```ts
{
  name: 'rename',
  description: "Rename this session; the agent's own title may replace it",
  owner: 'chord',
},
```

The `/` list, `/re` typed, 80x24 (order is Fzf's, as today):

```
 ──────────────────────────────────────────────────────────────────────────────
  /rename  Rename this session; the agent's own title may replace it
  /resume  Resume an earlier session, here or from another directory
  /greet   Say hello from the fake agent
```

- **The argument** is the rest of the line, as `/fork <name>`'s:
  `submitted` already gives it trimmed (`commands.ts:397`). Its whitespace
  runs, newlines included, are folded to one space before it goes anywhere,
  so what is sent, recorded and drawn is the one line CHD-445 draws.
- **An agent's own `/rename`** (none of the agents read advertises one;
  pi's is `/name`) is left out of the list by today's rule
  (`commands.ts:120-124`): chord's runs.
- **It applies to the front session**: main, or the picked child, as
  `/effort` does (`app/commands.ts:166-167` through `conversation()`). The
  note goes under the command, in the transcript it was typed in, as
  `/fork`'s does (`app/commands.ts:126-149`). It never renames a child's
  *name* (`parser` stays `parser`, CHD-627); it renames its session's title.
- **During a turn** it is accepted, like `/effort`: a title is not a
  prompt. The note lands where notes land today, after the last entry.

### What the person sees

The note under `› /rename <title>`, one line, `⎿` dim, its text dim when
it succeeded and `error` when it did not, as every `note` today
(`types.ts:540-560`). Words (the title shown as the agent answered it, which
may be cut by the agent: Claude answers the title as stored):

| State | Note | Tone |
| --- | --- | --- |
| `set_title` in flight | `Renaming to <title>…` (pending, replaced in place) | dim |
| Agent took it (advertises `sessionCapabilities.title`) | `Renamed to <title>` | dim |
| Agent without the capability (D3 b) | `Renamed to <title> in chord only: <agent> takes no title, and its own may replace it` | dim |
| Agent refused `set_title` | `Renamed to <title> in chord only: <agent> refused it: <message>` | error |
| No argument | `Name the session: /rename <title>` (and, when it has one, `. Now: <title>`) | dim |
| Session not open yet | `The session is not open yet; rename it once it is.` | error |
| Picked child that exited | `<name> has exited; its session cannot be renamed.` | error |

Whether a refused `set_title` keeps chord's own title (the "in chord only"
row) is protocol's and runtime's to settle; the words follow whichever they
choose. If it does not keep it, the row reads `Could not rename: <agent>
refused it: <message>` [error].

Renamed, 120x40 (claude, nothing else open):

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.

 › /rename Parser test tidy-up
   ⎿  Renamed to Parser test tidy-up
   ⋮  (25 empty rows)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                 Opus 5.5 · high effort
```

Renamed, 80x24:

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.

 › /rename Parser test tidy-up
   ⎿  Renamed to Parser test tidy-up
   ⋮  (9 empty rows)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                Opus 5.5 · high
```

### Where the new title shows

Where CHD-445 put the agent's title, at once, with no other line:

- the terminal's status (`App.tsx:1100-1109`, `programStatus`), on the
  next render;
- the agents list's title column, when the session has a child
  (CHD-445 §"The agents list"):

  ```
      main    Parser test tidy-up   claude · Opus 5.5 · high           ◦ idle 4s
      parser  Run the parser tests  codex · gpt-6.1 · medium           ◦ idle 1m        ✓ new reply
  ```

  and at 80x24 `    main    Parser test tidy-up   claude  ◦ idle 4s`;
- the next `/resume` and start picker (an open picker reads its rows once,
  CHD-445 `:299-301`);
- **not** the header's `resumed · … · <title>` line, which keeps what was
  resumed (CHD-445 `:301-302`).
- **`/status` gains a `Title` row** (screen under F2): with no child, the
  only place on screen that shows the title. *Owner choice I1* below.

The agent's own title replaces it on its next `session_info_update`, with
no line, as every rename by the agent today (CHD-445 `:287-299`). Claude
echoes a `session_info_update` for the `set_title` itself; telling the two
apart is protocol's question 1, and the screen does not depend on it: the
title shown is the last one, whoever set it.

### Keys

None. `/rename` is typed, as `/fork`, `/new`, `/effort` are; the owner
settled no global keys for typed commands (CHD-626 O6, the panel full at
40 lines). Nothing in `bindings.ts`; the shortcuts panel (`?`) is
unchanged; the command is listed in the `/` list with its description.

### State and logic

- No new window state. The title stays `Conversation.title`
  (`conversation.ts:761`), the record's entry is protocol's; `App` reads it
  as today.
- `src/ui/app/commands.ts`: `case 'rename'` calls a `sessions` method
  (`renameFront(title)`, the shape `forkTyped` has) and dispatches the
  `noted` outcome, pending first, under one `turnId`.
- Pure, with tests: the fold of the argument and the note's words, beside
  the other session notes (`src/session/choice.ts` style; protocol picks the
  module), tested in its mirrored `tests/` file; the command entry in
  `tests/ui/prompt/commands_test.ts`.

## F2 — the account in `/status`, a better sign-in failure

### `/status`

One `Account` row after `Agent`, per active account; one `Title` row after
it (F1, I1). The account's parts, cleaned, joined by ` · `, each only when
sent: `label`, `description`, `name`, `email`, `organization`. "Claude Max ·
name@example.com · Example Org"; an API key reads "Anthropic API key ·
ANTHROPIC_API_KEY" (`auth-status.js`'s `detail` as `description`).

120x40:

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.

 › /status
   ⎿  Agent:     claude
      Account:   Claude Max · name@example.com · Example Org
      Title:     Parser test tidy-up
      Model:     Opus 5.5
      Mode:      Auto
      Session:   6c1f2a0e-3b7d-4e19-9a51-0d2c8e4f7b13
      Directory: /work/app
   ⋮  (19 empty rows)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                 Opus 5.5 · high effort
```

80x24 (the row wraps under its value's column if it must, as every report
row):

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.

 › /status
   ⎿  Agent:     claude
      Account:   Claude Max · name@example.com · Example Org
      Title:     Parser test tidy-up
      Model:     Opus 5.5
      Mode:      Auto
      Session:   6c1f2a0e-3b7d-4e19-9a51-0d2c8e4f7b13
      Directory: /work/app
   ⋮  (3 empty rows)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                Opus 5.5 · high
```

| What chord holds | `Account` row(s) |
| --- | --- |
| Agent without `agentCapabilities.auth.status` | no row (*I2*) |
| Asked, no answer yet | `checking…` |
| `authenticated`, accounts | one row per account marked `active`, or every account if none is marked; a second row's label is blank |
| `authenticated`, no accounts | `signed in` |
| `unauthenticated` | `not signed in` |
| `not_required` | `none needed` |
| `unknown`, an unrecognised state (the SDK's MUST), or `auth/status` failed | `not reported by <agent>` |

The report is a snapshot, as every report: an `auth/status_update` after it
changes the next `/status`, not the one on screen. Nothing on the status
line or in the agents list shows the account; no notice when it changes.
A picked child's `/status` names its own process's account.

**Privacy.** `AuthAccount` is display only and "SHOULD NOT" be logged. The
report is window state, never recorded (`record.ts:630-760` records only
`prompt`, `update`, `asked`, `answered`), so the email reaches no file. The
`auth/status` traffic itself is protocol's (does chord's traffic log keep
it?).

### The sign-in failure at start

CHD-435's block stays; F2 adds one line at its top, from the last
`auth/status` answer or update, when there is one: `claude reports that no
account is signed in.` for `unauthenticated`, or `claude reports <accounts
as above>.` when it is signed in to something the start still refused. The
agent's `unauthenticated` carries no account (`toAcpAuthStatus`), so the
brief's "which account is missing" cannot be read from Claude's wire;
chord says the state, never a guess at the account.

120x40 (claude's `authMethods` as 0.107.0 sends them locally; the headline
is the agent's -32000 message, illustrative):

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 ⏺ claude did not start: Authentication required
   ⎿  claude reports that no account is signed in.
      claude offers these sign-ins:
        Claude Subscription · Use Claude subscription
        Anthropic Console · Use Anthropic Console (API usage billing)
      chord does not sign agents in. Sign in with claude's own CLI in a terminal, or set its API key where it offers
      one.
   ⋮  (24 empty rows)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

80x24:

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 ⏺ claude did not start: Authentication required
   ⎿  claude reports that no account is signed in.
      claude offers these sign-ins:
        Claude Subscription · Use Claude subscription
        Anthropic Console · Use Anthropic Console (API usage billing)
      chord does not sign agents in. Sign in with claude's own CLI in a
      terminal, or set its API key where it offers one.
   ⋮  (8 empty rows)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

*Owner choice I3* (with runtime): whether chord stops before `session/new`
on `unauthenticated` (the brief's words) or keeps the start as today and
uses the state to word the -32000 failure. The screen differs only in the
headline: stopping, it reads `claude did not start: claude reports that no
account is signed in.` and the block loses that line.

### State and logic

- `SessionState` (`src/ui/app/state.ts:141`) gains
  `auth?: AuthStatusResponse` (the SDK's type), and `SESSION_FIELDS`
  (`:1124`) its entry; an `auth_status` action sets it, dispatched by
  `app/sessions.ts` from the host's callback, as models reach the window
  (`model`, `:679`). Per session, because each session has its own agent
  process; a child shares nothing with main's.
- `reportFacts` (`reports.ts:58`) passes it; `statusReport` (`:385`) calls
  a new pure `accountRows(auth, agent)` in `reports.ts`, tested in
  `tests/ui/transcript/reports_test.ts`, which also cleans the strings.
- The sign-in line: `SignIn` (`src/session/sign_in.ts:18`) gains an
  optional `account?: string`, worded by a pure function there;
  `SignInBlock` draws it first. No new component.

## F3 — sessions open on the chosen mode, model and effort

Nothing new is drawn. What changes is what is not drawn: the status line's
first mode, model and effort are the ones chord asked for, as today after
`#applyStarting` (CHD-624 D1), only sooner.

- **A refused or ignored initial value** reads as today's line, the
  read-back finding the response's `configOptions` on another value and the
  fallback `set_*` refused (`conversation.ts:3398-3404`,
  `starting.ts:95-99`), today's capture at 80x24:

  ```
   ⏺ Could not start in nope mode, set by --permission-mode: the agent offers
     default, acceptEdits, plan
  ```

  [error]. A value the fallback sets after all draws nothing.
- **`session/new` refused because of an initial value** (an agent may answer
  -32602): today's start failure row, `⏺ claude did not start: <message>`,
  with CHD-454's block. Whether chord retries without the options is
  protocol's and runtime's, and a retry would be a workaround to put to the
  owner; the screen has no state of its own for it.
- No key, no slice, no component.

## F4 — notices as a dim line

### The line

A notice is its own transcript entry, drawn as a reply block is: `⏺` in
the gutter, then the `title`; the `description`, when sent, on the rows
under it, hanging at the text's column (3), wrapped at the room it has,
never cut. All dim. Blank lines inside a description fold to one break.

- **Glyph:** `⏺`, the transcript's one marker (width 1 under both width
  methods; `※` and `⚠` are East Asian ambiguous and would break columns).
- **Colour (*owner choice I4*):** the text always dim; the `⏺` dim for
  `info`, `warning` for `warning`, `error` for `error`, dim for any other
  severity. The title itself says what happened, so nothing rests on colour
  alone.
- **Place:** where it arrives among the turn's entries, as a tool call is:
  a notice mid-reply closes the reply block, and the reply's next chunk
  opens a new one, as the adapter's blockquote did. Outside a turn it is
  appended after the last entry and opens no cycle (`notice` is not in
  `CYCLE_WORK`, `cycles.ts:67-73`): no spinner, no OSC 7501, no bell. A
  subagent's notice goes into that subagent's entries, seen in its
  expanded view.
- **Repeats:** each is drawn; chord does not fold two alike (that would
  read their words). The adapter already drops repeats of a text it shows
  (`normalizeNoticeText`).
- **ctrl+o** (`app:toggleTranscript`): the same line; nothing folds.
- **Resume (*I5*, protocol's with the lead):** the notice arrives as an
  `update`, which the record keeps (`record.ts:727`), so a resumed session
  would draw it where it was. The SDK calls notices "live events rather
  than session history"; the bold text they replace was kept in history.
  Recommended: draw recorded notices on resume, as they were.

Idle, after a model switch that turns Auto off, 120x40 (Claude's words from
`session-mode.js:9-14`):

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.

 › /model sonnet
   ⎿  Switched to Sonnet 5.5

 ⏺ Auto mode unavailable
   The selected model does not support Auto mode; using Accept edits instead.
   ⋮  (22 empty rows)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ accept edits on (shift+tab to cycle)                                                       Sonnet 5.5 · high effort
```

80x24:

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › tidy the parser tests

 ⏺ Done: three tests merged into one table, all green.

 › /model sonnet
   ⎿  Switched to Sonnet 5.5

 ⏺ Auto mode unavailable
   The selected model does not support Auto mode; using Accept edits instead.
   ⋮  (6 empty rows)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ accept edits on (shift+tab to cycle)                      Sonnet 5.5 · high
```

Mid-turn, 120x40 (Claude's title from `session-fast-mode.js:146`, the
description illustrative):

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › rerun the lexer tests with coverage

 ⏺ Running the lexer suite with coverage now.

 ⏺ Fast mode turned off
   Rate limit for fast mode reached; it comes back after the limit resets.

 ⏺ Bash(bun test --coverage tests/lexer_test.ts)
   ⎿  Running…
   ⋮  (19 empty rows)

✻ Working… (12s · esc to interrupt)

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                 Opus 5.5 · high effort
```

80x24:

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › rerun the lexer tests with coverage

 ⏺ Running the lexer suite with coverage now.

 ⏺ Fast mode turned off
   Rate limit for fast mode reached; it comes back after the limit resets.

 ⏺ Bash(bun test --coverage tests/lexer_test.ts)
   ⎿  Running…
   ⋮  (3 empty rows)

✻ Working… (12s · esc to interrupt)

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                Opus 5.5 · high
```

An agent that does not send notices: nothing changes. An agent that
ignores the capability keeps sending its bold text, drawn as today.

### State and logic

- The entry kind (`notice`, with `severity`, `title`, `description`) is
  `src/session/transcript/`'s: `types.ts` and the reducer, protocol's
  draft; the window adds no slice.
- `src/ui/transcript/notice.ts`, pure: `noticeLines(notice, width)` →
  `{tone, lines}`, with the cleaning and the fold, tested in
  `tests/ui/transcript/notice_test.ts`.
- Drawn in `Transcript.tsx` beside the reply block with `useGap`, OpenTUI's
  `box`/`text` through `theme/text.ts`; no new component file is needed
  beyond the case, unless the case outgrows the file.

## F5 — the tool call names the subagent it started

### What it looks like

Claude 0.107 attaches the reference to a TaskStop or SendMessage call that
names a child, and to an Agent/Task call only when a permission request
kept it on screen (`native-subagents.js:1194-1222`); the Agent call is
otherwise drawn as chord's own `Agent(<title>)` block, which already names
the child. So the line appears mostly under calls *about* a child.

The call's first body line, under `⎿`, names the child as every other place
names a subagent, `agentHeadline(subagent, false)` (`subagents.ts:135`):
`Agent` bold, `(<title>)` plain, as `askerRow` draws it; the call's own
lines follow. A call with two references names each, one per line, in the
order sent.

120x40 (TaskStop's headline and result illustrative):

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › stop the build watcher, it is not needed

 ⏺ TaskStop
   ⎿  Agent(Watch the build)
      Stopped.

 ⏺ Stopped the build watcher; the other three agents are still running.
   ⋮  (23 empty rows)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                 Opus 5.5 · high effort
    background  ✻ 3 of main's agents working
```

80x24:

```
 ▀▄     chord v0.71.0
 ▀▀▀▄   claude · Opus 5.5
 ▄▀▀▀   /work/app
 ▀▀     ? for shortcuts · /help

 › stop the build watcher, it is not needed

 ⏺ TaskStop
   ⎿  Agent(Watch the build)
      Stopped.

 ⏺ Stopped the build watcher; the other three agents are still running.
   ⋮  (7 empty rows)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                Opus 5.5 · high
    background  ✻ 3 of main's agents working
```

- **Child not known** (a `sessionId` that is no subagent in this
  transcript, the main session's own, or a reference before its
  `subagent_update`): no line, as today. The RFD requires the announcement
  first, so a reference that arrives early names the child on the call's
  next update, which repeats it (the adapter puts it on every report with
  content).
- **Child ended**: still named, its entries stay; how it ended is its own
  block's.
- **A nested child** (a grandchild): found at any depth; named by its own
  headline, not its path.
- **chord's task agents** are chord calls, drawn by `chordLines`, not
  `contentLines`: unchanged.
- **Reaching it:** as today, ↓ from the prompt into the list under it and
  its `background` summary line, Enter into the background view, where the
  child's row stands under the same name. No new key, no jump from the call.

### State and logic

- Nothing new held: the reference stays in the call's `content` (CHD-624).
- `src/ui/transcript/agents/subagents.ts`, pure: `subagentById(entries,
  id)`, a depth-first find.
- `src/ui/transcript/tools/tools.ts`: `summary` (`:416`) gains a lookup
  parameter; `contentLines`' `default` keeps `session` as `[]`, and a pure
  `sessionLinks(call, lookup)` puts the headlines first. Tests in
  `tests/ui/transcript/tools/tools_test.ts` and the subagents test.

## `chord acp`

Nothing drawn: the window chord serves to another client has no screen.
What it relays, aliases and advertises is protocol's.

## Keys

| Key | Does | Rebindable | Panel |
| --- | --- | --- | --- |
| — | `/rename <title>` | — (a typed command) | unchanged; listed in the `/` list |
| ↓, Enter | reach a linked subagent, as today | as today | unchanged |
| ctrl+o | shows a notice the same | as today | unchanged |

`tests/ui/shortcuts/keys_test.tsx` needs nothing new: no key is added.

## States

| State | Status line | Transcript |
| --- | --- | --- |
| `/rename` in flight | unchanged | `⎿  Renaming to <title>…` |
| Renamed | unchanged; terminal status renamed | `⎿  Renamed to <title>` |
| Renamed, agent without `title` | unchanged | `… in chord only: …` |
| Refused, not open, exited | unchanged | one `error` note |
| `/status`, signed in | — | `Account:` row(s), `Title:` row |
| `/status`, signed out, unknown, no capability | — | `not signed in`, `not reported by <agent>`, no row |
| Start refused for sign-in | `? for shortcuts` | CHD-435's block with the account line first |
| Initial value refused | the agent's value | today's `Could not start …` line |
| Notice in a turn | spinner as before | `⏺ <title>` dim, description under it |
| Notice outside a turn | unchanged, no cycle | the same, after the last entry |
| Linked call | unchanged | `⎿  Agent(<title>)` first under the call |

Narrow (80x24) changes only where lines wrap; nothing is cut.

## Fixtures the screens need

Named for runtime, who owns the fake's scenarios: a fake that advertises
`sessionCapabilities.title` and answers `set_title` (and one that refuses
it); `auth.status` with each `AuthState`, two accounts one active, and an
update after a turn; a `notice` of each severity in and outside a turn and
in a subagent; a TaskStop call carrying a `session` reference to an
announced child, one to an unknown id, and one before the announcement.
Each screen above is then captured with `--fake --qa chd629-<name>` at both
sizes, as whole-window colour PNGs for the owner.

## Choices for the owner

- **I1. A `Title` row in `/status`.** a) Yes, after `Account`, `not given`
  when none. *Recommended*: with no child, nothing on screen shows the
  title `/rename` set. b) No; the terminal's status, the agents list and
  `/resume` are enough.
- **I2. `/status` for an agent without `auth.status`.** a) No `Account`
  row. *Recommended*: most agents chord runs cannot report one, and a row
  saying so in every report is noise. b) `Account: not reported by
  <agent>`, as `Model` and `Mode` do.
- **I3. Stop before `session/new` when `auth/status` says
  `unauthenticated`.** a) No: start as today, word the -32000 failure with
  the state. *Recommended*: Claude's `auth/status` waits up to 5 s for its
  CLI probe while nothing is known (`auth-status-reporter.js:107-115`), so
  asking before every start delays every start; and `unauthenticated` is the
  CLI's own login, not every route the agent may use (`auth-status.js`'s
  comment on `toAcpAuthStatus`). b) Yes, as the brief words it, when the
  answer is already there; c) Yes, waiting for it. Runtime weighs in.
- **I4. A notice's colour.** a) Dim text, the `⏺` in the severity's role.
  *Recommended*: an API error does not read like a hint. b) All dim, as
  the brief words it.

## Open questions

- **I5** (protocol, lead): draw a recorded notice on resume? Recommended yes.
- Whether a refused `set_title` keeps chord's title (protocol, runtime): the
  F1 note's words follow it.
- Whether `/rename` before the session opens is refused (drawn above) or
  held until it opens (runtime).
- The headline and result Claude gives a TaskStop or SendMessage call could
  not be read without a live run; the F5 screens mark them illustrative.

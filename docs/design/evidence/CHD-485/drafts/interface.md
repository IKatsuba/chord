# CHD-485 interface draft: chord's own agent on screen

The interface architect's answer to the brief's "interface" section. The screen,
its states and keys, and the state slices beneath it. Q5, Q7 and Q8, and the
screens of Q2 and Q4, are the owner's; each has its options, its evidence and a
recommendation, and none is settled here.

`builtin` stands in for the agent's name throughout (Q5), and `gpt-6.1-sol`
and `grok-4.7` for a plan's models (libfx `README.md:324`, `:352`). The words
in the drawings are proposals; libfx's own error messages are quoted as libfx
writes them.

Revised once after the critic's review, as the lead resolved it: sign-in
runs in the window in both Q1 options; the state machine is runtime's; `/cost`
and the context gauge follow protocol's enricher policy; Q4's and `/logout`'s
screens are drawn per option; every 80×24 drawing marked "the whole window"
is exactly 24 rows (checked by the renderer that drew them).

## What was read and run

- libfx 0.0.16, from `npm pack libfx@0.0.16` into an empty `/tmp` directory:
  `chatgpt-sign-in.js`, `grok-sign-in.js`, `chatgpt.js`,
  `types/chatgpt.d.ts`, `types/grok.d.ts`, `types/libfx.d.cts`, `README.md`.
  Line references are to those files.
- chord at origin/main (`4b09c049` in this worktree): the files named beside
  each point.
- `bun dev chord --fake --qa chd485-ui` in tmux at 120×40 and 80×24, for
  today's permission prompt (`permission`), tool calls (`tools`, `calls`),
  `/cost`, the shortcuts panel at both sizes and the link prompt (`link`).
  The drawings below copy those screens' shapes: frame, `⏺`/`⎿`, `›››`
  working line, the box above the prompt with a gap row, status line. The
  sign-in box itself does not exist yet, so it cannot be captured; its
  drawings are text, laid out by a script that fails on a row over the width
  or a window over its height. No real agent, model, provider or sign-in
  was reached. Claude Code's own `/login` screen was not captured (the lead's
  instructions limit hand checks to `--fake`), so where this draft says "as
  Claude Code", it means the shapes chord already copies from it, not a
  fresh capture.

## Where sign-in lives

### The options

- **A. A box in the window, above the prompt.** chord's own dialog, framed
  as the permission prompt and the pickers are, drawn over the transcript
  above the prompt (`src/ui/AGENTS.md`, CHD-545). It opens when the built-in
  agent starts without a credential, and on `/login`. One surface for the
  start and for switching.
- **B. A step of the title page**, before the window, as the agent picker is
  (`src/ui/app/Start.tsx:110`, `AgentsPage`). It covers only the start;
  `/login` mid-session still needs A's box, so it is two surfaces for one job.
- **C. The agent asks, over ACP elicitation**, which chord already draws: the
  link prompt (`src/ui/dialogs/Link.tsx:19`, captured below) for the
  browser's address, a form (`src/ui/dialogs/Form.tsx`) with an enum field
  for the provider and the way. ACP lets an elicitation be tied to a
  session or to a request (`ElicitationSessionScope |
  ElicitationRequestScope`, `@agentclientprotocol/sdk`
  `dist/v1/schema/types.gen.d.ts:795-820`), so an agent may ask during
  `session/new` before a session exists. What stops it today is chord's own
  handler: with nobody subscribed during a start it answers `cancel`
  (`src/session/elicitations.ts:127-130`; that is droid's "Sign-in was
  cancelled" in `docs/design/CHD-435.md`). That is chord's constraint and
  could change. It would also serve `chord acp`'s other clients. Against
  it: the link prompt has room only for its two choices, so a device code,
  a "port taken" state or an expiry would have to be the agent's message
  text; and those words would be the agent's strings, with no state of
  chord's to test.

Today's link prompt, which C would reuse (`--fake`, `link`, 80×24, the rows
that change):

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ fake asks you to open a link                                                 │
│ Sign in to Example to continue                                               │
│                                                                              │
│   https://example.com/oauth/authorize?client=abc&state=9f2c                  │
│   Opens example.com                                                          │
│                                                                              │
│ ❯ 1. Open in the browser                                                     │
│   2. Decline                                                                 │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
```

**Recommendation: A**, as the lead has resolved it for both Q1 options. The
box runs in chord's window process and writes the credential to the store.
In Q1-B the agent, a child process, only reads the store at its start and
writes back refreshed credentials; it draws nothing. What `chord acp` offers
its own clients for sign-in is protocol's (ACP `authMethods`), not this
screen.

**For the owner: the CHD-435 exception.** CHD-435 decided that chord does not
sign agents in and never calls `authenticate`
(`src/session/sign_in.ts:106`, `wayOn`). The box signs in chord's own agent.
Whether that is an exception the owner grants, scoped to the built-in agent
with CHD-435's line kept for every other agent, is the owner's question, not
this draft's.

### Its life

1. `chord builtin`, or the agent picked, with no credential in the store:
   the window opens as for any agent. The header says `builtin · not signed
   in`, a row says why, and the box opens on the provider step. The session
   is not started yet; the prompt is drawn but has no keys while the box does.
2. Provider → way → waiting (browser or code) → success, failure, expired
   or cancelled: runtime's state machine (below, "State slices"). Every step
   is a list of numbered choices; the box's keys are the pickers' and the
   permission prompt's.
3. Success: the box closes. The row under the reason says how it went and
   where the credential is kept, and the session starts. The header's second
   line becomes `builtin · ChatGPT · <model>`.
4. Esc on the first step, or Esc from a later one back to it: the attempt
   ends, the listener is closed (the brief's settled point), polling stops,
   and the row says `Not signed in. /login to sign in, or /new for another
   agent.` The prompt takes keys and answers chord's own commands only. A
   typed prompt gets the status line's notice `builtin is not signed in:
   /login`.
5. `/login` at any time opens the box again (switching, below). `/logout`
   signs out.

Order of work in the browser way: bind the listener first, then show the
address and open the browser (runtime's listener section). A taken 1455 is
then known before the person leaves for the browser, and the box goes to
"port taken" without opening a page that cannot come back.

## The sign-in screens

Colour roles (`src/ui/theme/theme.ts:73-120`, the `Palette`): the box's
border, title and `❯` are `permission`, as the permission prompt's and the
pickers' are; the address is `link`, the code bold in the terminal's own
foreground; a provider's note after ` · ` is dim; the failure sentence is
`error`; the "port taken" and "no store" sentences are `warning`; the
success row's `⎿` is dim and its text plain; the `›››` working line is
`accent`, as today. Nothing else is coloured.

"The whole window" drawings are every row of the window. The others show
the rows that change; the rows above are A's header and row. At 80×24 a box
taller than the room left takes rows from the transcript first, as the
permission prompt does (`src/ui/dialogs/Permission.tsx:205-212`): the header
scrolls off before the box is cut.

### A. Choosing the provider

120x40, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan



















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to builtin                                                                                                   │
│                                                                                                                      │
│ builtin runs on your ChatGPT or Grok plan. Your plan and its provider's terms apply to its turns.                    │
│                                                                                                                      │
│ ❯ 1. ChatGPT · a ChatGPT plan                                                                                        │
│   2. Grok · a Grok plan                                                                                              │
│                                                                                                                      │
│ Enter to choose · Esc to cancel                                                                                      │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

80x24, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan


╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to builtin                                                           │
│                                                                              │
│ builtin runs on your ChatGPT or Grok plan. Your plan and its                 │
│ provider's terms apply to its turns.                                         │
│                                                                              │
│ ❯ 1. ChatGPT · a ChatGPT plan                                                │
│   2. Grok · a Grok plan                                                      │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

The notes after each provider say only "a ChatGPT plan" and "a Grok plan":
libfx names no plans (`types/libfx.d.cts:626-663`), and chord should not list
plan tiers it cannot check. Only those two rows unless Q3 adds AI Gateway or
a custom server; each would be a row here, with its own next step (a key
field), not drawn.

The line on terms is there because Q9 is open. It stays only if the owner
wants it.

### B. Choosing the way

120x40, the box and below (the rows above as in A):

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT                                                                                                   │
│                                                                                                                      │
│ ❯ 1. In the browser · chord opens OpenAI's page and listens on localhost:1455 for its answer                         │
│   2. With a code · enter a short code on OpenAI's page, in any browser, on any device                                │
│                                                                                                                      │
│ Enter to choose · Esc to go back                                                                                     │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

80x24, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan



╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT                                                           │
│                                                                              │
│ ❯ 1. In the browser · chord opens OpenAI's page and listens on               │
│      localhost:1455 for its answer                                           │
│   2. With a code · enter a short code on OpenAI's page, in any               │
│      browser, on any device                                                  │
│                                                                              │
│ Enter to choose · Esc to go back                                             │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

For Grok, the first row says `xAI's page` and `a free port on 127.0.0.1`
(`grok-sign-in.js:36-37`). The order is the brief's: browser first.

### C. Waiting on the browser

Choosing "In the browser" is the key press that opens the page.
`src/links.ts:1-6` opens a link only on a key press, through `open`. The
address is drawn whole at 120 columns, as the link prompt draws its link.
At 80 it folds after its first row with the existing `Fold`
(`src/ui/dialogs/Fold.tsx`), since a 400-character address over five rows
helps nobody and "Copy the address" carries it whole.

120x40:

```text
 ››› Waiting for the browser… (12s)

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT in the browser                                                                                    │
│                                                                                                                      │
│ chord opened this address. Sign in there; chord goes on when OpenAI sends the browser back to localhost:1455.        │
│                                                                                                                      │
│   https://auth.openai.com/oauth/authorize?response_type=code&client_id=app_EMoamEEZ73f0CkXaXp7hrann&redirect_uri=ht  │
│   tp%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&scope=openid+profile+email+offline_access+api.connectors.read+api.co │
│   nnectors.invoke&code_challenge=…&state=…                                                                           │
│   Opens auth.openai.com                                                                                              │
│                                                                                                                      │
│ ❯ 1. Open it again                                                                                                   │
│   2. Copy the address                                                                                                │
│   3. Use a code instead                                                                                              │
│                                                                                                                      │
│ Enter to choose · Esc to give up                                                                                     │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

80x24, the whole window: the transcript gives way at the top:

```text

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan

 ››› Waiting for the browser… (12s)
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT in the browser                                            │
│                                                                              │
│ chord opened this address. Sign in there; chord goes on when                 │
│ OpenAI sends the browser back to localhost:1455.                             │
│                                                                              │
│   https://auth.openai.com/oauth/authorize?response_type=code&client_id=a     │
│   … +3 lines (2 to copy the whole address)                                   │
│                                                                              │
│ ❯ 1. Open it again                                                           │
│   2. Copy the address                                                        │
│   3. Use a code instead                                                      │
│                                                                              │
│ Enter to choose · Esc to give up                                             │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

The `›››` line is the existing working line with its elapsed time
(`src/ui/status/status.ts:659`, `workingLine`), worded for the wait. When the
redirect lands, the driver passes the whole address to `finishSignIn`
(`chatgpt-sign-in.js:62`, `grok-sign-in.js:53`); the working line says
`Finishing the sign-in…` until it returns. The page in the browser is the
listener's answer, which runtime words.

A redirect whose `state` is from another sign-in
(`*_SIGN_IN_STATE_MISMATCH`, an older tab) does not change this box: the
browser page shows the error and the listener keeps waiting (runtime's
transition). The box stays as drawn.

The browser flow has no deadline in libfx; runtime proposes one (its open
question 3). If it is taken, its end is the expired box of F, worded `The
browser did not come back in 10 minutes.`

### D. Port 1455 taken (ChatGPT only)

The redirect is fixed (`chatgpt-sign-in.js:12`); Grok picks its own port and
calls `startSignIn` again if that one is taken (runtime), so it never shows
this box.

120x40:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT in the browser                                                                                    │
│                                                                                                                      │
│ localhost:1455 is taken by another program. OpenAI sends the browser back only there, so chord cannot sign in in the │
│ browser while it is. Sign in with a code, or close that program and try again.                                       │
│                                                                                                                      │
│ ❯ 1. Use a code instead                                                                                              │
│   2. Try the browser again                                                                                           │
│                                                                                                                      │
│ Enter to choose · Esc to go back                                                                                     │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

80x24, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT in the browser                                            │
│                                                                              │
│ localhost:1455 is taken by another program. OpenAI sends the                 │
│ browser back only there, so chord cannot sign in in the browser              │
│ while it is. Sign in with a code, or close that program and try              │
│ again.                                                                       │
│                                                                              │
│ ❯ 1. Use a code instead                                                      │
│   2. Try the browser again                                                   │
│                                                                              │
│ Enter to choose · Esc to go back                                             │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Considered and left out of the MVP: a "Paste the address" choice, libfx's own
documented browser flow (`types/chatgpt.d.ts:13`, `:45-46`). It would reopen
the settled outcome (device code is what is offered), and with 1455 taken
the browser's callback may reach the program that holds the port.

### E. The device code

120x40:

```text
 ››› Waiting for the code… (1m 04s)

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT with a code                                                                                       │
│                                                                                                                      │
│ Open the address, sign in, and enter the code. chord goes on once you have.                                          │
│                                                                                                                      │
│   https://auth.openai.com/codex/device                                                                               │
│   Opens auth.openai.com                                                                                              │
│                                                                                                                      │
│   WXYZ-1234                                                                                                          │
│                                                                                                                      │
│ The code expires in 14 minutes. If OpenAI's page says device code sign-in is off, turn it on in ChatGPT's security   │
│ settings, or ask your workspace admin.                                                                               │
│                                                                                                                      │
│ ❯ 1. Open the address in the browser                                                                                 │
│   2. Copy the code                                                                                                   │
│   3. Copy the address                                                                                                │
│                                                                                                                      │
│ Enter to choose · Esc to give up                                                                                     │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

80x24, the whole window: the transcript gives way at the top:

```text
 ››› Waiting for the code… (1m 04s)
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT with a code                                               │
│                                                                              │
│ Open the address, sign in, and enter the code.                               │
│                                                                              │
│   https://auth.openai.com/codex/device                                       │
│                                                                              │
│   WXYZ-1234                                                                  │
│                                                                              │
│ The code expires in 14 minutes. If OpenAI's page says device                 │
│ code sign-in is off, turn it on in ChatGPT's security settings.              │
│                                                                              │
│ ❯ 1. Open the address in the browser                                         │
│   2. Copy the code                                                           │
│   3. Copy the address                                                        │
│                                                                              │
│ Enter to choose · Esc to give up                                             │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

The code is drawn on a row of its own, bold, with nothing else on it, so a
mouse selection or the terminal's double-click takes it whole. "Copy the
code" uses OpenTUI's clipboard service, as chord's copy does today
(`src/ui/app/selection.ts:4`; `copyToClipboardOSC52`,
`node_modules/@opentui/core/renderer.d.ts:613`).

Expiry is a countdown in whole minutes, `The code expires in N minutes`, from
the device sign-in's `expiresAt` (`types/chatgpt.d.ts:28`,
`types/grok.d.ts:29`). It is redrawn by chord's timer (`src/ui/app/timers.ts`)
once a minute, not every second, matching runtime's countdown. Under a
minute it says `in less than a minute`. ChatGPT's code lasts 15 minutes
(`chatgpt-sign-in.js:15`), Grok's as xAI's `expires_in` says
(`grok-sign-in.js:85,95`). The note on device code being off is libfx's own
warning, from its expiry message (`chatgpt-sign-in.js:106-109`), said up
front because ChatGPT gives no sign until expiry (runtime). It is ChatGPT's
alone; Grok's box leaves it out.

### F. Success, failure, expired, cancelled

Success, 120x40, the top of the window: the box closes, a row stays, the session starts:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · ChatGPT · gpt-6.1-sol
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Signed in to ChatGPT in the browser. Kept in the macOS Keychain.
```

Success, 80x24, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · ChatGPT · gpt-6.1-sol
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Signed in to ChatGPT with a code. Kept in the macOS Keychain.













╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                    gpt-6.1-sol · medium effort
```

Failure (any error but expiry), 120x40:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT                                                                                                   │
│                                                                                                                      │
│ The sign-in failed: OpenAI could not finish the sign-in (HTTP 502).                                                  │
│                                                                                                                      │
│ ❯ 1. Try again                                                                                                       │
│   2. Use a code instead                                                                                              │
│   3. Choose another plan                                                                                             │
│                                                                                                                      │
│ Enter to choose · Esc to cancel                                                                                      │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Failure, device code refused, 80x24, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT with a code                                               │
│                                                                              │
│ The sign-in failed: OpenAI did not issue a device code (HTTP 403).           │
│ ChatGPT accounts and workspaces must turn device code sign-in on in          │
│ ChatGPT's security settings first.                                           │
│                                                                              │
│ ❯ 1. Try again                                                               │
│   2. Sign in in the browser instead                                          │
│   3. Choose another plan                                                     │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Expired, 120x40:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to Grok with a code                                                                                          │
│                                                                                                                      │
│ The code expired before it was entered. Start again.                                                                 │
│                                                                                                                      │
│ ❯ 1. Get a new code                                                                                                  │
│                                                                                                                      │
│ Enter to choose · Esc to go back                                                                                     │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Expired, 80x24, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan




╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to Grok with a code                                                  │
│                                                                              │
│ The code expired before it was entered. Start again.                         │
│                                                                              │
│ ❯ 1. Get a new code                                                          │
│                                                                              │
│ Enter to choose · Esc to go back                                             │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Cancelled, 120x40, the top of the window: Esc on the first step; the listener is closed, the prompt takes keys:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Not signed in. /login to sign in, or /new for another agent.
```

Cancelled, 80x24, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Not signed in. /login to sign in, or /new for another agent.













╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

The failure sentence is `The sign-in failed: ` and then libfx's own
`message`, unchanged, as CHD-435 keeps an agent's own words. The
choices after it come from the error's `code`, never from its text:

| libfx code | Box | Choices |
| --- | --- | --- |
| `…_SIGN_IN_EXPIRED` (browser; `chatgpt-sign-in.js:47`) | failure | Try again · Use a code · Another plan |
| `…_DEVICE_CODE_EXPIRED` (`:106`, `grok-sign-in.js:104,115`) | expired | Get a new code (Esc goes back) |
| `…_DEVICE_CODE_UNAVAILABLE` (`chatgpt-sign-in.js:83`) | failure, ChatGPT adds the security-settings line | Try again · Browser · Another plan |
| `…_SIGN_IN_DENIED` (`grok-sign-in.js:117`) | failure | Try again · Another plan |
| `…_STATE_MISMATCH` | no box: the page shows it, the wait goes on (C) | none |
| `…_INVALID_ADDRESS` | failure | Try again |
| `LIBFX_GROK_ACCOUNT_UNAVAILABLE` | failure | Try again · Another plan |
| `…_SIGN_IN_FAILED`, anything else | failure | Try again · the other way · Another plan |

Cancelled leaves no box. The row says so and the window stays usable, as in
"Its life", step 4.

### G. No credential store (Q4's screens)

The options are runtime's C1 to C4 (refuse; a 0600 file the person names in
settings; environment only; memory for the process's life), and the owner's.
Runtime recommends C1 with C4 offered on the same screen. What a store gives
is the same in both Q1 options. **C4 depends on Q1**: in Q1-A the agent runs
in the window's process and can use the memory copy; in Q1-B the agent is a
child that reads the store at its start, and whether a memory-only
credential can reach it is runtime's open finding. The box offers a choice
only where it works: "Sign in for this run only" is drawn only when C4
reaches the agent, and otherwise the box is C1 alone.

C1 with C4 beside it, where C4 reaches the agent (Q1-A; Q1-B only if runtime finds a way), 120x40:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT                                                                                                   │
│                                                                                                                      │
│ chord keeps your sign-in in the system's credential store, and none answered: no Secret Service (gnome-keyring or    │
│ KeePassXC). Start one and try again, or sign in for this run only: chord forgets the sign-in when it quits.          │
│                                                                                                                      │
│ ❯ 1. Sign in for this run only                                                                                       │
│   2. Try the store again                                                                                             │
│                                                                                                                      │
│ Enter to choose · Esc to cancel                                                                                      │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

C1 alone, where C4 does not reach the agent, 80x24, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan


╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT                                                           │
│                                                                              │
│ chord keeps your sign-in in the system's credential store, and               │
│ none answered: no Secret Service (gnome-keyring or KeePassXC).               │
│ Start one and try again.                                                     │
│                                                                              │
│ ❯ 1. Try the store again                                                     │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

C4 chosen: the success row says so, 80x24, the top of the window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Signed in to ChatGPT for this run only: no credential store
      answered, so chord forgets the sign-in when it quits.
```

C2, a file the person named in settings, 80x24, the top of the window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · not signed in
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Signed in to ChatGPT. Kept in the file your settings name (mode
      0600), as no credential store answered.
```

C2, that file readable by others: refused, 80x24, the top of the window:

```text
 ⏺ builtin did not start: its credential file can be read by others
   ⎿  chord reads a credential file only at mode 0600. Run chmod 600 on
      the file your settings name, then start builtin again.
```

C3, environment only, 80x24, the top of the window:

```text
 ⏺ builtin did not start: no credential store answered
   ⎿  Set CHORD_CHATGPT_REFRESH_TOKEN, or start a Secret Service
      (gnome-keyring or KeePassXC), and start builtin again.
```

A slow store (bounded read), 120x40, the working line:

```text
 ››› Reading the sign-in from the macOS Keychain… (4s)
```

C2 is never offered in the box: runtime has the file only where the person
names it in settings, so no plaintext file is written by a key press in a
dialog. The box above says nothing of it either; the setting's name is
protocol's or runtime's to give. The variable in C3's row is a stand-in.

The bounded read has its own working line (the last drawing). When the
20 s bound runs out, the box opens on C1's screen with `The macOS Keychain
did not answer in 20 s.` in place of the no-Secret-Service sentence. The
store's name comes from the platform module (runtime): Keychain, Secret
Service or Credential Manager.

## Signing out and switching

- **`/logout`** (chord's command, `owner: 'chord'` in
  `src/ui/prompt/commands.ts:10-26`): a confirm box, then the credential is
  deleted from the store. Only for the built-in agent. With another agent,
  `/logout` is not on the list: chord does not sign other agents in or out.
- What happens to running sessions is open: protocol has a running session
  keep its credentials until its next refresh, and runtime is proposing the
  invalidation rule, which goes to the owner. Each option's outcome is drawn
  below, not settled:
  - **L1. This session ends at once.** This window's row says so; another
    window or child on the same account finds out at its next refresh, and
    shows the sign-in box under a row.
  - **L2. Every session goes on until its next refresh**, this one included,
    then shows the same box. The confirm box's "This session ends." becomes
    "Sessions go on until their sign-in next refreshes."
- **`/login`**: the box of A, with the provider signed in marked `✔`
  (`CURRENT_MARK`, `src/ui/pickers/picker.ts:22`). Picking it again signs in
  again (another account); picking the other provider signs in to it.
  Success starts a new session in place, as `/clear` does. The transcript
  stays above, under a row naming the new plan. Runtime keeps one account
  per provider, so a second account on the same provider replaces the
  first; the other provider's credential is kept unless `/logout` removes
  it. Whether a session can carry its conversation across providers is
  protocol's (Q6). This draft assumes it cannot.
- The agent runs on the provider last signed in to, kept in chord's
  settings as the agent's provider. Where that setting lives is protocol's.

/login while signed in, 120x40, the rows that change:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to builtin                                                                                                   │
│                                                                                                                      │
│ Signed in to ChatGPT. Signing in to another plan or account starts a new session; this transcript stays above it.    │
│                                                                                                                      │
│ ❯ 1. ChatGPT ✔ · sign in again, to another account                                                                  │
│   2. Grok · a Grok plan                                                                                              │
│                                                                                                                      │
│ Enter to choose · Esc to cancel                                                                                      │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                            gpt-6.1-sol · medium effort
```

/logout's confirm, 80x24, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · ChatGPT · gpt-6.1-sol
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 › /logout


╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign out of ChatGPT?                                                         │
│                                                                              │
│ chord forgets the sign-in in the macOS Keychain. This session ends.          │
│ OpenAI's own sessions in your browser stay signed in.                        │
│                                                                              │
│ ❯ 1. Sign out                                                                │
│   2. Keep the sign-in                                                        │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                    gpt-6.1-sol · medium effort
```

L1, this window: the session ends at once, 80x24, the rows that change:

```text
 › /logout
   ⎿  Signed out of ChatGPT. This session has ended; /login to sign in
      again, or /new for another agent.
```

L1 and L2, another window on the same account, at its next refresh, 80x24, the whole window:

```text
 ⏺ Renamed it; the one test passes.

 ⏺ builtin is signed out of ChatGPT
   ⎿  The sign-in was removed, here or in another chord. Sign in again to
      go on; this transcript stays above.






╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to builtin                                                           │
│                                                                              │
│ ❯ 1. ChatGPT · a ChatGPT plan                                                │
│   2. Grok · a Grok plan                                                      │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

L2, this window: the session goes on until its next refresh, 80x24, the rows that change:

```text
 › /logout
   ⎿  Signed out of ChatGPT. This session goes on until its sign-in next
      refreshes; then it asks you to sign in again.
```

Claude Code names its commands `/login` and `/logout`; chord takes the same
names. Neither name is taken in chord's list today
(`src/ui/prompt/commands.ts:11-26`) or in Claude Code's commands that chord
passes on as the agent's.

## Keys and the shortcuts panel

Every action in the box is a numbered choice. So the box adds **no new key**.
It answers the keys the permission prompt and the pickers already answer, and
the panel already lists (captured at 120×40 and 80×24):

- `1–9 to pick a choice`
- `↑ ↓ or j k to move between choices`
- `enter to pick the highlighted choice`
- `esc ← to leave a picker or shortcuts`, which covers the box's Esc. The
  hint in the box words it per step: `Esc to go back`, `Esc to give up`,
  `Esc to cancel`.

Copying and opening again are choices, not letter keys. A `c` or `o` key
would be a widget-owned key, with its own `keys.ts` entry and test
(`AGENTS.md`, "Every action has a key"), and would add nothing a digit does
not already do.

**How commands are findable today.** The `?` panel lists one line for all
slash commands, `/ @ @@ for commands, files or agents`
(`src/ui/shortcuts/keys.ts:274`, `commands: []`), and one command by name,
`/vim for vim mode` (`keys.ts:450-465`). `/vim` is listed because it turns
on a set of keys. Other commands (`/cost`, `/model`, `/new`) are found in
the slash list, with their descriptions, not in the panel. Following that:

| Action | Key | Rebindable | Where it is listed |
| --- | --- | --- | --- |
| sign in, switch | `/login` | no: a command, not a binding | slash list: `Sign in to a ChatGPT or Grok plan for builtin`; `?` panel: one new line, `/login /logout to sign builtin in or out`, `commands: []`, after `/vim` |
| sign out | `/logout` | no | slash list: `Sign out of builtin's plan`; the same panel line |
| give up a sign-in | `esc` | no: the pickers' Esc, as today | covered by `esc ← to leave a picker or shortcuts` |

The panel line follows `/vim`'s precedent: a command named in the panel
because a person may not guess it. At 80×24 the panel already scrolls ("↓ 5
lines below", captured), so one more line costs nothing in fit. If the owner
prefers commands only in the slash list, as `/cost` is, the panel line
goes; that is the only exception to take.

The key test (`tests/ui/shortcuts/keys_test.tsx`) needs the box added to the
widgets whose keys it presses, as the permission prompt and the link prompt
are. The box answers no key outside that list.

`/login` is listed for every agent (it switches to the built-in agent's
sign-in) and `/logout` only for the built-in agent. That is a choice to make.

## The picker entry and the header (Q5)

The start picker, 120x40 (title page rows above as today):

```text
 Select agent

 ❯   1.  builtin · chord's own agent · on a ChatGPT or Grok plan
     2.  agoragentic-acp · Agoragentic
     3.  auggie · Auggie CLI
     4.  autohand · Autohand Code
     5.  bob · Bob
     6.  claude · Claude Agent
   ↓ 7.  cline · Cline
     … +21 more

 ↑↓ or j/k to move · Enter or 1–9 to select · Esc to cancel
```

The same rows at 80x24:

```text
 ❯   1.  builtin · chord's own agent · on a ChatGPT or Grok plan
     2.  agoragentic-acp · Agoragentic
```

The row's title is chord's own: `chord's own agent · on a ChatGPT or Grok
plan`, drawn by `agentChoices` (`src/ui/pickers/picker.ts:131-148`) from a
`ListedAgent` with `from: 'builtin'`. That is a new value beside
`'npx' | 'uvx' | 'cli' | 'settings'` (`src/agents.ts:205-219`), and
`chord agents` writes it as `built in`. The row says nothing about whether a
sign-in is held: reading the store to say so could block the picker on a
locked keychain (G). The picker stays a pure list.

### Q5 options: the name

Taken names, so not available: `fx` (`src/clis.ts:43`, the fx CLI over ACP),
`codex`, `grok-build`, and every registry id (`src/registry.ts`). Also
`agents`, `acp` and `upgrade`, chord's subcommands (`src/main.tsx:611-664`),
since `chord <name>` must not mean both.

- **`builtin`**: says what it is. `chord builtin` reads plainly, and
  settings read `agents.builtin`. Recommendation.
- **`chord`**: the brand. `chord chord` and a header of `chord · …` under
  the wordmark read twice, and `agents.chord` in settings is easily misread
  as chord's own settings.
- **A short name of its own** (the owner's pick): reads best in the header,
  but says nothing until someone learns it.

Runtime's module folder (`src/agent/` in its draft, a placeholder) takes
the chosen name.

### Q5 options: the default

- **Keep `claude` as the picker's first preference** (`DEFAULT_AGENT`,
  `src/agents.ts:20`). The built-in agent is the picker's first row, so it is
  one `↑` away. Recommendation.
- **The built-in agent becomes the default.** Then a person with Claude
  Code installed lands on a sign-in box the first time.
- **The built-in agent when `claude` is not on PATH.** Kinder to a person
  with nothing installed, but it is a rule that changes the default by what
  PATH holds, which `offeredAgents` today does not do
  (`src/agents.ts:276-301`).

The first row is drawn first because it needs nothing installed. Today's
order is the registry's, then the table's (`src/agents.ts:89-98`). Putting
the built-in agent first is part of this question.

## The status line, the header and `/cost` for a plan (Q7)

What libfx reports: per turn, `FxUsage` with input, output, cache read, cache
write and reasoning tokens, each only when the provider gave it
(`types/libfx.d.cts:255-262`). It is on the turn's result (`:813`,
`FxEngineTurnResult.usage`) and on `model.end` hooks (`:408`). It reports no
price, no plan limit, no rate-limit window and no context window size:
nothing in `subscription.js` or the types reads one. `listModels` covers AI
Gateway only (`:1064`, `apiKey` required), so a plan's model list is not
libfx's to give (protocol's, `/model`).

Where the cost is made: chord does not price at draw time. `costFromTokens`
(`src/session/enrichers.ts:58-128`) writes a `usage_update` with chord's
estimate into the stream, and so into the session's record, before the
reducer or `/cost` sees it. A note in `spend_table.ts` alone would
contradict the record and the window's summed `/cost`. So each Q7 option is
an enricher policy first, which protocol specifies, and the screen only
draws what the record holds.

- **Header**: `builtin · ChatGPT · gpt-6.1-sol`. The provider sits between
  the agent and the model, so the plan in use is always visible.
- **Status line**: model and effort, as drawn. The context gauge (`N%
  context used`, `contextUsed`, `src/ui/status/status.ts:266`) appears only
  if protocol's O-U option gives the window a size. Protocol recommends none,
  so no drawing here shows one. With a source, it is drawn as for any agent.
- **`/cost`**: the options, drawn below.
  - **a. Cost unknown, never a numeric zero.** The enricher does not fill a
    cost for the built-in agent on a plan, and the record keeps tokens with
    no cost. `/cost` says the cost is unknown and why, in the shape of the
    existing "provider reports no cost" note
    (`src/ui/transcript/spend_table.ts:57`). The window's sum counts it as
    not reported, never as $0. Recommendation: a flat plan has no per-token
    cost, and an API-price estimate would read as a bill.
  - **b. chord's estimate at the model's API price, marked `~`**: the
    enricher runs as for any agent that gives no cost
    (`src/ui/transcript/spend.ts:28-58`), and `/cost` adds that the plan is
    not charged per token. Honest about the work done, but misleading as
    money, and the sum mixes it with real bills.
  - **c. a or b, plus the plan's limits.** libfx does not give them. chord
    reads Codex plan windows today only through the Codex CLI's app server
    (`src/session/codex_resources.ts:12-40`), which the person may not have
    installed, and has no Grok reader. Not for the MVP.

Option a (recommended): cost unknown, tokens kept, 120x40:

```text
 › /cost
   ⎿  Total cost:   unknown: builtin runs on your ChatGPT plan, which reports no cost per token
      Tokens in:    48,210
      Tokens out:   3,904
      Cache read:   41,000
      Session time: 6m 12s
```

Option b: chord's estimate at API prices, marked, 80x24:

```text
 › /cost
   ⎿  Total cost:   ~$0.0961 (chord's estimate at gpt-6.1-sol's API
                    price; your ChatGPT plan is not charged per token)
      Tokens in:    48,210
      Tokens out:   3,904
      Cache read:   41,000
      Session time: 6m 12s
```

## Tool rendering (Q8)

chord draws a call from its ACP `kind`, `title`, `rawInput`, `content` and
`locations`. The headline is a leading capitalised verb from the title, or
else the kind's Claude Code name: `read → Read`, `edit → Update`,
`execute → Bash`, `search → Search`, `fetch → Fetch`
(`src/ui/transcript/tools/tools.ts:66-77`, `:240-271`). Diffs come from
`diff` content, terminal output from `terminal` content
(`tools.ts:513-528`). Whatever Q1 answers, the built-in agent's calls reach
the transcript as ACP tool calls. Either its ACP adapter or the in-process
adapter writes the same updates, so the rendering question is what those
updates carry.

- **a. Claude Code's names, through chord's existing mapping.** Each tool
  sets its `kind` and a verb-first title: `Read src/greeting.ts`, `Update
  src/greeting.ts` with `diff` content, `Write notes.txt` for a new file,
  `` `bun test` `` (code span) with kind `execute` for `Bash(bun test)`,
  `Search greeting in src`. Output: `Read 4 lines` and `Found 3 files` as
  result text, the command's output as text content or a terminal. No new
  rendering code. Claude's and Codex's calls already look this way in chord.
  Recommendation.
- **b. libfx's tool names as titles** (`tool_start.name`,
  `types/libfx.d.cts:248-252`), say `read_file(…)`. Honest to the engine,
  but unlike every other agent on screen, and the names are chord's own
  anyway (the native backend turns fx's tools off).
- **c. A renderer of its own for the built-in agent**, keyed on the agent.
  Room for richer views, but it is a second path to keep level with the first.
  Nothing in the MVP's tools needs it.

How a running shell's output streams (a `terminal` the client owns, or text
content updated as it grows) is runtime's (`src/shell.ts`). Both already
draw: the `--fake` `tools` and `calls` scenarios show both.

Streaming, 120x40, the whole window:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · ChatGPT · gpt-6.1-sol
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 › rename greeting to welcome and run the tests

 ✻ Thinking…
   The greeting lives in src/greeting.ts; the tests import it by name.

 ⏺ Search(greeting in src)
   ⎿  Found 3 files

 ⏺ Read(src/greeting.ts)
   ⎿  Read 4 lines

 ⏺ Update(src/greeting.ts)
   ⎿  Updated src/greeting.ts with 1 addition and 1 removal
       1 - export const greeting = 'Hello';
       1 + export const welcome = 'Hello';

 ⏺ Bash(bun test tests/greeting_test.ts)
   ⎿  bun test v1.4.4
      tests/greeting_test.ts:
      ✓ welcome says hello [0.12ms]
      … +2 lines (ctrl+o to expand)

 ⏺ Renamed it; the one test passes.

 ››› Working… (18s · esc to interrupt)






╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                            gpt-6.1-sol · medium effort
```

Streaming, 80x24, the whole window:

```text
 ⏺ Update(src/greeting.ts)
   ⎿  Updated src/greeting.ts with 1 addition and 1 removal
       1 - export const greeting = 'Hello';
       1 + export const welcome = 'Hello';

 ⏺ Bash(bun test tests/greeting_test.ts)
   ⎿  bun test v1.4.4
      tests/greeting_test.ts:
      ✓ welcome says hello [0.12ms]
      … +2 lines (ctrl+o to expand)

 ⏺ Renamed it; the one test passes.

 ››› Working… (18s · esc to interrupt)






╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                    gpt-6.1-sol · medium effort
```

Thinking (`reasoning_delta`, `types/libfx.d.cts:246`) is drawn as any
agent's thought chunks are. A steer (`user_message`, `:247`) reaches the
turn from the queue as any agent's does: Tab sends the oldest queued row
(`src/ui/AGENTS.md`).

## The permission prompt for chord's own tools

The prompt draws the agent's own options in the agent's order and invents
none (`src/ui/dialogs/permission.ts:35-42`). For the built-in agent, chord is
the agent, so the option names are the design's to choose. The proposal
follows Claude Code's wording in chord's existing shape: `Allow`, `Allow
<edits | this command> for this session` (`allow_always`), `Deny`
(`reject_once`, Esc's answer, `src/session/permissions.ts:51-59`). The
request shows the call's diff or command, as the box already scrolls a
request in half the window (`src/ui/dialogs/Permission.tsx:205-212`). What
"for this session" covers, an exact command or its first word, and which
calls ask at all, are Q2's (runtime). The drawings take "edits" and "the
command's first word" as stand-ins.

An edit, 120x40, the rows that change:

```text
 ››› Waiting for permission… (3s)

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Update src/greeting.ts                                                                                               │
│                                                                                                                      │
│    1 - export const greeting = 'Hello';                                                                              │
│    1 + export const welcome = 'Hello';                                                                               │
│                                                                                                                      │
│ Do you want to proceed?                                                                                              │
│ ❯ 1. Allow                                                                                                           │
│   2. Allow edits for this session                                                                                    │
│   3. Deny                                                                                                            │
│                                                                                                                      │
│ Esc to reject                                                                                                        │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                            gpt-6.1-sol · medium effort
```

A command, 80x24, the whole window:

```text
 › rename greeting to welcome and run the tests

 ⏺ Update(src/greeting.ts)
   ⎿  Updated src/greeting.ts with 1 addition and 1 removal


 ››› Waiting for permission… (3s)

╭──────────────────────────────────────────────────────────────────────────────╮
│ Bash bun test tests/greeting_test.ts                                         │
│ in ~/projects/app                                                            │
│                                                                              │
│ Do you want to proceed?                                                      │
│ ❯ 1. Allow                                                                   │
│   2. Allow bun test for this session                                         │
│   3. Deny                                                                    │
│                                                                              │
│ Esc to reject                                                                │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                    gpt-6.1-sol · medium effort
```

## State slices and pure modules

One source of truth for the transitions: **the sign-in state machine is
runtime's** pure module, `src/<agent>/sign_in.ts` (`src/agent/` in runtime's
draft, named after Q5), with its driver `sign_in_run.ts` beside it. The
interface draws that machine's state and sends it the person's choices. It
holds no transition of its own. Following `src/ui/AGENTS.md`:

- **`src/ui/sign_in/state.ts`**: the box's slice. It holds the machine's
  current state as runtime's module types it (step, provider, way, address,
  code, `expiresAt`, error code and message), the current `attempt` id, and
  the box's own `highlighted` row. Nothing secret: no verifier, no token.
  Those stay with the driver.
- **`src/ui/sign_in/view.ts`**, pure, presentation only: `choicesFor(state)`
  (the rows and their order per step, including F's table), `wordsFor(state,
  store)` (every sentence above), `minutesLeft(expiresAt, now)` for the
  countdown. Tested with `bun:test` and fake timers.
- **`src/ui/sign_in/SignInBox.tsx`**: draws the slice with `box`/`text`/`span`
  through `theme/text.ts`, the list with `ChoiceList` and `borderOf`
  (`src/ui/pickers/Pickers.tsx`, which the link and permission prompts use),
  the address fold with `Fold`, and hears keys through `app/input.ts`'s
  `usePress`. It dispatches choices; it calls no libfx, no listener, no
  store. A new name, since `src/ui/app/SignIn.tsx` is CHD-435's block.
- **`src/ui/app/sessions.ts`**: wires the driver's states into the slice and
  the box's choices back to the driver, as it adapts the agents host today.
- **`src/ui/app/keys.ts`**: routes keys to the box while it is open, as it
  does for the permission prompt.
- **`src/ui/prompt/commands.ts`**: `login` and `logout` in `ChordCommand`.
- **`src/ui/shortcuts/keys.ts`**: the `/login /logout` line.
- **`src/agents.ts`** / **`src/ui/pickers/picker.ts`**: the built-in row
  (`from: 'builtin'`) and its note.

**Late events.** Every attempt (one sign-in from the provider step to its
end) gets a fresh id from the driver. Each state the driver reports carries
it. `sessions.ts` drops a state whose id is not the slice's current
`attempt`. So a redirect, a poll result or an expiry from an attempt the
person already left (Esc, "Use a code instead", "Choose another plan") never
reaches the box. The driver aborts that attempt's signal at the same moment
(runtime), so the drop is a second guard, not the only one.

`/cost`'s note and the record's missing cost are protocol's enricher policy
(Q7). `spend_table.ts` only draws "unknown" for a figure the record left
without a cost.

### OpenTUI

Every part above is `box`, `text`, `span` and the existing list, fold and
scroll widgets; OpenTUI has no component this needs that chord lacks. The
one gap: OpenTUI draws no QR code, and none is proposed. A device code is
short enough to type. One open check: whether a terminal turns the
wrapped 120-column address into one clickable link. The design does not
rely on it, as "Open it again" and "Copy the address" carry it.

### Fake and QA

`--fake` and `--qa` need the box reachable with no network: the driver's
states from a fixture, the store from runtime's memory store, already
"signed in" or not. That gives each screen above a scenario: port taken,
device code, expiry, failure codes, no store, signed out elsewhere. Then the
drawings here can be checked against `bun dev chord --fake --qa` captures at
both sizes. Which seam, around libfx's calls or libfx's `fetch` option
(`types/chatgpt.d.ts:5-9`), is runtime's.

## For the owner, from this draft

- **Q5**: the name (`builtin`, `chord`, a name of its own) and the default
  (`claude` kept, built-in default, built-in when `claude` is missing);
  recommended `builtin`, `claude` kept, built-in first in the picker.
- **Q7**: `/cost` for a plan (a cost unknown, b API-price estimate, c plus
  limits), each an enricher policy (protocol); recommended a. The context
  gauge follows protocol's O-U.
- **Q8**: tool rendering (a Claude Code names through ACP kinds and titles,
  b libfx's names, c a renderer of its own); recommended a.
- **Q4's screens**: C1 to C4 drawn; the box offers C4 only where it reaches
  the agent (depends on Q1 and runtime's finding).
- **The CHD-435 exception**: whether chord's sign-in box for its own agent
  is allowed beside "chord does not sign agents in".
- **`/logout`'s effect on running sessions**: L1 or L2, with runtime's
  proposal.
- **The `?` panel line for `/login /logout`**, after `/vim`'s precedent, or
  the slash list only.
- Asked in passing: the terms line in A (Q9).

## What could not be checked

- Claude Code's `/login` screen, not captured (hand checks were limited to
  `--fake`).
- The sign-in box on screen: it is not built, so its drawings are laid out
  text, not captures.
- Whether OpenAI's or xAI's page names the device code's format, so
  `WXYZ-1234` is a stand-in.
- Whether a terminal makes a wrapped address one link.

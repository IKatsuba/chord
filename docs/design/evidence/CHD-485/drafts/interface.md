# CHD-485 interface draft: chord's own agent on screen

The interface architect's answer to the brief's "interface" section. The screen,
its states and keys, and the state slices beneath it. Q5, Q7 and Q8, and the
screens of Q2 and Q4, are the owner's; each has its options, its evidence and a
recommendation, and none is settled here.

`builtin` stands in for the agent's name throughout (Q5), and `gpt-6.1-sol`
and `grok-4.7` for a plan's models (libfx `README.md:324`, `:352`). The words
in the drawings are proposals; libfx's own error messages are quoted as libfx
writes them.

## What was read and run

- libfx 0.0.16, from `npm pack libfx@0.0.16` into an empty `/tmp` directory:
  `chatgpt-sign-in.js`, `grok-sign-in.js`, `chatgpt.js`,
  `types/chatgpt.d.ts`, `types/grok.d.ts`, `types/libfx.d.cts`, `README.md`.
  Line references are to those files.
- chord at origin/main (`4b09c049` in this worktree): the files named beside
  each point.
- `bun dev chord --fake --qa chd485-ui` in tmux at 120×40 and 80×24, for
  today's permission prompt (`permission`), tool calls (`tools`, `calls`),
  `/cost`, the shortcuts panel and the link prompt (`link`). The drawings below
  copy those screens' shapes: frame, `⏺`/`⎿`, `›››` working line, status
  line. No real agent, model, provider or sign-in was reached. Claude Code's
  own `/login` screen was not captured (the lead's instructions limit hand
  checks to `--fake`), so where this draft says "as Claude Code", it means the
  shapes chord already copies from it, not a fresh capture.

## Where sign-in lives

### The options

- **A. A box in the window, in the prompt's place.** chord's own dialog,
  framed as the permission prompt and the pickers are, drawn over the
  transcript above the prompt (`src/ui/AGENTS.md`, CHD-545). It opens when the
  built-in agent starts without a credential, and on `/login`. One surface for
  the start and for switching.
- **B. A step of the title page**, before the window, as the agent picker is
  (`src/ui/app/Start.tsx:110`, `AgentsPage`). It covers only the start;
  `/login` mid-session still needs A's box, so it is two surfaces for one job.
- **C. The agent asks, over ACP.** If Q1 makes the agent an ACP agent chord
  starts, it could ask through ACP elicitation, which chord already draws:
  the link prompt (`src/ui/dialogs/Link.tsx:19`, captured below) for the
  browser's address, a form (`src/ui/dialogs/Form.tsx`) with an enum field
  for the provider and the way. It would also serve `chord acp`'s other
  clients. Against it: during a start chord answers every elicitation
  `cancel`, as nobody listens yet (`src/session/elicitations.ts:127-130`;
  that is droid's "Sign-in was cancelled" in `docs/design/CHD-435.md`), so
  the start path needs a listener first; the link prompt has no room for a
  device code or a "port taken" state beside its two choices; and the words
  would be the agent's message strings, with no state for chord to test.

Today's link prompt, which C would reuse (`--fake`, `link`):

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

**Recommendation: A**, whatever Q1 answers. If the agent runs as a child ACP
process, the box still runs in chord's window process, writes the credential
to the store, and the agent reads it at its start. What `chord acp` offers its
own clients for sign-in is protocol's (ACP `authMethods`), not this screen.

CHD-435 says chord does not sign agents in and never calls `authenticate`.
This box signs in chord's own agent, not another's. The design should say
that CHD-435's line (`src/session/sign_in.ts:106`) still holds for every
other agent, and that the built-in agent never shows it.

### Its life

1. `chord builtin`, or the agent picked, with no credential in the store:
   the window opens as for any agent. The header says `builtin · not signed
   in`, a row says why, and the box opens on the provider step. The session
   is not started yet; the prompt is drawn but has no keys while the box does.
2. Provider → way → waiting (browser or code) → success, failure, expired
   or cancelled. Every step is a list of numbered choices; the box's keys
   are the pickers' and the permission prompt's.
3. Success: the box closes. The row under the reason says
   how it went and where the credential is kept, and the session starts. The
   header's second line becomes `builtin · ChatGPT · <model>`.
4. Esc on the first step, or Esc from a later one back to it: the listener is
   closed (the brief's settled point), polling stops, and the row says `Not
   signed in. /login to sign in, or /new for another agent.` The prompt
   takes keys and answers chord's own commands only. A typed prompt gets the
   status line's notice `builtin is not signed in: /login`.
5. `/login` at any time opens the box again (switching, below). `/logout`
   signs out.

Order of work in the browser way: bind the listener first, then show the
address and open the browser. A taken 1455 is then known before the person
leaves for the browser, and the box goes to "port taken" without opening a
page that cannot come back.

## The sign-in screens

Colour roles (`src/ui/theme/theme.ts:73-120`, the `Palette`): the box's
border, title and `❯` are `permission`, as the permission prompt's and the
pickers' are; the address is `link`, the code bold in the terminal's own
foreground; a provider's note after ` · ` is dim; the failure sentence is
`error`; the "port taken" and "no store" sentences are `warning`; the
success row's `⎿` is dim and its text plain; the `›››` working line is
`accent`, as today. Nothing else is coloured.

Each 120×40 screen shows the whole window once (A). The others show the box
and what changes around it; the rows above are A's header and row.

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
│ ❯ 1. ChatGPT · a ChatGPT Plus, Pro, Business or Enterprise plan                                                      │
│   2. Grok · a Grok plan on xAI                                                                                       │
│                                                                                                                      │
│ Enter to choose · Esc to cancel                                                                                      │
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
│ builtin runs on your ChatGPT or Grok plan. Your plan and its provider's      │
│ terms apply to its turns.                                                    │
│                                                                              │
│ ❯ 1. ChatGPT · a ChatGPT Plus, Pro, Business or Enterprise plan              │
│   2. Grok · a Grok plan on xAI                                               │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts

```

The note after each provider is chord's, not libfx's. libfx names no plans
(`types/libfx.d.cts:626-663`), so the plan names need the owner's words or
go. Only those two rows unless Q3 adds AI Gateway or a custom server; each
would be a row here, with its own next step (a key field), not drawn.

The line on terms is there because Q9 is open. It stays only if the owner
wants it.

### B. Choosing the way

120x40, the box and the status line (the rows above as in A):

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT                                                                                                   │
│                                                                                                                      │
│ ❯ 1. In the browser · chord opens OpenAI's page and listens on localhost:1455 for its answer                         │
│   2. With a code · enter a short code on OpenAI's page, in any browser, on any device                                │
│                                                                                                                      │
│ Enter to choose · Esc to go back                                                                                     │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

80x24:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT                                                           │
│                                                                              │
│ ❯ 1. In the browser · chord opens OpenAI's page and listens on               │
│      localhost:1455 for its answer                                           │
│   2. With a code · enter a short code on OpenAI's page, in any browser,      │
│      on any device                                                           │
│                                                                              │
│ Enter to choose · Esc to go back                                             │
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
  ? for shortcuts
```

80x24:

```text
 ››› Waiting for the browser… (12s)

╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT in the browser                                            │
│                                                                              │
│ chord opened this address. Sign in there; chord goes on when OpenAI          │
│ sends the browser back to localhost:1455.                                    │
│                                                                              │
│   https://auth.openai.com/oauth/authorize?response_type=code&client_id=app_E │
│   … +3 lines (2 to copy the whole address)                                   │
│   Opens auth.openai.com                                                      │
│                                                                              │
│ ❯ 1. Open it again                                                           │
│   2. Copy the address                                                        │
│   3. Use a code instead                                                      │
│                                                                              │
│ Enter to choose · Esc to give up                                             │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts

```

The `›››` line is the existing working line with its elapsed time
(`src/ui/status/status.ts:659`, `workingLine`), worded for the wait. When the
redirect lands, chord passes the whole address to `finishSignIn`
(`chatgpt-sign-in.js:62`, `grok-sign-in.js:53`); the box shows `Finishing
the sign-in…` on the working line until it returns. The page in the browser
is chord's listener's answer: a line that says to go back to the terminal.
That page is runtime's to word.

### D. Port 1455 taken (ChatGPT only)

The redirect is fixed (`chatgpt-sign-in.js:12`); Grok picks its own port and
never meets this (`grok-sign-in.js:36-37`).

120x40:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT in the browser                                                                                    │
│                                                                                                                      │
│ localhost:1455 is taken by another program, maybe a Codex CLI or fx sign-in. OpenAI sends the browser back only      │
│ there, so chord cannot sign in in the browser while it is. Sign in with a code, or close that program and try again. │
│                                                                                                                      │
│ ❯ 1. Use a code instead                                                                                              │
│   2. Try the browser again                                                                                           │
│                                                                                                                      │
│ Enter to choose · Esc to go back                                                                                     │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

80x24:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT in the browser                                            │
│                                                                              │
│ localhost:1455 is taken by another program, maybe a Codex CLI or fx          │
│ sign-in. OpenAI sends the browser back only there, so chord cannot sign      │
│ in in the browser while it is. Sign in with a code, or close that program    │
│ and try again.                                                               │
│                                                                              │
│ ❯ 1. Use a code instead                                                      │
│   2. Try the browser again                                                   │
│                                                                              │
│ Enter to choose · Esc to go back                                             │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts

```

"Maybe a Codex CLI or fx sign-in" is a guess about who holds the port.
Unless the owner wants it, the design should drop it and say only that the
port is taken. One open choice for the owner sits here, not settled. libfx's
own documented way for the browser flow is to paste the address of the page
that did not load back into `finishSignIn` (`types/chatgpt.d.ts:13`,
`:45-46`; `chatgpt-sign-in.js:5-6`). With 1455 taken, the browser still lands
on `localhost:1455` and shows the other program's page or nothing, so a paste
is only sometimes possible. A third choice, "Paste the address", is the
library's own way, not a workaround. Whether to offer it is the owner's
call: the settled point names only device code.

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
│ The code lasts 15 minutes. If OpenAI's page says device code sign-in is off, turn it on in ChatGPT's security        │
│ settings, or ask your workspace admin.                                                                               │
│                                                                                                                      │
│ ❯ 1. Open the address in the browser                                                                                 │
│   2. Copy the code                                                                                                   │
│   3. Copy the address                                                                                                │
│                                                                                                                      │
│ Enter to choose · Esc to give up                                                                                     │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

80x24:

```text
 ››› Waiting for the code… (1m 04s)
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT with a code                                               │
│                                                                              │
│ Open the address, sign in, and enter the code.                               │
│                                                                              │
│   https://auth.openai.com/codex/device                                       │
│   WXYZ-1234                                                                  │
│                                                                              │
│ The code lasts 15 minutes. If OpenAI's page says device code                 │
│ sign-in is off, turn it on in ChatGPT's security settings.                   │
│                                                                              │
│ ❯ 1. Open the address in the browser                                         │
│   2. Copy the code                                                           │
│   3. Copy the address                                                        │
│                                                                              │
│ Enter to choose · Esc to give up                                             │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts

```

The code is drawn on a row of its own, bold, with nothing else on it, so a
mouse selection or the terminal's double-click takes it whole. "Copy the
code" uses OpenTUI's clipboard service, as chord's copy does today
(`src/ui/app/selection.ts:4`; `copyToClipboardOSC52`,
`node_modules/@opentui/core/renderer.d.ts:613`).

The expiry is said once, statically: ChatGPT's code lasts 15 minutes
(`chatgpt-sign-in.js:15`), and Grok's lasts as long as xAI's `expires_in` says
(`grok-sign-in.js:85,95`), so "lasts N minutes" is computed at the start.
There is no ticking countdown, so the box does not redraw every second. The
working line's elapsed time already moves. The note on device code being
off is libfx's own warning, from its expiry message
(`chatgpt-sign-in.js:106-109`). It is ChatGPT's alone; Grok's box leaves it
out.

### F. Success, failure, expired, cancelled

Success, 120x40: the box closes, a row stays, the session starts:

```text
 ▀▄     chord v0.69.0
 ▀▀▀▄   builtin · ChatGPT · gpt-6.1-sol
 ▄▀▀▀   ~/projects/app
 ▀▀     ? for shortcuts · /help

 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Signed in to ChatGPT in the browser. Kept in the macOS Keychain.

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                            gpt-6.1-sol · medium effort
```

Success, 80x24:

```text
 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Signed in to ChatGPT with a code. Kept in the macOS Keychain.

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                    gpt-6.1-sol · medium effort
```

Failure (any libfx error but expiry), 120x40:

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
  ? for shortcuts
```

Failure, device code refused, 80x24:

```text
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
│   2. Sign in in the browser instead                                                                                  │
│   3. Choose another plan                                                                                             │
│                                                                                                                      │
│ Enter to choose · Esc to cancel                                                                                      │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Expired, 80x24:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to Grok with a code                                                  │
│                                                                              │
│ The code expired before it was entered. Start again.                         │
│                                                                              │
│ ❯ 1. Get a new code                                                          │
│   2. Sign in in the browser instead                                          │
│   3. Choose another plan                                                     │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Cancelled, 120x40: Esc on any step; the listener is closed, the prompt takes keys:

```text
 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Not signed in. /login to sign in, or /new for another agent.

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Cancelled, 80x24:

```text
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
| `…_DEVICE_CODE_EXPIRED` (`:106`, `grok-sign-in.js:104,115`) | expired | Get a new code · Browser · Another plan |
| `…_DEVICE_CODE_UNAVAILABLE` (`chatgpt-sign-in.js:83`) | failure, ChatGPT adds the security-settings line | Try again · Browser · Another plan |
| `…_SIGN_IN_DENIED` (`grok-sign-in.js:117`) | failure | Try again · Another plan |
| `…_STATE_MISMATCH`, `…_INVALID_ADDRESS` | failure | Try again |
| `LIBFX_GROK_ACCOUNT_UNAVAILABLE` | failure | Try again · Another plan |
| `…_SIGN_IN_FAILED`, anything else | failure | Try again · the other way · Another plan |

Cancelled leaves no box. The row says so (F's last drawings) and the window
stays usable, as in "Its life", step 4.

### G. No credential store (Q4's screens)

Each Q4 option has its own screen; none is chosen here. What the owner's
other project met, from the board comment of 2026-11-08: the first read fails
with no Secret Service, a read can block on a locked keychain, and it bounded
reads at 20 s.

Q4 option a, refuse, 120x40:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT                                                                                                   │
│                                                                                                                      │
│ chord keeps your sign-in in the system's credential store, and this system has none it can reach: no Secret Service  │
│ answered (gnome-keyring or KeePassXC). Start one and try again.                                                      │
│                                                                                                                      │
│ ❯ 1. Try again                                                                                                       │
│   2. Choose another plan                                                                                             │
│                                                                                                                      │
│ Enter to choose · Esc to cancel                                                                                      │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

Q4 option b, an explicit 0600 file, 80x24:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign in to ChatGPT                                                           │
│                                                                              │
│ No credential store answered (gnome-keyring or KeePassXC). chord can         │
│ keep the sign-in in a file only you can read instead:                        │
│                                                                              │
│   ~/.config/chord/credentials.json  (mode 0600)                              │
│                                                                              │
│ ❯ 1. Keep it in the file                                                     │
│   2. Keep it until chord quits                                               │
│   3. Try the store again                                                     │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
```

Q4 option c, memory for the process's life, 80x24: the success row says so:

```text
 ⏺ builtin needs a sign-in to a ChatGPT or Grok plan
   ⎿  Signed in to ChatGPT. No credential store answered, so the sign-in
      lasts until chord quits.
```

Q4 option d, environment variables only, 80x24:

```text
 ⏺ builtin did not start: no credential store answered
   ⎿  Set CHORD_CHATGPT_REFRESH_TOKEN, or start a Secret Service
      (gnome-keyring or KeePassXC), and start builtin again.
```

A locked or slow store (bounded read), 120x40:

```text
 ››› Reading the sign-in from the macOS Keychain… (4s)

```

- **a. Refuse.** One box; nothing is kept anywhere else. Plainest, and a
  headless Linux box cannot use the agent at all.
- **b. An explicit 0600 file**, offered in the box, so the person chooses it
  each time no store answers. The file's place is runtime's to say; the path
  drawn is a stand-in.
- **c. Memory for the process's life.** No question asked; the success row
  says it. The next `chord builtin` asks again.
- **d. Environment variables only.** A start failure row in CHD-435's shape,
  no box. The variable's name is a stand-in.

b and c can be offered together, as b's drawing does. Recommendation:
**b with c beside it**, as in the drawing. The person picks each time, and a
plaintext file is never written without a key press. a is the fallback if the
owner wants no file at all.

The bounded read gets its own working line ("Reading the sign-in from the
macOS Keychain…"). When the bound runs out, the box opens on G's screen with
`The macOS Keychain did not answer in 20 s.`, and a store that cannot be
reached at all is treated the same way. The store's name comes from the platform
module (runtime): Keychain, Secret Service or Credential Manager.

## Signing out and switching

- **`/logout`** (chord's command, `owner: 'chord'` in
  `src/ui/prompt/commands.ts:10-26`): a confirm box (drawn below), then the
  credential is deleted from the store, the session ends, and the row says
  `Signed out of ChatGPT. /login to sign in again.` Only for the built-in
  agent. With another agent, `/logout` is not on the list: chord does not
  sign other agents in or out.
- **`/login`**: the box of A, with the provider signed in marked `✔`
  (`CURRENT_MARK`, `src/ui/pickers/picker.ts:22`). Picking it again signs in
  again (another account); picking the other provider signs in to it.
  Success starts a new session in place, as `/clear` does. The transcript
  stays above, under a row naming the new plan. The old credential is kept
  unless `/logout` removes it, so switching back costs no sign-in.
  Whether a session can carry its conversation across providers is
  protocol's (Q6). This draft assumes it cannot.
- Both providers may hold a credential at once; the agent runs on the one
  last signed in to, kept in chord's settings as the agent's provider. Where
  that setting lives is protocol's.

/login while signed in, 120x40:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Sign in to builtin                                                                                                   │
│                                                                                                                      │
│ Signed in to ChatGPT. Signing in to another plan or account starts a new session; this transcript stays above it.    │
│                                                                                                                      │
│ ❯ 1. ChatGPT ✔ · sign in again, to another account                                                                  │
│   2. Grok · a Grok plan on xAI                                                                                       │
│                                                                                                                      │
│ Enter to choose · Esc to cancel                                                                                      │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                          gpt-6.1-sol · medium effort · 4% context used
```

/logout, 80x24:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Sign out of ChatGPT?                                                         │
│                                                                              │
│ chord forgets the sign-in in the macOS Keychain and ends this session.       │
│ OpenAI's own sessions in your browser stay signed in.                        │
│                                                                              │
│ ❯ 1. Sign out                                                                │
│   2. Keep the sign-in                                                        │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                      gpt-6.1-sol · medium · 4%
```

After /logout, 80x24:

```text
 › /logout
   ⎿  Signed out of ChatGPT. /login to sign in again.

```

Claude Code names its commands `/login` and `/logout`; chord takes the same
names. Neither name is taken in chord's list today
(`src/ui/prompt/commands.ts:11-26`) or in Claude Code's commands that chord
passes on as the agent's.

## Keys and the shortcuts panel

Every action in the box is a numbered choice. So the box adds **no new key**.
It answers the keys the permission prompt and the pickers already answer, and
the panel already lists (captured at 120×40):

- `1–9 to pick a choice`
- `↑ ↓ or j k to move between choices`
- `enter to pick the highlighted choice`
- `esc ← to leave a picker or shortcuts`, which covers the box's Esc. The
  hint in the box words it per step: `Esc to go back`, `Esc to give up`,
  `Esc to cancel`.

Copying and opening again are choices, not letter keys, for that reason. A
`c` or `o` key would be a widget-owned key, with its own `keys.ts` entry and
test (`AGENTS.md`, "Every action has a key"), and would add nothing a digit
does not already do.

New entries:

| Action | Key | Rebindable | Panel |
| --- | --- | --- | --- |
| sign in, switch | `/login` | no: a command, not a binding | not in `?`; in the slash command list with `Sign in to a ChatGPT or Grok plan for builtin` |
| sign out | `/logout` | no | slash list: `Sign out of builtin's plan` |
| give up a sign-in | `esc` | no: the pickers' Esc, as today | covered by `esc ← to leave a picker or shortcuts` |

The key test (`tests/ui/shortcuts/keys_test.tsx`) needs the box added to the
widgets whose keys it presses, as the permission prompt and the link prompt
are. The box answers no key outside that list.

Whether `/login` and `/logout` are listed when the session's agent is not the
built-in one is a choice to make. The recommendation is `/login` always (it
switches to the built-in agent's sign-in) and `/logout` only for it.

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
price, no plan limit, and no rate-limit window: nothing in
`subscription.js` or the types reads one. `listModels` covers AI Gateway
only (`:1064`, `apiKey` required), so a plan's model list is not libfx's to
give (protocol's, `/model`).

- **Header**: `builtin · ChatGPT · gpt-6.1-sol`. The provider sits between
  the agent and the model, so the plan in use is always visible.
- **Status line**: unchanged in shape. Model, effort, and context used when
  the window is known: `contextUsed` (`src/ui/status/status.ts:266`) and the
  context window from `@pydantic/genai-prices`
  (`src/session/prices.ts:24`) when that data knows the plan's model. No
  cost on the status line, as today.
- **`/cost`**: the options, drawn below.
  - **a. Tokens, no price.** The cost row says the plan charges none per
    token. This is the existing "provider reports no cost" note
    (`src/ui/transcript/spend_table.ts:57`) with plan words. chord's price
    estimate is turned off for the built-in agent on a plan.
    Recommendation: a flat plan has no per-token cost, and an API-price
    estimate would read as a bill.
  - **b. chord's estimate at the model's API price, marked `~`**, as
    `spend.ts` already does for agents that give no cost
    (`src/ui/transcript/spend.ts:28-58`). It is honest about the work done,
    but misleading as money.
  - **c. a or b, plus the plan's limits.** libfx does not give them. chord
    reads Codex plan windows today only through the Codex CLI's app server
    (`src/session/codex_resources.ts:12-40`), which the person may not have
    installed, and has no Grok reader. Not for the MVP.

Option a (recommended): tokens, no price, 120x40:

```text
 › /cost
   ⎿  Total cost:   none per token: builtin runs on your ChatGPT plan
      Tokens in:    48,210
      Tokens out:   3,904
      Cache read:   41,000
      Reasoning:    1,212
      Session time: 6m 12s
```

Option b: chord's estimate at API prices, marked, 80x24:

```text
 › /cost
   ⎿  Total cost:   ~$0.0961 (chord's estimate at gpt-6.1-sol's API price;
                    your ChatGPT plan is not charged per token)
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

Streaming, 120x40:

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
  ? for shortcuts                                                          gpt-6.1-sol · medium effort · 4% context used
```

Streaming, 80x24:

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
  ? for shortcuts                                      gpt-6.1-sol · medium · 4%

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

An edit, 120x40:

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
  ? for shortcuts                                                          gpt-6.1-sol · medium effort · 4% context used
```

A command, 80x24:

```text
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
  ? for shortcuts                                      gpt-6.1-sol · medium · 4%

```

## State slices and pure modules

Following `src/ui/AGENTS.md`: a feature folder, a `state.ts` that knows only
its slice, pure snake_case logic beside a PascalCase component.

- **`src/ui/sign_in/state.ts`**: the box's slice.
  `{ step: 'provider' | 'way' | 'browser' | 'port_taken' | 'code' |
  'finishing' | 'failed' | 'expired' | 'no_store' | 'reading_store';
  provider?: 'chatgpt' | 'grok'; address?: string; code?: string;
  lastsMinutes?: number; error?: { code: string; message: string };
  highlighted: number; current?: provider }`. Nothing secret: no verifier,
  no token. Those stay with the driver (runtime/protocol). The working
  line's start time is in the slice for the elapsed time, as other waits
  keep theirs.
- **`src/ui/sign_in/sign_in.ts`**, pure: `next(state, event)` over driver
  events (`listening`, `port_taken`, `redirected`, `device_code`,
  `signed_in`, `failed`, `store_unavailable`) and choices; `choicesFor(state)`
  (the rows and their order per step, including the table in F);
  `wordsFor(state, store)` (every sentence above); `lastsMinutes(expiresAt,
  now)`. Tested with `bun:test` and fake timers, no network.
- **`src/ui/sign_in/SignInBox.tsx`**: draws the slice with `box`/`text`/`span`
  through `theme/text.ts`, the list with `ChoiceList` and `borderOf`
  (`src/ui/pickers/Pickers.tsx`, which the link and permission prompts use),
  the address fold with `Fold`, and hears keys through `app/input.ts`'s
  `usePress`. It dispatches choices; it calls no libfx, no listener, no
  store. A new name, since `src/ui/app/SignIn.tsx` is CHD-435's block.
- **`src/ui/app/sessions.ts`**: wires the driver's events into the slice and
  the box's choices back to the driver, as it adapts the agents host today.
- **`src/ui/app/keys.ts`**: routes keys to the box while it is open, as it
  does for the permission prompt.
- **`src/ui/prompt/commands.ts`**: `login` and `logout` in `ChordCommand`.
- **`src/ui/transcript/spend_table.ts`**: the plan's "no cost per token" note
  (Q7 a), given the provider by the figure.
- **`src/agents.ts`** / **`src/ui/pickers/picker.ts`**: the built-in row
  (`from: 'builtin'`) and its note.

Outside the interface, named here for the boundary only: the sign-in driver
(the listener's life, libfx's calls, polling, cancellation) and the store in
`src/platform/` are runtime's; what the agent sends as tool calls and which
provider setting it reads are protocol's.

### OpenTUI

Every part above is `box`, `text`, `span` and the existing list, fold and
scroll widgets; OpenTUI has no component this needs that chord lacks. The
one gap: OpenTUI draws no QR code, and none is proposed. A device code is
short enough to type. One open check: whether a terminal turns the
wrapped 120-column address into one clickable link. The design does not
rely on it, as "Open it again" and "Copy the address" carry it.

### Fake and QA

`--fake` and `--qa` need the box reachable with no network: the driver's
events from a fixture, the store from a fixture
(`tests/fixtures/fake_agent/`, as `resource_fixture.ts` does for resources).
That gives each screen above a scenario: port taken, device code, expiry,
failure codes, no store. Which seam, around libfx's calls or libfx's
`fetch` option (`types/chatgpt.d.ts:5-9`, every sign-in step takes
`fetch`), is runtime's.

## For the owner, from this draft

- **Q5**: the name (`builtin`, `chord`, a name of its own) and the default
  (`claude` kept, built-in default, built-in when `claude` is missing);
  recommended `builtin`, `claude` kept, built-in first in the picker.
- **Q7**: `/cost` for a plan (a tokens only, b API-price estimate, c plus
  limits); recommended a.
- **Q8**: tool rendering (a Claude Code names through ACP kinds and titles,
  b libfx's names, c a renderer of its own); recommended a.
- **Q4's screens**: refuse, a 0600 file offered in the box, memory for the
  process, environment only; recommended the file and memory offered side by
  side in the box.
- **Where sign-in lives**: the box (A), a title-page step (B), ACP
  elicitation (C); recommended A, with CHD-435's line kept for every other
  agent.
- Asked in passing: the paste-the-address choice when 1455 is taken
  (libfx's own documented flow, D); the plan names in A's notes; the terms
  line in A (Q9); whether `/login` is listed for other agents.

## What could not be checked

- Claude Code's `/login` screen, not captured (hand checks were limited to
  `--fake`).
- Whether OpenAI's or xAI's page names the device code's format, so
  `WXYZ-1234` is a stand-in.
- What OpenAI's and xAI's pages show on a redirect to a closed port, which
  bears on D's paste choice.
- Whether a terminal makes a wrapped address one link.
- Whether the plan models are in `@pydantic/genai-prices`' data, for the
  status line's context used.

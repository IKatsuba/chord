# CHD-573 interface draft: `chord acp`

Both answers are proposals: `chord acp` does not exist. The choices are options
for the lead. Line numbers are at this branch's head.

## 1. The extraction, as the interface sees it

### What the code establishes

- Children, teams, chord's MCP tools, monitors and record-keeping all live in
  one React hook, `useSessions` (`src/ui/app/sessions.ts:286`), which App calls
  once (`src/ui/app/App.tsx:545`).
- Its file imports the renderer (`sessions.ts:23`), so importing it reaches
  OpenTUI and React. From `src/headless.ts`, static non-type imports reach 65
  files and neither library. The only `src/ui/` files among them are
  `shortcuts/bindings.ts` and `theme/theme.ts`, through `src/settings.ts:11-12`.
- The body already falls in two. Lines 317-2779 (about 2460) run agents; from
  `conversation` at 2780 to the return at 4166 (about 1390) serve the window.
  This split is by function name and by where the helpers are called. I did not
  read all of each function.
- `Conversation`, `OpenAgents`, `TaskAgent`, the window agents and monitors and
  the transcript reducer are already in `src/session/`. So is the queue's
  origin: `deliverTo` calls `conversation.tell` (`sessions.ts:961`).

### What leaves `src/ui/`

Into one non-React layer in `src/session/`. Runtime owns its name and the order.

| Moves | From |
| --- | --- |
| Opening and starting: `conversationOf`, `childConversation`, `spawn`, `startChild`, `openAgent` | `sessions.ts:437-1324` |
| Teams: `runSelectedTeamAt`, `runTeamAt`, `openMember` | `sessions.ts:1471-1943` |
| Messages and ends: `tell`, `teamTell`, `tellEnded` | `sessions.ts:2011-2176` |
| Closing and clearing: `dropChild`, `closeAgent`, `clearChild`, `clearAgent`, `message` | `sessions.ts:2226-2542` |
| The MCP server's view, `view: WindowView` | `sessions.ts:2559` |
| `busyOf`, which `dropChild` calls; its armed-line words stay | `src/ui/app/closing.ts:34` |
| `settingPickedUp`, which `view` calls | `src/ui/app/setting_picked_up.ts:14` |
| `closeOnForcedExit`, the signal reap at `sessions.ts:2764` | `src/ui/app/renderer.tsx` |

Mapping every helper imported from `src/ui/` to its caller shows how little else
moves. Picker, list, background, status and team-words helpers are called only
from functions that stay.

### What the window then calls

`useSessions` stays at its path as a thin hook: it builds the layer once, wires
the port below, and returns the members it returns today (`sessions.ts:4166`).
`App.tsx` and `tests/ui/app/sessions_test.tsx` keep their call sites. The layer
gets its own React-free tests at the mirrored path.

The layer asks its driver for what it now gets from `SessionsWindow`
(`sessions.ts:270`) and `dispatch`:

- **Told:** the 11 window actions lines 317-2779 dispatch: `in_session`,
  `in_session_past`, `retired_heard`, `closing_heard`, `agent_opened`,
  `session_closed`, `agents_focused`, `failed`, `notice_opened`, `spend_closing`
  and `spend_closed`. `WindowedAction` stays in `src/ui/app/state.ts`, so the
  layer needs an event type of its own, which the window turns into actions.
  `ConversationEvent` is already below the interface. `failed` and part of the
  rest may be fields of another action: the count comes from a text search.
- **Window-only, absent under `chord acp`:** `notify` (`heard`), `redraw`
  (`runSelectedTeamAt`, `closeAgent`), `stopCommand` (`dropChild`, `clearChild`)
  and `showDraft` with the queue restore in `clearChild` (`sessions.ts:2346-2364`),
  which becomes one "these queued prompts came back" event. What `chord acp` does
  with that event is a question for protocol and runtime.
- **Asked:** `stateOf` for a session's transcript and queue (`sessions.ts:1992`,
  `2253`, `2348`). Options:
  1. **The driver answers from its own fold (recommended).** The window reads
     `all.sessions`, unchanged. `chord acp` keeps a small store running
     `reduceTranscript` (`src/session/transcript/reducer.ts`). One fold per
     process, and the window's batched replay (CHD-559) is untouched.
  2. **The layer folds and the window reads from it.** Cleaner in the end, but it
     rewrites how the window gets `in_session`, so its risk lands on every screen.
     I would cut it from this milestone.

### What stays, and why

- **Keys, focus and drawing:** `keys.ts`, `input.ts`, `layout.ts`, `App.tsx`,
  every component, every feature's `state.ts`. They mean something only with a
  screen.
- **Window-side `useSessions`:** `moveAgent`, `moveBackground`, `goToCall`,
  `agentRows`, `listed`, `background`, `lines`, `showDraftIn`, `takeBackQueue`,
  `openResume`, the pickers. They read view state (`agentsView`,
  `backgroundView`, `summaryFocus`).
- **The typed commands:** `runTyped`, `newTyped`, `forkTyped`, `stopTyped`,
  `showTyped` (`sessions.ts:3136-3552`) stay as callers of the layer, and they
  are the only callers of `ranNote`, `stoppedLine`, `teamRefusal`. If protocol's
  answer exposes chord's slash commands to the client, these need a second look.
- **`src/settings.ts`'s two `src/ui/` imports:** neither reaches React or
  OpenTUI, and nothing here needs them moved. I would cut that move.

The window's screens, keys and slices do not change. No slice, key or binding is
added, and the check is the existing UI tests plus a capture at both sizes.

A smaller package than this exists only by dropping the goal: `chord acp` on
`src/session/oneshot.ts`'s path reaches no children or teams, because those are
in the hook. Runtime weighs that.

## 2. Run by hand in a terminal

### Options

1. **Serve, with a note on stderr when stdin is a terminal (recommended).** stdout
   stays ACP only, a client's piped stdin never sees the note, and a person gets
   told what this is instead of a blank cursor. Typing JSON by hand keeps working.
2. **Serve in silence.** The simplest, but it looks hung.
3. **Refuse when stdin is a terminal, exit non-zero.** Clear, but it costs by-hand
   debugging, and refuses a transport that works.

### The screen under option 1

Same at 120x40 and 80x24: no window, no alternate screen, no raw mode, nothing
laid out by width. The longest note line is 77 columns, so it fits both. It is
the terminal's own line editing and echo, in its scrollback.

No colour roles: plain text with no escape bytes and no `theme.ts` role, as with
every `chord:` line before the window (`src/main.tsx:314-317`). No OpenTUI
component draws it.

Waiting, the only state chord itself draws (stderr):

```text
$ chord acp
chord: acp serves ACP on stdin and stdout, for a client that starts it.
chord: nothing to press here. Ctrl-D or Ctrl-C leaves; `chord` opens a window.
█
```

The person types a line that is not JSON. `hello` is the terminal's echo; the
second line is the SDK's, on stdout, unchanged
(`node_modules/@agentclientprotocol/sdk/dist/core/stream.js:45-48`):

```text
hello
{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}
█
```

The person types a request; the answer comes on stdout. A real answer is longer
and the terminal wraps it, at 80 sooner than at 120:

```text
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}
█
```

Leaving:

```text
^D                                  exit 0, nothing further said
^C                                  dies by the signal, back at the prompt
```

Streaming, a person's permission and error have no screen of their own: they are
ACP lines on stdout, or a `chord:` line on stderr as a failure already is.

### Which stream decides

| stdin | stdout | Result |
| --- | --- | --- |
| pipe | pipe | A client: no note |
| terminal | terminal | The screen above |
| terminal | pipe or file | The note still shows, on stderr; ACP goes to the file |
| pipe | terminal | No note; ACP lines on screen, and it ends at the pipe's EOF |

Only `process.stdin.isTTY` decides, in a pure function beside the command with a
test. Settings problems go to stderr as they do today (`src/main.tsx:174-181`).

### Keys

There are none of chord's. Ctrl-D and Ctrl-C are the terminal's line discipline
(EOF and SIGINT), so `keyCommand`, `src/ui/shortcuts/keys.ts` and `bindings.ts`
gain nothing, they cannot be rebound, and the shortcuts panel lists nothing:
`chord acp` has no panel to show it. Its `--help` line is where it is described.

### Checked and not checked

- **Run:** a throwaway SDK agent built with `agent({ name })` from a temporary
  directory outside the repository, on a real terminal in tmux at 120x40 and
  80x24, under Bun, answering only `initialize`. It gave the output above: the
  parse error, the answer, exit 0 on Ctrl-D, and return to the prompt on Ctrl-C.
  Its note had the same layout in other words: the wording above is proposed and
  was not run. No agent, model or provider was involved.
- **Not run:** chord's own start. Whether `src/main.tsx`'s static OpenTUI imports
  (`main.tsx:13`, `25`, `92-95`) write anything to stdout is runtime's gate. A
  running child at Ctrl-C or EOF is runtime's too: chord will need a handler that
  closes the tree, where the trial had none. Ctrl-D after typed text needs a
  second press in standard line editing; I did not test it.
- **Word clash:** `chord <agent>` is positional (`src/cli.ts:18`), so subcommand
  `acp` would take the word from any agent configured under that name. No agent
  `chord agents` lists here has it. I did not check how Cliffy resolves the clash,
  or how `agents` and `upgrade` handle it today.

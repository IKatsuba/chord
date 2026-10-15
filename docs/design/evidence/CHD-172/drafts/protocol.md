# CHD-172 — protocol draft

The protocol architect's answers to the brief's three protocol questions:
what reaches the agent and the record, the setting, and the clipboard path.
Every clipboard claim below was run on this machine (macOS, Bun, OpenTUI
0.6.0, @mariozechner/clipboard 0.3.9, tmux 3.6a) in scratch scripts under a
`mktemp -d` directory with `node_modules` symlinked to the repository's;
nothing under `src/`, `tests/`, `scripts/` or `lint/` was touched.

## In short

| Question | Answer |
| --- | --- |
| Does anything reach the agent? | No. No ACP message in or out changes. |
| Does anything reach the session record? | No. A selection and a copy are the window's, as a scroll, `/theme` or ctrl+o are. |
| chord's MCP tools | Unchanged. No tool reads or writes the clipboard or the selection. |
| The setting | `copyOnSelect`, `z.boolean()`, default `true`, user's file only, read at start (owner's: name, default, and whether anything but the file toggles it). |
| The clipboard path | OpenTUI's own clipboard service: `createClipboard({ host: createHostClipboard(), terminal: createRendererClipboardAdapter(renderer) })`, `writeText(text, { destination: 'best-available' })`. Local: the system clipboard natively, OSC 52 only if that fails. Over SSH: OSC 52 only. No pbcopy, no @mariozechner/clipboard for text. |
| "OSC 52 is refused" | Cannot be known. OpenTUI reports `osc52_support: "unknown"` and a write as `attempted`, never as received. Only the host write says `written`. |
| Inside tmux | The host write works as it does outside. OpenTUI's OSC 52 is wrapped in tmux's DCS passthrough, which tmux drops unless `allow-passthrough` is on (off by default). |

## 1. Nothing reaches the agent or the record

A drag, its highlight and the copy are drawn and done by the window, from
cells already on screen. No ACP request or notification carries them: the
agent has no method for "the person selected text", and none is wanted.
`src/acp/`, `src/session/` and `src/session/transcript/` are untouched; no
reducer action is added to the transcript reducer.

The record (`src/session/record.ts`) keeps what the reducer was handed from
the session: prompts, updates, served requests, messages, forms, interrupts,
results, exits, model, mode and config values. It keeps nothing of the
window's own state — not the scroll, not ctrl+o's view, not `/theme`'s
preview, not the status line's notes. A copy is that kind of thing, so it
gets no record line:

- Replaying it would draw nothing: a resumed session has no selection to
  restore and no clipboard to write.
- A line naming the copied text would put whatever the person selected —
  often a secret from a tool's output, a path, a token — into a file under
  chord's state directory, a second time and for good. A line with only the
  count is a line nobody reads.

`chord -p` draws nothing and is untouched. chord's MCP server gains no tool:
an agent reading the person's clipboard or selection is a capability nobody
asked for, and a privacy question in its own right.

Safety of the copy itself: the selected text is what OpenTUI drew, so an
agent's escapes have already gone through `Ansi` (SGR kept as style, every
other escape dropped). The text goes out base64-encoded inside OSC 52 or as
bytes to the system clipboard, never as raw bytes to the terminal, so an
agent cannot smuggle an escape into the terminal through a copy. An OSC 8
link copies as its visible text, not its URL.

## 2. The setting

### Shape

```ts
/**
 * `false` keeps a drag's selection until the copy key copies it; named as
 * Claude Code names its key, and read only from the user's file, as it is
 * about a person's hands, not a project.
 */
copyOnSelect: z.boolean(),
```

beside `mouse` in `SettingsFile` (`src/settings.ts`), added to `USER_ONLY`,
merged in the same `if (layer.copyOnSelect !== undefined)` form as `mouse`.
A `copyOnSelect` in a project's file is reported and left out, as `theme`,
`editorMode` and `mouse` are; a wrong value costs that key only (the
existing zod rule).

- **User's file only.** It is about a person's hands and habits, like
  `mouse` and `editorMode`, not about a project.
- **Name.** `copyOnSelect` is Claude Code's key; chord already names its keys
  as Claude Code does (`preferredNotifChannel`, `theme`, `editorMode`).
- **Default `true`**, as Claude Code's.
- **With `"mouse": false`** the setting does nothing: no reports, so no drag
  and no selection of chord's. That is not a problem to report; the guide's
  row says it.
- **Read at start**, like `mouse`, unless the owner wants a toggle that
  saves (option B below); then it is held in the window's state and
  `saveSetting(file, 'copyOnSelect', …)` writes it back as `/vim` does
  `editorMode`. `saveSetting`'s generic already accepts any `USER_ONLY` key.

### `/config` and the note

Claude Code's note says `disable auto-copy in /config`. chord's `/config`
lists the **agent's** select config options (`src/session/config.ts`,
`optionsFromConfigOptions`), each set through `session/set_config_option`.
Saying "in /config" would send the person to a list that does not have it.
The honest places for the toggle:

- **A. The settings file only** (as `mouse`). The note says
  `copied 59 chars to clipboard` and nothing more; the guide's settings
  table has the row. Cheapest; matches `mouse`.
- **B. A chord command that toggles and saves**, as `/vim` does
  (`/copy-on-select`, or a word the owner picks). The note could then say
  `copied 59 chars · /copy-on-select to stop`. One more command in the list
  and the panel; a choice someone makes once.
- **C. chord's own rows in `/config`** beside the agent's options. `/config`
  would then mix the agent's options (sent over ACP) with chord's (written
  to the settings file) in one picker; every chord setting would want a row
  next. A larger change to `/config` than this task.

Recommendation: A. The note's words beyond the count are the interface
draft's; they must not name `/config` unless C is chosen.

## 3. The clipboard path

### What OpenTUI 0.6.0 gives

`@opentui/core` exports, from `lib/clipboard.d.ts`:

- `createHostClipboard(options?)` — the system clipboard through the native
  library chord already ships (`libopentui`): `NSPasteboard`
  (`generalPasteboard`) on macOS; on Linux X11 (`TARGETS`, `UTF8_STRING`)
  and Wayland (`ext_data_control_v1`, `zwlr_data_control_v1`,
  `wl_data_device`), read from the strings of `libopentui.so` — no
  `xclip`, `wl-copy` or `pbcopy` needed. `writeText` resolves to
  `written | unsupported | cancelled | timed-out | failed`, with a timeout
  and an `AbortSignal`; `maxWriteBytes` is 8,388,608.
- `createRendererClipboardAdapter(renderer)` — OSC 52 through
  `renderer.copyToClipboardOSC52`, reporting `attempted`, `local-failure` or
  `not-attempted`, and the capability `supported | unsupported | unknown`.
- `createClipboard({ host, terminal })` — one service over both, with a
  policy per write: `terminal-only`, `host-only`, `best-available` (host
  first, OSC 52 only if the host is `unsupported` or `failed`; OSC 52 alone
  when `renderer.capabilities.remote`), `all-available` (both; the host
  skipped when remote unless `allowRemoteHost`).

`renderer.capabilities.remote` came out `true` when `SSH_CONNECTION` was
set and `false` otherwise.

### What was run

Host clipboard, `@mariozechner/clipboard` and pbcopy, outside tmux, each
read back with `pbpaste`:

```
host.writeText {"status":"written"} 5.2ms maxWriteBytes 8388608
read back text/plain "chd172 host ✓ ünïcode\nline two"
setText ok 3.6ms getText "chd172 mario ✓ ünïcode\nline two"
pbpaste: chd172 pbcopy ✓
```

The host script built with `bun build --compile` ran the same:
`{"status":"written"} 11.2ms`, `pbpaste` gave the text. (`libopentui` is
already embedded in chord's binary, CHD-309.)

OpenTUI's renderer and service inside a detached tmux pane
(`tmux -L … -f /dev/null`, 100×30), the pane's output captured with
`pipe-pane -O`:

```
caps {"osc52":true,"osc52_support":"unknown","remote":false,"multiplexer":"tmux",
      "terminal":{"name":"tmux","version":"3.6a","from_xtversion":true}}
copyToClipboardOSC52 true
best-available {"host":{"status":"written"},"terminal":{"status":"not-attempted","capability":"unknown"}}
all-available  {"host":{"status":"written"},"terminal":{"status":"attempted","capability":"unknown"}}
best-available (SSH_CONNECTION set) {"host":{"status":"not-attempted"},"terminal":{"status":"attempted","capability":"unknown"}}
```

`best-available` put the text on the system clipboard from inside tmux, as
outside. The OSC 52 bytes OpenTUI wrote inside tmux:

```
ESC P tmux; ESC ESC ] 52 ; c ; Y2hkMTcy… ESC ESC \ ESC \
```

that is, OSC 52 wrapped in tmux's DCS passthrough. Whether it reaches the
terminal outside, with a second tmux standing in for that terminal (outer
`set-clipboard on`, so a received OSC 52 shows as an outer buffer):

| Inner tmux | What was sent | Inner buffer | Reached outside |
| --- | --- | --- | --- |
| defaults (`set-clipboard external`, `allow-passthrough off`) | OpenTUI's wrapped OSC 52 | — | no |
| `allow-passthrough on` | OpenTUI's wrapped OSC 52 | — | **yes** |
| `set-clipboard external` | plain `ESC ] 52 ; c ; … BEL` | — | no |
| `set-clipboard on` | plain OSC 52 | yes | **yes** |
| `set-clipboard off` | plain OSC 52 | — | no |

So, by default, nothing an application writes inside tmux reaches the
clipboard by OSC 52, wrapped or plain; `copyToClipboardOSC52` still returns
`true`. A person running chord over SSH inside tmux needs
`set -g allow-passthrough on` for OpenTUI's form (a plain OSC 52 would
need `set -g set-clipboard on` instead; OpenTUI does not write that form
inside tmux, and chord should not write its own around it).

Not tried here: a real terminal outside tmux answering OpenTUI's capability
query (this session has no terminal, so `osc52_support` stayed `unknown`);
Linux X11 and Wayland; OSC 52 size limits (runtime's question 4).

### Which goes first

The task says "OSC 52, pbcopy where OSC 52 is refused". The spike says
that order cannot be built as written:

- A refusal is never seen. A terminal that drops OSC 52 answers nothing;
  OpenTUI reports `attempted` and `unknown`. "pbcopy where refused" would
  need a guess, which the one rule rules out.
- The host write is the only path that says it worked (`written`), works
  inside tmux with no configuration, and is OpenTUI's.

So the recommendation is OpenTUI's `best-available`: local runs write the
system clipboard and fall back to OSC 52 only if the host fails; SSH runs
write OSC 52 only (a host write there would land on the remote machine's
clipboard). That changes the task's order to fit the library, which is the
owner's to accept (owner question 3).

pbcopy is not needed: macOS-only, a process per copy, and the host write
does the same in-process. `@mariozechner/clipboard`'s `setText` works too,
but it is a second native module for what OpenTUI's already-loaded library
does with a timeout, an abort and a typed result; it stays for ctrl+v's
images. (OpenTUI's host `read` with `preferredTypes: ['image/png']` could
take ctrl+v's place one day; not this task.)

### Injectable, for tests

`ClipboardService` is an interface: the window takes one (built in
`main.tsx` / `renderer.tsx` from the real renderer, and disposed on quit),
and the harness hands a fake that records `writeText` calls and returns
the result a test wants. A test that wants to see OSC 52 bytes in
`harness.tsx`'s `Logged` terminal builds the service from a fake host
returning `unsupported` and OpenTUI's own adapter on the test renderer.
Tests never touch the real clipboard (CLAUDE.md).

### What the result means for the status line

| `writeText` result | Honest note |
| --- | --- |
| host `written` | copied N chars to clipboard |
| host `unsupported`/`failed`, terminal `attempted` | the text was sent to the terminal's clipboard; whether it took cannot be known |
| remote, terminal `attempted` | same as above |
| terminal `not-attempted` (`osc52_support: unsupported`) or `local-failure`, host not written | could not copy, with the host's error where there is one |
| host `timed-out` | could not copy: the clipboard did not answer |
| text over `maxWriteBytes` | `writeText` throws before writing; could not copy, too large |

The wording is the interface draft's; the split between "copied" and
"sent" is owner question 4.

## Failure cases, on the session side

- **The agent exits, a turn is cancelled, an update arrives late.** None of
  them reach the clipboard or the record through this feature. A copy reads
  what is drawn at release; what a late chunk or an exit line does to a
  held selection is the drawing's (runtime questions 2 and 3).
- **`/clear`, a tab switch, a closed tab.** The selection belongs to the
  window and is cleared with what it covered; nothing is sent.
- **A copy still pending at quit.** `ClipboardService.dispose()` aborts
  pending writes and waits for them; the quit path should await it with the
  renderer's other teardown, bounded by the host timeout.

## Open questions (for the other drafts)

- **Linux clipboard ownership after quit (runtime).** On X11 and Wayland the
  copying process owns the selection; when it exits, the text may go unless
  a clipboard manager took it. Whether OpenTUI's native backend hands it on
  could not be checked here. If it does not, a copy made just before quit is
  lost on a bare X11 session; `all-available` (OSC 52 as well) would cover
  terminals that take OSC 52.
- **What "chars" counts (interface).** The string's UTF-16 length, code
  points, or graphemes; Claude Code's count is likely `.length`.
- **Does the test renderer report `remote`?** If `testRender`'s capabilities
  are `null`, OpenTUI's adapter takes `remote` as `true`, so
  `best-available` would skip the host in tests; the fake service avoids it.

## Owner questions

Undecided, each with a recommendation.

1. **The setting's name, default and scope.**
   - a. `copyOnSelect`, boolean, default `true`, user's file only, read at
     start. *(recommended: Claude Code's key and default; `mouse`'s scope)*
   - b. The same, in both files.
   - c. No setting: always copy on release.
2. **Where the toggle lives, and what the note says after the count.**
   - A. The settings file only; the note is `copied N chars to clipboard`.
     *(recommended)*
   - B. A chord command that toggles and saves, as `/vim`; the note names it.
   - C. chord's own rows in `/config` beside the agent's options; the note
     says `/config`, as Claude Code's does.
3. **The clipboard's order** — the task's "OSC 52, pbcopy where refused"
   cannot be built, as no refusal is seen.
   - a. OpenTUI's `best-available`: the system clipboard locally (OSC 52 only
     if that fails), OSC 52 over SSH. *(recommended)*
   - b. `all-available`: both the system clipboard and OSC 52 locally,
     OSC 52 over SSH. Covers a Linux selection lost at quit; writes the
     clipboard twice.
   - c. `terminal-only`: OSC 52 always, as the task's first step; silent
     failure inside a default tmux and in terminals that drop it.
4. **The note when only OSC 52 was written** (SSH, or the host failed).
   - a. Say it differently: `sent N chars to the terminal's clipboard`.
     *(recommended: "copied" would claim what nobody saw)*
   - b. Say `copied N chars to clipboard` either way, as Claude Code does.
5. **chord over SSH inside tmux**, where OpenTUI's wrapped OSC 52 needs
   `allow-passthrough on`.
   - a. The guide says so (`set -g allow-passthrough on`), next to the
     existing `set -g mouse on` line. *(recommended)*
   - b. a, and an issue upstream asking OpenTUI for plain OSC 52 under tmux,
     which tmux's `set-clipboard on` takes.
   - c. Nothing.

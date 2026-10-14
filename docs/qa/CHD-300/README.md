# CHD-300 — M3 end to end on Bun

QA on main at implementation commit `010514e`, Bun 1.4.2, macOS arm64,
tmux 3.6a. Every agent was `tests/fixtures/fake_agent/main.ts`; no live
agent or model was used. The designer-approved appearance was left settled.

## What ran

- `bun run compile`, producing `dist/bun-darwin-arm64/chord`.
- Source: `bun run chord fake -C <scratch>/work --agent-command
  'bun /tmp/chd300-repo/tests/fixtures/fake_agent/main.ts --no-http'`.
  The supplementary Vim cases used `bun run chord:fake` itself.
- Binary: `dist/bun-darwin-arm64/chord fake -C <scratch>/work
  --agent-command 'bun /tmp/chd300-repo/tests/fixtures/fake_agent/main.ts
  --no-http'`.
- Isolated `tmux -L chd300` sessions at 120×40 and 80×24, each with its
  own `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and working directory under
  `/tmp/chd300/<case>`. `/tmp/chd300-repo` was a symlink to the checkout.
  The fixture's `--no-http` / `CHORD_FAKE_NO_HTTP=1` disabled chord's own
  M4 server in the agent capability declaration, keeping bearer tokens
  out of the MCP JSON readback. User MCP servers were still passed.
- Literal text and Enter separately, with keys for every in-app action.
  `CHORD_FAKE_STEP_MS=10` made streaming and intermediate states visible.
- Each main M3 case resized to the other acceptance size and back.
- `stty -g` before and after in the same non-interactive shell, tmux's
  alternate-screen and cursor flags, raw output through `pipe-pane`, and
  process ownership/cleanup through `/bin/ps`.

The checks followed CHD-299's repeat recipe. No component, renderer, parser,
protocol helper or implementation library was built. Existing fixtures,
ACP SDK, Ink, Vim engine, external-editor and clipboard library were
exercised as built. `clipboard.swift` is a macOS QA fixture only.

## Repeat setup

Create neutral scratch config/state/work directories and a symlink under
`/tmp` to the checkout. In the scratch project's `.chord/settings.json`,
set `agents.fake.command` to the fixture command above, so `/new` remains
on the fake. The user's scratch `settings.json` starts with:

```json
{
  "theme": "dark",
  "preferredNotifChannel": "bell",
  "mcpServers": {
    "user-docs": { "type": "http", "url": "http://localhost:9/docs" }
  }
}
```

The scratch working directory's `.mcp.json` contains:

```json
{
  "mcpServers": {
    "project-files": { "command": "echo", "args": ["m3-server"] }
  }
}
```

These are values to read back; the fake does not connect to these servers.
The scripted `EDITOR` is an executable shell script that writes
`edited draft from scripted EDITOR` plus a newline to its first argument;
`VISUAL` is empty. All settings writes stay in scratch directories.

For clipboard checks on macOS, compile `clipboard.swift` with a module cache
under `/tmp`, then run its `save <backup.plist>` action, followed by
`image <backup.plist>` to place a generated 2×2 PNG on the host clipboard.
Always finish with `restore <backup.plist>`. `tiff <backup.plist>` generates
the separate CHD-301 reproduction. The backup contains private clipboard
data and stays outside the repository; only the equality result is filed.

Seed another directory by opening a fake TUI there with the same scratch
state, sending `other directory M3 record`, and quitting. Use that state
for the main case. Do not synthesize session records.

## Keyboard reproduction

1. Capture the startup header. Ctrl+V, capture `[Image #1]`, then Enter and
   capture the fake's image receipt.
2. Type `original draft`, Ctrl+G, capture the saved editor text, then Enter.
3. `/vim`, type `one two three`, Escape. Drive `0 w b e h l $`, `dw`, `u`,
   `3w`, `cw` and insert `ONE`; Escape, then `x`, `u`, `dd` and `p`.
   Clear the draft's lines before typing `/vim` again to turn it off.
4. `/theme`, Down to Light, Enter; `/theme`, Up to Dark, Enter. Capture the
   preview and the selected result, with ANSI colours retained.
5. Send `shell`. Capture before output, between output deltas, and after
   its failing exit. Ctrl+O opens the whole terminal output.
6. Send `subagent`. Capture the running group and child permission; Ctrl+O
   expands its work and nested grandchild. Press 1, capture the background
   child after the parent ends, then its completion. Home/PageDown/End
   inspect the expanded work without changing the transcript.
7. Send `compact`; capture the spinner, completion and Ctrl+O summary.
   Send `compactfail`; its in-progress state is capture 30 and its visible
   failure is above the MCP panel in capture 31.
8. `/mcp`, capture the names/transports/definition files, Escape. Send `mcp`,
   Ctrl+O and scroll for the fake's exact `session/new` server readback.
9. Send a first prompt and leave `first unsent draft`. Ctrl+X then c opens
   another session; send another prompt and leave `second unsent draft`.
   Ctrl+X p/n restores each tab's draft and transcript. Clear the draft.
10. `/resume`, capture current directory; Ctrl+A, capture all directories;
    Ctrl+A, capture the current directory again; Escape.
11. Send `error`, capture the failure. Send `slow`, Escape, capture
    `Interrupted by user`. Resize to the other size and back. Ctrl+D quits.
12. In a new scratch configuration, rebind Chat Enter to `chat:newline`
    and Ctrl+S to `chat:submit`, and Global Ctrl+T to `session:new`.
    Type `rebound`, Enter, `submit`, Ctrl+S; Ctrl+T opens another tab.
    `?` shows the effective keys. Quit.
13. In separate scratch cases choose `osc9` and `osc777` as notification
    channels. Send `text`, then `permission`, press 1, and quit. Raw output
    contains both the completed-turn and permission-wait notifications.

The supplementary `*-vim-extra` cases type `alpha beta`, Ctrl+J,
`gamma delta`, Escape, and drive `0 w b e ^ $ h l k j`, `dw`, `cw`, `A`
and `o`. The resulting draft is `ALPHA beta!`, `middle`, `delta` on three
lines. Ctrl+C clears the entire draft before Ctrl+D quits: Ctrl+U clears
only a line, and Ctrl+D intentionally preserves an unsent draft.

## Evidence map

Each `source-120`, `source-80`, `binary-120`, `binary-80` prefix has `-m3`,
`-rebound`, `-osc9`, `-osc777`, `-vim-extra` and `-m3-other` directories.
`.txt` and `.ansi` captures are unedited tmux screens, the latter preserving
colour and the normal-mode cursor mark. Expanded and scrolling captures
cover content taller than 24 rows.

| M3 row | Evidence within every size/build prefix |
| --- | --- |
| Image paste | m3 01-image-placeholder, 02-image-received |
| External editor | m3 03-editor-return, 04-editor-submitted |
| Vim modes and motions | m3 05–10; vim-extra 01–07 and 02-motion-* |
| Light/dark themes | m3 11–14, including ANSI preview/selection |
| Startup logo/version/model/directory | m3 00-header |
| Wait notifications | m3 terminal.raw.ansi.gz (BEL); osc9/osc777 terminal.raw.ansi.gz and raw-output.json |
| Live terminal stream and exit | m3 15–19 |
| Nested subagents | m3 20–26, folded/expanded, permission, background and completion |
| Compaction | m3 27–30, failure visible above the panel in 31 |
| MCP settings and .mcp.json reach session/new | m3 31–34, panel and fake JSON readback |
| Custom prompt/app keys | rebound 01–04 |
| Several sessions and switching | m3 35–37 |
| Session list across directories | m3-other 01; m3 38–40 |
| Error/interrupt/resize | m3 41–44 |
| Quit, terminal and owned processes | cleanup.json in every case; raw-output.json |

`terminal.raw.ansi.gz` files decompress to the unedited bytes of the main and notification
cases, including startup and teardown. `raw-output.json` identifies exact
OSC sequence offsets/hex bytes, standalone BEL offsets and terminal control
counts. BEL counts also
include OSC terminators; the main case's standalone BEL writes can be read
in the decompressed raw stream. The Swift clipboard data equality is in
`clipboard-restoration.json`.

## What was seen

All in-scope rows were driven at both sizes from source and the host binary.
PNG paste reached the fake as `image/png, 132 bytes`; editor text returned
and was submitted. Vim showed both mode marks, retained multiline editing,
changed/deleted words, undid and put text back. Theme selection persisted in
scratch settings, and the captured palette changed between Light and Dark.
The startup header named version `0.0.0`, fake, its model and scratch directory.

Terminal deltas appeared under the running call before its exit code 1.
Subagent work remained under its own block, including the grandchild and
child permission; the failed sibling and background child completion were
visible. Compaction showed the running spinner, completed summary and the
fake's failure. `/mcp` and the fake's JSON agreed on the user HTTP server and
project stdio server. Rebound submit and new-session actions worked, and
switching tabs restored each unsent draft. Ctrl+A changed `/resume`'s scope
and exposed the seeded session in another directory. Agent errors and Esc
interrupts stayed visible after resize.

All final captured quits exited 0 with equal before/after `stty`,
`alternate=0`, `cursor=1` and no owned processes remaining. Raw output has
alternate-screen leave and cursor-show sequences. The generated clipboard
fixture was removed and the original clipboard data restored unchanged.

## Scope and findings

Out of scope: startup splash (CHD-241, blocked on the owner), elicitation
forms (CHD-98, blocked on the owner), rewind Esc Esc (CHD-102, owner decision),
and Linux display clipboard delivery (CHD-297). Desktop notification delivery
cannot be proved in tmux; BEL / OSC 9 / OSC 777 bytes were proved instead.
Physical kitty keyboard negotiation was not checked.

CHD-163 remains the existing fake subagent gap: parent plan, parent Codex wait
call, lone child's +N fold, and all-Done group header cannot be shown by this
scenario. The available nested/running/failed/background/permission states
were captured; this check does not claim those four missing states.

Filed **CHD-301**: a generated macOS NSImage TIFF with IEEEFP samples is
rejected by the clipboard decoder, from source and binary. Evidence is in
`source-120-tiff` and `binary-120-tiff`; the status line reports the error,
and ordinary text still works. The library itself rejects the same fixture.
No evidence establishes a Bun migration regression. PNG acceptance passes;
this separate finding does not hold CHD-300 open.

## Verification

`bun run check` passed in the foreground: 51 lint tests and 1,508 tests
across 109 files, zero failures; the fake/session/UI suite took 481.81 seconds.
Expected fixture editor/shell diagnostics and caught Vim-library diagnostics
appeared on stderr, as in CHD-299; the command exited 0.

The final `/bin/ps` audit found no fake agents, and tmux reported no CHD-300
server running. All 26 captured quits exited 0. Counts, cleanup and the host
binary hash are in `verification.json`. No implementation code changed.
Evidence is committed locally on main for chd-lead to close CHD-300 and
decide what remains of M3 besides its three owner rows and filed findings.
The 325 paired text/ANSI screens and four acceptance audits cover the rows
above. The seven privacy tests passed with the evidence staged, and
`git diff --cached --check` passed. Raw streams are gzip-compressed to preserve
terminal carriage returns exactly without treating them as source whitespace.

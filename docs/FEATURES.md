# Features

What gets built, and in which order. chord is the Dart terminal app in
[github.com/IKatsuba/chord](https://github.com/IKatsuba/chord), built on
chord_tui. The TypeScript app at `ts-final` is reference history; the Dart
app is its own specification.

"framework" means it is built in `packages/chord_tui/lib/` as a general
widget or service with tests of its own; "port" means it is chord's own and
lives in `lib/`, `bin/` and `tool/`. The tasks are on the board, project
`CTUI`, one milestone per section below.

## Core (done)

The element tree, `setState`, `InheritedWidget`, layout in cells (`Row`,
`Column`, `Expanded`, `Padding`, `Align`, `Stack`, `Box`), text measured and
wrapped in cells, ANSI spans, keys and chords, `Focus` and `Actions`,
`TextInput`, `Spinner`, `KeyHelp`, the cell-diffing renderer, `runApp`, and
the tester.

## F — the framework chord needs

| Feature                                       | Where     | Notes |
| --------------------------------------------- | --------- | ----- |
| Scrolling and virtualised lists (done)         | framework | `ScrollController`, `ListView.builder`, following the bottom; the transcript, pickers and logs |
| Layers over the window (done)                 | framework | `Positioned` in `Stack`, an `Overlay` for pickers floating over the transcript |
| Theme: colour roles, dark or light (done)     | framework | `Theme` as an `InheritedWidget`; the terminal's background read with OSC 11 |
| Markdown (done)                               | framework | a maintained parser, drawn in cells; code blocks with a border |
| Code with highlighting (done)                 | framework | a maintained highlighter's grammars |
| Diff (done)                                   | framework | numbered, highlighted, long lines wrapped under their code |
| Text area (done)                              | framework | multiline, wrapping, OpenTUI editing keys, in-editor selection, paste, history hook |
| Fold, Table, Picker, Dialog (done)            | framework | the building blocks of chord's dialogs and pickers; fuzzy filter |
| Terminal services (done)                      | framework | OSC 52 copy, `$EDITOR` and back, bell and OSC 9 / 777, terminal title and user variables, kitty keyboard protocol |
| Rebinding file, grouped shortcuts panel (done) | framework | a keybindings file that moves keys bound through `Actions`, read at run time; no code generation |

## M0 — skeleton

| Feature                                       | Where     | Notes |
| --------------------------------------------- | --------- | ----- |
| The port's package, `chord`, `chord <agent>`, `chord agents` (done) | port | the repository root, the pinned registry and agents' CLIs |
| ACP client (done)                              | port      | JSON-RPC over the agent's stdio |
| Fake agent for tests (done)                   | port      | the Dart scripted agent the tests and `--fake` drive |
| Standalone binary (done)                      | port      | `dart compile exe` |

## M1 — talk to an agent

| Feature                                       | Where     | Notes |
| --------------------------------------------- | --------- | ----- |
| Session and transcript reducer (done)          | port      | `session/new`, `session/prompt`, updates folded into the transcript |
| Transcript: replies, thinking, tool calls, edits as diffs (done) | port | Markdown, Fold, Diff and the scrolling list from F |
| Prompt: multiline, history, queue, interrupt (done) | port      | the text area from F |
| Permission prompt (done)                      | port      | inline choice, numbers and arrows, Esc rejects |
| Plan, status line, spinner with elapsed time, errors (done) | port | |
| Start page and agent picker (done)            | port      | the logo, version and directory above the picker |
| Quit and the shortcuts panel (done)           | port      | ctrl+c twice, ctrl+d; `?` on an empty prompt |

## M2 — daily driver

| Feature                                       | Where     | Notes |
| --------------------------------------------- | --------- | ----- |
| Modes, model picker, config options (done)    | port      | shift+tab, `/model`, effort; `/model` and `/config` wait through startup |
| Slash commands with completion, client commands (done) | port    | the agent's and chord's own |
| Drag selection and copy (done)               | framework + port | `SelectionArea`, code copy buttons and keyboard block picking |
| `@` file mentions, `@@` agent names (done) | port      | fuzzy finder |
| Bash mode (done)                              | port      | `!` prefix |
| Sessions saved and resumed (done) | port      | `--continue`, `--resume`, `/resume` |
| Steering, reverse history search, verbose view (done) | port     | Tab, ctrl+r, ctrl+o |
| Headless one-shot and `chord acp` (done) | port      | `-p` with agent notices on stderr, ACP on stdio |
| Usage and cost, settings files (done) | port      | `/status` account facts and sign-in guidance at startup or during a turn |

## M3 — the rest

| Feature                                       | Where     | Notes |
| --------------------------------------------- | --------- | ----- |
| Image paste (done)                            | port      | |
| `$EDITOR`, vim mode, themes, custom keybindings (done) | port    | on F's services |
| Header, splash, notifications, tab status (done) | port      | `chord_session` terminal user variable for launchers |
| Live command output, subagents, elicitation forms, compaction (done) | port | |
| Fork, MCP servers, session list (done) | port      | |
| chord upgrade and distribution (npm, Homebrew, GitHub Releases) (in progress) | port and tools | Official-binary refusal names npm, Homebrew and checked archives; self-replacement remains (CTUI-143) |

## M4 — agents that start agents

| Feature                                       | Where     | Notes |
| --------------------------------------------- | --------- | ----- |
| chord's MCP server, children, messages (done) | port      | `open_agent`, `send_message`, `spawn_task`, the agents list |
| Monitors and the background view (done)       | port      | |

## M5 — teams

| Feature                                       | Where     | Notes |
| --------------------------------------------- | --------- | ----- |
| Team files, `/team`, runs, teams on resume (done) | port      | `.chord/teams/<name>.md` |

## M6 — the chord repository

| Feature                                       | Where     | Notes |
| --------------------------------------------- | --------- | ----- |
| Pre-swap preparation (CTUI-191) (done)         | app and tools | Adapted guide and developer docs, independent tests, fake screenshots and shared version |
| Repository swap (CTUI-190) (planned)           | repository | Land the prepared Dart app and retained adapter in IKatsuba/chord; keep TypeScript history at `ts-final` |

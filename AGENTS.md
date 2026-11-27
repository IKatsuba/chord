# AGENTS.md

This file provides guidance for every coding agent and person working here.
It is binding.

## What this is

This repository, github.com/IKatsuba/chord, holds the Dart terminal app and its
Flutter-shaped framework, chord_tui. `README.md` describes the app;
`packages/chord_tui/README.md` describes the framework;
`docs/FEATURES.md` is the map of what gets built and in which order,
`docs/decisions.md` is why things are the way they are. Read these before the
first change.

There are four things in the tree, and they do not mix:

- **The framework**, `packages/chord_tui/` (package `chord_tui`): widgets,
  layout, text, keys, the renderer, the tester. It knows nothing about agents
  or chord.
- **The port**, at the root (package `chord`, depends on the framework by
  path): the terminal app, its ACP connections, sessions and screens.
  The TypeScript app is preserved at the `ts-final` tag for reference.
- **The Cursor Cloud adapter**, `packages/cursor-cloud-acp/`: a TypeScript
  ACP adapter with its own Bun workspace tooling and npm release.
- **The website**, `site/` (package `chord_site`): a chord_tui app compiled
  to Wasm and drawn by wterm, with live framework examples, chord screen
  fixtures and recordings. It depends on chord for the fixtures and has no
  shared release version.

The point of the port is to prove the framework: whenever the port needs
something a terminal app would generally need (a scrolling list, a picker, a
markdown renderer), it is built in `packages/chord_tui/lib/` with tests,
and the port only uses it. Only what is chord's own (ACP, sessions, teams,
its screens) lives in the root `lib/`.

Everything here (code, comments, docs, commit messages, test names) is in
English, and nothing names a home directory, a key, or a person's machine.
`../chord` is the only path outside the repository that may be written down.

## The rules

**The framework is written from scratch.** `packages/chord_tui/lib/` does
not depend on nocterm or any other terminal UI package.

**A maintained package before our own code, for what is not about the
terminal.** Grapheme segmentation, markdown parsing, highlighting grammars,
diffing, fuzzy matching, YAML, JSON-RPC: look on pub.dev for a maintained
package that works under `dart compile exe`, try it, and say in the handover
what you tried. Writing our own is the answer only when the package is shown
not to fit, and that finding goes into `docs/decisions.md`. When a package
does not do directly what the task asks, do not write a workaround around it
on your own call: stop and hand the owner the question with the options.

**The Dart app is its own specification.** `ts-final` is history for
reference, not a requirement for new behaviour. Before the swap, "the
original" and `../chord` in designs and decisions mean the TypeScript app.

**Every action has a key.** Nothing on screen needs a pointer. A new action
is bound through `Actions`, with a description, and the shortcuts panel
lists it.

**Logic lives where a test reaches it.** State and reducers are plain Dart
with no widget in them; widgets draw state and dispatch.

The framework and port share a version. The root `pubspec.yaml` is the
source; the release bump updates it, `packages/chord_tui/pubspec.yaml`,
`lib/version.dart` and the root `pubspec.lock` together.

## Commands

```sh
# Framework commands, from the repository root:
(
  cd packages/chord_tui
  # the dependencies, as pubspec.lock pins them
  dart pub get
  dart analyze                        # framework types and lints
  dart format .                       # lay out the tree
  dart format --output=none --set-exit-if-changed .   # check the layout
  dart test                           # the framework's tests
  dart test -t publish --run-skipped   # committed HEAD's archive, dry run only
  dart doc                            # generate the framework's API docs
  dart pub global activate pana       # install the local package checker
  dart pub global run pana --no-warning . # local package score
  dart test test/widgets_test.dart    # one file
  dart test test/cursor_test.dart     # editor cursor styles and visibility
  dart test test/terminal_services_test.dart # user variables and services
  dart test test/terminal_open_url*_test.dart # system and WSL link opening
  dart test test/foundation/text_editing_layout_test.dart
  dart test test/foundation/text_editing_selection_test.dart
  dart test test/widgets/text_area_selection_test.dart
  dart test test/widgets/text_area_rows_tester_test.dart
  dart test test/widgets/focus_test.dart \
    test/widgets/focus_reparent_tester_test.dart
  dart test test/host_terminal*_test.dart
  dart test test/process_io_test.dart test/run_app_failure_tester_test.dart
  dart test test/foundation/playback_test.dart test/playback_example_test.dart
  dart test test/widgets/playback*_test.dart
  dart test test/widgets/key_help_boundary*_test.dart
  dart test test/widgets/display_text*_test.dart test/widgets/*button*_test.dart
  dart test test/widgets/link*_test.dart \
    test/widgets/can_request_focus*_test.dart
  dart test test/widgets/scrollbar*_test.dart \
    test/widgets/scroll_view*_test.dart
  dart test test/widgets/scrolls_on_wheel*_test.dart
  dart test test/widgets/exit_scope*_test.dart
  dart test test/widgets/focus_scope_dispatch*_test.dart
  # Wasm builds and exit paths; Node on PATH for execution:
  dart test test/run_app*wasm*test.dart --run-skipped
  # System Chrome; CHROME overrides its path:
  dart test -t browser --run-skipped
  dart test test/run_app_test.dart    # startup and drawing failure cleanup
  dart test test/run_app_signal*_test.dart # signal exits and ignored fallback
  # driver drain, launch failure and identity
  dart test test/expect_*test.dart
  dart test test/terminal_mouse_test.dart \
    test/terminal_mouse_lifecycle_test.dart
  dart test test/terminal_hangup_test.dart test/terminal_hangup_tester_test.dart
  dart test -n 'a chord waits'        # tests whose names match
  # demo keys, quit, SIGHUP and failed startup
  dart test -t compile --run-skipped
  dart test test/run_app_exit_compile_test.dart --run-skipped
  dart run example/main.dart          # example: Ctrl+O folds, Ctrl+Q quits
  dart run example/demo.dart          # the framework's own demo
  dart run example/code.dart          # highlighted, numbered, wrapped code
  dart run example/markdown.dart      # Markdown, including streamed replies
  dart run example/markdown_run_controls.dart # recorded copy/run actions
  dart run example/markdown_wrap.dart # table cells and long URLs
  dart run example/markdown_wrap.dart --narrow # narrow table fallback
  dart run example/diff.dart          # numbered, highlighted, wrapped diffs
  dart run example/display_text.dart # block-glyph display sizes and colours
  dart run example/button.dart       # action buttons, focus and disabled state
  dart run example/link.dart         # links and terminal services
  dart run example/scrollbar.dart    # list position and thumb
  dart run example/scroll_view.dart  # live widgets and focus following
  dart run example/playback.dart     # recorded terminal, steps and panning
  dart run example/diff_view.dart     # selected diff rows and full counts
  dart run example/middle.dart        # text retaining both ends around ...
  dart run example/layers.dart        # anchored layers over a streaming list
  dart run example/overlay_visibility.dart # visible-surface completion guard
  dart run example/overlay_visibility.dart --passive # transparent follower
  dart run example/picker.dart        # numbered choices with a fuzzy filter
  dart run example/picker_preview.dart # highlight preview before acceptance
  dart run example/fold.dart          # folding output and aligned table columns
  dart run example/dialog.dart        # a framed question over the window
  dart run example/form.dart          # validated fields, choices and buttons
  dart run example/form.dart --narrow # whole-field scrolling
  dart run example/form.dart --narrow --long-list # partial option scrolling
  # multiline editing, wrapping and scrolling
  dart run example/text_area.dart
  dart run example/text_area_viewport.dart  # shown rows and gutter
  dart run example/text_area_spans.dart # style-only full-text projection
  dart run example/error_boundary.dart  # drawing failure and fallback
  dart run example/key_help.dart        # grouped help and pending chords
  dart run example/key_help.dart --rebound # runtime keymap, Quit on Ctrl+Q
  dart run example/text_area_key_filter.dart  # delegate keys from live input
  # services and redraw
  dart run example/terminal_services.dart --scripted-editor
  dart run example/terminal_services.dart --scripted-editor --editor-fails
  dart run example/mouse.dart         # captured pointer reports and wheel log
  dart run example/selection.dart     # semantic selection, no clipboard
  dart run benchmark/list_view.dart   # list frames and cached switches, no IO
  dart run benchmark/markdown_stream.dart  # streamed Markdown, no terminal
  # selection work and retained-source counts
  dart run benchmark/selection.dart
  dart run benchmark/picker.dart --count=2000 # exact heights and navigation
  dart test test/widgets/markdown_blocks_test.dart
)
# App commands, from the repository root:
dart pub get                       # app dependencies, including chord_tui
dart analyze                       # app types and lints
dart format .                      # format both packages
dart format --output=none --set-exit-if-changed .
dart test                          # the port's tests
dart test test/session test/ui  # sessions and screens
dart test test/registry_test.dart # pinned registry and launch data
dart test test/headless_notice_tester_test.dart
dart test test/notify_session_var_test.dart
dart test test/session/sign_in_account_fake_test.dart
dart test test/ui/app/status_account_window_test.dart
dart test test/ui/app/sign_in_account_window_test.dart
dart test test/ui/app/session_var_window_test.dart
dart test test/ui/app/settings_starting_window_test.dart
dart test test/ui/prompt/prompt_rows_test.dart
dart test test/ui/dialogs/questions_note_rows_test.dart
dart test test/ui/dialogs/questions_note_reflow_tester_test.dart
dart test test/ui/dialogs/plan_note_tester_test.dart
dart test test/ui/dialogs/plan_scroll_test.dart
dart test test/ui/dialogs/plan_note_scroll*_test.dart
dart test test/ui/dialogs/plan_note_rebound_tester_test.dart
dart test test/ui/app/plan_note_keys_test.dart
dart test test/ui/app/cmd_history_window_tester_test.dart
dart test test/ui/app/prompt_press_tester_test.dart
dart test test/ui/prompt/prompt_arrows_test.dart \
  test/ui/prompt/prompt_modified_arrows_tester_test.dart
dart test test/ui/app/help_command_tester_test.dart
dart test test/cli_once_test.dart test/cli_once_tester_test.dart
dart test test/cli_acp_missing_value_tester_test.dart
dart test test/session/replay_legacy_plan_tester_test.dart
dart test test/ui/app/starting_commands_window_test.dart
dart test test/ui/app/chord_cursor_window_test.dart
dart test test/ui/app/prompt_selection_window_test.dart
dart test test/ui/app/code_click_session_window_test.dart \
  test/ui/app/code_click_session_window_tester_test.dart
dart test test/ui/app/textarea_held_window_test.dart
dart test test/ui/dialogs/plan_box_held_fake_test.dart
dart test test/session/opening_meta_test.dart
dart test test/acp_server_leave_test.dart
dart test test/session/monitors_run_test.dart
dart test test/session/conversation_monitors_starting_test.dart
dart test test/session/conversation_monitors_starting_tester_test.dart
dart test test/ui/background
dart test test/session/record_stopping_test.dart
dart test test/ui/app/program_status_window_test.dart
dart test test/acp_monitors_fake_test.dart
dart test test/session/session_fork_fake_test.dart
dart test test/ui/app/fork_window_test.dart
dart test test/settings_tool_test.dart
dart test test/ui/app/settings_tool_window_test.dart
dart test test/acp_settings_tool_fake_test.dart
dart test test/teams_test.dart
dart test test/yaml_stringify_test.dart
dart test test/session/agents_host_teams_test.dart
dart test test/ui/app/team_command_window_test.dart
dart test test/ui/app/propose_window_test.dart
dart test test/ui/teams
dart test test/platform/resources_readers_test.dart
dart test test/platform/group_exec_contract_test.dart
dart test test/platform/process_libc_tester_test.dart
dart test test/platform/platform_wasm_tester_compile_test.dart --run-skipped
dart test test/platform/heap*_test.dart test/cli_heap_test.dart
dart test test/cli_help_columns*_test.dart
dart test test/acp_set_title_targeted*_test.dart
dart test test/session/sessions_targeted_tester_test.dart
dart test test/acp_team_fake_test.dart
dart test test/kept_test.dart
dart test \
  test/channel_test.dart test/node_semver_test.dart
dart test \
  test/cli_upgrade_test.dart test/upgrade_test.dart
dart test test/upgrade_brew_test.dart
dart test test/tool/release_test.dart test/tool/release
dart test test/tool/release/x64_sdk*_test.dart
dart test \
  test/tool/npm_test.dart test/tool/formula_test.dart
dart test \
  test/tool/ci_test.dart test/tool/workflow_test.dart
dart test test/tool/shards_test.dart
dart test test/tool/screenshots_test.dart test/tool/screenshots_tester_test.dart
dart test test/tool/recordings*_test.dart
dart test test/tool/genai_prices_test.dart \
  test/tool/currency_symbols_test.dart
dart test test/fixtures/fake_agent
# List one CI shard; paths are relative to the selected package:
dart run tool/shards.dart --package=. --shard=1/3
dart run tool/shards.dart --package=packages/chord_tui --shard=1/3
# CI release-target checks on a Linux x64 host:
dart run tool/ci.dart linux-x64
dart run tool/ci.dart linux-arm64
dart test test/tool/release/build_compile_test.dart \
  --run-skipped
dart test test/leave_zones_compile_test.dart --run-skipped
# The port's compiled launcher, window and ACP server smoke tests:
dart test -t compile --run-skipped
# ACP, picker and record benchmarks, no terminal:
dart run benchmark/acp_updates.dart
dart run benchmark/acp_server.dart
dart run benchmark/picker.dart --count=2000
# Data generators use Node; install @pydantic/genai-prices 0.2.3 first:
dart run tool/genai_prices.dart \
  --package node_modules/@pydantic/genai-prices
dart run tool/currency_symbols.dart # Node with ICU 78.1
dart run benchmark/record_scan.dart # generated records
# Record scan flags: --files=N --big-count=N --big-mb=N --runs=N;
# --dir=PATH reuses a completed set; --keep retains it.
dart run bin/chord.dart          # start page and agent picker
dart run bin/chord.dart codex -C . # session directory
dart run bin/chord.dart codex --no-mcp-servers # no MCP servers
dart run bin/chord.dart codex --continue # latest session here
dart run bin/chord.dart --resume # pick an earlier session
dart run bin/chord.dart agents   # list agents and commands
dart run bin/chord.dart agents -C . --json
dart run bin/chord.dart acp      # serve ACP on stdio
dart run bin/chord.dart upgrade --help # install-specific upgrade
dart run tool/release.dart --help # maintainer release stages
dart run bin/chord.dart codex -p "Explain this project"
git diff | dart run bin/chord.dart codex -p "Review this" \
  --output-format json
dart run bin/chord.dart --help
dart run bin/chord.dart --version
dart run tool/dev.dart chord --fake # fake runtimes and limits
dart run tool/dev.dart chord --fake --qa teams # fresh capture
# README and guide images; tmux and Chrome (CHROME overrides its path):
dart run tool/screenshots.dart # all 12 images, Dart fake only
dart run tool/screenshots.dart start logo # start page and both logos
dart run tool/record_history.dart --omitted # isolated saved past
# Standalone screen fixtures, no agent:
dart run tool/permission.dart
dart run tool/notice.dart # F2 reopens, F3 toggles permission
# The notice fixture accepts --light or --plain; it saves no dismissal.
dart run tool/form.dart --long-link # held link folding
dart run tool/form.dart --permission-over # F2 covers, F3 answers
dart run tool/agents.dart # subagents, launches and messages
dart run tool/children.dart # open agents and the list, no agent
dart run tool/children.dart --many # the list folded to … +N more
dart run tool/children.dart --codex # codex labels, no agent
# The children fixture also accepts --asking, --unseen, --exited, --failed,
# --tall, --held, --tasks, and --light or --plain.
dart run tool/start.dart
dart run tool/start.dart --resume
dart run tool/splash.dart # slow startup, no agent; Ctrl+Q quits
dart run tool/resume.dart --many # local/all choices, no IO
dart run tool/failed_start.dart # commands after failed startup
dart run tool/steering.dart # in-memory ACP; F1 lists controls
dart run tool/steering_replay.dart # recorded personal steering
dart run tool/prompt.dart
dart run tool/plan.dart
dart run tool/status.dart  # --light or --plain for other themes
dart run tool/settings.dart # --config or --values
dart run tool/crash.dart
dart run tool/raw_output.dart # Read without exit bookkeeping
dart run tool/shell.dart # recorded output, no shell
dart run tool/bash.dart --code # recorded shell and copy actions
dart run tool/mentions.dart # injected files, empty recipients
dart run tool/mentions.dart --agents
dart run tool/mentions.dart --many --slow
# The mentions fixture also accepts --light or --plain.
dart run tool/wheel.dart # transcript wheel, no agent
dart run tool/wheel.dart --help --tall-draft
dart run tool/wheel.dart --permission # overflowing proposal
dart run tool/wheel.dart --fitting # fitting proposal
dart run tool/selection.dart --pick # recording copy, no clipboard
dart run tool/selection.dart --manual # explicit selection copy
mkdir -p build
dart compile exe bin/chord.dart -o build/chord
./build/chord agents
# AOT session and record benchmarks, no terminal:
dart compile exe benchmark/acp_updates.dart -o build/acp_updates
./build/acp_updates
dart compile exe benchmark/acp_server.dart -o build/acp_server
./build/acp_server
dart compile exe benchmark/record_scan.dart -o build/record_scan
./build/record_scan
```

```sh
# Website commands, from the repository root:
(
  cd site
  dart pub get
  dart analyze
  dart format --output=none --set-exit-if-changed .
  dart test                          # routes, pages, recordings and build logic
  dart test test/live*_test.dart test/chord_page*_test.dart
  dart test test/article*_test.dart test/home*_test.dart
  dart test test/recording*_test.dart test/tool/sources_test.dart
  dart run tool/sources.dart          # refresh lib/sources.g.dart
  dart run tool/build.dart build      # static output in site/build/
  dart run tool/build.dart serve      # loopback preview with SPA fallback
  # Use the same --base on build and serve for a subpath (default /):
  dart run tool/build.dart build --base=/chord/
  dart run tool/build.dart serve --base=/chord/ --port=8080
  dart test -t compile --run-skipped  # build output, files and imports
  dart test -t browser --run-skipped  # Chrome smoke at / and /chord/
  dart run tool/terminal.dart         # native shell fixture, no browser
)
# Browser tests use system Chrome; CHROME overrides its path.
# Build fetches checksum-pinned wterm and fonts into .dart_tool/site_cache/.
# A host serves .wasm as application/wasm and index.html for page paths.
```

```sh
# Adapter commands, from the repository root:
bun install
bun dev quality cursor-cloud-acp
bun test ./tests/scripts ./lint
bun dev release cursor-cloud-acp --help # owner releases; help only here
```

Static checks, as the teams call them: `dart analyze` in the root,
`packages/chord_tui/` and `site/` (run `dart pub get` in each first), and
`dart format --output=none --set-exit-if-changed .` at the root, all clean.

The framework's `publish` test exports its folder from committed HEAD
outside git and runs `dart pub publish --dry-run`, checking zero warnings
and a framework-only archive. It does not check uncommitted changes.
Teams never publish;
`dart pub publish` must always include `--dry-run`.

## Layout

The framework is under `packages/chord_tui/`; these paths are relative to
that folder:

```text
.pubignore                 excludes files from the published archive
CHANGELOG.md               framework release notes
lib/chord_tui.dart          what an app imports
lib/testing.dart            the tester: testWidgets, press, shows
lib/web.dart                HostTerminal and WebTerminal for browser apps
lib/src/web/web_terminal.dart page terminal, clipboard, links and title
lib/src/terminal/host_terminal.dart host callbacks, modes and restoration
lib/src/terminal/process_*.dart native and web runApp exit/reporting
lib/src/terminal/settle_input_*.dart native input settling and web stub
lib/src/foundation/playback.dart recorded screens and playback reducer
lib/src/widgets/playback.dart Playback, PlaybackController and PlaybackBar
lib/src/widgets/key_help.dart KeyHelp and embedded KeyHelpBoundary
lib/src/foundation/         geometry, editing, selection and widget state
lib/src/foundation/text_editing.dart editing, selection and row movement
lib/src/foundation/vim.dart pure vim normal-mode state and editing reducer
lib/src/foundation/form.dart form fields, validation and navigation reducer
lib/src/foundation/scroll_state.dart scroll reducer and retained list anchor
lib/src/foundation/item_extents.dart measured item heights and versions
lib/src/terminal/           styles, cell buffers, renderer and terminal services
lib/src/terminal/terminal.dart terminal IO, services and user variables
lib/src/terminal/clipboard_image.dart platform clipboard image reading
lib/src/terminal/open_url.dart platform and WSL system link opening
lib/src/text/               widths, rich text, word wrap and fuzzy matching
lib/src/text/wrap_ansi.dart  wrap-ansi layout for TextLayout.wrapAnsi
lib/src/text/selection_layout.dart selection shaping and part row lookup
lib/src/input/              keys, chords, kitty alternates and SGR mouse input
lib/src/rendering/          render boxes: layout and paint
lib/src/widgets/            the widget tree, focus and actions, the widgets
lib/src/widgets/keymap.dart runtime rebinding by action id
lib/src/widgets/form.dart   validated form, buttons and keyboard input
lib/src/widgets/scroll_controller.dart retained scroll and row anchors
lib/src/widgets/scroll_view.dart live widget scrolling and Scrollable
lib/src/widgets/scrollbar.dart list and scroll view position thumb
lib/src/widgets/button.dart FilledButton and OutlinedButton
lib/src/widgets/link.dart URI and action links
lib/src/widgets/display_text.dart scalable block-glyph text
lib/src/widgets/exit_scope.dart embedded exit interception
lib/src/widgets/markdown.dart Markdown and blocksOf styled rows per block
test/                       framework tests
test/main_example_test.dart package example folding and keys
test/host_terminal*_test.dart host input, modes, restoration and reuse
test/process_io_test.dart native failure reporting
test/run_app_failure_tester_test.dart runApp cleanup failures
test/run_app*wasm*test.dart Wasm builds and exit paths through Node
test/web_terminal_browser_test.dart web input, resize, clipboard and reuse
test/foundation/playback_test.dart timed frames, steps and looping
test/widgets/playback*_test.dart playback controls, clipping and lifecycle
test/widgets/key_help_boundary*_test.dart embedded help and pending chords
test/playback_example_test.dart runnable recording example
test/publish_dry_run_test.dart committed archive contents and zero warnings
test/cursor_test.dart       editor cursor styles, visibility and focus
test/binary_smoke_test.dart compiled demo keys, quit and closed-pty SIGHUP
test/run_app_exit_compile_test.dart compiled startup and write failure cleanup
test/fixtures/run_app_exit.dart terminal failures and beforeExit exit fixture
test/run_app_signal*_test.dart signal cleanup, re-raise and fallback exits
test/fixtures/run_app_signal*.dart isolated termination-signal fixtures
test/expect_*test.dart       driver drain, launch failure and PID reuse guards
test/fixtures/expect_driver.dart expect driver and spawned-program cleanup
test/terminal_flush*_test.dart bounded output flush, mode restoration and reuse
test/terminal_hangup*_test.dart SIGHUP exit and flush-error boundaries
test/fixtures/terminal_hangup*.dart pty hangup and flush-failure fixtures
test/terminal_open_url*_test.dart platform and WSL link opening
test/terminal_open_url_detached_test.dart detached opener and start failures
test/fixtures/open_url_detached.dart app terminal with fake system openers
test/terminal_mouse*_test.dart mouse ownership and terminal reuse
test/fixtures/terminal_mouse*.dart isolated mouse-mode pty fixtures
test/foundation/           text editing, scroll, fold, picker and table widths
test/foundation/text_editing_selection_test.dart selection and editing keys
test/rendering/            item extents and clipping
test/widgets/              layout, layers, focus, rich widgets and lifecycle
test/widgets/display_text*_test.dart glyphs, sizes, style and clipping
test/widgets/*button*_test.dart action keys, dense faces and input lifetime
test/widgets/link*_test.dart URI, action and terminal ownership
test/widgets/scrollbar*_test.dart thumb geometry, fades and lifecycle
test/widgets/scroll_view*_test.dart live layout, reveal and focus following
test/widgets/scrolls_on_wheel*_test.dart wheel routing and defaults
test/widgets/exit_scope*_test.dart embedded exit ownership
test/widgets/focus_scope_dispatch*_test.dart scope keys and deferred requests
test/widgets/text_area_selection_test.dart editor selection and key help
test/widgets/focus_reparent_tester_test.dart focus across rebuilds and moves
test/widgets/list_view_switch_test.dart retained heights across list switches
test/widgets/diff_wrap*_test.dart diff wrapping, measurement and selection
test/widgets/markdown_code_frame*_test.dart code frames and character wrapping
benchmark/                 list, Markdown, selection and picker benchmarks
benchmark/list_view.dart    list frames, resize, streaming and cached switches
example/main.dart           the package's runnable example
example/playback.dart       recorded terminal, pause, steps and panning
example/display_text.dart   block-glyph sizes and per-run colours
example/button.dart         action buttons, focus and disabled state
example/link.dart           URI and action links
example/scrollbar.dart      list position and thumb
example/scroll_view.dart    live widgets and focus following
example/demo.dart           the framework's demo
example/code.dart           highlighted code, numbering and wrapping
example/markdown.dart       Markdown and streamed replies
example/markdown_run_controls.dart recorded copy/run actions
example/markdown_wrap.dart  table-cell and URL wrap boundaries
example/diff.dart           generated and unified diffs
example/diff_view.dart      selected diff rows and full counts
example/middle.dart         text retaining both ends around ...
example/layers.dart         anchored layers over a streaming list
example/overlay_visibility.dart layer visibility and transparent followers
example/picker.dart         numbered choices with a fuzzy filter
example/picker_preview.dart highlight preview before acceptance
example/fold.dart           folding output and aligned table columns
example/dialog.dart         a framed question over the window
example/form.dart           validated fields and field/option scrolling
example/text_area.dart      multiline editing, wrapping and scrolling
example/text_area_viewport.dart shown rows and gutter
example/text_area_spans.dart style-only full-text projection
example/error_boundary.dart drawing failure and fallback
example/key_help.dart       grouped help, pending chords and --rebound keymap
example/text_area_key_filter.dart live input key delegation
example/terminal_services.dart clipboard, editor, notifications and title
example/mouse.dart          captured pointer reports and wheel log
example/selection.dart      semantic selection, lazy sources and held scrolling

```

The app and repository, from the root:

```text
site/pubspec.yaml          chord_site, unpublished and version-independent
site/lib/router.dart       History API paths, parents and not-found routes
site/lib/site.dart         page shell, global keys and navigation
site/lib/pages/            home, chord, recordings, framework and install
site/lib/keys_panel.dart   modal shortcuts panel
site/lib/article.dart      chord_tui pages: index, article, margin and pager
site/lib/live_plate.dart   live frames with captioned entry and exit keys
site/lib/live/            prompt, permission, plan and start screen fixtures
site/lib/scroll_page.dart page scrolling over live widgets
site/lib/band.dart         the green slogan band
site/lib/sources.g.dart    generated example code the pages show
site/lib/key_row.dart      tappable keys for narrow windows
site/lib/web/browser_host.dart browser history and recording fetches
site/web/main.dart         Wasm entrypoint and page-lifetime WebTerminal
site/web/gallery.dart      nine imported framework examples
site/web/index.html        full-window wterm host and Wasm loader
site/tool/build.dart       static build, pinned assets and preview server
site/tool/sources.dart     shown example code copied into lib/sources.g.dart
site/tool/serving.dart     base paths, SPA fallback and content types
site/tool/terminal.dart    native site shell fixture
site/test/                routes, articles, live fixtures and recordings
site/test/tool/           build, source drift, pinned assets and serving tests
site/test/browser/        built-site Chrome smoke under both bases
site/build/               generated static website
packages/cursor-cloud-acp/  TypeScript Cursor Cloud ACP adapter
package.json               Bun workspace, for the adapter only
bun.lock                   pinned Bun dependencies, for the adapter only
bunfig.toml                Bun settings, for the adapter only
tsconfig.json              TypeScript settings, for the adapter only
eslint.config.ts           ESLint settings, for the adapter only
.prettierrc.json            format settings, for the adapter only
.prettierignore             format exclusions, for the adapter only
.npmrc                     npm settings, for the adapter only
scripts/                   Bun tooling and release, for the adapter only
tests/scripts/             tooling tests, for the adapter only
lint/                      ESLint rules and tests, for the adapter only
bin/chord.dart             app entrypoint
lib/                       chord app
pubspec.yaml               app manifest and shared version source
pubspec.lock               pinned app dependencies and framework version
lib/acp_agent.dart multi-session ACP server on stdio
lib/acp/      ACP client, dispatchers, traffic and lifecycle
lib/acp/agent_app.dart served methods
lib/acp/host_fold.dart hosted session event folding
lib/acp/params.dart ACP parameter checks
lib/acp/plans.dart cursor and grok plan request mapping
lib/acp/stdio.dart protocol output and drain
lib/acp/upstream_turns.dart client turn and queue state
lib/agent_name.dart child name checks
lib/channel.dart release channel names and version labels
lib/node_semver.dart npm version validation and ordering
lib/distribution.dart npm, Homebrew and GitHub distribution names
lib/upgrade.dart registry versions and package-manager upgrades
lib/js_trim.dart JavaScript-compatible whitespace trimming
lib/closest_string.dart nearest option by code-point edit distance
lib/kept.dart future outcomes awaited across error zones
lib/files.dart ignore-aware file discovery and mention links
lib/ignore.dart nested gitignore rules
lib/images.dart clipboard and file image attachments
lib/mcp.dart settings and .mcp.json servers, checks and precedence
lib/notices.dart dimcode warning, eligibility and dismissal record
lib/notify.dart notification channels, wait detection and session variable bytes
lib/status.dart terminal status across the window's agents
lib/settings.dart user/project settings, saves and precedence
lib/settings_tool.dart checked reads, masked values and changes
lib/teams.dart team files, checks, discovery and saving
lib/yaml_stringify.dart team frontmatter as npm yaml writes it
lib/editor.dart prompt editing through VISUAL, EDITOR or vi
lib/headless.dart one-shot reply, diagnostics and JSON result
lib/platform/ native process groups and launcher, with web stand-ins
lib/platform/*_ffi.dart native launcher, libc and architecture bindings
lib/platform/*_web.dart web stand-ins for those native bindings
lib/platform/signals.dart signal exits
lib/platform/heap.dart SIGUSR2 memory reports and JIT heap snapshots
lib/platform/resources.dart provider limits and reader ownership
lib/platform/resource*.dart executables, processes and fixtures
lib/shell.dart shell scripts, output and process-group stopping
lib/server/   chord's MCP server, tools and runtime offers
lib/session/  records, replay, queue, cycles, usage and cost
lib/session/oneshot.dart one prompt without a window
lib/session/agents_host.dart children, teams, forks and tasks
lib/session/window_agents.dart roster, attention and naming
lib/session/open_agents.dart child ownership and closing
lib/session/tasks.dart task state and message wrapping
lib/session/team_command.dart /team forms and replies
lib/session/team_selection.dart per-run choices and receipts
lib/session/budgets.dart provider limit types and checks
lib/session/resource_access.dart limits reader interface
lib/session/resource_normalization.dart provider facts checked
lib/session/codex_resources.dart Codex limits and JSON-RPC
lib/session/monitors.dart command runs, events, ends and resume
lib/session/window_monitors.dart monitor ownership and limits
lib/session/new_args.dart /new arguments and refusals
lib/session/busy.dart active turn, queue and task checks
lib/session/upstream.dart client capabilities and update mapping
lib/session/upstream_commands.dart hosted slash commands
lib/session/auth_status.dart reported account state and account wording
lib/session/sign_in.dart sign-in guidance and account-free records
lib/session/servers.dart MCP transport filtering
lib/session/place.dart per-directory startup settings
lib/session/setting_picked_up.dart saved settings applied live
lib/session/waits.dart agent wait and unseen-result state
lib/session/plan_asks.dart plan approval lifecycle and recording
lib/session/elicitations.dart forms, links and their answers
lib/session/questions.dart agent questions and answer mapping
lib/session/subagents.dart nested ACP session routing
lib/session/transcript/ entries, updates and transcript reducer
lib/session/transcript/compactions.dart compaction fold
lib/session/transcript/plans.dart plans updated and removed by id
lib/session/transcript/subagents.dart nested work, stops and ends
lib/session/transcript/chord.dart chord tool metadata
lib/ui/app/   state, keys, startup guidance, copy/shell and quit
lib/ui/app/context.dart live key context and binding ownership
lib/ui/app/terminal.dart terminal services and session variable ownership
lib/ui/app/window_fold.dart per-session event and intent folding
lib/ui/app/agents_room.dart request and agent list row budgets
lib/ui/app/scrolls.dart per-session transcript scrolling
lib/ui/app/rename.dart session title command
lib/ui/agents/ agent list rows, glyphs and shared clock
lib/ui/background/background.dart monitor/task/agent items
lib/ui/background/state.dart background view state and reducer
lib/ui/background/view.dart rows, details, frame and log scrolling
lib/ui/background/summary_line.dart background summary widget
lib/ui/background/background_view.dart background frame and work
lib/ui/dialogs/ permissions, plans, questions, forms and links
lib/ui/dialogs/form.dart schema fields, checks and answer words
lib/ui/dialogs/form_box.dart elicitation form box
lib/ui/dialogs/questions.dart question steps, keys and answers
lib/ui/dialogs/questions_box.dart agent question box
lib/ui/dialogs/link.dart web-link choices and host
lib/ui/dialogs/plan_scroll.dart overflowing plan Note paging
lib/ui/dialogs/asker.dart named child request header
lib/ui/dialogs/leave.dart request-to-agent-list key handoff
lib/ui/header/ mark, wordmark, directory and resumed facts
lib/ui/pickers/ agent, settings, resume, teams and MCP list
lib/ui/plan/  live checklist and finished plan records
lib/ui/prompt/ input, images, history/search, queue and completion
lib/ui/prompt/named_top.dart named child prompt border
lib/ui/shortcuts/ bound-key catalog and scrolling panel
lib/ui/shortcuts/bindings.dart bindings, actions and layout keys
lib/ui/splash/ drifting startup mark and slow-start hint
lib/ui/status/ reported facts and timed working line
lib/ui/theme/ named palettes, live preview and theme resolution
lib/ui/teams/ saved and running teams, tables and receipts
lib/ui/transcript/ entries, sources, code picking and scrolling
lib/ui/transcript/compaction.dart compaction and summary
lib/ui/transcript/agent_colours.dart agent name colours
lib/ui/transcript/spend_table.dart window-wide cost table
lib/ui/transcript/tools/chord.dart chord tool rows
lib/ui/transcript/tools/settings_row.dart settings read/save rows
lib/ui/transcript/tools/proposal*.dart team proposals and save box
lib/ui/transcript/tools/resource_lines.dart provider limits rows
lib/ui/transcript/tools/selection_lines.dart per-run choice rows
lib/ui/transcript/agents/ nested blocks, trees and messages
tool/         dev runner, screen fixtures and release tools
tool/targets.dart macOS and Linux, arm64 and x64 targets
tool/npm.dart platform packages and the Node shim
tool/formula.dart stable Homebrew formula from archive checksums
tool/ci.dart native build/version or Linux cross-compile check
tool/shards.dart each test file assigned to exactly one CI shard
tool/screenshots.dart PNGs, logos and three-size recordings from the Dart fake
tool/recordings.dart timed ANSI frames and labelled screenshot steps
tool/screenshots_team.md team fixture for captures
tool/screenshots_proposal.md proposed team fixture for captures
tool/release.dart maintainer release command
tool/release/ builds, notices, archives, signing and release state
tool/release/x64_sdk.dart checked x64 Dart SDK download and shared cache
tool/macos/chord.entitlements hardened-runtime Dart entitlement
tool/notice.dart dimcode notice, no agent or dismissal writes
tool/form.dart covered form and held-link fixtures
tool/agents.dart nested work, launches and messages
tool/children.dart open agents, their states and the list
tool/genai_prices.dart pinned pricing from --package <dir>, read with Node
tool/currency_symbols.dart pinned currency signs from Node's Intl
test/kept_test.dart future identity and cross-zone outcomes
test/leave_zones_compile_test.dart failed-close SIGHUP/ACP exit
test/acp/     in-memory, scripted-child and fake ACP tests
test/acp_*    server sessions, turns, settings and reopen tests
test/acp_monitors_fake_test.dart monitor pushes and stop requests
test/acp_settings_tool_fake_test.dart shared settings approval
test/settings_tool_test.dart reads, masking and planned changes
test/settings_team_selection_test.dart team preference checks
test/teams_test.dart team files, checks and saves
test/yaml_stringify_test.dart pinned YAML output fixtures
test/acp_team_fake_test.dart ACP teams through the fake agent
test/acp_resources_leave_test.dart reader cleanup on ACP exit
test/acp_server_leave_test.dart MCP server cleanup on ACP exit
test/cli_start_compile_test.dart native startup and closed-pty exit
test/agents_json_test.dart catalog JSON fields and ordering
test/cli_agents_json*_test.dart JSON output and settings directory
test/cli_cwd*_test.dart session directory and resume precedence
test/notices*_test.dart notice eligibility and dismissal records
test/headless_notice*_test.dart warning stderr and reply output
test/acp_notice*_test.dart warning relay and session isolation
test/cli_heap_test.dart window-only heap signal registration
test/cli_help_columns*_test.dart help description alignment
test/acp_set_title_targeted*_test.dart unloaded session title reads
test/cli_acp_test.dart ACP CLI parsing
test/cli_acp_missing_value_tester_test.dart ACP missing option values
test/cli_once*_test.dart repeated and combined CLI option refusals
test/cli_acp_compile_test.dart native ACP stdio and exits
test/registry_test.dart pinned registry and launch data
test/fixtures/ Dart fake cache, harness, runtime catalog and pinned data
test/fixtures/fake_agent/ scripted Dart ACP agent
test/server/  MCP admission, role tools and runtime offers
test/server/settings_change_test.dart approval and file writes
test/tool/children_test.dart scripted child fixture flags
test/channel_test.dart release channel checks
test/node_semver_test.dart pinned npm semver boundaries
test/cli_upgrade_test.dart upgrade CLI options and dispatch
test/upgrade*_test.dart registry and package-manager upgrades
test/tool/release_test.dart release CLI help and refusals
test/tool/release/ release stages, state and recording runners
test/tool/release/build_compile_test.dart native build checks
test/tool/release/x64_sdk_test.dart SDK cache, downloads and checks
test/tool/release/x64_sdk_tester_test.dart archive input boundaries
test/tool/release/x64_sdk_provision_tester_test.dart staging and cache races
test/tool/release/x64_sdk_fetch_tester_test.dart HTTP fetches on loopback
test/tool/npm_test.dart package layout, manifests and shim
test/tool/formula_test.dart stable formula and archive checksums
test/tool/ci_test.dart native/cross-compile runner and command boundaries
test/tool/shards_test.dart shard coverage and command-line checks
test/tool/screenshots*_test.dart shots, fake argv, ANSI frames and logo crop
test/tool/recordings*_test.dart frame thinning, labels and step boundaries
test/tool/workflow_test.dart CI jobs, SDK and read permissions
.github/workflows/ci.yml Ubuntu checks, sharded suites and Linux builds
test/platform/ launcher, process groups and signals, AOT included
test/platform/group_exec_contract_test.dart launcher contract between versions
test/platform/process_libc_tester_test.dart native process binding boundaries
test/platform/platform_wasm_tester_compile_test.dart web platform seams
test/platform/heap*_test.dart heap signal ownership and complete file writes
test/session/ session, conversation, transcript and fake scenarios
test/session/opening_meta_test.dart Claude opening metadata
test/session/sessions_targeted_tester_test.dart targeted reads and handles
test/session/replay_legacy_plan_tester_test.dart legacy plan replay
test/session/monitors*_test.dart runs, boundaries and resume
test/session/conversation_monitors_test.dart monitor event turns
test/session/conversation_monitors_starting_test.dart startup stop and cleanup
test/session/conversation_monitors_starting_tester_test.dart startup ownership
test/session/window_monitors_test.dart owner routing and limits
test/session/agents_host_monitors_test.dart host monitor tools
test/session/oneshot_notice_test.dart one-shot dimcode warning
test/session/session_fork_fake_test.dart ACP fork and past
test/session/agents_host_fork_test.dart fork admission and tools
test/session/agents_host_teams_test.dart runs and team ownership
test/session/agents_host_selected_test.dart choices and receipts
test/session/team_selection_test.dart selection policy and checks
test/session/conversation_ask_test.dart chord ask lifecycle
test/ui/app/  keys, commands, settings, copy and fake window
test/ui/app/starting_commands_window_test.dart startup commands
test/ui/app/chord_cursor_window_test.dart pending-chord cursor
test/ui/app/prompt_selection_window_test.dart select-all, undo and redo
test/ui/app/code_click_session_window_test.dart session code copy/run clicks
test/ui/app/code_click_session_window_tester_test.dart code click lifecycle
test/ui/app/textarea_held_window_test.dart editor key reach and line edges
test/ui/app/cmd_history_window_tester_test.dart command-arrow prompt history
test/ui/app/prompt_press_tester_test.dart prompt press boundaries
test/ui/app/help_command*_test.dart repeated help and panel ownership
test/ui/app/background*_test.dart view, logs and subagent stops
test/ui/app/notice_window*_test.dart notice keys and geometry
test/ui/app/sessions_notices_test.dart session notice ownership
test/ui/app/program_status_window_test.dart all-agent status
test/ui/app/monitors_window_test.dart owner updates and resume
test/ui/app/form_interrupt*_test.dart form stop and recovery
test/ui/app/fork_window_test.dart fork, clear, close and resume
test/ui/app/settings_tool_window_test.dart save box and live use
test/ui/app/team_command_window_test.dart /team and picker
test/ui/app/propose_window_test.dart team proposal approval
test/ui/app/teams_spend_window_test.dart team cost ownership
test/ui/teams/ tables, saved teams and recorded receipts
test/ui/background/ monitors, tasks, agents, summary and logs
test/ui/dialogs/ permissions, plans, questions, forms and links
test/ui/dialogs/plan_box_held_fake_test.dart plan Note keys and held focus
test/ui/dialogs/plan_note_tester_test.dart end-only Note editing and cursor
test/ui/dialogs/plan_scroll_test.dart Note paging reducer
test/ui/dialogs/plan_note_scroll*_test.dart Note paging and edit following
test/ui/dialogs/plan_note_rebound_tester_test.dart rebound Note page keys
test/ui/app/plan_note_keys_test.dart Note page-key ownership
test/ui/dialogs/questions_note_reflow_tester_test.dart Note growth and shrink
test/ui/header/ mark rows and colour boundaries
test/ui/pickers/ agent, settings and resume choices
test/ui/plan/ checklist selection, drawing and lifecycle
test/ui/prompt/ editing, history, queue and command matching
test/ui/prompt/prompt_arrows_test.dart modified-arrow history navigation
test/ui/prompt/prompt_modified_arrows_tester_test.dart history row boundaries
test/ui/shortcuts/ catalog, panel geometry and state
test/ui/splash/ startup frames, geometry, timing and lifecycle
test/ui/status/ reported facts, working timers and drawing
test/ui/transcript/ entries, tool output, sources and code picking
test/ui/transcript/transcript_switch_test.dart session switches
test/ui/transcript/monitors_left_test.dart resumed monitor note
test/ui/transcript/tools/settings*_test.dart rows and selection
test/ui/transcript/tools/diff_fake_test.dart fake diff wrapping
benchmark/    ACP/session folding, fake flood, resume picker and record scans
benchmark/acp_server.dart server load, framing and replay
benchmark/record_scan.dart generated record scans
docs/images/                screenshots, logos and <shot>.<size>.rec.json
docs/guide.md               flags, keys, settings and saved teams
docs/development.md         builds, release, benchmarks and fixtures
docs/FEATURES.md            the map
docs/decisions.md           append-only decisions log
docs/design/<key>.md        the design of a task that needed one
.chord/teams/               the teams that build this
```

The app lives under `lib/`, with snake_case file names;
`lib/ui/prompt/history.dart` has its test in
`test/ui/prompt/history_test.dart`.

## Tests

- A widget is tested through `package:chord_tui/testing.dart`: render at a
  size, press keys, check the screen. Widget tests need no terminal.
- Loaded runs count only while the host stays awake. On macOS, use
  `caffeinate -dimsu dart test` in the package being tested. A run interrupted
  by sleep, with cases lasting far past their timeouts, is void; rerun awake.
- Record handle-closure proofs use `/proc/self/fd` on Linux or `lsof` on
  macOS; other hosts and Macs without `lsof` skip with a reason.
- The port's signal-owner pty, exit, crash, entrypoint, agent lookup and
  session teardown fixtures use cached kernel snapshots built once in
  `setUpAll`, under the runner's fixed 12-minute setup limit. Cases keep
  their runtime budgets; compilation does not consume them.
- Terminal flush and hangup tests use POSIX ptys and `expect` to check
  bounded release, mode restoration, reuse and SIGHUP exit. Errors from
  `StdioTerminal`'s own tty input count as a hangup; supplied and non-tty
  inputs still report errors. If its own tty input ends and flushing fails,
  that failure is suppressed: with `handleSignals`, `runApp` re-raises SIGHUP;
  without it, it waits up to two seconds for the embedder's handler before
  its usual exit.
  Re-raised HUP, INT and TERM get 500 ms for delivery before fallback exit
  `128 + signal number`. Supplied or non-tty input keeps flush-error reporting.
  The framework's `compile` tag checks demo SIGHUP when its pty closes.
  Services editor pty cases skip on Linux: after the editor returns,
  dart:io can stall the window until the next key (CTUI-193).
  `runExpect` returns after the driver's exit and at most two seconds of
  output draining, even if an orphan holds a stream open. Failed launches
  remove their temporary directory. Teardown kills surviving drivers and
  recorded spawns with their process trees, even after the driver ends.
  Spawn PID reuse is checked by Linux start-tick equality or macOS kernel
  start microseconds no later than the spawn record; the remaining macOS
  limits are in `docs/decisions.md`.
- The port's tests never reach a real model or a real agent: pure modules
  directly, the window through the tester, ACP through in-memory processes
  and scripted children. The Dart fake under `test/fixtures/fake_agent/`
  runs through `test/fixtures/fake.dart` and `fake_harness.dart`, with a
  kernel snapshot cached in `.dart_tool` by its sources, imported app
  sources, dependencies and SDK. The fake and pinned fixtures run with Dart.
  Session tests cover transcript, queue, cancellation, autonomous cycles,
  permissions, records and replay through pure modules,
  scripted sessions and the fake. The runtime catalog admits only fake or
  scripted starts; child tests set `CHORD_FAKE_CHILD_RUNTIME=fake`. The dev
  runner with `--fake` uses the fake for every runtime: main, children, team
  leads and members, `/new` and forks, with fixture resource limits. MCP tests
  use loopback HTTP, including an AOT server. Record tests and captures use
  isolated `XDG_STATE_HOME`, never the person's state. The fake's canned HISTORY
  is not persistent agent history. The port's `compile` tag checks the
  native launcher, start page, resume routes and fake session in a pty,
  including SIGHUP exit and agent cleanup when it closes, plus
  `test/cli_acp_compile_test.dart` on stdio. Pty and by-hand note cases
  need the system `expect`. Run the tag explicitly.
- Upgrade tests use scripted managers and loopback registry servers. Release
  tests use recording runners; npm layout tests run the shim with Node when
  available. The build compile test builds both Linux targets; its signed
  Darwin case needs an arm64 Mac for `codesign` and execution, and skips
  elsewhere even with `--run-skipped`. Release commands,
  including `--dry-run`, authenticate npm and may submit to Apple: only the
  maintainer runs them; teams may inspect `--help`. CI runs on Ubuntu:
  analyze both packages, format, actionlint, three shards per suite, both
  compile tags with `expect`, and the npm shim with Node 22.13. It builds
  linux-x64 natively and cross-compiles linux-arm64; `check` requires every
  job to pass. Darwin builds belong to the maintainer's local release.
- The site has VM tests for responsive pages, live chord fixtures, articles,
  generated source drift and all three recording sizes.
  Its `compile` tag builds the static folder; its `browser` tag drives
  system Chrome through the built site at `/` and `/chord/`, including
  history, mouse, kitty keys, resize, touch and fixed 7 px cells. The
  framework's `browser` tag checks WebTerminal; its Wasm compile tests use Node.
  These tags are skipped by default. CI's required `site` job runs the
  site's static, VM, build and browser checks and the framework browser
  checks. The site uses 12.5 px type on 16 px rows with -0.5 px letter
  spacing at every width: 205x56 cells at 1440x900, 55x52 at 390x844 and
  51x40 at 360x640. Box-line seams at fractional DPR 1.25 and 1.5 are
  accepted; the wterm report is drafted, not posted. Build output has no
  size budget; deployment is separate work.
- A unit without a test that would fail without it is not finished.
- Check the screen at 120x40 and at 80x24. For terminal cursor changes,
  check a physical window focused and unfocused in a supporting terminal;
  tmux captures do not prove its hollow unfocused appearance.

## The board

Tasks live on the board, project `CTUI`: `board status`, `board next`,
`board show CTUI-n`. Every write takes `--actor` with your own name.
`board skill` prints the whole guide.

## Git

- A task's work happens on its own branch, made from `main`
  (`git switch -c <key> main`), never on `main` itself.
- Commits are conventional (`feat:`, `fix:`, `docs:`, `test:`, `chore:`),
  local, and carry no trailers of any kind. Nobody pushes.
- Every commit is signed. Commit with plain `git commit`, never with an
  override of signing; if signing fails, stop and say so.

## Comments

A comment says why, not what. Public names in `packages/chord_tui/lib/`
carry a `///` line saying what the thing is for; `dart analyze` enforces
`public_member_api_docs` there.

# Developing chord

The developer reference for the Dart app and its fixtures. See the
[guide](guide.md) for flags, settings and keys, and [AGENTS.md](../AGENTS.md)
for the binding development rules.

## Run from source

With Dart 3.12 or later, run from the repository root:

```sh
dart pub get
(cd packages/chord_tui && dart pub get)
dart run tool/dev.dart chord --fake
```

## Build a binary

From the repository root, after `dart pub get`:

```sh
mkdir -p build
dart compile exe bin/chord.dart -o build/chord
./build/chord agents
./build/chord --help
./build/chord --version
./build/chord codex
```

The binary needs no Dart runtime. Catalog starts require the runner or
CLI on PATH; settings commands and `--agent-command` bypass that check.
The `compile`-tagged smoke tests check named and picked agent starts,
version, agent listing, a fake session and the ACP server on stdio.

## Maintainer release

From the repository root, inspect the release command without starting it:

```sh
dart run tool/release.dart --help
```

The maintainer runs `dart run tool/release.dart chord` locally
on an arm64 Mac. It needs an x64 Dart SDK of the same version under Rosetta
(`CHORD_DART_X64` names its `bin/dart`), the local Developer ID identity and
notarytool profile, npm and GitHub authentication, and the Dart fake agent.
Preflight requires a clean tree and, for publishing, `origin` targeting
`IKatsuba/chord`, with the version's branch level with it. Stable releases
publish from `main`; channels from their named branches, with npm's channel
tag and a GitHub pre-release draft. `--bump` updates `pubspec.yaml`,
`lib/version.dart`, the framework's `packages/chord_tui/pubspec.yaml` and
its entry in the root `pubspec.lock` together.

Stages install, check, compile four binaries, sign, self-test, notarise,
pack and publish. Output in `build/release/` includes npm packages,
`archives/chord-<os>-<cpu>.tar.gz` and `archives/SHA256SUMS`. A stable
release also writes `build/release/chord.rb` for the maintainer to review
and commit to `IKatsuba/homebrew-tap` after publishing the GitHub draft.
macOS packages use the signed and notarised bytes; archives omit extended
attributes. Interrupted releases resume from `.release/chord/state.json`;
rerun without `--bump`.

Even `--dry-run` authenticates npm and can submit to Apple; it is a
maintainer operation. Tests use recording runners. CI builds linux-x64
natively and cross-compiles linux-arm64; Darwin builds, publication and
Apple submission remain the maintainer's local checks.

For a window that has grown large, run `kill -USR2 <pid>` after leaving the
start page. It keeps running and writes `heaps/chord-<pid>-<time>.json`
under chord's XDG state directory, with pid, time, current and peak RSS,
and build id. Under `dart run` or `tool/dev.dart`, it also writes a
Dart-format `.heapsnapshot` for Dart DevTools. The shipped binary writes
`heap-error.txt` instead of a snapshot. Nothing prints in the window.

## ACP and sessions

`lib/acp/` starts agents in their own process groups, initialises ACP,
opens sessions, sends prompts and cancellation, and handles permission
requests through a callback. Traffic includes messages and stderr; closing
stops the agent and its group. On SIGTERM, SIGINT, SIGHUP or a crash, chord
closes its agents and kills their remaining groups before exiting. Closing
the terminal or tmux session ends chord and its agent. Cleanup failures
still preserve the first signal. chord uses `runApp(handleSignals: false)`
to keep that single signal owner.
The window declares notices, compaction, plans by id, elicitation (forms
and links), nested ACP subagents and terminal output deltas. `-p` declares
the same; `chord acp` relays notices when its client takes them.
Claude sessions disable unused prompt suggestions on opening, resume and fork.
Filesystem and terminal requests are unsupported.

`lib/session/` opens, clears and resumes sessions, saves admitted prompts
and enriched history, queues prompts, cancels turns, changes mode/model/config
and holds permissions, forms and links. Autonomous cycles run as separate turns:
the working line runs, Esc interrupts, and permissions stay held until
attended with Ctrl+X, then A. Its reducer folds
replies, thoughts, tool calls, command output, plans and errors into a
transcript; `lib/ui/app/` keeps each session's queue, draft, scroll and
agent status, and routes input to the picked agent. `lib/ui/transcript/`
draws streaming Markdown replies, collapsed
thoughts, tool status and summaries, live command output, full diffs,
compactions, nested subagents, turn outcomes and finished plans. Failed prompts
show a red `⏺` row and leave the prompt usable. A sign-in refusal shows
`<agent> needs a sign-in: <message>` and the offered sign-in ways, preceded
by the reported account when available. Sign-in messages and ways are
saved and replayed; account facts are never saved. Ctrl+O expands details.
PageUp/PageDown, Home/End and Shift+Up/Down scroll; a rule shows lines below and new output while
scrolled back. End resumes following. The wheel scrolls one line per
report wherever the pointer is; overflowing shortcuts, proposal and
completion bodies consume it, while fitting bodies and numbered setting
pickers bubble to the transcript. Wheel input is ignored while closing.

Records use a version-1 JSONL store: UUID-named files under
`chord/records` in the XDG state directory. Set `XDG_STATE_HOME` or `HOME`;
without the former, the package derives the state directory from the latter.
Merely opening or reading a session appends nothing. A submitted prompt or
an autonomous cycle releases held opening/history lines before its work
is saved. Existing bytes, including opaque history, stay intact. Supported
history, including nested ACP subagents, is drawn; meaningful omissions
produce one plain line:
`Some saved history is not shown in this version.` Child records restore
task history and messages; a left-open note names long-lived children
and team runs with their agent counts without reopening them. Monitors are
not revived: a note names those left running, and the agent is told once
it connects.
Close the session in the other pane before resuming here: processes can
interleave appends. There is no interprocess lock, queue bound, flush
deadline or power-loss durability guarantee. A record write failure warns
once and leaves the session running; later events retry.
Late usage from a cleared or replaced session stays in its old record.

From the repository root:

```sh
dart test
dart test -t compile --run-skipped
dart test test/cli_upgrade_test.dart test/upgrade_test.dart
dart test test/upgrade_brew_test.dart
dart test test/channel_test.dart test/node_semver_test.dart
dart test test/tool
dart run benchmark/acp_updates.dart
dart run benchmark/acp_server.dart
# AOT benchmark, including the session layer:
mkdir -p build
dart compile exe benchmark/acp_updates.dart -o build/acp_updates
./build/acp_updates
```

Tests use in-memory processes, scripted children and the Dart fake agent.
Session tests cover queue, cancellation, permissions, transcript folding,
settings and clear/resume isolation. Record tests cover appends, personal
steering and autonomous-cycle replay, and cancelled IO cleanup under
isolated state. Widget tests cover screens, input, commands, stale results,
selection/copy and code picking; copy adapters record requests. Compile
tests cover the launcher, startup, resume and a fake session in an 80x24
pty, including SIGHUP exit and agent cleanup when the pty closes. ACP binary
tests cover usage, EOF, broken output, signals, the by-hand note and
JSON-only stdout. Compiled failure cases cover SIGHUP and ACP cleanup
after an agent close fails. Pty and by-hand note cases need the system
`expect`. Resume source/fixture captures cover 120x40 and 80x24; native
120x40 was not run. The [resume validation
record](design/evidence/CTUI-26/validation/README.md) retains
JIT/AOT cleanup proof and scale measurements. First-layout/resize hitches
remain. The [picker
measurements](design/evidence/CTUI-54/performance.md) record
2,000-choice AOT navigation group medians of 0.242–0.653 ms versus
25.177–25.809 ms historically. Stable navigation does no all-choice shaping;
cold widths still shape every choice, with wrapped 10,000-choice resizes of
62–65 ms. These exclude disk, agent and physical display latency and do not
measure retained heap. Physical isolate count/exit latency remain
unmeasured. Switching back to a session reuses unchanged entry heights:
[the AOT benchmark](decisions.md#ctui-80-item-extents-live-on-the-scrollcontroller)
measures 0.36–0.38 ms median at 10,000 entries. First visits and width
changes still measure every entry. The ACP benchmark reports heartbeat
lateness, frames,
cancellation and memory, including folding at 10 000 entries, with an AOT
heartbeat budget of 16 ms at p99. Fake flood runs skip with a reason if
unavailable. Physical focused/unfocused cursor appearance still needs an
owner check in a supporting terminal; [tmux
captures](design/evidence/CTUI-50/visual.md) prove placement and
style only. The [search/verbose screen
record](design/evidence/CTUI-27/u27c2-look.md) retains
tiny-editor, exact-width and inactive-held-request layout limits. Long
paths wrap after `/` and other word-break punctuation. Search paste
filtering and reentrant steering recovery are recorded in
[decisions](decisions.md).

Standalone screens need no agent; run from the repository root:

```sh
dart run tool/permission.dart
dart run tool/notice.dart # F2 reopens, F3 toggles permission
dart run tool/form.dart --permission-over # F2 covers, F3 answers
dart run tool/form.dart --long-link # held link, Ctrl+X A attends
dart run tool/agents.dart # nested work, launches and messages
dart run tool/children.dart # open children and the agents list
dart run tool/children.dart --asking # docs waits on permission
dart run tool/start.dart
dart run tool/start.dart --resume
dart run tool/splash.dart # slow startup, no agent; Ctrl+Q quits
dart run tool/resume.dart --many # local/all choices, no IO
dart run tool/failed_start.dart # client commands after failure
dart run tool/steering.dart # in-memory ACP; F1 lists controls
dart run tool/steering_replay.dart # recorded personal steering
dart run tool/raw_output.dart
dart run tool/shell.dart # recorded output, no shell
dart run tool/bash.dart --code # recorded shell and copy actions
dart run tool/mentions.dart # injected file names, empty recipients
dart run tool/mentions.dart --agents
dart run tool/mentions.dart --many --slow
dart run tool/settings.dart # --config or --values
dart run tool/wheel.dart
dart run tool/wheel.dart --help --tall-draft
dart run tool/wheel.dart --permission
dart run tool/wheel.dart --fitting
dart run tool/selection.dart --pick # recording copy, no clipboard
dart run tool/selection.dart --manual # explicit selection copy
```

The children fixture accepts `--asking`, `--unseen`, `--exited`, `--failed`,
`--tall`, `--many`, `--held` and `--tasks` for requests, unseen news, exits,
failed starts, wrapped names, up to eight children, held messages and tasks.
Flags combine; named children take places before `--many` fills the rest.
`--codex` labels children with the Codex runtime; `--light` and `--plain`
change its theme. Ctrl+Q quits. It starts no agent.

The notice fixture accepts `--light` or `--plain`; Ctrl+Q quits. It starts
no agent and saves no dismissal.

The mentions fixture accepts `--light` or `--plain`; `--agents` populates
recipients, `--many` supplies 100 files and `--slow` delays matching. It starts
no agent or filesystem walk.

## Screenshots

From the repository root, with tmux and Chrome installed:

```sh
dart run tool/screenshots.dart            # all 12 images in docs/images/
dart run tool/screenshots.dart edit fork  # only these shots
dart run tool/screenshots.dart logo       # both transparent logos
```

Set `CHROME` to the Chrome executable outside its usual macOS location.
The tool uses the installed browser and downloads none. It runs chord with
the Dart fake in isolated settings and state, captures a 120×37 terminal,
and writes framed PNGs to `docs/images/`. Logos use the title page's 57×8
art without a frame. Team and proposal fixtures live beside the tool in
`tool/screenshots_team.md` and `tool/screenshots_proposal.md`.

## Pinned data

The data generators use `node` on PATH. Install
`@pydantic/genai-prices@0.2.3` in a scratch directory, then pass its package
folder to `dart run tool/genai_prices.dart --package <dir>` to regenerate
`lib/session/price_data.dart`. The package folder is required; a version
other than 0.2.3 is refused.

`dart run tool/currency_symbols.dart` regenerates the currency signs and
their recorded test fixture from Node's `Intl`. It requires ICU 78.1
(CLDR 48); a different ICU version is refused.

## Fake agent

The tests and dev runner use the Dart agent under `test/fixtures/fake_agent/`,
with a kernel snapshot cached under `.dart_tool` by its sources, imported
app sources, dependencies and SDK.

From the repository root:

```sh
dart run tool/dev.dart chord --fake
dart run tool/record_history.dart --omitted # isolated saved past
```

The runner starts `chord fake --agent-command` with the fake's command and
keeps separate state across runs through `XDG_STATE_HOME`. `--fake` uses
fixture resource limits and the fake for every runtime: main, children,
tasks, team leads and members, `/new` and forks. Teams must use models the
fake offers (`fake-large` or `fake-small`); stage one for running-team captures.
`--qa <name>` passes a fresh capture directory as `-C`, with isolated state,
configuration and fixture limits. Put runner options before chord's arguments.
`CHORD_FAKE_SCENARIO` selects a scenario; the prompt sends to it. The runner
exits with a reason if the fake cannot run. Its canned HISTORY checks replay
plumbing, not a real agent's persistent history.

See [FEATURES](FEATURES.md) for the roadmap.

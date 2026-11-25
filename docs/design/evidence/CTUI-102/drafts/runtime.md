# CTUI-102 runtime draft: builds, release, upgrade at run time, tests

Runtime architect, for design task CTUI-129. Answers R1-R5 of the brief,
then the module layout, failure scenarios, test plan, units and owner
questions. Everything measured below was run in this worktree on an arm64
Mac with Dart 3.13.5; nothing was published, pushed, run remotely, or
fetched from a registry.

## What was measured

| Trial | Result |
| --- | --- |
| `dart compile exe --help` (3.13.5) | `--target-os` {android, fuchsia, ios, linux, macos, windows}, `--target-arch` {arm, arm64, ia32, riscv32, riscv64, x64}. |
| `--target-os=linux --target-arch=x64` from macOS arm64 | Builds in 15 s: `ELF 64-bit LSB pie executable, x86-64`, dynamically linked against glibc, highest symbol `GLIBC_2.18`. |
| `--target-os=linux --target-arch=arm64` | Builds in 14 s: `ELF 64-bit LSB pie executable, ARM aarch64`, `GLIBC_2.18`. |
| `--target-os=macos --target-arch=arm64` (the host) | Builds in 12 s: `Mach-O 64-bit executable arm64`, ad-hoc linker-signed, `minos 14.0`, links only libSystem, Security, CoreFoundation, Foundation, CoreServices, libobjc. |
| `--target-os=macos --target-arch=x64` | Refused, exit 128: `Unsupported target platform macos_x64. Supported target platforms: linux_arm, linux_arm64, linux_riscv64, linux_x64`. |
| Re-sign the macOS binary `--options runtime`, no entitlements | `--version` and `agents` are SIGKILLed (exit 137). |
| Same with `com.apple.security.cs.allow-jit` (the original's one entitlement) | SIGKILLed (137). |
| Same with `com.apple.security.cs.allow-unsigned-executable-memory` | `--version`, `--help` and `agents` run, exit 0. |
| `codesign --verify --strict` on the unsigned build | Valid; the snapshot sits inside the Mach-O, so `codesign --force` replaces the ad-hoc signature cleanly. |
| Native code in the build | None but libc through `DynamicLibrary.process()` (`lib/src/terminal/terminal.dart`, `example/chord/lib/platform/process.dart`, `group_exec.dart`); no build hooks, no bundled dylibs. Platform branches (`__error` vs `__errno_location`) are taken at run time, so a cross-compiled binary picks the right one. |
| `actionlint 1.7.12` (with shellcheck) on a candidate release workflow (shape below) | Clean, exit 0. |
| `act 0.2.82 -n` on the same workflow | Lists both jobs, then skips every matrix row (macOS labels unsupported, no Docker daemon); act prints that this version has two CVEs. Not a usable check. |

The scratch outputs are in the gitignored `build/`.

## R1. Four targets: who builds what

From an arm64 Mac, `dart compile exe` builds three of the four targets:
`darwin-arm64` natively, `linux-x64` and `linux-arm64` by cross-compiling
(Dart's cross-compilation targets Linux only). `darwin-x64` cannot be
built from an arm64 Dart SDK. Three ways to get it:

- **A GitHub `macos-15-intel` runner**, the x64 macOS label GitHub keeps
  after retiring `macos-13`. As far as I know it is announced as the last
  Intel image, kept into 2027: worth checking against GitHub's notice
  before relying on it.
- **The x64 Dart SDK under Rosetta on the owner's Mac**:
  `arch -x86_64 <x64-sdk>/bin/dart compile exe …` builds natively for x64
  by its own reckoning. Not tried: it needs the SDK downloaded, which this
  run did not do. It should be the first step of CTUI-132, and the release
  would pin that SDK's version beside the arm64 one. The original already
  needs Rosetta on that Mac for its x64 self-test.
- **Dropping darwin-x64**: three packages instead of four. A departure
  from the original's four targets, so the owner decides.

Linux binaries need glibc ≥ 2.18 (2013), so no Alpine/musl, as with the
original's Bun binaries (`bun-linux-*`, not `-musl`). The macOS binary
says `minos 14.0`, so it refuses to start on macOS 13 and older. That
comes from Dart's prebuilt runtime, not from us. The guide's "Install"
should say so, and it differs from what the original's Bun binary allows.

Runners, if CI builds: `macos-14` (arm64), `macos-15-intel` (x64),
`ubuntu-24.04` (x64), `ubuntu-24.04-arm` (arm64). Each builds natively and
can run the binary it built. Linux binaries can be built on any one runner
or on the Mac, but only an arm64 Linux runner can run the arm64 one.
`ubuntu-24.04-arm` is free for public repositories; for a private one,
check the plan.

Where the release runs is an owner question (Q1). Options:

1. **Local, as the original** (recommended). `dart run
   example/chord/tool/release.dart` on the owner's arm64 Mac runs the
   original's stages in the original's order: preflight, npm auth, bump,
   compile all four (three by the host SDK, darwin-x64 by the Rosetta SDK
   or, failing that, fetched from a CI build of the same commit with `gh
   run download`), sign, self-test, notarise, pack with SHA256SUMS,
   publish with `--tag <channel>`, push the tag, draft a GitHub release.
   The draft carries the four binary archives and SHA256SUMS, where the
   original's carries source archives (see Differences). The original's
   keychain identity and notarytool keychain profile, so no secret leaves
   the Mac. CI keeps a check-only workflow, as the original's `ci.yml`
   does, which also compiles natively on all four runners and runs
   `--version`. That catches an SDK regression on a target the Mac only
   cross-compiles.
2. **CI builds, local signs and publishes.** A `workflow_dispatch` on the
   version commit's sha builds four unsigned binaries as artifacts; the
   local release downloads them, checks their kind and sums, then signs,
   notarises, packs, publishes, tags and drafts as in 1. It does without
   the Rosetta SDK, but makes the release depend on a remote run and adds
   a stage (`fetch`) the original lacks.
3. **All in CI.** On a pushed tag: build, sign with a Developer ID
   certificate imported into a temporary keychain, notarise with an App
   Store Connect API key, pack, publish to npm (trusted publishing over
   OIDC, or a token), draft the release. This departs furthest from the
   original: the original tags only after npm answers and has the owner
   approve each publish in the browser, and here the tag comes first and
   nothing is approved by hand. It needs the secrets of Q3.

## R2. The GitHub Releases workflow

The shape I checked with actionlint, for options 2/3, or as the CI
artifact source in option 1:

- **Trigger**: `push: tags: ['v*']` (option 3), or `workflow_dispatch`
  with a `ref` input (options 1/2: the local release asks for the run and
  waits on it). The first step checks the tag or ref against
  `example/chord/pubspec.yaml`'s version with `channelOf`, so a tag the
  release didn't make fails at once.
- **Matrix**: `include` rows `{runner, os, cpu}` for the four targets.
  `fail-fast: true`, since a release missing a platform is no release.
  `dart-lang/setup-dart@v1` with the SDK pinned to the exact version the
  local release uses; a test holds the two together.
- **Steps per row**: `dart pub get` in `example/chord`, `dart compile exe
  example/chord/bin/chord.dart -o dist/chord-<os>-<cpu>`, run
  `--version` and compare it with the tag, upload artifact
  `chord-<os>-<cpu>` (`if-no-files-found: error`).
- **Release job** (`needs: build`, `permissions: contents: write`, the
  rest `contents: read`): download with `merge-multiple`, `tar -czf
  chord-<os>-<cpu>.tar.gz`, `sha256sum` into `SHA256SUMS` in sha256sum's
  own format (as the original's `sums.ts` writes it), then `gh release
  create "$TAG" --draft --verify-tag [--prerelease] --title … --notes ''
  *.tar.gz SHA256SUMS`. `--prerelease` exactly when the tag has a channel,
  as the original's `draftRelease`. Never more than a draft: publishing
  it stays the owner's, as in the original.
- **Asset names**: `chord-<os>-<cpu>.tar.gz` with `os` ∈ {darwin, linux}
  and `cpu` ∈ {arm64, x64}, the original's npm spelling (`targets.ts`), so
  the shim, the npm packages, the formula and the archives all share one
  name per target. One `targets.dart` table feeds the release tool, the
  npm layout, the formula and the workflow test.

Checking it without running it remotely:

- `actionlint` (installed, clean on the candidate) as a static check
  beside `dart analyze`, with shellcheck for the `run:` scripts.
- A Dart test that parses the workflow with `package:yaml` (already a
  dependency) and checks that the matrix equals `TARGETS`, that the
  artifact names follow `chord-<os>-<cpu>`, that the SDK equals the
  pinned one, that `--draft` is present and nothing is published or
  pushed, and that `--prerelease` hangs on the channel test.
- The steps themselves live in Dart under `example/chord/tool/release/`
  (archive, sums, check tag), so the workflow only calls them, and the
  same code runs in the local dry run and the tests.
- `act` is not a check here: no macOS runners, it needs a Docker daemon,
  and the installed version reports CVEs.

## R3. macOS signing and notarisation

What is forced: a Dart AOT binary under the hardened runtime needs
`com.apple.security.cs.allow-unsigned-executable-memory`. The original's
`allow-jit` alone gets it SIGKILLed (measured above, ad-hoc signed). So
`example/chord/tool/macos/chord.entitlements` carries that key instead,
and `sign.ts`'s read-back comparison is kept. `natives` (signing
OpenTUI's and the clipboard's dylibs) has no counterpart: the Dart binary
embeds no library. Notarisation is still unproven for a Dart binary until
the owner's first real submission; the release's dry run includes it as
the original's does ("so chord's still submits to Apple"), and only the
owner runs it.

The secrets for each option (Q3):

| Where | Signing | Notarising |
| --- | --- | --- |
| Local (options 1, 2) | The team's Developer ID Application identity in the login keychain, found by team id as `lib.ts` `identity()` does. | A `notarytool` keychain profile, as `notarise.ts`'s `PROFILE`. |
| CI (option 3) | `MACOS_CERTIFICATE_P12` (base64), `MACOS_CERTIFICATE_PASSWORD`, a throwaway keychain password; imported with `security import` into a temporary keychain deleted at the end. | `APPLE_API_KEY_P8` (base64), `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` for `notarytool submit --key … --key-id … --issuer …`. |
| CI npm (option 3) | npm trusted publishing (OIDC, no secret, `id-token: write`), or `NPM_TOKEN` (an automation token that bypasses 2FA). | |

A bare Mach-O cannot be stapled, as the original's `notarise.ts` says;
Gatekeeper looks up the ticket online for a quarantined copy. npm and
brew installs aren't quarantined; a browser download of the release
archive is.

## R4. `chord upgrade` at run time

The command runs outside the window (a subcommand like `agents`), so no
terminal mode, no frame, no isolate. It does one registry read, at most,
and spawns one process.

**Registry read.** `GET https://registry.npmjs.org/<package>` (the URL
the original fixes, not npm's configured registry), one request, no
retry, no fallback. That's the original's cliffy `NpmProvider.getVersions`
on stable and `channelVersions` on a channel. Use `package:http`'s
`Client` (already in the lock as transitive, maintained by dart-lang),
made a direct dependency. The provider takes the base `Uri` and the
`Client` as constructor parameters; production passes the constant and
`IOClient`. No environment variable overrides it, since the original has
none. Words, kept from the original:

- non-2xx on stable: `chord could not read the versions of <pkg> from the
  npm registry: couldn't fetch the latest version - try again after
  sometime` (cliffy's sentence);
- non-2xx on a channel: `…: the registry answered <status>`;
- channel without a tag: `…: it has no tag <channel>, the channel this
  chord is on`;
- a transport failure: `…: <message>`, where the message is the
  exception's own `message` (`ClientException.message` /
  `SocketException.message`, with `osError.message` appended when
  present), not its `toString()`. Node's `fetch failed` and Dart's text
  differ; only the part after the colon does, and tests assert our prefix
  and the text the fake causes;
- an answer that isn't JSON or lacks `dist-tags`/`versions`: `…: the
  registry's answer is not a package document`. The original lets a
  `SyntaxError`/`TypeError` through here. Dart's `FormatException`/cast
  errors would say less, so this one line is written out (listed under
  Differences).

`versions` is `Object.keys(versions).reverse()`: Dart's
`jsonDecode` gives a `LinkedHashMap`, so insertion order is kept and
`.keys.toList().reversed` matches.

**Timeouts.** The original has none: `fetch` waits for as long as the
connection is open, and a person ends a hung read with Ctrl+C. Dart's
`HttpClient` has no connection or response timeout by default either, so
following the original costs nothing (recommended). Bounding it (connect
30 s, whole answer 60 s, with `…: no answer in 60 seconds`) is a
departure, so it's Q5.

**Spawning the manager.** `Process.start(argv[0], argv.skip(1),
environment: env, includeParentEnvironment: false, mode:
ProcessStartMode.inheritStdio)`. That's the original's `stdio: 'inherit'`
and `{env: {...env}}`: progress shows, and an OTP or corepack prompt can
be answered. No timeout, as in the original. Outcomes:

- exit 0 → `A chord already running keeps <from> until it is started
  again.`
- exit n ≠ 0 → `<argv joined> exited with status <n>.`
- killed: Dart reports `exitCode` as `-signo` on POSIX; the name comes
  from `ProcessSignal`'s `signalNumber` table (`SIGTERM`) → `<argv> was
  killed by SIGTERM.`
- not found: `ProcessException` with `errorCode == 2` (ENOENT) → `<manager>
  is not on PATH. Install <manager>, or upgrade chord with the manager
  that installed it.` A test pins that the lookup uses `env`'s `PATH`, as
  Node's spawn does, and not the parent's.
- found but not executable (EACCES 13): passed through as the
  exception's message, as the original passes any non-ENOENT error.

**Signals.** The upgrade installs no handler: Ctrl+C sends SIGINT to the
foreground process group, so the manager and chord both get it, and
chord dies by it with Dart's default action, as Node's does in the
original. The manager then ends or finishes by its own handling. The
window's `dieBySignal` is not involved: no agent and no terminal mode
need putting back.

**Offline guarantees.** `chord upgrade --help`, `chord --help` and `chord
--version` never build a client (the original needs
`hasRequiredPermissions() → false` to stop cliffy's version check; the
port has no such check to stop). `-l` and a bare `upgrade` read once.
`--version <v>` reads nothing on any channel (the original's "a version
named is taken as it is").

**Homebrew and release-binary sources** (the shape depends on I2-I4):

- Homebrew: chord reads nothing; it runs `brew upgrade <formula>` under
  the same runner and words, and refuses `--version <v>` (brew installs
  only what the formula holds). `-l` reads nothing from brew; whether it
  lists the npm versions or refuses is interface's call.
- Release binary, if the owner picks self-replace (I3): GitHub
  `GET /repos/<owner>/<repo>/releases` unauthenticated (60 requests/hour:
  a 403 with `x-ratelimit-remaining: 0` gets its own sentence), pick the
  newest non-draft release whose tag's channel equals the running one,
  download `SHA256SUMS` and the target's archive into a temporary file
  in the binary's own directory, verify the sum (`package:crypto`,
  dart-lang, already transitive), extract with system `tar`, `chmod
  0755`, and `rename` over the running binary. That's atomic on one
  filesystem; the running process keeps the old inode, which fits the
  "keeps <from> until restarted" line. An unwritable directory refuses
  before downloading and names it. A download that stalls has no bound,
  like the registry read (Q5 covers both). What it costs: a GitHub
  client, an archive step, a writable-directory check, a partial-file
  cleanup on signal, roughly CTUI-131's size again. Refusing with the
  `curl`/`tar` lines to run by hand costs nothing.

## R5. The npm shim for a Dart binary

The original's shim works unchanged for a Dart binary, with the names
swapped (`@<scope>/chord-<os>-<cpu>`) and one wording check:

- The shim spawns `bin/chord` with inherited stdio and forwards SIGINT,
  SIGTERM, SIGHUP. When the terminal closes, the kernel sends SIGHUP to
  the whole foreground group and the shim forwards one more. Chord's
  `dieBySignal` holds a second signal while it leaves, so the double
  delivery is harmless, as with the original's Bun binary.
- Chord dies by re-raising (`raiseSignal`, with fallback exit `128 + n`
  after 500 ms). The shim sees either the signal (and re-raises it) or
  the status (and exits with it), so the shell sees the same outcome
  either way.
- `Platform.resolvedExecutable` inside chord is the platform package's
  `bin/chord`, not `chord.js`. The launcher (`--chord-group-exec`,
  `process.dart:83`) re-runs that binary, which is right, and the upgrade
  reads that same path for install detection (resolved with
  `resolveSymbolicLinksSync`, as the original's `realpathSync`).
- No dynamic libraries to ship, so `NATIVE_NOTICES` (FFmpeg/zlib) goes.
  Their place in each platform package is taken by the Dart SDK's BSD
  licence and the licences of the pub packages compiled in, which a
  binary distribution must carry. CTUI-133 collects them from
  `.dart_tool/package_config.json` at pack time into one `NOTICES` file
  (Q6).
- `os`/`cpu` and exact-version `optionalDependencies` stay as in
  `npm.ts`. The binary must keep mode 0755 through `npm pack`, which the
  original's `pack` checks by installing the tarballs. Kept.

## Module layout

None of it is in `lib/`: nothing here is something a terminal app needs
in general (agrees with F3's expected answer). All in the port, named
after the original's files:

| Original | Port | Test |
| --- | --- | --- |
| `src/upgrade.ts` | `example/chord/lib/upgrade.dart`: `detectSource` (pure), `installArgv` (pure), `UpgradeProvider` (registry `Uri` + `http.Client` + `runManager` injected), `runManager`, `upgradeCommand` | `test/upgrade_test.ts` → `example/chord/test/upgrade_test.dart`; `test/upgrade_run_test.dart` (real `runManager` on scripted managers) |
| `src/channel.ts` | `example/chord/lib/channel.dart` (framework's draft) | `example/chord/test/channel_test.dart` |
| `scripts/targets.ts` | `example/chord/tool/targets.dart`: `{os, cpu, dartOs, dartArch, runner}` | `example/chord/test/tool/targets_test.dart` |
| `scripts/dev/npm.ts` | `example/chord/tool/npm.dart`: layout and the shim text | `example/chord/test/tool/npm_test.dart`, `npm_shim_test.dart` |
| `scripts/dev.ts` RELEASE + `release` command | `example/chord/tool/release.dart` (`args`, the RELEASE text and options as the original) | `example/chord/test/tool/release_cli_test.dart` |
| `scripts/dev/release/{stages,build,sign,notarise,pack,sums,publish,state,lock,bump,version,preflight,selftest,authenticate,continue,select,lib}.ts` | `example/chord/tool/release/<same>.dart`; `source.ts` keeps only `ghReady`/`draftRelease` (no source archives) | `example/chord/test/tool/release/<same>_test.dart` |
| `scripts/macos/chord.entitlements` | `example/chord/tool/macos/chord.entitlements` (`allow-unsigned-executable-memory`) | read back by `sign_test` |
| (new) | `.github/workflows/release.yml`, and a check-only `ci.yml` if Q1 is option 1 | `example/chord/test/tool/workflow_test.dart` |
| (new, CTUI-134) | `example/chord/tool/formula.dart`: the formula rendered from `SHA256SUMS` | `example/chord/test/tool/formula_test.dart` |

The release's `Release` context keeps the original's shape: `root`,
`env`, `tty`, `out`, `err`, `sleep`, and a `run(argv, {stdio, input,
cwd})` returning `{status, stdout, stderr}`. Every external tool (`dart`,
`codesign`, `xcrun`, `ditto`, `plutil`, `file`, `npm`, `git`, `gh`,
`tar`, `security`) goes through `run`, so each stage is tested with a
recording fake runner and a scratch root, and `sleep` is instant in
tests. Release-only packages (`crypto` for sums, if the upgrade doesn't
already need it) go in the port's `dev_dependencies`. `tool/` runs from
the package, so they never reach the shipped binary's dependency list.

## Failure and concurrency scenarios

| Scenario | Expected outcome |
| --- | --- |
| Registry 503 on a stable build | One request; stable wording (cliffy's sentence) after the prefix; nothing spawned; exit 1. |
| Registry 503 on a channel build | One request; `the registry answered 503`; nothing spawned. |
| Channel with no dist-tag | `it has no tag rc, the channel this chord is on`; never falls back to `latest`. |
| Connection refused / DNS failure | One request; `…: <message>`; no retry. |
| Registry accepts and never answers | Waits, as the original; Ctrl+C ends chord (Q5 if bounded). |
| Garbage JSON / no `dist-tags` | `…: the registry's answer is not a package document`. |
| Three builds on three channels read concurrently, answers reversed | Each resolves its own tag (the original's CHD-577 test). |
| Running version that `channelOf` refuses (`1.0.0-next`) | Building the command doesn't throw; the read throws the channel error before any request. |
| `--version <v>` | No request on any channel; `installArgv(manager, v)` runs. |
| Manager missing from `PATH` | `<m> is not on PATH…`; the `$ …` line was already printed. |
| Manager exits 1 | `<argv> exited with status 1.`; no "keeps" line. |
| Manager killed by SIGTERM | `<argv> was killed by SIGTERM.` |
| Ctrl+C during install | Both chord and the manager get SIGINT; chord dies by it; no handler, no half-printed lines from chord. |
| Unidentified install | Refusal with the four manager lines (plus the brew line and the release-binary line if I2 adds sources); nothing spawned, nothing read before the refusal on `--version <v>`. |
| Release: a stage's tool fails | `release: <words>` on stderr, exit 1; state left for resume as in the original. |
| Release: darwin-x64 SDK missing (option 1) | Preflight refuses before npm auth, naming the SDK path it looked for and the CI fallback command. |
| Release: built binary of the wrong kind | `file` check refuses (`KINDS` with Dart's strings: `ELF 64-bit LSB pie executable, x86-64` etc.). |
| Release: signed binary SIGKILLed by a wrong entitlement | Self-test fails at `--version` (exit 137) before notarise. |
| Workflow: tag doesn't match pubspec | The first step fails in every row; no draft. |
| Shim on an unsupported platform / without optional deps | The original's message, unchanged but for the names. |
| Shim: chord ends by SIGHUP | Shim re-raises SIGHUP; the shell sees a death by SIGHUP. |

## Test plan

No test reaches the network, npm, brew, GitHub, Apple or a real agent.

- **Pure**: `detectSource` rows (the original's table, plus brew Cellar
  paths and the release-binary marker if chosen), `installArgv`,
  `channelOf`, `publishArguments`, release version/bump, state judging,
  sums, formula rendering, targets, the RELEASE text and options.
- **Registry over loopback**: `HttpServer.bind(InternetAddress.loopbackIPv4,
  0)` serving the original's `DOCUMENT`; a 503; a handler that never
  answers (with a test timeout, or the bound if Q5 picks one); a closed
  port for connection refused; invalid JSON. Each test counts requests
  (one, or zero for `--help`/`--version`/`--version <v>`) and checks the
  path `/<scope>%2F…` or `/@scope/chord` exactly as the original asks.
- **Manager runner, real processes**: a temp directory on `env`'s `PATH`
  holding scripted `npm`/`bun` shell scripts that exit 0, exit 3, `kill
  -TERM $$`; another env with an empty `PATH` dir for ENOENT; a
  non-executable file for EACCES. Output is inherited, so the test
  checks only the outcome and words, plus a marker file the script
  writes with its argv and environment (proving `env` is the child's
  whole environment and the lookup uses its `PATH`).
- **Command through the CLI**: `upgradeCommand` built with the fake
  registry `Uri` and a recording runner: the `$ …` line, the "keeps"
  line, `-l` output, `--force`, the refusals (interface fixes the words).
- **Release stages**: each with a recording fake `run` and a scratch git
  root: the argv of every `dart compile exe` (target flags per row),
  `codesign` with `--options runtime --entitlements … --identifier`,
  `notarytool submit/log`, `npm pack`, `npm publish --tag <channel>`
  only when not a dry run, `git tag`/`push`, `gh release create --draft
  [--prerelease]` with the archives and SHA256SUMS; resume from each
  state as the original's tests do.
- **Real compile, `compile` tag** (explicit, as the port's other compiled
  tests): build `linux-x64`, `linux-arm64` and the host target into a
  temp dir and check `file` kinds; on macOS, ad-hoc sign the host binary
  with `--options runtime` and the entitlements file, then run
  `--version`. That keeps the measured SIGKILL from coming back unseen.
- **npm layout and shim**: `tool/npm.dart` into a temp dir; `npm_shim_test`
  runs `node bin/chord.js` against a platform package whose `bin/chord` is
  a scripted fake (argv passthrough, exit status, SIGHUP re-raise,
  missing-package message). Skipped with a reason when `node` is absent,
  as the fake-agent tests skip without bun. It runs `node`, never `npm`.
- **Workflow**: `workflow_test.dart` as in R2; `actionlint` added to the
  static checks the teams run, if the owner wants a tool beyond `dart`
  (else by hand, recorded in the handover).
- **By hand, owner only**: the first real notarisation; a local brew tap
  with `file://` archive URLs and `HOMEBREW_NO_AUTO_UPDATE=1` for the
  formula (CTUI-134).

## Units

- **CTUI-130 channels and versioning**: `channel.dart` and tests;
  `--version` with the label. Runtime adds nothing beyond the
  pubspec/`version.dart` test the framework draft settles (F2).
- **CTUI-131 upgrade per install source**: `upgrade.dart` with injected
  registry and runner, `runManager`, the words above, loopback and
  scripted-manager tests. If I3 picks self-replace for release binaries,
  split it out as **CTUI-131b** (GitHub read, download, verify, swap).
- **CTUI-132 release build and GitHub Releases**: too large for one
  unit. I propose:
  - **132a** targets, compile of four (incl. the Rosetta-SDK trial
    first), kind checks, archives, SHA256SUMS, dry run; the `compile`-tag
    test.
  - **132b** sign (new entitlement), self-test, notarise, with fake-runner
    tests.
  - **132c** bump, state/resume, lock, publish, tag, draft, as the
    original's CHD-623 machinery.
  - **132d** the workflow(s) and `workflow_test`, actionlint.
- **CTUI-133 npm shim**: `tool/npm.dart`, the shim, NOTICES, pack and
  install check of the tarballs (the original's `pack`), shim test.
- **CTUI-134 Homebrew formula and tap**: `tool/formula.dart` from
  SHA256SUMS; tap push is a release stage after the owner publishes the
  draft (the archives' URLs aren't public before that).

## Packages tried or chosen

- `package:http` (dart-lang): registry and GitHub reads; already
  transitive; loopback-testable through `IOClient`. `dart:io`
  `HttpClient` alone would also do; `http` is preferred for its
  `ClientException` and simpler body handling.
- `package:crypto` (dart-lang): SHA256 for SHA256SUMS and any download
  check; already transitive.
- `package:yaml` (already direct): the workflow test.
- `package:args` (already direct): `tool/release.dart`.
- Archives: system `tar`/`ditto`, as the original uses `ditto` and `npm
  pack`; `package:archive` not needed.
- `pub_semver`: the framework draft's (F1).
- Tools: `actionlint` works; `act` doesn't (see above).

## Differences from the original, with reasons

1. Entitlement `allow-unsigned-executable-memory` instead of `allow-jit`:
   a Dart AOT binary is killed under the hardened runtime without it
   (measured).
2. No `natives` stage and no FFmpeg/zlib source archives: the Dart
   binary embeds no native library. The draft release carries the four
   binary archives and SHA256SUMS instead, because GitHub Releases is now
   a distribution (the owner's decision of 2026-11-22). The packages
   carry Dart/pub licence NOTICES instead of `NATIVE_NOTICES`.
3. darwin-x64 is built by a second (x64, Rosetta) SDK or a CI runner, not
   by the one compiler call `bun build --compile` makes for all targets.
4. macOS 14 minimum (from Dart's runtime), against Bun's lower floor.
5. Transport-failure text after the prefix is Dart's, not Node's `fetch
   failed`; a malformed registry answer gets one written sentence where
   the original lets a `SyntaxError` through.
6. No cliffy: the offline `--help`/`--version` comes from never building
   a client, not from `hasRequiredPermissions() → false`.
7. `KINDS` strings follow Dart's output (`pie executable`).

## Owner questions

- **Q1. Where the release runs.** (1) Local on the arm64 Mac as the
  original, a check-only CI compiling all four (recommended); (2) CI
  builds, local signs and publishes; (3) all in CI.
- **Q2. darwin-x64.** (a) Keep, built by the x64 SDK under Rosetta
  locally, with the `macos-15-intel` runner as fallback (recommended,
  pending the trial in 132a); (b) keep, built only on `macos-15-intel`;
  (c) drop Intel Macs.
- **Q3. Signing and notarisation secrets.** (a) Local keychain identity
  and notarytool profile as the original (fits Q1 1/2; recommended); (b)
  CI secrets: `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`,
  `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, and npm
  trusted publishing or `NPM_TOKEN` (Q1 3).
- **Q4. Package and repository names.** The original publishes
  `@chorded/chord` and `@chorded/chord-<os>-<cpu>` and drafts on
  `IKatsuba/chord`. The port can't publish over those. Which npm names,
  which GitHub repository for releases, and which formula/tap? CTUI-131's
  constants, the shim and the workflow all hang on it. Options: (a) take
  over the original's names when the port replaces it (versions must then
  continue above the original's); (b) new names (e.g. a different scope);
  (c) decide later, with the constants in one place.
- **Q5. Network bounds.** (a) None, as the original: Ctrl+C ends a hung
  read (recommended); (b) connect 30 s and whole answer 60 s for the
  registry (and a stall bound for a binary download, if any), with
  `no answer in <n> seconds`.
- **Q6. Licence notices.** (a) One `NOTICES` per platform package and in
  each release archive, from the Dart SDK licence and every compiled pub
  package's licence (recommended); (b) the port's LICENSE only (a gap
  for BSD-licensed code compiled in).

# CTUI-102 brief: chord upgrade, release channels, three distributions

Design task CTUI-129, parent CTUI-102. Children to map units onto:
CTUI-130 (channels and versioning), CTUI-131 (upgrade command per install
source), CTUI-132 (release build and GitHub Releases workflow), CTUI-133
(npm shim), CTUI-134 (Homebrew formula and tap). Units may be split or
added; say so in the draft.

## The problem

The port has a version (`example/chord/lib/version.dart`, held to
`example/chord/pubspec.yaml` by a test, `0.0.1`) and no way to ship or
upgrade. The owner decided (2026-11-22): `chord upgrade` as the original
does it, with release channels, an upgrade following the installed
channel; distribution through npm, Homebrew and binaries on GitHub
Releases, all three. Nothing is published, pushed or run remotely by any
team.

## The specification in ../chord

- `src/channel.ts`: `checkChannel`, `channelOf`, `VersionError`. A
  channel is the first pre-release identifier of `<x.y.z>-<channel>.<n>`;
  stable has none; anything else shaped like a pre-release throws.
  Tests: `tests/channel_test.ts`.
- `src/upgrade.ts`: cliffy's `UpgradeCommand` over a provider for the
  package manager that installed the running binary, found from the
  binary's real path (npm, bun, pnpm, yarn; npx/bunx caches and
  unidentified paths refuse with the commands to run by hand). Exact
  versions only; `latest` is npm's `latest` on stable, the channel's
  dist-tag on a pre-release; a missing tag fails naming the channel;
  `--version`, `-l`, `--force`. Wired in `src/main.tsx` as
  `upgradeCommand(realpathSync(execPath()), process.env, version)`.
  Tests: `tests/upgrade_test.ts`.
- `docs/guide.md` "Install": the shim, platforms, signed and notarised
  macOS binaries, upgrade wording.
- `scripts/targets.ts`, `scripts/dev/npm.ts`: four platform packages
  `@chorded/chord-<os>-<cpu>` carrying `bin/chord` with `os`/`cpu`, and
  `@chorded/chord` with a Node shim `bin/chord.js` and the platforms as
  exact-version optional dependencies.
- `scripts/dev/release/*`, `steps.ts`, `scripts/dev.ts` (RELEASE text):
  the release runs on the owner's arm64 Mac, not in CI: preflight, npm
  auth, bump (`--bump`, `--channel` with branch named after the channel),
  compile all four targets, sign and notarise macOS, self-test, pack with
  SHA256SUMS, publish with `--tag <channel>`, push the tag, draft a GitHub
  release (`--prerelease` on a channel) carrying source archives only,
  resumable state in `.release/<package>/state.json`.
- `.github/workflows/ci.yml`: checks only, no release job.

## What a person sees and presses

- `chord upgrade`: upgrades the install it runs from, through the source
  that installed it, to the latest version of its channel; prints the
  command it runs; says a running chord keeps the old version until
  restarted.
- `chord upgrade --version <v>`, `chord upgrade -l`, `chord upgrade
  --force --version <v>`: as the original.
- An install not identified: refusal naming how to upgrade by hand.
- `chord --version`: the version, channel label included.

## Constraints

- The build is a Dart AOT binary (`dart compile exe
  example/chord/bin/chord.dart`), macOS and Linux, arm64 and x64.
- AGENTS.md binds: package before own code (pub_semver for versions,
  `args`/existing CLI parsing, `http` or dart:io for the registry, etc.;
  record what was tried); the port follows the original, and every
  difference is listed with its reason; logic in pure Dart reachable by
  tests; no test reaches the network, a registry, npm, brew or GitHub:
  fake registries over loopback, injected runners.
- The upgrade command lives in the port (`example/chord/lib/upgrade.dart`,
  `channel.dart`). Release tooling is the port's too
  (`example/chord/tool/`), unless a piece is general enough for `lib/`;
  say which and why.
- Nothing publishes, pushes or runs a workflow remotely. Workflows and
  formulae are written and checked locally (actionlint/`brew style` if
  available, a dry run that stops before publish).

## Non-goals

- Windows. A self-updating binary swap in place outside a package
  manager unless the design shows the release-binary install needs it
  (that is a question to answer, below). Auto-update checks on start.

## Open questions, by owner

framework (version and channel model, where code sits, packages):
- F1. pub_semver against channel.ts: does it parse, compare and expose
  the pre-release list as `semver` does (`1.0.0-next.01` invalid, numeric
  vs string identifiers, `validRange` refusal of channel names)? Where it
  differs, what is the smallest faithful port.
- F2. Version source of truth for the Dart build: pubspec, a generated
  file, `--define` at compile time; how `version.dart` and the release
  agree. (Choice is an owner question if more than one is sound; give
  options.)
- F3. Which parts are framework (`lib/`) and which port; expect "none in
  lib/" unless argued.

interface (the command a person meets, and the files a release author
writes):
- I1. `chord upgrade` help, options, outputs and refusals word for word
  against cliffy's UpgradeCommand and upgrade.ts, for each install
  source; how `--help`/`--version` stay offline.
- I2. How an install knows its source (npm-family manager by real path as
  the original; Homebrew by Cellar path or a marker; a GitHub Releases
  binary by location or marker); give options, the owner chooses.
- I3. What upgrade does for a Homebrew install (`brew upgrade <formula>`
  with channel formulae or taps?) and for a release binary (refuse with
  instructions, or download, verify SHA256 and replace); options with
  their cost.
- I4. Homebrew channels: one formula per channel (`chord`, `chord@next`),
  a tap per channel, or stable only; names are owner questions.

runtime (processes, network, release pipeline, tests):
- R1. Building four targets: Dart cross-compilation (`--target-os`,
  `--target-arch`) support by host as of Dart 3.13, which runners or
  machines are needed for macOS x64/arm64 and Linux arm64/x64; local
  release on the owner's Mac as the original, or a GitHub Actions
  workflow, or both (owner question with options).
- R2. The GitHub Releases workflow: trigger, matrix, artifacts naming,
  SHA256SUMS, pre-release from channel, draft; how it is checked without
  running remotely.
- R3. Signing and notarisation of macOS binaries in CI or locally:
  secrets needed; an owner question.
- R4. The registry/brew/GitHub reads of `upgrade`: fetching, timeouts,
  failures and their words; spawning the manager with inherited stdio;
  ENOENT; signals; how each is tested with no network.
- R5. npm shim: the original's Node shim unchanged, or anything a Dart
  binary needs differently (signals, exit codes, dynamic libraries).

Every draft: state the units it implies, mapped to CTUI-130..134 (or new
ones), the packages tried, the differences from the original with
reasons, and the owner questions it raises, each with options.

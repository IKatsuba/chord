# CTUI-102: chord upgrade, release channels and three distributions

The owner decided (2026-11-22) that the port gets `chord upgrade` as the
original has it, with release channels, an upgrade following the channel
it was installed from, and that it ships through npm, Homebrew and binaries
on GitHub Releases. This design maps that onto a Dart AOT build. The
specification is `../chord`: `src/channel.ts`, `src/upgrade.ts` with
`tests/channel_test.ts` and `tests/upgrade_test.ts`, `docs/guide.md`
"Install", `scripts/targets.ts`, `scripts/dev/npm.ts`,
`scripts/dev/release/` with `steps.ts` and the RELEASE text of
`scripts/dev.ts`, and `.github/workflows/ci.yml`. The drafts and the
critic's review are in `docs/design/evidence/CTUI-102/drafts/`.

Nothing here publishes, pushes or runs a workflow remotely, and no test
reaches npm, a registry, brew, GitHub, Apple or an agent. Every owner
question is on the board, on the task it blocks; until answered, a unit
builds what does not depend on it and leaves the answer's value in one
named constant or one switch.

There is no window here: `chord upgrade` prints and exits, like `chord
agents`. No key, no `Actions` binding, no shortcuts entry. Nothing goes
into `lib/`: versions, channels, package managers and releases are about
distributing one program, not drawing a terminal.

## Units

| Unit | Task | What | Gated by | Waits for |
| --- | --- | --- | --- | --- |
| U1 | CTUI-130 | `node_semver.dart` (per Q358), `channel.dart`, the version source (per Q359), release version logic `tool/release/version.dart` | Q358, Q359 | |
| U2 | CTUI-131 | `upgrade.dart` and `cli.dart` wiring: npm family, unidentified refusal, `-l`, the command truth table, the runner, registry reader | Q360 (names constant), Q365-Q370 | CTUI-130 |
| U3 | CTUI-132 | `tool/targets.dart`, compile of four targets, kind checks, archives, SHA256SUMS, NOTICES, `compile`-tag test | Q361, Q362 | |
| U4 | CTUI-135 | upgrade through Homebrew | Q371, Q373 | CTUI-131, CTUI-134 |
| U5 | CTUI-133 | npm layout and shim, shim test | Q360 | CTUI-132 |
| U6 | CTUI-136 | sign, self-test, notarise (recording runner) | Q364 | CTUI-132 |
| U7 | CTUI-137 | release tool: bump, state, resume, preflight, publish argv, tag, draft (recording runner) | Q363 | CTUI-130, CTUI-133, CTUI-136 |
| U8 | CTUI-138 | check-only CI, workflow test, actionlint | Q363 | CTUI-132 |
| U9 | CTUI-134 | Homebrew formula rendered from SHA256SUMS, reviewable output | Q371, Q372 | CTUI-132 |

A self-replacing release binary (Q366 option 2) has no unit until the owner
chooses it; it would add a GitHub reader, download, verify and swap, about
the size of U2, and the receipt of Q365 option 2.

## U1. Versions and channels (CTUI-130)

### channel.dart

File for file with `src/channel.ts`, same messages, same check order
(format, range, `latest`, `main`):

```dart
/// Why a version cannot be released, said as the release dies with it.
final class VersionError implements Exception {
  const VersionError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Refuses a name that cannot be a channel, which is an npm tag and a branch.
void checkChannel(String name);

/// The channel of [version], its first pre-release identifier; null for a
/// stable version.
String? channelOf(String version);
```

`channelOf('v1.0.0')` is stable, as in the original (semver normalises it
and it has no label); pubspec refuses such a version, so it is unreachable
through the tree, and a test pins it.

### Matching npm's semver (Q358)

pub_semver 2.2.1 orders pre-releases exactly as `semver` does, but differs
on validation in twelve measured ways (framework draft, table under F1):
it takes `1.0.0-next.01`, `01.0.0`, components above 2^53−1 and versions
over 256 characters; it refuses `v1.0.0` and surrounding whitespace that
semver normalises; it keeps and orders build metadata; it has no npm range
check and no pre-release increment. Within `^[a-z][a-z0-9-]*$`, npm's
`validRange` accepts exactly `^v*(x|0|[1-9][0-9]{0,15})$` with the number
at most 9007199254740990 (evaluated exhaustively to five characters and on
a million random longer names). The other pub.dev packages do not fit
(decisions entry). Q358 chooses between our own `node_semver.dart` (valid,
prerelease, `isRangeName`, compare, gt, `incStable`, `incChannel`; about
80 lines; pub_semver for ordering with build metadata dropped), pub_semver
behind guards, or pub_semver alone. Until it is answered no code is
written for this part.

Tests: every case of `tests/channel_test.ts` under the same names; the
twelve rows as boundaries; a parity test in the shape of
`registry_test.dart` that runs one bun process over a fixed list against
`../chord/node_modules/semver` (or `CHORD_SOURCE`), skipped with a reason
without bun or the checkout.

### The version (Q359)

Today `example/chord/pubspec.yaml` and `lib/version.dart` hold `0.0.1`,
tied by a test. Q359: keep both, written by the release bump in one commit
(recommended); a generated file; or `-D` at compile time (a binary could
claim a version the tree does not hold). npm `package.json`s and the
formula are written from the version at pack time; none is a source.
`chord --version` is unchanged: `chord 1.0.0-next.3` names its channel.

### Release version logic

`releaseVersion`, `isVersionArgument`, `Bump` (`scripts/dev/release/
version.ts`, `select.ts`, `bump.ts`'s pure parts) go to
`example/chord/tool/release/version.dart` here, not in U7: they are the
only other users of `channelOf` and the semver differences, so one test set
covers them. Rules, as the original: a bump counts from npm's latest stable
version; `--channel <name>` gives `<x.y.z>-<name>.<n>`, `n` up by one if
pubspec already holds that channel's pre-release of it, else 0.

## U2. `chord upgrade` (CTUI-131)

### Parsing and help

`runCli` dispatches `upgrade` to its own `upgradeParser`, as `acp`; the
main command's options are refused by construction, as cliffy's
`noGlobals()`. Usage errors as the port's other refusals: help on stdout,
`\n  error: <message>\n\n` on stderr, exit 2, with the nearest-option
suggestion (`chord upgrade -V`: `Unknown option "-V". Did you mean option
"-v"?`). `chordHelp` gains `upgrade` after `acp` with the original's
description. The help, in `args`' layout with the original's words:

```text
Usage: chord upgrade
Version: 0.0.1

Upgrade chord executable to latest or given version.

Options:
  -h, --help                 Show this help.
  -l, --list-versions        Show available versions.
      --version=<version>    The version to upgrade to.
                             (defaults to "latest")
  -f, --force                Replace current installation even if not out-of-date.
  -v, --verbose              Log verbose output.
```

The longest line is 85 columns; at 80x24 the terminal wraps it, as it
wraps `chord agents --help` today. Help and `--version` never build a
client; tests prove it with an injected version source that throws on any
call (the proof is the injection, not a proxy variable).

### Detecting the install (Q365)

`File(Platform.resolvedExecutable).resolveSymbolicLinksSync()`, the
original's rows in order with the names of Q360 (one constant file):
npx and bunx caches → none; bun's `install/global`; pnpm's `global/…/.pnpm`;
yarn's `yarn/global`; npm's `lib/node_modules/<pkg>/node_modules/<platform
package>`. Under the shim the resolved executable is the platform
package's `bin/chord`, as the Bun binary's `execPath` is. Q365 option 1
(recommended) adds only Homebrew's Cellar row (U4); a release download is
unidentified.

### What it does: the truth table

cliffy's `upgrade()` over `ManagerProvider`, measured from cliffy 1.3.1.
"Reads" counts registry requests.

| Call | Reads | Outcome |
| --- | --- | --- |
| `--help`, `chord --version` | 0 | text, exit 0 |
| `-l` | 1 | versions, newest first, running one `* `; failed read: the message, exit 1 (D6) |
| bare, already latest | 1 | stderr `You're already using the latest available version <v> of chord.`, exit 0 |
| bare, newer exists | 2 (check, resolve) | runs the manager |
| `--version <v>`, `v` not listed | 1 | not-found text (below), exit 1 |
| `--version <v>`, `v` running | 1 | stderr `You're already using version <v> of chord.`, exit 0 |
| `--version <v>`, listed | 1 | runs the manager |
| `--force` | 1 (resolve) | runs the manager |
| `--force --version <v>` | 0 | runs the manager |
| unidentified install | as above | refusal after the reads, nothing spawned |

`latest` is npm's `latest` dist-tag on a stable build and the dist-tag
named by `channelOf(running)` on a pre-release, asked lazily so a refused
running version fails only the read. The read: `GET
https://registry.npmjs.org/<pkg>` through `package:http`, the base `Uri`
and the `Client` injected; versions are the document's keys reversed. No
timeout (Q367 decides). Words, with prefix `chord could not read the
versions of <pkg> from the npm registry: `:

- stable, non-2xx: `couldn't fetch the latest version - try again after sometime`
- channel, non-2xx: `the registry answered <status>`
- channel with no tag: `it has no tag <channel>, the channel this chord is on`
- transport failure: the exception's own message (Node's text differs)
- refused running version: `channelOf`'s message
- not a package document: `the registry's answer is not a package document` (Q370)

Not found, stderr, exit 1:

```text
The provided version 9.9.9 is not found. The latest version is 0.55.0.

    Visit https://npmjs.org/package/<pkg> for available releases or run again with the -l or --list-versions command.
```

With a near miss (`v0.55.0`) the hint is ` Did you mean 0.55.0?`.

Running the manager: `npm install --global <pkg>@<to>`, `bun add --global
…`, `pnpm add --global …`, `yarn global add …`, always an exact version.
Success (stdout):

```text
<the manager's own output>
A chord already running keeps 0.54.0 until it is started again.
Successfully upgraded chord from version 0.54.0 to 0.55.0! (https://npmjs.org/package/<pkg>/v/0.55.0)
```

With `-v`, before it: `Upgrading chord to the latest version` (or `to
version <v>`), `Upgrading chord:`, `  - current version: …`, `  - target
version: …`, `$ <argv>`. Without `-v` the `$` line is not printed: cliffy's
`log` is verbose-only. Failures (stderr, exit 1), each after `Failed to
upgrade chord from version <from> to <to>.`: `<argv> exited with status
<n>.`, `<argv> was killed by SIG<NAME>.`, `<manager> is not on PATH.
Install <manager>, or upgrade chord with the manager that installed it.`

Unidentified (stderr, exit 1):

```text
Failed to upgrade chord from version 0.54.0 to 0.55.0.
chord cannot tell which package manager installed <path>. If one did, upgrade with it: npm install --global <pkg>@0.55.0, bun add --global <pkg>@0.55.0, pnpm add --global <pkg>@0.55.0, yarn global add <pkg>@0.55.0.<extra> A build from source upgrades with <Q369>.
```

`<extra>` names each other adopted source (U4's ` Homebrew upgrades with
brew upgrade <tap>/<formula>.`; under Q366 option 1, ` A release binary is
replaced by chord-<os>-<cpu>.tar.gz from https://github.com/<repo>/releases/tag/v0.55.0,
checked against its SHA256SUMS.`). The source-build sentence never fills
in the running path: under `dart run` it is the Dart VM, and a compile
there would overwrite the SDK (critic 2).

`-l`: one version per line, newest first by semver, unparseable last by
string order; more than 25 in cliffy's table, 8 columns filled column by
column, each as wide as its widest cell. A pure `formatVersions`, pinned
against the original's `printVersions` on fixed lists.

Colours: plain (Q368).

### The runner

One contract for every external command:

```dart
/// Runs [argv] as a person would type it, looked up on [env]'s PATH.
abstract interface class Runner {
  /// The terminal's stdio; no timeout. Throws [RunFailure].
  Future<void> inherit(List<String> argv, Map<String, String> env);
  /// Captured, for a short local query (brew list). Throws [RunFailure].
  Future<String> capture(List<String> argv, Map<String, String> env);
}
```

`RunFailure` is one of exit status, signal or not found (ENOENT, `errorCode
== 2`); other errors pass through. `Process.start` with
`includeParentEnvironment: false` and, for `inherit`,
`ProcessStartMode.inheritStdio`. No signal handler: Ctrl+C reaches the
foreground group, so manager and chord both get it and chord dies by it.

### Tests

Pure: detection rows, argv, `formatVersions`, every text. Registry over
loopback (`HttpServer.bind(loopbackIPv4, 0)`): the original's document, 503,
missing tag, invalid JSON, a closed port; each test counts requests per the
truth table, and owns the server and client, closing both with `force:
true` in `tearDown` so an unanswered request cannot outlive it. Runner on
real processes: scripted `npm` and `bun` on a temporary `PATH` that exit 0,
exit 3, `kill -TERM $$`, an empty `PATH` for ENOENT, a marker file proving
the environment is exactly `env`; children reaped in `finally`. The command
through `runCli` with fake source and recording runner for each row of the
table. Cases from `tests/upgrade_test.ts` under their names, including
three channel builds read concurrently with answers reversed (CHD-577).

## U3. Release build (CTUI-132)

`example/chord/tool/targets.dart` is the one table, `{os, cpu, dartOs,
dartArch}` for darwin and linux, arm64 and x64, read by the release, the
npm layout, the formula and the workflow test.

Measured on Dart 3.13.5 from an arm64 Mac: `--target-os=linux` builds
x64 and arm64 (glibc ≥ 2.18 on those samples), the host builds
darwin-arm64 (`minos 14.0`), and `--target-os=macos --target-arch=x64` is
refused (`Unsupported target platform macos_x64`). Q362 decides Intel
macOS; under option 1 the first step of U3 is the Rosetta-SDK trial, and
until it passes Intel support is unproven. The floors (macOS 14 from Dart's
runtime, glibc from the native builds, no musl) are stated in the install
text only after U3 has run each binary on its own platform.

The archive contract, shared by U2's hint, U5, U8, U9 and the docs:

- `chord-<os>-<cpu>.tar.gz`, `os` ∈ {darwin, linux}, `cpu` ∈ {arm64, x64}
  (the original's npm spelling); no version in the name, the tag carries it.
- Members at the top: `chord` (mode 0755), `LICENSE`, `NOTICES`.
- `SHA256SUMS` beside them in sha256sum's format, names relative, as the
  original's `sums.ts`.
- Tag `v<version>`, draft only, `--prerelease` exactly when `channelOf` is
  non-null.
- Archives and npm packages are made only from the binaries U6 signed and
  notarised (darwin) and the kind-checked builds (linux); the pack step
  refuses a darwin binary whose `codesign --verify --strict` fails or whose
  notarisation the release state does not record (critic 4).

NOTICES: the Dart SDK's licence, the licence of every pub package compiled
in (from `.dart_tool/package_config.json`), and the repository's own
retained notices (the README's credits). Required, not an option: built in
U3 before any archive, used by U5. `NATIVE_NOTICES` and the `natives` stage
have no counterpart: the Dart binary embeds no library.

Tests: argv of every compile, kind strings (Dart's `pie executable`),
archive members and modes from `tar -tzvf`, sums. A `compile`-tag test
builds the host and both linux targets, checks kinds, and on macOS ad-hoc
signs the host binary with `--options runtime` and the entitlements file
and runs `--version`, so the measured SIGKILL cannot come back unseen.

## U4. Upgrade through Homebrew (CTUI-135)

Detection: real path `/Cellar/<formula>/<version>/bin/chord` with
`<formula>` in the list U9 ships (one formula under Q371 option 1),
under any prefix. The flow, with no registry read: `-v` prints `Upgrading
chord to the latest version` and `$ brew upgrade <tap>/<formula>`; run it
inherited (`brew reinstall` with `--force`); then `capture` `brew list
--versions <formula>`.

- Observation lists the formula: the newest version on the line is taken
  as installed (brew links the newest after an upgrade). Changed: `A chord
  already running keeps <from> …` and `Successfully upgraded chord from
  version <from> to <to>! (https://github.com/<repo>/releases/tag/v<to>)`.
  Unchanged: `You're already using the latest available version <from> of
  chord.`, exit 0.
- Observation fails, is empty or unparseable: stderr `brew upgrade
  <tap>/<formula> finished, but chord could not tell which version is
  installed now: <reason>. Run brew list --versions <formula>.`, exit 1;
  it says the upgrade may have happened.
- brew fails: `Failed to upgrade chord from version <from> to latest.` and
  the runner's words; brew missing: the not-on-PATH sentence.
- `--version <v>` and `-l`: per Q373; option 1 refuses with no read:
  `Homebrew installs only the version its formula names: brew upgrade
  <tap>/<formula>. For another version, install chord with npm (npm install
  --global <pkg>@<v>) or from https://github.com/<repo>/releases.` (for
  `-l`, `npm view <pkg> versions`).

## U5. npm (CTUI-133)

`example/chord/tool/npm.dart` lays out the original's shape under Q360's
names: one package per target with `bin/chord`, `LICENSE`, `NOTICES`, `os`
and `cpu`; the main package with the original's Node shim, unchanged but
for names, and the targets as exact-version optional dependencies. The
shim needs nothing new for a Dart binary: it forwards SIGINT, SIGTERM and
SIGHUP; chord's `dieBySignal` holds the second SIGHUP; chord re-raises, and
the shim re-raises or exits with the status. Tests: the layout into a temp
dir; `node bin/chord.js` against a scripted platform binary (argv, status,
SIGHUP re-raise, missing-package message), skipped without `node`. No test
runs `npm`. The original's pack check (installing the tarballs) is a real
npm run and stays the owner's, in the real release; teams check tarball
contents and modes with `tar`.

## U6. Signing and notarisation (CTUI-136)

`example/chord/tool/macos/chord.entitlements` carries
`com.apple.security.cs.allow-unsigned-executable-memory`, not the
original's `allow-jit`: measured, a hardened-runtime Dart binary is
SIGKILLed with `allow-jit` alone and runs with this key. `sign.ts`'s
read-back comparison, the self-test (`--version`, `-p`, the window in its
own tmux, as `selftest.ts`) and notarisation follow the original, with
credentials per Q364. Every tool goes through the release runner and is
tested with a recording fake; only the owner signs and submits for real.
Notarisation of a Dart binary stays unproven until then. A bare Mach-O is
not stapled, as in the original.

## U7. Release tool (CTUI-137)

`dart run example/chord/tool/release.dart`, the original's RELEASE text,
options and stages in order, under Q363 (option 1: the owner's Mac, as the
original). Two rules the critic made explicit:

- Branch and npm tag are separate. Stable: branch `main`, `npm publish`
  with no `--tag` (npm's `latest` moves). Channel: branch `<channel>`,
  `npm publish --tag <channel>`. Draft `--prerelease` on a channel.
- The teams' checks run every stage against a recording runner. The
  original's own `--dry-run` authenticates npm, reads the registry and
  submits to Apple; it is the owner's, never run by a team or a test.

Under Q363 option 2, the downloaded artifacts must prove the release's
built commit (run id, head sha, all four rows complete, SDK version, sums)
before signing, refused otherwise, with fake-runner tests; this applies
only if that option is chosen.

## U8. CI (CTUI-138)

A check-only workflow: `permissions: contents: read`, a matrix over
`targets.dart` on native runners (macos-14, the Intel runner per Q362,
ubuntu-24.04, ubuntu-24.04-arm), `dart compile exe` and `--version`. No
draft, no upload outside the run, no secret. Its steps call Dart entry
points under `tool/` whose runner allows only `dart`, `file` and `tar`
and fails on anything else, so the test proves control flow, not YAML
strings. `workflow_test.dart` parses the YAML with `package:yaml` and
checks matrix, permissions and pinned SDK; `actionlint` is clean.
A release workflow (Q363 option 3, or the artifact source of option 2) is
written only after that answer and the owner's approval; no team runs any
workflow remotely.

## U9. Homebrew formula (CTUI-134)

`example/chord/tool/formula.dart` renders the formula from SHA256SUMS and
the archive contract: per-platform `on_macos`/`on_linux`, `on_arm`/
`on_intel` URLs to `https://github.com/<repo>/releases/download/v<v>/
chord-<os>-<cpu>.tar.gz`, `bin.install "chord"`, `desc "A full-screen
terminal client for ACP coding agents."`, `test do assert_match
version.to_s, shell_output("#{bin}/chord --version") end`. Channel layout
per Q371; under option 2 or 3 a fixed channel list in one table feeds
formula names, `conflicts_with` and U4's detection together. Publication
per Q372; option 1 writes the file for the owner to review and commit,
since the archive URLs exist only after the owner publishes the draft and
the release has already ended. Tests: rendered text against a fixed
SHA256SUMS; `brew style` by hand if brew is present, recorded in the
handover.

## Differences from the original

| Difference | Reason |
| --- | --- |
| Homebrew and release-binary sources, their sentences in the refusal | Owner's decision of 2026-11-22 |
| Draft release carries four archives, SHA256SUMS; no source archives | GitHub Releases is now a distribution; no native libraries to source |
| `allow-unsigned-executable-memory` entitlement | Measured SIGKILL with `allow-jit` |
| No `natives` stage; NOTICES with Dart and pub licences | Dart binary embeds no library |
| darwin-x64 built by another SDK or runner | Dart cannot cross-compile to macOS (Q362) |
| macOS 14 floor | Dart's runtime |
| Semver from Q358's choice | No Dart package validates as npm semver |
| Offline help by never building a client | No cliffy version check to switch off |
| Transport-failure text after the prefix | Dart's exception, not Node's |
| Plain text | Q368 |
| `-l` on a failed read prints the message, exit 1 | The original dies with an uncaught error and a stack: a slip of the original (D6); fixed, tested, logged |
| `-v` errors print the message; malformed registry document has a sentence | Q370 |
| Source-build sentence | No `bun dev compile --install` in the port (Q369) |
| `VersionError implements Exception` | Dart's convention; same text |

## Critic findings

All twenty accepted; the design above carries each. One part of 10 is
rejected: the `-l` crash (D6) is fixed as a slip of the original under the
owner's standing instruction that the lead fixes, tests, logs and reports
small slips of the original; D7 and the malformed document went to the
owner (Q370). Finding 11's package trial was done by the lead (decisions
entry); the custom parser stays an owner question (Q358).

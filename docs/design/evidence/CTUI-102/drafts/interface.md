# CTUI-102 interface draft: `chord upgrade`, install sources, channels

Answers I1-I4 of the brief. Everything a person types or reads is given
word for word; where a word depends on an owner answer it is written as
`<pkg>`, `<scope>`, `<repo>`, `<tap>`, `<formula>` and the question that
fills it is in "Owner questions" at the end.

Sources read: `../chord/src/upgrade.ts`, `src/channel.ts`,
`tests/upgrade_test.ts`, `src/main.tsx` (the `upgrade` wiring and the
`cli.parse` catch), `docs/guide.md` "Install", `scripts/dev/npm.ts`,
`scripts/targets.ts`, and cliffy 1.3.1 in `../chord/node_modules/@cliffy`:
`command/upgrade/upgrade_command.js`, `_check_version.js`, `logger.js`,
`upgrade/upgrade.js`, `provider.js`, `provider/npm.js`. Offline runs of
the original (bun present, version 0.71.0): `chord upgrade --help`,
`chord --help`, `chord --version`, `chord upgrade -V`,
`chord upgrade --version` (no value). Nothing was run that reaches a
registry. The port: `example/chord/lib/cli.dart`, `bin/chord.dart`,
`lib/version.dart`, `chord agents --help` run locally.

There is no window here: `chord upgrade` is a CLI command that prints and
exits, like `chord agents`. No key, no `Actions` binding, no shortcuts
panel entry; "every action has a key" does not apply. "120x40 and 80x24"
applies only as line width: the help is `args`' usage, unwrapped, as
`chord agents --help` is today; the terminal wraps a long line.

## 1. What the original does, exactly (the specification)

### 1.1 The help (offline)

`chord upgrade --help`, original, colours stripped:

```text

Usage:   chord upgrade
Version: 0.71.0

Description:

  Upgrade chord executable to latest or given version.

Options:

  -h, --help                      - Show this help.
  -l, --list-versions             - Show available versions.
  --version            <version>  - The version to upgrade to.                             (Default: "latest")
  -f, --force                     - Replace current installation even if not out-of-date.
  -v, --verbose                   - Log verbose output.

```

Cliffy hides `-r, --registry` (one provider), `-o, --output` (no provider
supports a binary upgrade) and `--no-spinner` (spinner off). The command
takes `noGlobals()`, so the main command's `-V`/`--version` is not
inherited: `chord upgrade -V` is refused with
`Unknown option "-V". Did you mean option "-v"?`, and
`chord upgrade --version` with no value with
`Missing value for option "--version".` (help on stdout, message on
stderr, as every Cliffy usage error).

`chord --help` lists it under Commands as
`upgrade           - Upgrade chord executable to latest or given version.`

### 1.2 Why help and `--version` stay offline in the original

Cliffy's `checkVersion` runs on help and on `--version`: when the main
command has an `upgrade` subcommand that lists versions, it asks
`hasRequiredPermissions()` and, if true, reads the registry to append
`(New version available: …)` to the version. `ManagerProvider` overrides
`hasRequiredPermissions()` to `false`, so the check stops before any read.
Help, `chord -V`, `chord --version` and `chord upgrade --help` never touch
the network.

### 1.3 The flow (cliffy `upgrade()` over `ManagerProvider`)

1. Unless `--force`: `isOutdated(from, to)` reads the versions (one
   registry read), then:
   - `to` not in the list: throws "The provided version … is not found…"
   - `latest == from == to`: warns "You're already using the latest
     available version …" and stops, exit 0.
   - `from == to`: warns "You're already using version …", exit 0.
2. `resolveVersion`: `latest` becomes the channel's (or npm `latest`'s)
   exact version (a second registry read); a named version stays.
3. In a try: `provider.upgrade()`: refuses an unidentified install, or
   logs `$ <argv>`, runs the manager with inherited stdio, then says the
   running chord keeps the old version.
4. On success: "Successfully upgraded …" with the npm page of the version.

Logger routing (cliffy's `createLogger`): `log` goes to stdout **only with
`-v`**; `info` to stdout always; `warn` and `error` to stderr. So the
`$ npm install …` line the brief mentions is printed only with `-v`; the
"keeps … until it is started again" line is printed always. Any error in
the action prints its message on stderr (the whole error object with
`-v`) and exits 1. An error inside step 3 is preceded by
`Failed to upgrade chord from version <from> to <to>.`; an error in step
1 or 2 (a registry read) is not.

`-l` runs as an option action, outside the action's try: on success it
prints the versions and exits 0; a failed read (or a channel with no tag)
escapes Cliffy as a plain Error, which `main.tsx`'s catch rethrows (it
handles only `ValidationError`), so the original dies with an uncaught
error and a stack trace. See D6.

## 2. The port's command

### 2.1 Where it is parsed

`runCli` dispatches `args.firstOrNull == 'upgrade'` to its own
`upgradeParser` before `chordParser`, as it does `acp`. Not
`chordParser.addCommand('upgrade')`: `args` hands a parent's options to a
command (the reason `agents` carries a stray-option list), and Cliffy's
`noGlobals()` refuses them; a separate parser refuses `-V`, `-C`, `-p`…
by construction, and `--version` is the subcommand's own option, never
the main flag. Usage errors follow the port's refusal ("The port refuses a
call as the original's Cliffy does"): `upgradeHelp` on stdout,
`\n  error: <message>\n\n` on stderr, exit 2. Unknown options get the
suggestion `unknownAgentsOption` already computes (Levenshtein over the
command's own options), so `chord upgrade -V` says
`Unknown option "-V". Did you mean option "-v"?` as the original.
`chord upgrade extra` says `Too many arguments: extra`.

`chordHelp`'s Commands gains the row
`('upgrade', 'Upgrade chord executable to latest or given version.')`
after `acp`, as the original orders them.

### 2.2 `chord upgrade --help` (port)

`args`' layout, the original's words and order (the port's help decision);
the test pins the exact text:

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

The longest line is 85 columns; at 80x24 the terminal wraps the `-f`
line, as it wraps `chord agents --help`'s `--json` today. If the owner
picks R-B (release binary replaced in place, §5), cliffy would show
`-o, --output <path>` "Install the upgraded binary to this path instead of
replacing the current one." and the port adds it then.

### 2.3 Offline guarantee in the port

There is no `checkVersion` in the port, so nothing reads a registry on
help or version, by construction. The command's reads go through one
injected `VersionSource` (npm registry reader, brew lister); `runCli`
takes it as a parameter like `lookup` and `open`. Tests: `chord --help`,
`chord -V`, `chord --version`, `chord upgrade --help`, `chord upgrade -h`
and every usage refusal run with a source that throws on any call, and a
compiled-binary smoke test runs `chord upgrade --help` with
`HTTPS_PROXY`/`HTTP_PROXY` set to a closed loopback port as a second
guard.

### 2.4 `chord --version`

Unchanged: `chord -V` prints `<version>`, `chord --version` prints
`chord <version>`. The channel label is the version's own pre-release
part, as in the original: `chord 1.0.0-next.3`. Nothing is appended (the
original's "New version available" never shows, §1.2). Plain text, as the
port's `--version` already is (the original colours `chord` bold and the
version bright blue).

## 3. Outputs per install source

Plain text throughout (D1). `<from>` is the running version, `<to>` the
resolved target. stdout/stderr and exit code given for each.

### 3.1 npm, bun, pnpm, yarn (as the original)

Detection by the binary's real path
(`File(Platform.resolvedExecutable).resolveSymbolicLinksSync()`), the
original's rows in order with the port's package names (O1):

| path contains | manager |
| --- | --- |
| `/_npx/<x>/node_modules/<scope>/<base>-(darwin\|linux)-` | none (cache) |
| `/bunx-<x>/node_modules/<scope>/<base>-(darwin\|linux)-` | none (cache) |
| `/install/global/node_modules/<scope>/<base>-(darwin\|linux)-` | bun |
| `/global/<x>/(<y>/)?node_modules/.pnpm/<scope>+<base>-(darwin\|linux)-` | pnpm |
| `/yarn/global/node_modules/<scope>/<base>-(darwin\|linux)-` | yarn |
| `/lib/node_modules/<pkg>/node_modules/<scope>/<base>-(darwin\|linux)-` | npm |

(`<pkg>` = `<scope>/<base>`, e.g. `@chorded/chord`; the shim spawns the
platform package's `bin/chord`, so a Dart AOT binary's resolved
executable is that path, as the Bun binary's `execPath` is.)

Install argv, exact version always:
`npm install --global <pkg>@<to>`, `bun add --global <pkg>@<to>`,
`pnpm add --global <pkg>@<to>`, `yarn global add <pkg>@<to>`.

`latest` = npm's `latest` dist-tag on a stable build, the dist-tag named
by `channelOf(<from>)` on a pre-release.

**`chord upgrade`, stable 0.54.0 -> 0.55.0, npm** (exit 0):

```text
<npm's own output, inherited>
A chord already running keeps 0.54.0 until it is started again.
Successfully upgraded chord from version 0.54.0 to 0.55.0! (https://npmjs.org/package/<pkg>/v/0.55.0)
```

(stdout. The URL is cliffy's `NpmProvider.getRepositoryUrl`.)

**With `-v`**, before npm's output (stdout):

```text
Upgrading chord to the latest version
Upgrading chord:
  - current version: 0.54.0
  - target version: 0.55.0
$ npm install --global <pkg>@0.55.0
```

With `--version 0.55.0` the first line is
`Upgrading chord to version 0.55.0`.

**Already latest** (stderr, exit 0):
`You're already using the latest available version 0.55.0 of chord.`

**Named version already running** (stderr, exit 0):
`You're already using version 0.55.0 of chord.`

**Version not in the registry**, `--version 9.9.9` (stderr, exit 1):

```text
The provided version 9.9.9 is not found. The latest version is 0.55.0.

    Visit https://npmjs.org/package/<pkg> for available releases or run again with the -l or --list-versions command.
```

With `--version v0.55.0` where `0.55.0` exists, the hint is
` Did you mean 0.55.0?` instead of the latest-version sentence (cliffy's
`getVersionHint`).

**Registry read fails** (stderr, exit 1, no "Failed to upgrade" line):
- channel build, HTTP status:
  `chord could not read the versions of <pkg> from the npm registry: the registry answered 503`
- channel with no tag:
  `chord could not read the versions of <pkg> from the npm registry: it has no tag rc, the channel this chord is on`
- stable build, HTTP status (cliffy's inner words kept, D5):
  `chord could not read the versions of <pkg> from the npm registry: couldn't fetch the latest version - try again after sometime`
- connection failure: the same prefix, then the Dart exception's message
  (D4).
- running version no channel can have (`1.0.0-next`):
  `chord could not read the versions of <pkg> from the npm registry: 1.0.0-next is not a release of a channel: a pre-release is written <x.y.z>-<channel>.<n>`

**Manager fails** (stderr, exit 1):

```text
Failed to upgrade chord from version 0.54.0 to 0.55.0.
npm install --global <pkg>@0.55.0 exited with status 1.
```

killed: `… was killed by SIGINT.`; not on PATH:
`pnpm is not on PATH. Install pnpm, or upgrade chord with the manager that installed it.`
(both after the "Failed to upgrade" line; with `-v` the `$` line
precedes them on stdout).

**`--force`**: skips step 1 (no "already using", no not-found check);
`--force --version <v>` reads nothing at all, as the guide says.

**`-l`** (stdout, exit 0): every version, newest first by semver, the
running one marked `* `, the rest indented two spaces:

```text
  1.0.0-next.4
  1.0.0-beta.1
* 0.67.0
```

More than 25 versions: cliffy's `Table`, 8 columns, filled column by
column (`ceil(n / 8)` rows), each column as wide as its widest cell, one
space between columns. The tester pins the layout against the original's
`printVersions` run on a fixed list with bun, offline (a pure function).
A failed read prints the registry message above on stderr, exit 1 (D6).

### 3.2 Unidentified install (refusal)

As the original: the registry is read as in steps 1-2 (so the target
version can be named), then:

```text
Failed to upgrade chord from version 0.54.0 to 0.55.0.
chord cannot tell which package manager installed /home/u/bin/chord. If one did, upgrade with it: npm install --global <pkg>@0.55.0, bun add --global <pkg>@0.55.0, pnpm add --global <pkg>@0.55.0, yarn global add <pkg>@0.55.0.<extra> A build from source upgrades with git pull and dart compile exe example/chord/bin/chord.dart -o /home/u/bin/chord.
```

(stderr, exit 1, one line after the first.) `<extra>`, present only for
sources the owner adopts (D2):
` Homebrew upgrades with brew upgrade <tap>/<formula>.` and
` A release binary is replaced by chord-0.55.0-<os>-<cpu>.tar.gz from https://github.com/<repo>/releases/tag/v0.55.0, checked against its SHA256SUMS.`
The last sentence names the port's own build (D3; option O8). Under
`dart run`, the resolved executable is the Dart VM, so `chord upgrade`
from a checkout is refused with the VM's path; the original behaves the
same under `bun dev` (bun's path).

### 3.3 Homebrew (new; recommended H1 of §4)

Detection: real path matches
`/Cellar/<formula>/<version>/bin/chord` with `<formula>` one of the
port's formula names (O5). Covers `/opt/homebrew`, `/usr/local` and
`/home/linuxbrew/.linuxbrew`. Checked after the npx/bunx rows; it cannot
collide with npm's row (Homebrew Node's globals live in
`<prefix>/lib/node_modules`, not the Cellar).

`chord upgrade` (no `--version`): no registry read of our own; Homebrew
decides what is latest for the formula, which already is the channel.

- `-v` lines (stdout): `Upgrading chord to the latest version`, then
  `$ brew upgrade <tap>/<formula>`.
- run `brew upgrade <tap>/<formula>`, inherited stdio, no timeout (brew
  runs its own `brew update` first).
- then `brew list --versions <formula>` (local, offline), captured, to
  learn what is installed now.
- changed (stdout, exit 0):

  ```text
  A chord already running keeps 0.54.0 until it is started again.
  Successfully upgraded chord from version 0.54.0 to 0.55.0! (https://github.com/<repo>/releases/tag/v0.55.0)
  ```

- unchanged (stderr, exit 0):
  `You're already using the latest available version 0.54.0 of chord.`
  (after brew's own "already installed" warning).
- brew fails: `Failed to upgrade chord from version 0.54.0 to latest.`
  then `brew upgrade <tap>/<formula> exited with status 1.` (exit 1;
  "to latest" because Homebrew resolves it, not chord).
- brew not on PATH:
  `brew is not on PATH. Install brew, or upgrade chord with the manager that installed it.`
- `--force` alone: `brew reinstall <tap>/<formula>` (same messages).
- `--version <v>` and `-l`: refused, stderr, exit 1, no read:

  ```text
  Homebrew installs only the version its formula names: brew upgrade <tap>/<formula>. For another version, install chord with npm (npm install --global <pkg>@<v>) or from https://github.com/<repo>/releases.
  ```

  (for `-l` the parenthesis reads `npm view <pkg> versions`). Options in
  O6.

### 3.4 GitHub Releases binary (recommended R-A of §5)

Not identified (S1 of §4): the refusal of §3.2, which names the release
asset. With a receipt (S2), the refusal is specific instead:

```text
Failed to upgrade chord from version 0.54.0 to 0.55.0.
chord was installed from a GitHub release at /home/u/bin/chord. Download chord-0.55.0-linux-x64.tar.gz and SHA256SUMS from https://github.com/<repo>/releases/tag/v0.55.0, check it with shasum -a 256 -c SHA256SUMS --ignore-missing, and put its chord in place of /home/u/bin/chord.
```

The target version comes from the same reader as npm's (§3.1), since one
release publishes the same version everywhere; if the owner wants the
release binary independent of npm, the reader becomes GitHub's releases
API (runtime's R4).

## 4. How an install knows its source (I2), options for the owner

- **S1. Real path only (recommended).** npm family as the original;
  Homebrew by `/Cellar/<formula>/<v>/bin/chord`; a release binary is
  simply "unidentified" and gets the refusal that names the release
  asset. Cost: none beyond regex rows and tests; one binary per target
  serves all three channels; no file to keep in step. Weakness: the
  refusal cannot say "you installed from GitHub".
- **S2. Path plus a receipt for release binaries.** The release tarball
  carries `chord` and `chord.install` (`{"source":"github-release"}`)
  side by side; the upgrade reads it beside the real path. A copy of the
  binary alone falls back to unidentified (safe). Cost: one more file in
  the tarball (CTUI-132), one more reader; needed only if R-B (§5) is
  chosen, since a binary swap must know it owns the location.
- **S3. Compile-time define** (`-Dchord.source=npm|brew|release`). Three
  builds per target, each signed and notarised, SHA256 differs per
  channel, and a binary moved between sources lies. Not recommended.

## 5. What upgrade does for Homebrew and for a release binary (I3)

Homebrew:

- **H1. `brew upgrade <tap>/<formula>`, then read `brew list --versions`
  (recommended).** Cost: two process calls, no network code of ours,
  tests with an injected runner. `--version`/`-l` refused (O6).
- **H2. Read the channel's latest from the npm registry or GitHub first,
  compare, then `brew upgrade`.** Gives cliffy's full flow (already
  latest / not found) before brew runs, but the tap can lag the release,
  so chord would announce a version brew does not install. Not
  recommended.
- **H3. Refuse with `brew upgrade <tap>/<formula>` as the hint.** Cheapest;
  departs from "upgrades the install it runs from".

Release binary:

- **R-A. Refuse with the asset to download (recommended).** Cost: a
  sentence; matches the brief's non-goal (no self-swap) and the
  original, which has no release-binary install at all.
- **R-B. Download, verify SHA256, replace in place.** Read the release
  (GitHub API, unauthenticated limit 60 requests/hour), download
  `chord-<to>-<os>-<cpu>.tar.gz` and `SHA256SUMS`, check, extract (pub
  `archive`), write beside the real path, `chmod 755`, rename over it (a
  running chord keeps its inode; macOS signature travels with the file).
  Adds `-o, --output <path>` to the help as cliffy does. Costs: a new
  unit, write-permission and cross-device failures with their words, a
  loopback fake GitHub for tests, and S2 to know the location is ours.
- **R-C. An install script (`curl … | sh`) that writes the receipt and
  can be re-run to upgrade.** A further artifact to sign off and keep;
  `chord upgrade` would still be R-A or R-B.

## 6. Homebrew channels (I4)

- **B1. One tap, one formula per channel** (recommended if channels go to
  Homebrew at all): `<formula>` for stable and `<formula>-<channel>` (or
  `<formula>@<channel>`) for each channel, each with `conflicts_with` the
  others, all installing `bin/chord`. The formula name in the Cellar path
  is the channel; switching channel is `brew uninstall` one and
  `brew install` the other. `-` avoids Homebrew's "versioned formula"
  meaning of `@` (its audits treat `name@x` as a version of `name`);
  `@` reads like npm's `pkg@next`. Name is the owner's.
- **B2. A tap per channel** (`<owner>/chord` and `<owner>/chord-next`,
  both formula `chord`). Two repositories to publish to; `brew upgrade
  chord` becomes ambiguous when both are tapped. Not recommended.
- **B3. Stable only on Homebrew**; channels through npm alone. Cheapest;
  a Homebrew install never sees a pre-release, so §3.3's channel question
  disappears. Reasonable as a first step.

The formula's own text, for CTUI-134: `desc "A full-screen terminal
client for ACP coding agents."` (the npm package's description), `test
do assert_match version.to_s, shell_output("#{bin}/chord --version")
end`, no caveats.

## 7. The npm shim (CTUI-133), what the person reads

The original's shim unchanged but for names; its two messages:

```text
chord: no <scope>/<base>-linux-x64 is installed. chord runs on macOS and Linux, arm64 and x64; reinstall <pkg> on one of those, with optional dependencies.
chord: /…/bin/chord did not start: <error>
```

`<pkg>` description: `A full-screen terminal client for ACP coding
agents.`, the original's keywords. (Runtime answers R5 for signals and
exit codes.)

## 8. Install text for the port's README (CTUI-131..134)

The original's guide paragraph with the port's names, and one paragraph
per adopted source:

```markdown
## Install

    npm install -g <pkg>

The npm package is a small shim around a prebuilt standalone binary for
your platform (macOS and Linux; arm64 and x64). The macOS binaries are
signed and notarised.

    brew install <tap>/<formula>

Or download `chord-<version>-<os>-<cpu>.tar.gz` for your platform from
GitHub Releases, check it against `SHA256SUMS`, and put `chord` on your
PATH.

`chord upgrade` follows npm's `latest` tag on a stable build or the
build's channel tag on a pre-release, through the package manager that
installed it (npm, bun, pnpm or yarn); a Homebrew install upgrades its
formula. Install a channel with `npm install -g <pkg>@next`.
`chord upgrade --version <version>` installs that version;
`chord upgrade -l` lists versions. A missing channel tag fails naming the
channel, including with `--version` or `-l`;
`chord upgrade --force --version <version>` bypasses that check.
```

(Only "There is no Node build of chord" and the Bun build-from-source
lines of the original are dropped: the second becomes the Dart compile
line.)

## 9. State, logic and widgets

No widget. Pure Dart, reachable by tests, in `example/chord/lib/`:

- `upgrade.dart`: `InstallSource` (sealed: `Manager(npm|bun|pnpm|yarn)`,
  `Homebrew(formula)`, `Unidentified(path)`, and `ReleaseBinary(path)`
  under S2), `detectSource(realPath, {receipt})`, `installArgv`,
  `brewArgv`, the texts (`unidentifiedText`, `notOnPathText`,
  `homebrewVersionText`, cliffy's "already using", "not found", "Failed",
  "Successfully" sentences), `planUpgrade` (cliffy's `upgrade()` flow as a
  function over an injected `VersionSource` and `Runner`, returning the
  lines for stdout/stderr and the exit code), `formatVersions` (the `-l`
  list and table).
- `channel.dart`: framework's draft (F1).
- `cli.dart`: `upgradeParser`, `upgradeHelp`, the dispatch, refusals.
- `bin/chord.dart`: wires the real reader, the real runner and
  `Platform.resolvedExecutable` resolved.

Nothing in `lib/` of the framework: there is nothing a terminal app needs
here (agrees with F3's expected answer).

## 10. Differences from the original, with reasons

- **D1. Plain text, no colours.** Cliffy colours these lines (dim, bold,
  bright blue, yellow, red, green `*`) even under `NO_COLOR` and when
  piped. The port prints its CLI output plain (its `--version` and help
  already are, per "The port's help is the original's wording in `args`'
  layout"). Owner to confirm (O7).
- **D2. Homebrew and release-binary sources and the refusal's extra
  sentences.** The original ships through npm only; the owner's decision
  of 2026-11-22 adds two sources. Wording is new; owner to confirm.
- **D3. Build-from-source sentence.** The original's
  `git pull and bun dev compile --install` does not exist in the port;
  proposed `git pull and dart compile exe example/chord/bin/chord.dart -o
  <the real path>` (O8).
- **D4. Connection-failure message.** After the fixed prefix, the
  original shows Bun's fetch error; the port shows the Dart exception's
  message. Unavoidable.
- **D5. Kept as is:** cliffy's
  `couldn't fetch the latest version - try again after sometime` on a
  stable build's failed read, and the registry reads before an
  unidentified refusal. Faithful, if odd; flagged for the lead in case
  they count as original slips.
- **D6. `-l` on a failed read.** The original dies with an uncaught error
  and a stack trace (§1.3); the port prints the registry message on
  stderr and exits 1. An original slip in the sense of the memory rule:
  fix, test, log in `docs/decisions.md`, report.
- **D7. `-v` on an error.** Cliffy prints the whole error object
  (`Error: …` with a stack) under `--verbose`; the port prints the same
  message as without `-v`: a Dart stack trace of the port's frames means
  nothing to a person. Owner to confirm.
- **D8. Help layout** is `args`', per the existing decision; the words,
  options and order are the original's.

## 11. Units

- **CTUI-130 channels and versioning**: `channel.dart` (framework's), and
  `chord --version` unchanged (§2.4), with a test that a pre-release
  version prints whole.
- **CTUI-131 upgrade command, npm family**: §2, §3.1, §3.2 (refusal
  without the Homebrew/release sentences until those land), `-l`
  formatting, offline tests of §2.3. Faithful port of
  `tests/upgrade_test.ts` cases.
- **CTUI-131b (new) upgrade for Homebrew**: §3.3 and the refusal's
  Homebrew sentence; depends on O5/O6. Could fold into CTUI-134.
- **CTUI-131c (new, only if R-B)**: release-binary self-replace with S2's
  receipt and `-o, --output`.
- **CTUI-132 release build and GitHub Releases**: artifact names the
  person reads (`chord-<version>-<os>-<cpu>.tar.gz`, `SHA256SUMS`, tag
  `v<version>`, pre-release when `channelOf` is non-null), the receipt
  under S2; the refusal sentence of §3.2 depends on these names.
- **CTUI-133 npm shim**: §7, package names (O1).
- **CTUI-134 Homebrew formula and tap**: §6, formula text, README §8.

## Owner questions

- **O1. npm package names.** (a) `@chorded/chord` and
  `@chorded/chord-<os>-<cpu>`, the port taking over the original's
  packages (its 0.0.1 is far below the original's live 0.71.x; a publish
  would have to continue the original's numbering); (b) a name of its
  own, e.g. `@chorded/chord-dart` and `@chorded/chord-dart-<os>-<cpu>`
  (recommended while both exist); (c) another scope.
- **O2. GitHub repository** the releases live in (`<repo>`; this checkout
  has no remote).
- **O3. Source identification**: S1 (recommended), S2, S3 (§4).
- **O4. Release-binary upgrade**: R-A (recommended), R-B, R-C (§5).
- **O5. Homebrew**: tap name (`<tap>`, e.g. `<owner>/tap` from repository
  `<owner>/homebrew-tap`), formula name (`chord`?), and channel layout
  B1 (with `-` or `@`), B2 or B3 (§6).
- **O6. Homebrew `--version` and `-l`**: (a) refuse with §3.3's text
  (recommended); (b) `-l` lists the npm registry's versions, `--version`
  refused; (c) `--version` installs the release binary over the Cellar
  copy (not recommended: brew no longer owns what it tracks).
- **O7. Colours**: plain text as the rest of the port's CLI (recommended),
  or cliffy's colours on a terminal only.
- **O8. Build-from-source sentence**: (a) the `dart compile exe … -o
  <real path>` line (recommended); (b) a `tool/dev.dart compile
  --install` added to the port and named instead, as the original's
  `bun dev compile --install`.

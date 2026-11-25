# CTUI-143 interface draft: what a person sees from `chord upgrade` on a release binary

Answers questions 4 to 7 of the brief. `chord upgrade` is a command, not a
screen: no keys, no shortcuts panel, no focus. Its interface is the help,
the lines it prints, on which stream, and the exit code. Plain text (Q368),
message only, never a stack (Q370), exit 0 or 1 (2 for usage, unchanged).

## Where the words come from

The original chord never reaches a binary upgrade: `upgradeCommand` passes
`standalone: false`, so cliffy's binary path is dead code there. But that
path exists in the very cliffy 1.3.1 the original pins
(`node_modules/@cliffy/upgrade/upgrade.ts` `upgradeBinary`,
`install_binary.ts`, `extract-binary.ts`, `provider/github.ts`), and it
already has words for most rows: the `-v` steps, a failed download, a
missing asset, a missing member. Those are the closest thing to an original
this feature has, so the draft takes them as they are and marks them
**cliffy**. Words from chord's own `upgrade.ts` (ManagerProvider) are
marked **chord**. Every sentence with neither source is marked **new**.

cliffy's binary path writes, in order: `log` (stdout, `-v` only) for each
step, `info` (stdout) for success, `error` (stderr) for
`Failed to upgrade …` and then the error's message. The port's `runUpgrade`
already has that shape; the release source fits it with no new stream
rules.

Example values throughout: running `0.54.0`, newest `0.55.0`, machine
`darwin-arm64`, binary `/usr/local/bin/chord`, `<repo>` =
`IKatsuba/chord` (`githubRepo`).

## Q4. Every line, per row of U2's truth table, release source

Reads are counted in the units framework chooses (Q1); the column below
says what is read, not how many requests: "list" is the release list, "one"
is one release by tag, "files" is the archive and SHA256SUMS. framework
fills in the request counts.

| Call | Reads | Outcome |
| --- | --- | --- |
| `--help`, `chord --version` | none | text, exit 0, unchanged (no client built) |
| `-l` | list | versions, newest first, running one `* `, through `formatVersions`; failed read: the message, exit 1 |
| bare, already latest | list | stderr `You're already using the latest available version 0.54.0 of chord.`, exit 0 **cliffy** |
| bare, newer exists | list, files | download, check, replace (below) |
| `--version <v>`, not listed | list | not-found text (below), exit 1 |
| `--version <v>`, `v` running | list | stderr `You're already using version 0.54.0 of chord.`, exit 0 **cliffy** |
| `--version <v>`, listed | list, files | download, check, replace |
| `--force` | list, files | download, check, replace, even when `<to>` is running |
| `--force --version <v>` | one, files | download, check, replace; no release `v<v>`: failure (below) |

`-f` on the running version replaces the file with the same release's
binary, as `brew reinstall` and cliffy's force do; the success lines are
printed as for any other version (`from version 0.54.0 to 0.54.0`), which
is what cliffy prints too.

### Success (stdout, exit 0)

```text
A chord already running keeps 0.54.0 until it is started again.
Successfully upgraded chord from version 0.54.0 to 0.55.0! (https://github.com/IKatsuba/chord/releases/tag/v0.55.0)
```

First line **chord** (ManagerProvider's `info`), second **cliffy** with
GithubProvider's `getRepositoryUrl(name, version)`, the same URL U4's
Homebrew success already prints. Nothing else is printed without `-v`:
no manager writes to the terminal here, so the person sees nothing during
the download (see the spinner question below).

### `-v` (stdout, before the success lines)

```text
Upgrading chord to the latest version
Upgrading chord:
  - current version: 0.54.0
  - target version: 0.55.0
  - target: darwin-arm64
  - asset: chord-darwin-arm64.tar.gz
  - downloading: https://github.com/IKatsuba/chord/releases/download/v0.55.0/chord-darwin-arm64.tar.gz
  - downloading: https://github.com/IKatsuba/chord/releases/download/v0.55.0/SHA256SUMS
  - sha256: 3f5a…(64 hex)… matches SHA256SUMS
  - installing: /usr/local/bin/chord
```

- Lines 1 to 4: **cliffy**, as U2 (`to version 0.55.0` with `--version`).
- `  - target:`, `  - asset:`, `  - downloading:`, `  - installing:`:
  **cliffy** (`upgradeBinary`, `installBinary`). cliffy spells the target
  with Deno's `aarch64`/`x86_64`; the port prints the archive's own
  spelling (`arm64`/`x64`, `runningMachine()`), because that is the word
  in the asset name on the next line. A deliberate departure, for the
  lead to log.
- The second `  - downloading:` (SHA256SUMS) is **new** in cliffy's form:
  cliffy downloads one file.
- `  - sha256: <hex> matches SHA256SUMS` is **new**: the one check cliffy
  does not do, said where it happens.
- If runtime adopts a macOS signature check (Q9) it gets one **new** line
  after the sha256 line: `  - signature: Developer ID, team <TEAMID>`;
  if it adopts a smoke run (Q10): `  - runs: chord 0.55.0`. Neither line
  exists unless the step does.
- The URL printed is the one actually requested, whatever framework picks
  (Q1): the browser URL above, or the API asset URL cliffy requests. A
  token is never part of what is printed.
- `  - installing:` names the real path, links resolved, the file that is
  replaced. When the binary was started through a link the line is
  `  - installing: /opt/chord/bin/chord (linked from /usr/local/bin/chord)`,
  the parenthesis **new**.
- There is no `$ <argv>` line: nothing is spawned. Should runtime spawn
  `codesign` for the signature check, it is not shown as `$ …`: it is
  chord's own check, not a command the person would retype.

### Not found (stderr, exit 1)

```text
The provided version 9.9.9 is not found. The latest version is 0.55.0.

    Visit https://github.com/IKatsuba/chord/releases for available releases or run again with the -l or --list-versions command.
```

**cliffy**, with near-miss hint unchanged (`--version v0.55.0` gives
` Did you mean 0.55.0?`: the port's versions are tags without `v`). One
departure: cliffy's GithubProvider fills the URL with `getRepositoryUrl(name)`,
the bare repository (`https://github.com/IKatsuba/chord`). The draft names
`/releases`, which is where "available releases" are. For the lead; if
the strict cliffy URL is wanted, the repository root works too.

### `-l` (stdout, exit 0)

The version of every release `--version` would accept (framework decides
which: Q1; the interface asks only that `-l` and `--version` agree, so a
listed version is never "not found"), through the unchanged
`formatVersions`, running one marked:

```text
  0.56.0-beta.1
  0.55.0
* 0.54.0
  0.53.0
```

### Failures (stderr, exit 1)

Every failure after the reads begins with the **cliffy** line
`Failed to upgrade chord from version 0.54.0 to 0.55.0.`, then the
message, then one **new** line saying the state of the installed binary:

- before the swap, always: `/usr/local/bin/chord is unchanged.`
- the swap itself is a rename (framework, Q3), so there is no
  half-replaced state; a failure after the rename (a later fsync or a
  cleanup) is reported as success's opposite only if framework finds a
  step that can fail there, with:
  `/usr/local/bin/chord is replaced by 0.55.0, but <what failed>.` **new**
- a temporary file chord could not delete:
  `A partial download is left at /usr/local/bin/.chord.upgrade-<random>; delete it.` **new**
  (the name is framework's).

The messages, in the order they can occur:

| Failure | Message | Source |
| --- | --- | --- |
| list read: transport | `chord could not read the releases of IKatsuba/chord from GitHub: <the exception's message>` | **new** prefix, in the npm reader's form |
| list read: non-2xx, GitHub JSON error | prefix + `<message> <documentation_url>` | **cliffy** (`gitFetch`) |
| list read: non-2xx, other body | prefix + `GitHub answered <status>` | **new**, as `the registry answered <status>` |
| list read: rate limited (403/429, remaining 0) | prefix + `GitHub allows 60 requests an hour from this address without a token, and they are used up until 14:05. Try again then, or set GITHUB_TOKEN.` | **new**; the token clause only if runtime adopts tokens (Q8); time local, `HH:MM`, from `x-ratelimit-reset` |
| list read: not a release list | prefix + `GitHub's answer is not a list of releases` | **new**, as Q370's sentence |
| no release for a stable build | prefix + `it has no stable release` | **new** |
| no release for the channel | prefix + `it has no release on the channel beta, the channel this chord is on` | **new**, as `it has no tag <channel>, …` |
| running version refused | prefix + `channelOf`'s message | **chord** |
| `--force --version <v>`, no such release | `IKatsuba/chord has no release v9.9.9.` | **new** (cliffy has none: force skips the not-found check) |
| archive missing from the release | `No asset "chord-darwin-arm64.tar.gz" found in release "v0.55.0" of IKatsuba/chord. Available assets: SHA256SUMS, chord-linux-x64.tar.gz` (or ` The release has no assets.`) | **cliffy** |
| SHA256SUMS missing from the release | the same sentence with `"SHA256SUMS"` | **cliffy** |
| download non-2xx | `Failed to download chord-darwin-arm64.tar.gz: 404 Not Found` (or `SHA256SUMS`) | **cliffy** (`status statusText`; Dart's `reasonPhrase`) |
| download transport | `Failed to download chord-darwin-arm64.tar.gz: <the exception's message>` | **cliffy**'s head, **new** tail |
| SHA256SUMS unreadable | `SHA256SUMS of v0.55.0 is not in sha256sum's format (line 3).` | **new** |
| no line for the archive | `SHA256SUMS of v0.55.0 has no line for chord-darwin-arm64.tar.gz.` | **new** |
| two lines for it | `SHA256SUMS of v0.55.0 names chord-darwin-arm64.tar.gz more than once.` | **new** |
| checksum mismatch | `chord-darwin-arm64.tar.gz does not match SHA256SUMS of v0.55.0: expected <64 hex>, downloaded <64 hex>. It may be damaged or tampered with; nothing was installed.` | **new** |
| binary missing from the archive | `Binary "chord" not found in archive "chord-darwin-arm64.tar.gz". Available entries: LICENSE, NOTICES` | **cliffy** |
| archive breaks the contract | `chord-darwin-arm64.tar.gz is not a release archive of chord: <reason>.` with reasons `it is not a gzip-compressed tar`, `it holds ../chord, which is not at its top`, `chord in it is a link`, `it holds extra, which is not chord, LICENSE or NOTICES`, `chord in it is larger than <limit>` | **new**; the list of reasons follows framework's checks (Q2) |
| signature (if adopted, Q9) | `The downloaded chord is not signed by the Developer ID of team <TEAMID>: <codesign's first line>.` | **new** |
| smoke run (if adopted, Q10) | `The downloaded chord printed "<first line>" for --version, not chord 0.55.0.` | **new** |
| directory not writable | the refusal of Q6 | **new** |
| write or rename fails otherwise | `chord could not replace /usr/local/bin/chord: <OS message>.` (EXDEV, ENOSPC, EROFS…) | **new**; `_messageOf`'s `FileSystemException` form for the tail |
| path not resolvable | `_messageOf`'s `FileSystemException` text, as today | **chord** port |

The unchanged line follows each of these except the read failures, which
come before `Failed to upgrade …` (as U2: the reads stop before the
upgrade begins, and nothing could have changed). Under `-l` a read failure
is the message alone, exit 1, as U2.

Example, mismatch:

```text
Failed to upgrade chord from version 0.54.0 to 0.55.0.
chord-darwin-arm64.tar.gz does not match SHA256SUMS of v0.55.0: expected 9c1e…, downloaded 04ab…. It may be damaged or tampered with; nothing was installed.
/usr/local/bin/chord is unchanged.
```

(Hashes are printed in full, 64 hex each; shortened here only.)

### Ctrl+C

No handler, as U2: chord dies by the signal and prints nothing more. Before
the rename the binary is unchanged; a temporary file may be left beside it
under framework's name (hidden, `.chord.upgrade-…`), which the next upgrade
may sweep if framework chooses so. No words.

### Spinner and progress

cliffy's default shows a spinner, `Upgrading chord from version 0.54.0 to
0.55.0...`; the original turns it off (`spinner: false`) because the
manager writes to the same terminal. Here nothing writes during a download
of about 30 MB, so without `-v` the person sees nothing until success.

**OWNER** (small):

- (a) Nothing, as the original configures cliffy. Recommended: plain
  text, nothing to clear, identical in a pipe and a terminal; `-v` shows
  each step.
- (b) cliffy's spinner sentence printed once, as a plain line on stderr,
  only when stderr is a terminal: `Upgrading chord from version 0.54.0
  to 0.55.0...` **cliffy**.
- (c) A byte count or percentage, redrawn: needs `\r`, which Q368 (plain)
  argues against.

### Widths

Nothing is drawn: lines are written whole and the terminal wraps them. The
longest are the success line (about 115 columns), the `-v` download lines
(about 100) and the failure messages; at 120 columns the success line fits,
at 80 every long line wraps, as U2's do. No line depends on the width.

## Q5. `-o, --output <path>`

cliffy enables `-o, --output <path>` "Install the upgraded binary to this
path instead of replacing the current one." whenever a provider supports a
binary upgrade; the original never shows it (one npm provider). In cliffy
it writes the binary to the path (or `<dir>/chord` for a directory), and
its rename replaces a link there with a file rather than following it.

**OWNER**: options:

- (a) Drop it (recommended). The help stays exactly as it is for every
  install; `chord upgrade` keeps U2's rule that it upgrades the install it
  runs from and never puts a second chord elsewhere. The not-writable case
  does not need it: Q6 names the hand-made way. No link or directory
  semantics to specify or test.
- (b) Keep it as cliffy has it, in every install's help (the help is
  static: it must not depend on detection), refused on npm and Homebrew
  installs with a **new** sentence `--output is only for a release binary;
  <manager> upgrades this chord with <argv>.` Its link rule: write to the
  path as given, a link there replaced by the file (cliffy's), or followed
  (safer, a departure). `-o` naming the running binary's own path is the
  plain upgrade.
- (c) Keep it and show it only when the running binary is a release
  binary. Help would then differ between installs of the same version,
  which no other chord help does.

## Q6. A directory chord cannot write

chord never raises its own privileges, never re-runs itself under sudo, and
never asks for a password. The check is made before the download, on the
directory that holds the real path (`access(W_OK)`, framework's), so a
person is not made to wait for 30 MB to be refused; the real write and
rename can still fail later and then take the same words.

```text
Failed to upgrade chord from version 0.54.0 to 0.55.0.
chord cannot write to /usr/local/bin, which holds /usr/local/bin/chord: permission denied. chord does not raise its own privileges: run sudo chord upgrade to replace it as root, or replace it by hand: a release binary is replaced by chord-darwin-arm64.tar.gz from https://github.com/IKatsuba/chord/releases/tag/v0.55.0, checked against its SHA256SUMS.
/usr/local/bin/chord is unchanged.
```

**new**, except the last clause, which is today's `releaseText`. Through a
link: `… which holds /opt/chord/bin/chord (linked from
/usr/local/bin/chord) …`. A read-only file system gives the OS's words in
place of `permission denied` and drops the sudo clause (root cannot write
there either).

**OWNER**: name `sudo chord upgrade`?

- (a) Name it, then the hand-made way (recommended, the text above). It is
  what the person will try, and the binary was most likely put there with
  sudo. Caveats runtime should weigh: sudo resets the environment (a
  `GITHUB_TOKEN` is lost; a proxy may be too), and the download then runs
  as root.
- (b) Only the hand-made way. Never suggests running network code as
  root; one more step for the person.
- (c) Name `sudo` and nothing else. Shortest; leaves no way for a person
  without sudo.

## Q7. `releaseText` and the unidentified refusal afterwards

`releaseText` stops being a refusal: the `official` branch now upgrades. Its
words survive as the hand-made clause of Q6, lowered to follow a colon,
unchanged otherwise (`a release binary is replaced by chord-<machine>.tar.gz
from https://github.com/<repo>/releases/tag/v<to>, checked against its
SHA256SUMS.`).

`unidentifiedText` is now reached only by a binary without the official
stamp: a build from source or `dart run`. Every stamped binary takes the
release path (Q365's order), so a release binary is never "unidentified".
The refusal's sentences each say "if this is how it came, upgrade so"; the
release sentence can no longer be true of the binary it is shown to.

- (a) Drop the release sentence (recommended):

```text
Failed to upgrade chord from version 0.54.0 to 0.55.0.
chord cannot tell which package manager installed <path>. If one did, upgrade with it: npm install --global @chorded/chord@0.55.0, bun add --global @chorded/chord@0.55.0, pnpm add --global @chorded/chord@0.55.0, yarn global add @chorded/chord@0.55.0. Homebrew upgrades with brew upgrade ikatsuba/tap/chord. A build from source upgrades with git pull and dart compile exe example/chord/bin/chord.dart -o <path of your chord>.
```

- (b) Replace it with an invitation, **new**: ` A release binary from
  https://github.com/IKatsuba/chord/releases upgrades itself with chord
  upgrade.` Useful to someone choosing a distribution, but it is advice to
  switch, not a way to upgrade this binary. For the lead; no owner
  question unless the lead disagrees.

`machine` stays a parameter of `unidentifiedText` only if (b) is taken.

## What is pure and what is passed in

- Pure, beside `upgrade.ts`'s texts: every sentence above as a function of
  its values (`releaseFailureText`, the not-writable refusal, the
  rate-limit sentence from a reset `DateTime` and a formatter), the `-v`
  step lines, the "unchanged" and "replaced but" lines. Tests pin each
  string; the success, not-found and `-v` lines are tested against the
  cliffy words quoted above.
- Passed in: the release source (beside `VersionSource`), the filesystem
  seam, the clock for the rate-limit time, `machine`, `realPath`.
- No widget, no state: nothing here is drawn.

## Where the port differs, for the lead's log

| Difference | Reason | Whose |
| --- | --- | --- |
| A release binary replaces itself at all | Q366 (a); the original ships only through npm | owner, decided |
| cliffy's binary-path words used though the original never reaches them | the nearest original words for the row | lead |
| `  - target:` spelt `darwin-arm64`, not Deno's `darwin-aarch64` | the archive's spelling, printed next to the asset name | lead |
| not-found URL `…/releases`, not the repository root | where releases are listed | lead |
| sha256, unchanged-state, not-writable and contract sentences | cliffy checks no sum and says nothing of the old binary | new |
| no spinner | the original's `spinner: false`; Q368 | **OWNER** (small) |
| no `-o/--output` | U2's one-install rule | **OWNER** |
| `sudo chord upgrade` named | the likely next step | **OWNER** |

## Needed from the others

- framework: the request count per row (fills the Reads column), which URL
  is downloaded (printed by `-v`), which releases `-l` lists and `latest`
  picks (so `-l` and `--version` agree), the sums and archive refusals
  (the reasons list), the temporary file's name, whether any step after
  the rename can fail (the "replaced, but" line).
- runtime: tokens or not (the rate-limit sentence's last clause), the
  rate-limit headers read, signature check and smoke run (their `-v` line
  and failure sentence exist only if adopted), timeouts (a timed-out read
  or download needs one more sentence: `GitHub did not answer within
  <n> s`, **new**, if any), and whether the not-writable check before the
  download is acceptable as advisory.

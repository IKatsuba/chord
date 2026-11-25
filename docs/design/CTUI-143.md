# CTUI-143: `chord upgrade` replaces an official release binary

The owner answered Q366 (a): on a binary installed from GitHub Releases,
`chord upgrade` downloads the new release, verifies it and replaces
itself. Today such a binary (stamped `--define=chord.official=true`, matched
by no npm row and no Cellar row, Q365's order) stops at `releaseText`. This
design turns that refusal into the upgrade. Parent design:
`docs/design/CTUI-102.md` (U2's truth table and words, U3's archive
contract, U4). Brief, drafts and their revisions after the critic are in
`docs/design/evidence/CTUI-143/drafts/`.

The original (`../chord`) ships only through npm and never reaches a
binary upgrade, but the cliffy 1.3.1 it pins has one (`upgradeBinary`,
`installBinary`, `GithubProvider`): its words are used where a row exists
there, and every other sentence is marked new below.

Nothing here publishes or pushes. No test reads `api.github.com` or
`github.com` or downloads anything real: loopback servers only, bases and
clients injected. Nothing reaches an agent runtime. Nothing goes into
`lib/`: it is about distributing one program.

## Open owner questions

| Q | Asks | Recommended | Blocks |
| --- | --- | --- | --- |
| Q381 | What a release must prove beyond SHA256SUMS (immutable releases, minisign over SHA256SUMS) | (c) both | U5; U1's `immutable` field and the forced row's read |
| Q382 | GitHub client: `package:http` + own parse, or `github` 9.26.0 which does not fit as it is | `package:http` | U1 |
| Q383 | `archive` 4.7.1 relied on for `TarDecoder.files.last` inside the callback (behaviour, not docs) | pinned as is | U2 |
| Q384 | `-o/--output` | drop | U4 (help) |
| Q385 | What the not-writable refusal suggests | `sudo chord upgrade`, then the manual way | U4 (words) |

Until answered, a unit builds what does not depend on the answer and keeps
the answer's value in one constant or one switch.

## Units

| Unit | What | Gated by |
| --- | --- | --- |
| U1 | `lib/releases.dart`: `parseReleases`, `nextPage`, `pickLatest`, `releaseVersions`, `assetUrl`, `ReleaseReader implements VersionSource` (memoised), rate-limit mapping; `cli.dart` resolves the real path before opening the source and opens `ReleaseReader` for an official, row-less binary | Q382 (Q381 adds `immutable`) |
| U2 | `lib/sums.dart` (shared with `tool/release/archive.dart`, behaviour of the tool unchanged), `lib/release_archive.dart` (`ArchiveCaps`, `inflate`, `checkMember`, `checkMembers`, `extractChord`, `machineOfBinary`); darwin code requirement with the signing constants moved from `tool/release/sign.dart` to `lib/distribution.dart` | Q383 |
| U3 | `lib/replace.dart`: `planReplace`, `InstallFs` (dart:io + `posix`), `replaceBinary`; the smoke run over `spawnGroup` with its own narrow signal handler | |
| U4 | `upgrade.dart`: the official branch runs U1–U3; every text below as pure functions; `_messageOf` learns the new errors; `releaseText` and `unidentifiedText` reworded; the `compile`-tag test | Q384, Q385 |
| U5 | Signature over SHA256SUMS: minisign format parser, `package:cryptography` verify, pinned key list, fallback rule; release-tool signing stage (recording runner) | Q381 (only if b, c or d) |

Order: U1, U2 and U3 in parallel; U4 after them; U5 after Q381.

## What a person sees

Same command, same help (unless Q384 keeps `-o`), same options. Plain text
(Q368), message only (Q370), exit 0, 1, or 2 for usage.

### The truth table, release source

"API" counts reads of `GET /repos/IKatsuba/chord/releases` (one listing,
paged, memoised per run); "files" are downloads from
`https://github.com/IKatsuba/chord/releases/download/v<to>/…`, which is not
the API and has no API quota.

| Call | API | Files | Outcome |
| --- | --- | --- | --- |
| `--help`, `chord --version` | 0 | 0 | text, exit 0; no client built |
| `-l` | 1 | 0 | versions, newest first, running `* `, through `formatVersions`; failed read: the message, exit 1 |
| bare, already latest | 1 | 0 | stderr `You're already using the latest available version <v> of chord.`, exit 0 (cliffy) |
| bare, newer exists | 1 | 2 | download, check, replace |
| `--version <v>`, not listed | 1 | 0 | not-found text, exit 1 |
| `--version <v>`, running | 1 | 0 | stderr `You're already using version <v> of chord.`, exit 0 (cliffy) |
| `--version <v>`, listed | 1 | 2 | download, check, replace |
| `--force` | 1 | 2 | download, check, replace, even onto the running version |
| `--force --version <v>` | 0 (1 by tag under Q381 b/c/d) | 2 | download, check, replace; no release `v<v>`: failure |

Under Q381 (c) or (d) the files add one signature per pinned key tried.
Bare `chord upgrade` reads the list once, where U2's npm path reads twice
(cliffy asks its provider for the check and again for the target): same
answer, half the quota (a difference, listed below).

### Which releases count, and `latest`

A release is kept when `draft` is false and its tag is `v` plus a version
`node_semver.valid` returns unchanged; for a channel version `channelOf`
must not throw. Others are dropped, never guessed at. `-l` lists every kept
version and `--version` accepts any of them, so a listed version is never
"not found".

- Stable build: `latest` is the highest-semver kept release with
  `prerelease == false` and no channel. Not GitHub's "latest" flag, which
  goes by date and would let a later backport win.
- Channel build: the highest kept release on its own channel with
  `prerelease == true`. It never moves to a stable, as npm's channel tag
  never does; `--version <stable>` does.
- A release whose `prerelease` flag disagrees with `channelOf` is listed
  but is never anyone's `latest`.
- This is not npm's dist-tag (which the owner can move to an older
  version): on GitHub the highest version is the latest. A `latest` lower
  than the running version is installed as cliffy would (U2's equality
  comparison, unchanged); only a person deleting releases can make it so.
- The chosen release missing `chord-<machine>.tar.gz` or `SHA256SUMS`
  stops the upgrade; it does not fall back to an older release.
- Paging: `per_page=100`, `Link: rel="next"` followed only on the API
  base's own scheme, host and port, at most 10 pages, more is an error.

### Success (stdout, exit 0)

```text
A chord already running keeps 0.54.0 until it is started again.
Successfully upgraded chord from version 0.54.0 to 0.55.0! (https://github.com/IKatsuba/chord/releases/tag/v0.55.0)
```

First line chord's (U2), second cliffy's with GithubProvider's URL, as U4's
Homebrew success already prints. Nothing else without `-v`: no spinner, as
the original configures cliffy (`spinner: false`).

### `-v` (stdout, in the order things happen)

```text
Upgrading chord to the latest version
Upgrading chord:
  - current version: 0.54.0
  - target version: 0.55.0
  - target: darwin-arm64
  - asset: chord-darwin-arm64.tar.gz
  - downloading: https://github.com/IKatsuba/chord/releases/download/v0.55.0/SHA256SUMS
  - downloading: https://github.com/IKatsuba/chord/releases/download/v0.55.0/chord-darwin-arm64.tar.gz
  - sha256: <64 hex> matches SHA256SUMS
  - signature: Developer ID, team YQ8ZD2KZ3T
  - runs: chord 0.55.0
  - installing: /opt/chord/bin/chord (linked from /usr/local/bin/chord)
```

Lines 1 to 4 as U2 (`to version <v>` with `--version`). `target`, `asset`,
`downloading`, `installing` are cliffy's, with the target spelt as the
archive spells it (`arm64`, not Deno's `aarch64`). New: the second
`downloading`, `sha256`, `signature` (darwin only), `runs`, and the
`(linked from …)` parenthesis, present only when started through a link.
Under Q381 (c) a `  - signed: SHA256SUMS by key <keyid>` line follows the
sums download. There is no `$ <argv>` line: chord's own checks are not
commands a person would retype.

### Not found (stderr, exit 1)

```text
The provided version 9.9.9 is not found. The latest version is 0.55.0.

    Visit https://github.com/IKatsuba/chord/releases for available releases or run again with the -l or --list-versions command.
```

cliffy's, near-miss hint unchanged; the URL names `/releases` where
cliffy's GithubProvider names the repository root.

### Failures (stderr, exit 1)

After the reads, every failure prints cliffy's `Failed to upgrade chord
from version <from> to <to>.`, the message, then the new state line
`<real path> is unchanged.` Read failures come before, as in U2, with no
state line (nothing has started). Every failure before the rename is
provably "unchanged": the target is never opened for writing.

| Failure | Message | Source |
| --- | --- | --- |
| list transport | `chord could not read the releases of IKatsuba/chord from GitHub: <exception's message>` | new prefix, in the registry reader's form |
| list non-2xx with GitHub's JSON error | prefix + `<message> <documentation_url>` | cliffy (`gitFetch`) |
| list non-2xx otherwise | prefix + `GitHub answered <status>` | new |
| rate limit (403/429, `x-ratelimit-remaining: 0`) | prefix + `GitHub allows 60 requests an hour from this address without a token, and they are used up until <HH:MM>.` (`retry-after`: `try again in <n> seconds.`) | new |
| not a release list | prefix + `GitHub's answer is not a list of releases` | new, as Q370's |
| no stable release / none on the channel | prefix + `it has no stable release` / `it has no release on the channel <c>, the channel this chord is on` | new |
| running version refused | prefix + `channelOf`'s message | chord |
| forced version with no release | `IKatsuba/chord has no release v<v>.` | new |
| asset or SHA256SUMS missing | `No asset "<name>" found in release "v<to>" of IKatsuba/chord. Available assets: …` | cliffy |
| download non-2xx / transport | `Failed to download <name>: <status> <reason>` / `: <exception's message>` | cliffy |
| SHA256SUMS malformed / no line / two lines | `SHA256SUMS of v<to> is not in sha256sum's format (line <n>).` / `has no line for <name>.` / `names <name> more than once.` | new |
| checksum mismatch | `<name> does not match SHA256SUMS of v<to>: expected <hex>, downloaded <hex>. It may be damaged or tampered with; nothing was installed.` | new |
| archive too large | `<name> is larger than <n> MiB, more than a release of chord holds.` | new |
| binary missing | `Binary "chord" not found in archive "<name>". Available entries: …` | cliffy |
| archive breaks the contract | `<name> is not a release archive of chord: <reason>.` (not gzip-compressed tar; holds `<x>`, which is not chord, LICENSE or NOTICES; `<x>` in it is not a regular file; `<x>` appears twice; `<x>` is larger than <n>) | new |
| wrong machine | `The chord in <name> is built for <os-cpu>, not <machine>.` | new |
| darwin code requirement | `The downloaded chord is not signed by the Developer ID of team YQ8ZD2KZ3T: <codesign's first line>.` | new |
| smoke run | `The downloaded chord printed "<first line>" for --version, not chord <to>.` / `exited with status <n>` / `was killed by <SIG>` / `did not finish within 30 seconds` / `wrote more than 64 KiB` | new |
| owner differs | `<path> belongs to <user>, not to <you>; chord replaces only a binary of the user running it.` | new |
| directory shared | `<dir> can be written by other users, so chord will not install into it.` | new |
| not writable | per Q385 (below) | new |
| other write or rename failure | `chord could not replace <path>: <OS message>.` | new |

After the rename, nothing is a failure: see "The commit point".

### Not writable (Q385 option 1, recommended)

```text
Failed to upgrade chord from version 0.54.0 to 0.55.0.
chord cannot write to /usr/local/bin, which holds /usr/local/bin/chord: permission denied. chord does not raise its own privileges: run sudo chord upgrade to replace it as root, or replace it by hand: a release binary is replaced by chord-darwin-arm64.tar.gz from https://github.com/IKatsuba/chord/releases/tag/v0.55.0, checked against its SHA256SUMS.
/usr/local/bin/chord is unchanged.
```

Checked before any download. On a read-only filesystem the OS's words
replace `permission denied` and the sudo clause is dropped. The last clause
is today's `releaseText`, which survives only here.

### The unidentified refusal

`unidentifiedText` is now reached only by unstamped builds (source,
`dart run`), so its release-binary sentence is dropped and its `machine`
parameter with it. The npm, Homebrew and source sentences stay.

## How it works

### The order of one upgrade

1. Read the list (memoised), pick `to` (pure), run U2's `_isOutdated`.
2. Plan the replace (before any download): resolve the real path; `stat`
   it (mode, uid, gid) and its directory; refuse an owner other than the
   effective user (root included: chord never `chown`s); refuse a
   directory writable by others without the sticky bit, or writable by a
   group other than the effective user's primary group; prove the
   directory writable by an exclusive create and delete of the staging
   name `.chord.upgrade-<random>`.
3. Make a private temporary directory (`Directory.systemTemp.createTemp`,
   0700).
4. Download SHA256SUMS (cap 64 KiB); under Q381 (c)/(d) its signature,
   verified before the sums are parsed; parse strictly (`recordedSum`).
5. Download the archive into the temporary directory, hashing as it
   writes, capped at 64 MiB and at the listed asset size; compare the
   hash. Nothing parses the archive before it matches.
6. Inflate with `GZipDecoder().decodeStream(maxOutputSize: 260 MiB)` into
   a temporary tar.
7. Create the staging file exclusively beside the target and keep its
   handle; the tar pass checks each entry before its body (type `'0'` or
   NUL only, name exactly `chord`/`LICENSE`/`NOTICES`, each once, `chord`
   ≤ 256 MiB, the texts ≤ 1 MiB each, at most 3 entries) and writes
   `chord`'s body into the handle; then `checkMembers` (all three, `chord`
   0755).
8. Set the old mode's low nine bits (setuid, setgid, sticky dropped),
   `fsync`, close.
9. Check the staging file: `machineOfBinary` (Mach-O or ELF header against
   `runningMachine()`); on darwin `/usr/bin/codesign --verify --strict
   -R=<requirement>`; the smoke run.
10. `rename(staging, target)`: the commit point.
11. Best effort: `fsync` the directory, delete the temporary directory.
    Print success.

Any failure in 2 to 10 deletes the staging file (if made) and the
temporary directory, and reports "unchanged".

### The commit point

The rename is the install. After it, every step (directory `fsync`,
deleting the temporary directory, writing the success lines) can fail, and
none of them turns the outcome into a failure: a failed cleanup prints
`chord could not delete <path>: <message>.` on stderr after the success
lines and the exit stays 0. The result of the rename is held outside the
error handling that prints "Failed to upgrade", so a cleanup exception can
never print "unchanged" after an install. Durability: the file is
`fsync`ed before the rename; the directory `fsync` is best effort, so
after a power loss the path holds the old or the new binary, and the
design claims no more than that.

### Concurrency

No lock. Two upgrades stage under different random names, each fully
checked, and both rename; the last rename wins and each reports what it
installed at its own commit point. Neither claims to know the final state
afterwards, and an older target can win the race over a newer one: the
person ran two upgrades. A lock was rejected as more mechanism than the
case deserves (a lock file in the install directory, or an `fcntl` lock
that needs the running binary open for writing, which Linux refuses).

A window running when its binary is replaced keeps its inode and its old
code ("A chord already running keeps …" stays true), but starts new agents
through `Platform.resolvedExecutable --chord-group-exec`, now the new
binary. That already holds after npm and Homebrew upgrades; pinning the
launcher as a cross-version contract is CTUI-150.

### Signals

As U2, no signal handler, with one exception. SIGINT, SIGTERM or SIGHUP
before the rename kill chord by the signal's default action; Dart `finally`
blocks do not run, so a `chord-upgrade-*` directory in the system
temporary directory and a hidden `.chord.upgrade-<random>` beside the
binary may remain. They are documented, not swept: a sweep by pid or age
cannot prove ownership and would widen what a root-run upgrade deletes. A
signal after the rename leaves the upgrade done. The exception is the
smoke run: its child leads its own session, so the terminal's SIGINT does
not reach it. During the smoke run only, chord watches SIGINT, SIGTERM and
SIGHUP; on one it SIGKILLs the child's group, deletes the staging file and
re-raises, as `platform/signals.dart` does.

### The smoke run

Through `spawnGroup` (`lib/platform/process.dart`) with its own
`ProcessGroups`, environment `{PATH, HOME}` only, cwd the private
temporary directory, stdin closed. One 30 s deadline from before the start
until the exit and both pipes' end; at most 64 KiB of stdout and stderr
together. On deadline or cap: SIGKILL the group, cancel both
subscriptions, wait up to 2 s, require `kill(-pid, 0)` to answer ESRCH.
Pass only exit 0 with stdout exactly `chord <to>\n`. It runs after every
integrity check, so it runs only code as trusted as what is about to be
installed; it catches the wrong platform, a broken snapshot, the
hardened-runtime SIGKILL of a Dart binary signed without
`allow-unsigned-executable-memory`, and an old genuine release served as a
new one.

### Network

- Bases `https://api.github.com/` and `https://github.com/` are compiled
  defaults (`String.fromEnvironment`), never read from the environment;
  `githubRepo` from `distribution.dart`.
- No token is read or sent (`GH_TOKEN`, `GITHUB_TOKEN`, `GH_HOST` and
  `GITHUB_API_URL` are ignored). The repository is public; the rate-limit
  message names the reset time.
- Headers: `User-Agent: chord/<version>` on every request; `Accept:
  application/vnd.github+json` and `X-GitHub-Api-Version: 2022-11-28` on
  API reads only.
- Redirects followed by hand, at most 5, a hop to another scheme refused;
  no host allow-list (GitHub has renamed its asset host before; integrity
  comes from the checks, not the host).
- No timer on reads or downloads: Q367 ("as the original, no timeout")
  carries over; Ctrl+C is the person's timeout. Only the smoke run, a
  local child, is bounded.
- `HTTPS_PROXY` honoured, as people behind proxies need; TLS stays end to
  end.

### Packages

| Package | Use | Finding |
| --- | --- | --- |
| `http` (already) | list and downloads | fits; `github` 9.26.0 does not fit as it is (Q382) |
| `crypto` (already) | sha256 while streaming | fits; 30 MiB in ~150 ms |
| `archive` 4.7.1, pinned exactly | gzip inflate with `maxOutputSize`, tar entries | fits with the `files.last` reliance (Q383); its `ArchiveFile.isFile` is true for FIFOs and devices, so the type comes from `TarFile.typeFlag` |
| `posix` 6.5.4 (arrives with `archive`) | `stat` uid/gid, `geteuid`, `getegid`, `chmod`, directory `fsync` | fits; match `PosixException.code`, never its text |
| `cryptography` 2.9.0 | U5 only: Ed25519, BLAKE2b-512 | matches minisign 0.12 on every vector under AOT (as do `pinenacl` 0.6.0 and `ed25519_edwards` 0.3.2) |
| system `tar` | not used | two flavours, a process per upgrade |

## Threats

Assets: the person's chord and what it later runs with their privileges.

| # | Threat | What the design does | Residual |
| --- | --- | --- | --- |
| T1 | MITM | `https` bases compiled in, system roots, redirects never change scheme | CA mis-issuance |
| T2 | Corrupt or truncated download | byte count vs `Content-Length` and the listed size; sha256 vs SHA256SUMS before parsing | none |
| T3 | Someone who can write the release replaces archive and SHA256SUMS | darwin: pinned code requirement (Developer ID anchor, Team ID `YQ8ZD2KZ3T`, identifier `dev.katsuba.chord`, from the signing constants), so a GitHub account alone cannot forge it. Linux: nothing, unless Q381 (c)/(d) | Linux as safe as the GitHub account until Q381 |
| T4 | Replay: an old genuine release served as new | the smoke run must print `chord <to>`; under Q381 (c)/(d) the signed trusted comment names the tag (archive names carry no version) | a genuine old binary passes codesign: signer authentication is not freshness |
| T5 | Downgrade | bare upgrade takes the highest version on its channel, never GitHub's date-based flag | a release writer deleting newer releases (T3's attacker) |
| T6 | Draft or pre-release taken for stable | drafts dropped; stable requires both `prerelease == false` and no channel | none |
| T7 | Wrong platform | asset from `runningMachine()`, `machineOfBinary`, the smoke run | none |
| T8 | Path traversal, links, devices, FIFOs, extra members | nothing extracted by name; type `'0'`/NUL only, exact names once, only `chord`'s body written into a file chord made | depends on Q383 |
| T9 | Decompression bomb, metadata flood | 64 MiB compressed, 260 MiB inflated (measured: a 1 GiB pax flood cut in 0.4 s at 11.7 MB RSS), per-entry and count caps | a matching-sum flood wastes under a second of CPU |
| T10 | Another local user tampering with staging or target | owner must be the effective user; directory not writable by others (sticky excepted) or by a foreign group; staging created exclusively and written through its handle | ancestor directories and ACLs are trusted: whoever can write them can replace chord anyway |
| T11 | Hostile environment | no token or base variable read; `/usr/bin/codesign` by absolute path; smoke run gets `{PATH, HOME}` | `HTTPS_PROXY` (T1 holds) |
| T12 | Interruption | everything before the rename is temporary files; rename atomic; file `fsync`ed first | leftovers after a signal, documented |
| T13 | Running downloaded code (smoke run) | only after sums, codesign and (Q381) signature | Linux without Q381: T3 one step earlier |
| T14 | Running as root (`sudo chord upgrade`) | no `chown`, no setuid bits, owner must match; the download and smoke run then run as root | the person chose root |

SHA256SUMS alone is a corruption check; on Linux it is the only check until
Q381 is answered. Signer authentication (T3), archive-to-tag binding (T4,
Q381 c/d), freshness (T5) and corruption (T2) are separate guarantees and
the table names which mechanism gives each. `spctl` and
`codesign --check-notarization` are not gates: the bare Mach-O is not
stapled, so they are online lookups that fail offline, and Gatekeeper never
assesses chord's own download (no quarantine attribute, measured). GitHub
artifact attestations do not fit: the release builds on the owner's Mac,
and Dart has no maintained Sigstore client.

Q381 option (c), if chosen, specifies U5: files `SHA256SUMS.<KEYID>.minisig`
(ED, `minisign -H`), trusted comment exactly `chord v<to> SHA256SUMS`,
binaries pin `[primary, offline spare]`, the first pinned key whose file
exists must verify (an existing file that fails refuses; no retry into
acceptance), planned rotation by dual signing for at least 12 months and 10
releases, a skipped-bridge fallback to the newest verifiable release above
the running one with a "run again" line, an emergency release signed by
every pinned key after a compromise, and a manual reinstall when every
pinned key is lost. The trial and the full policy are in
`drafts/runtime.md`, "Revision after critic".

## Tests

All over loopback: one fake GitHub per test (`HttpServer.bind(loopbackIPv4,
0)`) serving the listing, `releases/download/…` that 302s to `/assets/…`,
and a request log; clients with `findProxy` returning `DIRECT` (Dart sends
`127.0.0.1` through `http_proxy`); server and client closed with `force:
true` in `tearDown`. Loopback is `http`: it proves the redirect and scheme
logic, not TLS validation, and the design says so.

- U1, pure: stable vs channel picking, flag/channel disagreement, invalid
  and `v`-less tags, drafts, a missing asset, paging at exactly 100, the
  `Link` origin rule, rate-limit mapping from status and headers. Reader:
  request counts per row of the truth table, 403/429, 404, non-JSON, a
  closed port, six redirects, a scheme-changing redirect, headers present
  on API reads and absent on downloads, no `authorization` header ever.
- U2, pure: sums lines (space and `*`, duplicate, missing, upper-case hex
  refused) through the tool's existing tests too; members and caps.
  Archives built in the test with `package:archive`'s encoder and
  hand-written headers, not the release's macOS `tar` argv (which GNU tar
  rejects): FIFO named `LICENSE`, char and block devices, links with empty
  and real targets, pax `path=../chord`, GNU long name, pax `size` above
  the cap, a `g` global header (accepted), `chord/`, a fourth member, a
  missing `NOTICES`, a matching-sum metadata flood and bomb stopped by the
  inflated cap, and a bsdtar-shaped archive with pax headers before every
  member (accepted). `machineOfBinary` on Mach-O and ELF heads. codesign on
  darwin with an ad-hoc binary: refused by the requirement (3), by a byte
  appended (1); argv through a recording runner on Linux.
- U3: real files in temp directories: plain target, a symlink (link kept,
  target replaced, mode kept), a read-only directory (skipped as root), an
  `o+w` directory, a foreign group, a foreign owner, `InstallFs` failing at
  each step before the rename (target bytes unchanged, staging gone) and
  after it (outcome installed, warning printed), two concurrent swaps
  through a barrier. Smoke run with scripted executables: right version,
  other version, exit 3, `kill -KILL $$`, not executable, stdout and
  stderr floods with an injected small cap, a hang with an injected 1 s
  deadline, an exited parent whose descendant holds the pipe, a descendant
  that `setsid`s out (its recorded pid killed by the test), the deadline
  covering the drain; a signal during the smoke run in a child Dart process
  (as `run_app_signal*_test.dart`). Only pids a test started are killed.
- U4: every text pinned; the command through `runCli` with a fake source
  and recording filesystem for every row; npm and Cellar rows still win
  over the stamp; a guard that the release's `compileArgv` adds no define
  but `officialDefine`.
- `compile` tag, `test/upgrade_release_compile_test.dart`: bind the fake
  first; copy `example/chord` into two temporary trees with
  `lib/version.dart` and `pubspec.yaml` edited to an old and a new version
  (Q359's literal stays the source; nothing outside the temp trees
  changes); compile both stamped with the bases as defines pointing at the
  fake and, on darwin, `-Dchord.codeRequirement='identifier
  "dev.katsuba.chord"'`; sign the new one ad hoc with the runtime option,
  entitlements and that identifier; archive it in the contract's layout
  with SHA256SUMS; install the old one behind a symlink; run `<link>
  upgrade` with a minimal environment; assert the lines, the link kept, the
  bytes, mode 0755, the new `--version`, the request log. On darwin a
  second case without the requirement define refuses the ad-hoc binary
  and leaves the old bytes.

## Differences from the original and from U2

| Difference | Reason |
| --- | --- |
| A release binary replaces itself | Q366 (a); the original ships only through npm |
| cliffy's binary-path words, which the original never reaches | the nearest original words for these rows |
| Target spelt `darwin-arm64`, not `darwin-aarch64` | the archive's spelling, printed beside the asset |
| Not-found URL `…/releases`, not the repository root | where releases are listed |
| One list read for bare upgrade, not two | GitHub's 60 reads an hour; same answer |
| `latest` is the highest version, not a dist-tag | GitHub has no tags to move; its own flag goes by date |
| sha256, signature, smoke, state and refusal sentences | cliffy checks no sum and says nothing of the old binary |
| Owner, group and shared-directory refusals; no `chown`, no setuid bits | T10, T14 |
| One signal handler, during the smoke run only | the child leads its own session |
| No `-o/--output` | Q384 (recommended) |

## Critic findings

Thirteen findings; all accepted, two after a second trial.

- 1, 2 (archive type and caps): accepted. Framework re-measured: the type
  is visible only as `TarDecoder.files.last` inside the callback; with it
  every hostile fixture is refused, and inflating first with
  `maxOutputSize` bounds metadata floods. The reliance went to the owner
  (Q383) rather than being called a fit.
- 3 (root `chown` before verification): accepted, resolved more strictly:
  a foreign owner is refused even as root, there is no `chown`, the
  staging file is written through its own handle, and shared directories
  are refused; ancestors and ACLs are stated as trusted.
- 4 (work after the rename): accepted: the commit point above.
- 5 (immutable under `--force --version`; replay vs signer): accepted:
  trust checks are never bypassed (one read by tag under Q381 b/c/d), and
  the four guarantees are named apart.
- 6 (post-rename inode check): accepted: dropped; last writer wins, said
  honestly. The lock is rejected on cost, not as a marker file.
- 7 (signals): accepted: one contract, default death plus the smoke-run
  handler; leftovers documented, not promised cleaned.
- 8 (truth table, `latest`): accepted: one table and one transcript above.
  Rejected in part: a `latest` lower than the running version follows
  cliffy, so no departure needs the owner.
- 9 (smoke bounds): accepted: deadline over drain, output cap, group kill.
- 10 (compile test versions; TLS): accepted: temporary tree copies; TLS
  evidence boundary stated.
- 11 (macOS tar flags in Linux tests): accepted: fixtures by the encoder.
- 12 (minisign readiness, rotation): accepted: verifier trialled against
  real minisign vectors; rotation policy written; still gated on Q381.
- 13 (stale-file sweep): accepted: no sweep.

Side findings filed: CTUI-150 (the `--chord-group-exec` launcher as a
cross-version contract) and CTUI-151 (release archives record the
`com.apple.provenance` xattr in pax headers; `--no-xattrs` drops it).

# CTUI-143 framework draft: release list, verification, the swap

Answers questions 1 to 3 of the brief: where versions come from on a
release binary, how a download is checked and unpacked, and how the file
chord runs from is replaced. Everything sits in the port
(`example/chord/lib/`); nothing in `lib/`. Interfaces are pure functions
plus three injected seams: the HTTP client and base `Uri`s (as
`RegistryReader`), and an install filesystem for the swap.

## Measured and tried

All trials ran in a scratch directory outside the repository, compiled
with `dart compile exe` (Dart 3.13.5, darwin-arm64), against loopback
servers and fixture archives built with the release's own `tar` flags
(`--uid 0 --gid 0 --uname root --gname root --no-mac-metadata -czf`), a
30 MiB random `chord`. No GitHub request was made.

### Packages

| Package | Version | AOT | Finding |
| --- | --- | --- | --- |
| `crypto` | 3.0.8 (already a dependency) | yes | `sha256.bind(file.openRead())` over 30 MiB: 152 ms; chunked conversion lets the download hash as it writes. |
| `archive` | 4.7.1 | yes | `GZipDecoder().decodeLazy(InputFileStream)` into `TarDecoder().decodeStream(verify: true, keepEntries: false, callback:)` streams; every header comes with name, size, mode, uid and link flags before any content is read. Extracting `chord` with `writeContent(OutputFileStream)`: 25 ms. Pulls in `path` and `posix`. Details below. |
| `posix` | 6.5.4 (comes with `archive`) | yes | `chmodWithMode`, `chown`, `stat` (uid, gid), `geteuid`, `link`, `fsync` work. Its `chmodWithMode` keeps only the low nine bits (drops setuid, which suits), and its chmod error text says "chown failed": match `PosixException.code` (errno), never the message. |
| `github` | 9.26.0 | yes | Pages `GET /repos/{repo}/releases` by `Link: rel="next"`; endpoint and `http.Client` injectable. Does not fit as it is, below. |
| system `tar` | bsdtar / GNU tar | n/a | Not chosen: two flavours with different link and `..` handling, a process per upgrade, and a member check would still be ours. |

`archive` 4.7.1 against hostile fixtures (all through the lazy path):

| Fixture | What the decoder reports |
| --- | --- |
| release-shaped | `chord` 0755 31457280 uid 0, `LICENSE` 0644, `NOTICES` 0644 |
| symlink member `link -> /etc/passwd` | `isFile == true` **and** `isSymbolicLink == true`, `symbolicLink` set |
| hard link member | `isFile == true`, `isSymbolicLink == true`, `isHardLink == true` |
| `../chord`, `/tmp/NOTICES` | names kept verbatim; nothing is sanitised |
| directory member `d/` | `isFile == false` |
| 2 GiB of zeros in 2 MB (bomb) | header size 2147483648 reported before inflation; refusing by header size: 30 ms. Without refusing, the headers-only pass inflated all of it in 539 ms without holding it in memory. |
| archive built without `--no-mac-metadata` | an extra `._chord` AppleDouble member |
| truncated gzip, junk | `ArchiveException` (`gzip: unexpected end of input`, `Invalid gzip data`) |
| CRC bytes zeroed, a flipped byte inside `chord` | **accepted**: the lazy path checks neither the CRC nor the content |

So: a link is told by `isSymbolicLink`/`isHardLink`, not by `isFile`; names
must be checked by us; and the archive may be parsed only after its sha256
has matched SHA256SUMS, which is what catches corruption. Peak RSS of the
header pass over the 30 MiB archive: 116 MB; the implementation should
re-measure and may cap it (open question F4).

The `github` package does not fit as it is:

- A 403 or 429 with `x-ratelimit-remaining: 0` comes out as `UnknownError`
  with an empty message: the rate-limit facts runtime's question 8 needs
  are lost.
- `handleStatusCode` does `response.headers['content-type']!`: an error
  answer without a content type throws a `TypeError` (an `Error`, which
  `runUpgrade`'s `on Exception` does not catch).
- The `Release`/`ReleaseAsset` models have no `digest` and no `immutable`.
- The User-Agent is fixed to `github.dart`; `X-GitHub-Api-Version` is sent
  on `getLatestRelease` but not on the paged list.
- No `per_page`: 30 releases a page.

### This Mac (darwin-arm64, APFS)

Two ad-hoc signed, hardened-runtime binaries with the port's entitlement
(`v1`, `v2`), replaced through Dart's own `File` API:

| Case | Result |
| --- | --- |
| Write `v2` to a new file beside a running `v1`, chmod, `renameSync` over it | the running `v1` finishes normally; a new exec of the path runs `v2`; `codesign --verify --strict` passes |
| `cp v2` over the path **in place** while `v1` runs | the next exec of the path is **SIGKILLed (137)** |
| In-place write after `v1` exited | ran; not relied on |
| Extended attributes of the file Dart wrote | only `com.apple.provenance`; no `com.apple.quarantine`, so Gatekeeper never assesses it |
| Mode of a new file | 0644 (umask); kept by rename, so it must be set |
| `rename` onto a symlink | replaces the link with a regular file; the link's target untouched |
| Directory 0555, file 0755 | creating the staging file fails `Permission denied, errno = 13` before anything changes; the file itself is still writable in place (never used) |
| Old 0750 carried to the new file by chmod; `File.copySync` | 0750 both |
| The running process after the swap | `Platform.resolvedExecutable` still names the path, now the new binary (see "Needs from runtime") |

Linux was not measured here (no container daemon running). There a write
open of a running executable fails `ETXTBSY`; `rename(2)` over it does not.
The design never opens the target for writing, so neither platform's
in-place hazard is reachable; the Linux CI target runs the swap tests.

## 1. The release list and which release is `latest`

### Options

| Read | Gives | Against |
| --- | --- | --- |
| A. `GET {api}/repos/{repo}/releases?per_page=100`, paged by `Link: rel="next"` | every published release: tag, `draft`, `prerelease`, assets (name, size, download URL, digest) | rate limit 60/h unauthenticated; pages |
| B. `GET …/releases/latest` | GitHub's latest: newest non-draft, non-prerelease by date unless the release set `make_latest` | no channels, no `-l`, a backport published later becomes latest |
| C. `GET …/releases/tags/v<v>` | one release | only for a known version |
| D. `{github}/{repo}/releases/download/v<v>/<asset>` (and `/releases/latest/download/…`) | the file, no API, no API rate limit | no list, no channel latest, no `-l` |

### Recommendation

A for every listing and every `latest`, D for every download. One list read
yields the whole `Versions` (`-l`, the not-found hint, `latest` of the
running channel) and the assets of each release, so a missing asset is
refused before anything is downloaded. Downloads always go to the
constructed URL `{download}/{repo}/releases/download/v<to>/<name>` (the
same as `browser_download_url`), so `--force --version <v>` keeps U2's
zero list reads and needs no API at all. B and C are not used.

The reader is memoised per invocation: bare `chord upgrade` reads the list
once, not twice as U2's npm path does (cliffy asks the provider twice). A
second read costs a sixtieth of the hourly limit and could disagree with
the first. Whether the test counts follow U2 or this is runtime's
(question 8) and interface's call; the reader supports both.

| Call | List reads | Downloads |
| --- | --- | --- |
| `-l` | 1 (pages) | 0 |
| bare, already latest | 1 | 0 |
| bare, newer exists | 1 (U2: 2) | SHA256SUMS, archive |
| `--version <v>`, not listed / running | 1 | 0 |
| `--version <v>`, listed | 1 | 2 |
| `--force` | 1 | 2 |
| `--force --version <v>` | 0 | 2 |

### Which releases count

From each page, a release is kept when:

- `draft` is false (the API shows drafts only to a token with push access,
  but a token may be in use);
- its tag is `v` followed by a version `node_semver.valid` returns
  unchanged (`v1.2.3`, `v1.2.3-next.4`); tags without `v`, with build
  metadata, or not npm semver are dropped, never guessed at;
- for a channel version, `channelOf` does not throw.

`-l` lists every kept version, through `formatVersions` as today.
`--version <v>` accepts any kept version, as npm accepts any published one.

`latest`:

- **Stable build** (`channelOf(running) == null`): the highest semver kept
  release with `prerelease == false` and `channelOf(version) == null`. Not
  GitHub's latest flag: the list does not carry it, and by date a later
  backport would downgrade. In the port's release flow (stable only from
  `main`) the highest is also the last published, which is what npm's
  `latest` names.
- **Channel build**: the highest kept release with `channelOf(version) ==
  channel` and `prerelease == true`. It does not move to a later stable:
  npm's `<channel>` tag never does (the release publishes a stable without
  `--tag`), and the GitHub path should agree with the npm path for the
  same binary. A person moves to stable with `--version <stable>`.
- A release whose `prerelease` flag disagrees with `channelOf` (a release
  tool slip or a hand edit) is listed but never `latest` of anything.
- No kept release for the stable line: `ReleaseError('there is no stable
  release')`; for a channel: `ReleaseError('it has no release on channel
  <c>, the channel this chord is on')`, the counterpart of the npm text.

An asset missing on the chosen release is **not** skipped to an older one
(that would print "already latest" on a broken release): the upgrade stops
naming the release and the asset. The same for a missing `SHA256SUMS`.

Pages: `per_page=100`; follow `rel="next"` only to the same scheme, host
and port as the API base (a `Link` header cannot send the reader, or a
token, elsewhere), at most 10 pages (1000 releases); more is an error
rather than a silent truncation. One page is about 5 KB per release.

### Interface

```dart
// example/chord/lib/releases.dart

/// A published release of chord as the GitHub list gives it.
final class Release {
  const Release({
    required this.version,
    required this.prerelease,
    required this.assets,
  });

  /// The version of tag `v<version>`, valid npm semver.
  final String version;

  /// GitHub's pre-release mark.
  final bool prerelease;

  /// Asset name to its size in bytes and GitHub's `sha256:` digest if any.
  final Map<String, ({int size, String? digest})> assets;
}

/// Why the release list could not be read or used, in chord's words.
final class ReleaseError implements Exception { … final String message; }

/// The kept releases of one page body; throws [ReleaseError] when the body
/// is not a JSON array of release objects.
List<Release> parseReleases(String body);

/// The next page's URI from a `Link` header, only on [base]'s origin;
/// null when there is none.
Uri? nextPage(String? link, Uri base);

/// `latest` of [channel] (null for stable) among [releases]; throws
/// [ReleaseError] when there is none.
Release pickLatest(List<Release> releases, String? channel);

/// The [Versions] of a release binary running [running].
Versions releaseVersions(List<Release> releases, String running);

/// The download URL of [asset] on release [version].
Uri assetUrl(Uri download, String version, String asset);

/// The GitHub list behind [VersionSource]: one memoised read.
class ReleaseReader implements VersionSource {
  ReleaseReader({
    required http.Client client,
    required String running,
    Uri? api,       // https://api.github.com/
    Map<String, String> headers = const {},  // runtime's: UA, Accept, token
  });
  @override
  Future<Versions> read();
  /// The releases of the last read, for the asset check.
  Future<List<Release>> releases();
  @override
  void close();
}
```

`runUpgrade` takes the reader through the existing `OpenVersions`; the CLI
picks `ReleaseReader.open` instead of `RegistryReader.open` when the binary
is official and no npm or Cellar row matched. This needs the realPath
before the source opens (today `_upgrade` opens the source first): a small
reorder in `cli.dart`.

## 2. SHA256SUMS, the archive and what is extracted

### Order

1. Download `SHA256SUMS` (small; cap 64 KiB) and look up
   `chord-<machine>.tar.gz`.
2. Download the archive into a fresh `Directory.systemTemp.createTemp`
   (mode 0700), hashing while writing, with a byte cap: the list's asset
   size if known, and never more than 256 MiB.
3. Compare the hash with the recorded one. **Nothing parses the archive
   before this matches.**
4. Read the headers and extract `chord` into the staging file (section 3),
   checking the members as they come.
5. Check the members as a whole, then the binary's machine.

### Sums

One parser shared with the release tool, moved out of
`tool/release/archive.dart` into `example/chord/lib/sums.dart` (the tool
already imports `package:chord/distribution.dart`):

```dart
// example/chord/lib/sums.dart

/// The file the sums are recorded in.
const sumsFile = 'SHA256SUMS';

/// One line of sha256sum's output: 64 lower-case hex, a space, a space or
/// `*`, the name.
final sumLine = RegExp(r'^([0-9a-f]{64}) [ *](.+)$');

/// The sums [text] records for [name]: empty, one, or several.
List<String> sumsOf(String text, String name);

/// Why a SHA256SUMS cannot be used, in chord's words.
final class SumsError implements Exception { … }

/// The one sum [text] records for [name]; strict for a downloaded file:
/// any non-empty line that is not a sum line, no line for [name], or two
/// lines for [name] throws [SumsError].
String recordedSum(String text, String name);
```

`checkSum` in the tool keeps its behaviour through `sumsOf` (no sum, two
sums, mismatch; garbage lines ignored as today). The upgrade uses the
strict `recordedSum`: the release writes exactly one line per archive, so
anything else is not a SHA256SUMS of this release. Names are compared
whole; a name with a `/` cannot match `chord-<machine>.tar.gz`. Lower-case
hex only, as `recordSums` writes and sha256sum prints.

### Members

Pure, over what the tar decoder reports:

```dart
// example/chord/lib/release_archive.dart

/// One tar header as the upgrade checks it.
final class Member {
  const Member({
    required this.name,
    required this.regular,   // isFile && !isSymbolicLink && !isHardLink
    required this.size,
    required this.mode,
  });
  final String name;
  final bool regular;
  final int size;
  final int mode;
}

/// Why an archive is not the release's, in chord's words.
final class ArchiveRefused implements Exception { … }

/// The archive contract: exactly `chord`, `LICENSE` and `NOTICES`, each
/// once, each a regular file at the top (no `/`, no `..`, no leading `/`),
/// `chord` 0755 and at most [maxBinary] bytes, nothing else (no
/// directories, links, devices or `._` members). Throws [ArchiveRefused].
void checkMembers(List<Member> members, {int maxBinary = 256 << 20});

/// Refuses one header as soon as it is seen, before its content is read:
/// any name outside the contract, any non-regular entry, a `chord` above
/// [maxBinary]. The decoder never inflates a bomb's body.
void checkMember(Member member, {int maxBinary = 256 << 20});

/// The `<os>-<cpu>` a binary's first 20 bytes say it is for: a 64-bit
/// Mach-O (magic 0xfeedfacf, cputype arm64 0x0100000c or x86_64
/// 0x01000007) or a 64-bit little-endian ELF (e_machine 0xB7 or 0x3E);
/// null for anything else.
String? machineOfBinary(List<int> head);
```

Extraction itself (`extractChord(File archive, RandomAccessFile into)`) is
the one place `package:archive` is used: the lazy gzip, the tar decoder
with `verify: true`, `checkMember` in the callback, `chord`'s content
written into the staging file, `checkMembers` on the full list at the end.
`LICENSE` and `NOTICES` are read for their headers only. The member mode
is checked, not applied: the installed mode comes from the old file.
`machineOfBinary` against `runningMachine()` refuses the wrong platform's
binary even when its archive was named right.

On darwin, `codesign --verify --strict` (with or without a designated
requirement) runs on the staging file before the swap if runtime and the
owner choose it (question 9); the measurement above shows the embedded
signature survives this write and rename unchanged.

## 3. The swap

### Options

| Way | Atomic | Running binary | Verdict |
| --- | --- | --- | --- |
| Write the new bytes over the target in place | no: a crash leaves half a binary | macOS: next exec SIGKILLed (measured); Linux: `ETXTBSY` | refused |
| `File.copySync(new, target)` | no (in place underneath) | as above | refused |
| Staging file in the target's directory, `rename(2)` over the target | yes | old process keeps its inode (measured) | **chosen** |
| Staging in system temp, rename | `EXDEV` across filesystems | — | refused |
| Rename the old aside, rename the new in, delete the old | two steps, a window with no binary at the path | — | refused |

### The steps

1. **Target.** The real path the install rows already resolve
   (`resolvedExecutablePath()`): a symlink in `PATH` stays a link and its
   target is replaced. Replacing the link itself (measured: rename onto a
   link replaces the link) would leave the real binary old and the link
   gone. A hard-linked binary's other names keep the old inode; accepted.
2. **Plan, before any download.** `stat` the target: its mode, uid and gid.
   The planned staging name is `.<basename>.upgrade-<random>` in the same
   directory. Creating it exclusively (`File.createSync(exclusive: true)`,
   `O_EXCL`, so a planted symlink or file of that name fails rather than
   being followed) and deleting it proves the directory writable; done
   right after the version is chosen, so a person without rights is told
   before 30 MB are fetched. A target owned by another user than the
   effective one is refused (the rename would change its owner) unless the
   effective user is root, who `chown`s the staging file to the old owner.
3. **Stage.** Create the staging file exclusively, extract `chord` into it
   (section 2), set the old mode with the low nine bits only (setuid,
   setgid and sticky dropped: downloaded code is never made setuid),
   `chown` when root, `fsync` the file.
4. **Check.** Machine of the binary; optionally codesign; optionally the
   smoke check (runtime's question 10), all on the staging file, which has
   the final mode and sits on the final filesystem.
5. **Swap.** `rename(staging, target)`: one system call, atomic on POSIX.
6. **Durability.** `fsync` the directory (open read-only, `fsync`), best
   effort: its failure is ignored, as the rename is already visible.

Any failure in steps 2 to 5 deletes the staging file and the temporary
directory; the target was never opened for writing, so the message can say
the installed binary is unchanged without a check. A failed `rename` leaves
the old file (atomicity). After step 5 nothing remains that can fail, so
there is **no rollback and no old copy kept**: the only state a person can
be left in is old (failure, kill before rename) or new (success, kill after
rename). A SIGKILL between 3 and 5 leaves a stale `.chord.upgrade-*` beside
the binary; interface and runtime decide whether a later upgrade removes
stale ones (only those older than a bound, so a concurrent upgrade's file
is spared).

Why not keep the old file for rollback: Dart has no hard-link API
(`posix.link` has), it doubles the disk in the bin directory, and with the
smoke check before the rename there is nothing after the rename to roll
back from.

Directory not writable (root-owned `/usr/local/bin`, a read-only mount,
`EROFS`), out of space (`ENOSPC` while staging), a target that vanished
between plan and rename: all fall into "failure before rename". Cross-
filesystem is unreachable: the staging file is always beside the target.

### What Dart lacks, and from where

| Need | `dart:io` | Taken from |
| --- | --- | --- |
| exclusive create | `File.createSync(exclusive: true)` | dart:io |
| write, fsync file | `RandomAccessFile.writeFromSync`, `flushSync` (fsync on POSIX) | dart:io |
| rename | `File.renameSync` | dart:io |
| stat uid/gid | no (`FileStat` has mode only) | `posix.stat` |
| chmod | no | `posix.chmodWithMode` |
| chown, geteuid | no | `posix.chown`, `posix.geteuid` |
| fsync a directory | no | `posix.open` + `posix.fsync`, or skipped |

`posix` 6.5.4 already arrives with `archive`, is maintained, and works
under AOT (above). The port's own FFI in `lib/platform/` is the
alternative; a package first, per AGENTS.md.

### Interface

```dart
// example/chord/lib/replace.dart

/// Where and how the binary at a real path is replaced.
final class ReplacePlan {
  final String target;     // the real path
  final String staging;    // .<base>.upgrade-<random> beside it
  final int mode;          // old mode & 0x1ff
  final int? chownTo;      // old uid when running as root, else null
  final int? chgrpTo;
}

/// Why the binary cannot be replaced, before anything is written.
final class NotReplaceable implements Exception { … }

/// The plan for [target] whose stat is [uid], [gid], [mode], run as
/// [euid], with [random] naming the staging file; throws [NotReplaceable]
/// for an owner that is not [euid] when [euid] is not 0. Pure.
ReplacePlan planReplace({
  required String target,
  required int mode,
  required int uid,
  required int gid,
  required int euid,
  required String random,
});

/// The filesystem the swap goes through; the real one over dart:io and
/// package:posix, a recording one in tests (EACCES, ENOSPC, a failing
/// rename at each step).
abstract interface class InstallFs {
  ({int mode, int uid, int gid}) stat(String path);
  int euid();
  RandomAccessFile createExclusive(String path);
  void chmod(String path, int mode);
  void chown(String path, int uid, int gid);
  void rename(String from, String to);
  void delete(String path);
  void syncDirectory(String dir);   // best effort
}

/// What became of the installed binary.
sealed class Replaced {}
final class Unchanged extends Replaced { final Object reason; }
final class NowNew extends Replaced {}

/// Steps 3 to 6: [stage] writes the new binary into the open staging
/// file, [check] vets the staged path; any throw before the rename ends
/// [Unchanged] with the staging file deleted.
Future<Replaced> replaceBinary(
  ReplacePlan plan,
  InstallFs fs, {
  required Future<void> Function(RandomAccessFile staging) stage,
  required Future<void> Function(String staged) check,
});
```

`runUpgrade`'s `official` branch then reads: plan (and the writable probe),
download sums, download archive, verify, `replaceBinary` with
`extractChord` as `stage` and machine/codesign/smoke as `check`, print.

## Cost per upgrade

| Step | Cost |
| --- | --- |
| List | 1 to 10 requests of up to ~500 KB JSON; parse linear in releases |
| Pick | O(n log n) over kept releases, n ≤ 1000 |
| Downloads | SHA256SUMS ≤ 64 KiB; archive ~30 MB once, hashed while written (≈150 ms CPU per 30 MiB) |
| Extract | one streaming pass (≈25 ms for 30 MiB), headers refused before content |
| Disk | the archive in temp plus the staging file beside the target: about 2× the binary, both removed on any end |
| Memory | measured 116 MB peak for the header pass; to re-measure and bound in the build |
| Swap | 1 exclusive create, write, chmod, fsync, rename, directory fsync |

Nothing runs per frame: this is a command, not a widget.

## What changes in existing files

- `example/chord/lib/upgrade.dart`: the `official` branch stops at
  `releaseText` today; it calls the release flow instead. `releaseText`
  and `unidentifiedText` wording are interface's (question 7). `_messageOf`
  learns `ReleaseError`, `SumsError`, `ArchiveRefused`, `NotReplaceable`.
  The success line's link for this path is the GitHub release tag, as
  `_brewUpgrade` prints.
- `example/chord/lib/cli.dart` (`_upgrade`): the real path resolved before
  the source opens, so an official, row-less binary opens a
  `ReleaseReader`.
- `example/chord/tool/release/archive.dart`: `sums`, `_sumLine` and the
  lookup in `checkSum` come from `lib/sums.dart`; behaviour unchanged.
- New: `lib/releases.dart`, `lib/sums.dart`, `lib/release_archive.dart`,
  `lib/replace.dart`; `pubspec.yaml` gains `archive` and `posix` (exact
  versions as the port pins its others, per the lead).
- `docs/decisions.md` (lead): the package findings above and the
  "no rollback copy" choice.

## Needs from interface

- The sentence for each failure class this draft defines: list read
  (`ReleaseError` texts above, as prefix plus reason like the registry's),
  no release on the channel, release lacks the asset or SHA256SUMS,
  SHA256SUMS malformed / no line / two lines, sha256 mismatch (both
  hashes?), archive refused (with the reason), wrong machine, not writable
  (path and `sudo` or manual steps, question 6), owner differs, disk full,
  rename failed; each with "the installed binary is unchanged", which this
  design can always say before the rename.
- Whether `-o/--output` exists (question 5). The plan takes any target
  path; an `-o` path that does not exist has no old mode (0755 then) and
  no running-binary concern, and is not symlink-resolved unless decided.
- `-v` lines for list read, each download (size from the list), verify,
  extract and swap.

## Needs from runtime

- Headers for the list read (User-Agent `chord/<version>`, `Accept:
  application/vnd.github+json`, `X-GitHub-Api-Version`), a token or not,
  and that it goes only to the API origin (the `nextPage` origin rule
  above serves this); redirects of downloads to
  `objects.githubusercontent.com` (the `http` client follows them; no token
  may follow).
- Rate-limit and timeout policy (memoised read assumed above).
- Codesign with a pinned Team ID, and the smoke check: if adopted, both run
  in `check`, before the rename.
- **The running chord after a swap execs the new binary.** The port starts
  every agent through itself (`--chord-group-exec`, `lib/platform/
  group_exec.dart`) by `Platform.resolvedExecutable`, which after the
  rename names the new file (measured). An old window then launches agents
  through the new version's launcher. The npm and Homebrew paths already
  have this property; it makes the `--chord-group-exec` frame a contract
  between versions, or the launcher must be reached through the running
  inode. Runtime's question 11 should settle which.
- Concurrency: two upgrades stage under different random names and both
  rename; the last wins, each a verified binary. No lock is proposed.
- Stale staging files and signals (Ctrl+C during download: delete the
  staging file and the temp directory).

## Owner questions

**OWNER F1: the GitHub client.** AGENTS.md: a package that does not fit as
it is goes to the owner. `github` 9.26.0 builds under AOT and pages the
list, but loses rate-limit answers (`UnknownError`, empty message), throws
a `TypeError` on an error answer without a content type, lacks `digest`,
and fixes the User-Agent.

- (a) **Recommended**: no GitHub client; `package:http` (already a
  dependency, as `RegistryReader` uses it) and `parseReleases` over
  `dart:convert`, about the size of `_document`. One endpoint, five
  fields.
- (b) `github` 9.26.0 as it is, accepting its error handling (rate limits
  told as an unknown error; the `TypeError` caught as an `Error`).
- (c) `github` with a fork or patch upstream for the error handling.

No other decision here needs the owner: `archive`, `crypto` and `posix`
fit as they are; `latest` follows the npm path's meaning.

## Open questions (not the owner's)

- F2: memoised list read (1 read for bare upgrade) vs U2's two reads,
  for parity of test counts. Recommended: memoised.
- F3: the caps (SHA256SUMS 64 KiB, archive and binary 256 MiB, 10 pages):
  numbers for runtime to confirm.
- F4: the 116 MB peak of the lazy decoder over a 30 MiB archive: measure
  in the build; if it matters, gunzip with `dart:io`'s `gzip.decoder` into
  a temporary tar and decode that from file.
- F5: whether stale `.chord.upgrade-*` files are removed by a later
  upgrade (runtime and interface).

## Revision after critic

Critic findings 1 and 2, re-measured with `archive` 4.7.1 under `dart
compile exe` (darwin-arm64) against hand-made ustar fixtures. This section
replaces `Member.regular`, the "Order" steps 2 and 4 of section 2, and
open question F4; the rest stands.

### 1. The entry type is the boundary, and it is visible

Critic is right: `ArchiveFile.isFile` (and `TarFile.isFile`) is `typeFlag
!= '5'`, so a FIFO, a device or a link with an empty target passes
`isFile && !isSymbolicLink && !isHardLink`. The `ArchiveFile` handed to the
callback carries no type at all.

The type is visible through public API: `TarDecoder.files` is a public
`List<TarFile>`, and `TarFile` (exported by `package:archive/archive.dart`)
has public `typeFlag`, `filename`, `fileSize` and `nameOfLinkedFile`. With
`keepEntries: true`, 4.7.1's `_add` appends the entry's `TarFile` to
`files` before it calls the callback, so in the callback `decoder.files.last`
is the entry being reported: its header and every metadata header before
it are applied (pax `path`/`size`, GNU long name), its body not yet read
(with `storeData: true` the body is a lazy subset of the stream; the 2 GiB
member of the first trial was refused in 30 ms). An error thrown from the
callback comes out of `decodeStream` as itself (a `StateError` stays a
`StateError`).

The rule: refuse every entry whose `typeFlag` is not `'0'` or `''` (a NUL
type byte parses as the empty string); then the name, the per-name cap and
the count. Results, each fixture `chord`, `LICENSE`, `NOTICES` with one
entry changed:

| Fixture | What the callback sees (`files.last`) | Outcome |
| --- | --- | --- |
| release-shaped | `[0] chord 4096`, `[0] LICENSE`, `[0] NOTICES` | accepted |
| v7, NUL type byte | `[''] chord` | accepted |
| FIFO named `LICENSE` | `[6] LICENSE size 0`, `ArchiveFile.isFile == true` | refused at that entry |
| char device `NOTICES` | `[3] NOTICES size 0`, `isFile == true` | refused |
| block device | `[4]`, `isFile == true` | refused |
| contiguous file `chord` | `[7] chord` | refused (not `0`) |
| symlink, empty target | `[2] LICENSE link ""`, `isSymbolicLink == false` | refused by type |
| hard link, empty target | `[1] LICENSE link ""`, `isSymbolicLink == false` | refused by type |
| hard link to `chord` | `[1] LICENSE link "chord"` | refused |
| pax `x` with `path=../chord` | `[0] "../chord"` (the pax name applied) | refused by name |
| pax `x` with `size=314572800` | `[0] chord size 314572800` | refused by cap, body unread |
| GNU `L` long name `../chord` | `[0] "../chord"` | refused by name |
| pax `g` global `path=../evil` | `[0] chord`, names unchanged | accepted (globals do not rename) |
| `chord/` as type `0` (v7 directory) | `[0] "chord/" isFile false` | refused by name |
| pax record over 1 MiB | never reaches the callback | `ArchiveLimitException` from the decoder |

Metadata headers (`x`, `X`, `g`, `G`, `L`, `K`) are consumed by the decoder
and never reach the callback, so they cannot be refused one by one. They
must not be: **the release's own archives carry them.** `tar` with
archive.dart's flags (`--uid 0 … --no-mac-metadata`, bsdtar 3.5.3 on this
Mac) writes a pax `x` header `PaxHeader/chord` before each member, holding
`mtime=…`, `LIBARCHIVE.xattr.com.apple.provenance=…` and
`SCHILY.xattr.com.apple.provenance=…`. Any reader the upgrade uses has to
accept pax headers and ignore their unknown records. (A side finding for the
release tool, not this design: `--no-mac-metadata` does not stop the
provenance xattr from being recorded; `--no-xattrs` would.)

The caveat: that `files` is appended before the callback runs is 4.7.1's
behaviour, not documented API. It is held by pinning `archive: 4.7.1`
exactly and by the FIFO and device fixtures above as tests: if a later
version called the callback first, `files.last` would be the previous entry
and the FIFO test would accept, failing.

### 2. One set of caps, and what bounds metadata

| Cap | Enforced by | Where |
| --- | --- | --- |
| compressed archive ≤ 64 MiB and ≤ the listed asset size | our download loop counting bytes | before the sum, before any parsing |
| inflated tar ≤ 260 MiB (256 + 2 × 1 MiB + headers) | `GZipDecoder().decodeStream(…, maxOutputSize:)` | after the sum matches |
| `chord` ≤ 256 MiB, `LICENSE` and `NOTICES` ≤ 1 MiB each, by header size (after pax `size`) | the callback | before the body |
| at most 3 regular entries, each name once | the callback | at the 4th |
| each metadata record ≤ 1 MiB; a GNU sparse map ≤ 1 MiB | the package (`TarFile.maxMetadataSize`, `ArchiveLimitException`) | while parsing |
| count of metadata records | nothing in the package | bounded only by the inflated cap |

Metadata floods with matching sums (the sum of `paxflood1024.tar.gz` was
taken and would match its SHA256SUMS line; parsing is what is measured),
decoded fully through the lazy path with no cap:

| Fixture | Compressed | Metadata inflated | Time | Peak RSS |
| --- | --- | --- | --- | --- |
| 1 pax `x` of ~1 MiB | 1.3 KB | 1 MiB | 1 ms | 20 MB |
| 64 pax `x` of ~1 MiB | 71 KB | 64 MiB | 33 ms | 104 MB |
| 1024 pax `x` of ~1 MiB | 1.1 MB | 1 GiB | 353 ms | 114 MB |
| one `x` of 1 MiB of `k=v` records | 1.8 KB | 1 MiB | 6 ms | 23 MB |
| 1024 pax `g` of ~1 MiB | 1.1 MB | 1 GiB | 302 ms | 92 MB |
| 100000 GNU `L` headers | 629 KB | 49 MiB | 138 ms (then refused by name) | 48 MB |

Memory stays flat (the decoder keeps one record at a time; the ~100 MB is
the lazy decoder's window), time grows with inflated metadata at about
0.35 s per GiB. At the 1000:1 ratio of these fixtures a 64 MiB archive
could hold some 60 GiB of metadata, about 20 s of CPU: a nuisance, not a
memory exhaustion, but unbounded by the package's lazy path, whose
`decodeLazy` takes no limit.

The bound, as the package is: inflate first with the public
`GZipDecoder().decodeStream(InputFileStream(archive),
OutputFileStream(tar), verify: true, maxOutputSize: 260 << 20)` into the
0700 temporary directory, then decode the tar from `InputFileStream(tar)`
(random access, so the tar pass stays lazy over the file). Measured: the
1 GiB flood stops at the cap with `ArchiveLimitException` (`The decoded
data is larger than the 272629760 bytes allowed`) after 396 ms, peak RSS
11.7 MB; the release-shaped archive inflates in under 1 ms. This bounds
every metadata count, the bomb (now cut at 260 MiB, ~0.4 s, instead of
refused by its header) and replaces F4: the 116 MB lazy-window peak is
gone from the gzip stage. Cost: a temporary tar of the inflated size
(~30 MB for a real release, never above 260 MiB), deleted with the
directory.

So section 2's order becomes: download with the compressed cap → sum →
inflate with the inflated cap → tar pass with the type/name/size/count
checks in the callback, `chord`'s body written into the staging file →
`checkMembers` on the whole → `machineOfBinary`.

### Interfaces changed

```dart
/// One tar entry as the upgrade checks it, from TarDecoder.files.last.
final class Member {
  const Member({
    required this.name,
    required this.type,   // TarFile.typeFlag: '0' or '' is a regular file
    required this.size,   // TarFile.fileSize, pax size applied
    required this.mode,
  });
  final String name;
  final String type;
  final int size;
  final int mode;
}

/// The caps, one set, used by the download, the inflate and the members.
abstract final class ArchiveCaps {
  static const compressed = 64 << 20;  // and the listed asset size
  static const binary = 256 << 20;
  static const text = 1 << 20;         // LICENSE, NOTICES
  static const inflated = binary + 2 * text + (2 << 20);
  static const entries = 3;
}

/// Inflates [archive] into [tar], at most [ArchiveCaps.inflated] bytes;
/// throws [ArchiveRefused] above it or on a bad gzip stream.
void inflate(File archive, File tar);

/// The tar pass: [checkMember] on each entry before its body, `chord`
/// written into [staging], [checkMembers] at the end.
void extractChord(File tar, RandomAccessFile staging);
```

`checkMember` refuses, in this order: a type other than `'0'` or `''`, a
name outside `chord`/`LICENSE`/`NOTICES` (which covers `/`, `..`, a
trailing `/` and `._`), a repeated name, a size above its cap, a fourth
entry. `checkMembers` then requires all three present and `chord` 0755.

### Does the package fit as it is

Yes, by this measurement: (1) every non-regular entry is refused before
its body through public `TarDecoder.files` and `TarFile.typeFlag`; (2) every
size and count is bounded by the public `maxOutputSize` and the callback.
No wrapper and no own reader. The one dependence on behaviour rather than
documentation (`files` appended before the callback) is pinned by version
and by tests.

If the lead or critic counts that dependence as a workaround, it goes to
the owner with these options, none picked here:

- (a) `archive` 4.7.1 pinned, as above, the ordering held by tests.
- (b) A thin wrapper driving the package's public `TarFile.read` and
  `TarMetadata` in our own loop, so the type is checked in our code
  rather than through `files.last`.
- (c) Our own reader of ustar plus pax `x`/`g` (records ignored except
  `path`, `size`, which are refused or applied), about 150 to 250 lines
  with tests; it must accept the pax headers bsdtar writes.
- (d) The system `tar` (`-t` to list types, then `-x` of the three names),
  bsdtar on macOS and GNU tar on Linux, with their differing listings.

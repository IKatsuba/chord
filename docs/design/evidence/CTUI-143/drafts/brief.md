# CTUI-143 brief: `chord upgrade` replaces an official release binary

Worktree: `chorded-tui-worktrees/CTUI-143`, branch `CTUI-143` from main
876fe80c. Parent design: `docs/design/CTUI-102.md` (U2, U3, U4) and its
decisions entries. Merged code: `example/chord/lib/upgrade.dart`,
`lib/distribution.dart`, `lib/cli.dart` (`_upgrade`, ~l.1300),
`tool/targets.dart`, `tool/release/build.dart` (`officialDefine`),
`tool/release/archive.dart` (sums, members).

## The problem

The owner answered Q366 (a): on a binary installed from GitHub Releases,
`chord upgrade` downloads the new release, verifies it and replaces itself.
Today such a binary (built with `--define=chord.official=true`, matched by
no npm row and no Cellar row) reaches `runUpgrade`'s `official` branch and
stops with `releaseText`: "A release binary is replaced by
chord-<os>-<cpu>.tar.gz from …, checked against its SHA256SUMS." The
interim refusal becomes the real upgrade.

Owner facts, settled (do not reopen):

- Releases live in `IKatsuba/chord`, tag `v<version>`, assets
  `chord-<os>-<cpu>.tar.gz` (members `chord` 0755, `LICENSE`, `NOTICES`),
  `SHA256SUMS` beside them in sha256sum format. Pre-releases are drafted
  `--prerelease` exactly when the version has a channel (Q358/`channelOf`).
- Detection order (Q365): npm rows, then Homebrew Cellar, then the official
  stamp = GitHub Releases, otherwise self-built (Q369 line). No marker file.
  Every release binary carries the stamp, including the ones inside npm
  packages and the Homebrew archive; the order is what tells them apart.
- Homebrew carries stable only (Q371). No timeout on the npm read (Q367;
  whether that carries to GitHub reads is an open question below). Plain
  text (Q368). Message only, no stack (Q370).
- darwin binaries are signed (Developer ID, hardened runtime, entitlement
  `allow-unsigned-executable-memory`) and notarised but not stapled (bare
  Mach-O). Linux binaries are unsigned.
- The original (`../chord`) has no such path: it ships only through npm.
  This is a port-only feature; the words and the truth table should stay
  as close to cliffy's `upgrade` (U2) as the new source allows.

## What a person sees and types

Same command, same help, same options (`-l`, `--version`, `-f`, `-v`). On
a release binary:

- `chord upgrade`: reads the releases, finds the newest for its channel,
  downloads its archive and SHA256SUMS, checks, replaces the file it runs
  from, prints `A chord already running keeps <from> until it is started
  again.` and `Successfully upgraded chord from version <from> to <to>!
  (https://github.com/IKatsuba/chord/releases/tag/v<to>)`.
- `chord upgrade -l`: versions from GitHub Releases (not npm), the running
  one marked, through `formatVersions`.
- `chord upgrade --version <v>`, `-f`: as U2's truth table, against the
  release list.
- Failures say what failed and that the installed binary is unchanged (or,
  if not provably unchanged, exactly what state it is in).

## Constraints

- Hard rules: nothing published or pushed; no test reads the real GitHub
  API or downloads anything real; loopback servers only
  (`HttpServer.bind(loopbackIPv4, 0)`), base URLs and clients injected, as
  `RegistryReader` is. Nothing reaches an agent runtime.
- Packages first for what is not the terminal (AGENTS.md): `package:http`,
  `package:crypto` and `package:archive` (or the system `tar`) are
  candidates; a GitHub client package must be tried and the finding
  recorded. A package that does not fit as it is goes to the owner.
- Port only: everything under `example/chord/`; nothing in `lib/`.
- Logic reachable by tests: pure functions for release picking, sums
  parsing, archive member checks, replace planning; I/O behind injected
  interfaces (a `ReleaseSource` beside `VersionSource`, a filesystem seam
  for the swap).
- Must work under `dart compile exe` on darwin-arm64, darwin-x64,
  linux-x64, linux-arm64.

## Non-goals

- Changing the npm or Homebrew paths, or the detection order.
- An installer script, a receipt file, auto-update or update checks at
  startup.
- Windows.
- Publishing a release, signing keys in CI, or changing how the owner
  releases, except where a security answer needs a new release artifact
  (that is an owner question, not a decision here).

## Open questions, by owner

framework (data, parsing, verification, the swap's mechanics):

1. Release list: GitHub REST `GET /repos/{repo}/releases` (paged) vs
   `releases/latest` vs `releases/tags/v<v>` vs the
   `github.com/<repo>/releases/download/v<v>/…` redirect without the API.
   How many reads per row of U2's truth table. Which release is `latest`
   on a stable build (non-prerelease, non-draft, highest semver or
   GitHub's "latest" flag?) and on a channel build (highest pre-release of
   that channel? may a channel move to a later stable?). Versions not
   valid npm semver, tags without `v`, releases missing this target's
   asset.
2. SHA256SUMS parsing and matching (reuse `archive.dart`'s rule, one line
   per name, duplicates refused), archive extraction (tar.gz, members
   exactly the contract, no paths, no links, size limits), which sha256
   package.
3. The swap: temp file in the same directory, `rename(2)` over the real
   path (after resolving symlinks: replace the target, keep the link),
   mode and owner kept, fsync, what happens on a busy text file (Linux
   ETXTBSY does not apply to rename; macOS code-signing cache on in-place
   writes), a root-owned or read-only directory, a different filesystem,
   rollback (keep the old file until the new one is in place?).

interface (what the person sees):

4. Every line printed, per row of U2's truth table, for the release source:
   success, already latest, not found, `-l`, `-v` steps (download size?
   progress? the `$ <argv>` line has no counterpart), each failure.
5. `-o/--output <path>` (Q366's original wording): keep, drop, or owner
   question. Its interaction with symlinks and with the running binary.
6. The not-writable case: refuse with a sentence naming `sudo chord
   upgrade` or the manual steps? Never escalate on its own.
7. What `releaseText` and the unidentified refusal say afterwards.

runtime (processes, network, failure, security, tests):

8. GitHub API: unauthenticated limit (60/h per IP), `GITHUB_TOKEN` /
   `GH_TOKEN` use or not (a token sent only to api.github.com, never to
   the redirect host), User-Agent, `Accept`, API version header, 403/429
   with rate-limit headers, redirects to `objects.githubusercontent.com`.
   Timeouts: Q367 says none for npm; does a 30 MB download follow it?
9. Threat model: name each threat (compromised release/account, MITM,
   tampered SHA256SUMS served beside a tampered archive, downgrade to an
   old vulnerable version, partial download, archive path traversal or
   symlink members, a decompression bomb, TOCTOU in the target directory,
   a hostile `GH_HOST`/`GITHUB_API_URL`/proxy environment, a draft or
   pre-release mistaken for stable, a binary for the wrong platform) and
   what the design does about each. Whether SHA256SUMS alone (same origin
   as the archive) is enough, and what more is possible: on macOS
   `codesign --verify --strict` plus a designated requirement pinning the
   Team ID, `spctl`, notarisation online check; GitHub artifact
   attestations / immutable releases; a minisign/ed25519 signature over
   SHA256SUMS with a key pinned in the binary. Any choice that adds a
   release artifact or changes the release is the owner's: frame it as a
   question with options and a recommendation.
10. A smoke check of the new binary before swapping (`<new> --version`
    prints `chord <to>`): worth it, and its risk (running downloaded code
    before trust is settled).
11. Concurrency: two upgrades at once, an upgrade while chord windows run
    (the running process keeps its inode; ACP servers started from the
    path later get the new one).
12. Tests: loopback GitHub API and download host, fixture archives built in
    the test, a temp install dir (symlink, read-only dir, cross-device not
    reproducible: how covered), the swap on real files, a `compile`-tag
    test that upgrades a compiled stamped binary from a loopback release.

Each architect: answer your questions with the options you considered and
a recommendation, list what you need from the others, and mark anything
that only the owner can decide as **OWNER** with options. Write only your
own draft in `docs/design/evidence/CTUI-143/drafts/`.

# CTUI-143 runtime draft: network, threats, smoke run, concurrency, tests

Author: runtime (architects). Answers the brief's questions 8 to 12. Data
shapes, parsing and the swap's file mechanics are framework's (Q1 to Q3);
words are interface's (Q4 to Q7). Where this draft constrains those, it
says so and lists the need at the end.

## Summary of recommendations

1. GitHub reads: no token, no environment variable read, compiled-in
   `https` bases; one API read per release listing, downloads through the
   non-API `releases/download` host (no API quota); redirects followed by
   hand, scheme never changes; 403/429 with `x-ratelimit-remaining: 0`
   named as the rate limit with its reset time. No timer, as Q367 (owner to
   confirm it carries over).
2. Integrity order: archive streamed to a private temp dir, size-capped,
   sha256 computed while streaming; checked against SHA256SUMS before a
   byte is decompressed; only the `chord` member is ever written, by a name
   chord chooses; on darwin `codesign --verify --strict -R=<Developer ID +
   Team YQ8ZD2KZ3T + identifier dev.katsuba.chord>`; then a bounded smoke
   run `<new> --version` must print `chord <to>`; then `rename(2)`.
3. SHA256SUMS alone protects against corruption and truncation only, not
   against anyone who can write the release. On darwin the pinned code
   requirement closes that unless the Developer ID key is stolen too; on
   Linux nothing does. Closing it is **OWNER** (O1, below): recommended, a
   minisign-format ed25519 signature over SHA256SUMS, key pinned in the
   binary, trusted comment carrying the tag.
4. Concurrency: no lock; unique exclusive temp names, last rename wins, and
   each upgrade checks after its rename that the path is still its inode.
   Running windows keep their inode, but start every new agent through the
   binary at the same path (`--chord-group-exec`): that launcher contract
   must be stable across versions (pinned by a test).
5. Tests over loopback only, a fake GitHub (API + download host) in one
   `HttpServer`, archives built in the test with the system `tar`, real
   files in temp dirs, and two `compile`-tag tests that upgrade a stamped
   compiled binary from a loopback release (success, and darwin refusal of
   an unpinned signature).

## Measured on this Mac (macOS 26.6.2, Dart 3.13.5, arm64)

| What | Result |
| --- | --- |
| `build/chord` (unstamped AOT) | 20 589 184 bytes; `gzip -6` 7 802 095 bytes (0.54 s) |
| sha256 of the binary | 0.075 s (`shasum`) |
| first `--version` of a fresh copy | 0.57 s wall (first exec of a new file), prints `chord 0.0.1` |
| ad-hoc binary, `--identifier dev.katsuba.chord` | `codesign --verify --strict`: 0; `-R='anchor apple generic and certificate leaf[subject.OU] = "YQ8ZD2KZ3T"'`: **3** ("failed to satisfy specified code requirement(s)"); `-R='identifier "dev.katsuba.chord"'`: 0; `-R='identifier … and anchor apple generic'`: 3 |
| same binary, one byte appended | `--verify --strict`: **1** ("main executable failed strict validation") |
| a Developer ID, notarised app in place (team 2ZEFAR8TH3) | full Developer ID requirement with its own team: 0; with YQ8ZD2KZ3T: **3**; `--check-notarization` added: 0 in 0.41 s |
| Apple's `/bin/ls` | `anchor apple`: 0; team requirement: 3 |
| `spctl -a -t exec` on the ad-hoc binary | rejected, 3 |
| replace a running signed binary by `rename` | running process finishes with old output; inode changes; next launch runs new: as expected |
| overwrite in place (same inode), running and not | not killed at this size (tiny ad-hoc binary); not reproduced, so not relied on either way |
| Dart `HttpClient` redirects | follows 5 by default; strips `authorization`, `cookie`, `proxy-authorization`, `www-authenticate` on cross-origin hops (`shouldCopyHeaderOnRedirect`, `http_impl.dart`), copies every other header |
| Dart proxy | `findProxyFromEnvironment` honours `http(s)_proxy`/`no_proxy` and does **not** exempt `127.0.0.1` (matters for tests) |
| minisign, signify, cosign on this Mac | none installed; `gh` is |

codesign exit codes are distinct and stable enough to map: 0 ok, 1
signature invalid/tampered, 3 valid signature that fails the requirement.
A Dart HTTP download of 8 MB with sha256 in chunks is well under a second
on loopback; no isolate is needed (a CLI command draws no frame).

## Q8. GitHub API use

### Hosts and reads

- API base `https://api.github.com/`, download base `https://github.com/`,
  both compiled constants (`String.fromEnvironment` defaults, see the
  compile test), never read from the environment at run time. Repository
  `githubRepo` from `distribution.dart`.
- Reads (framework settles the shape in Q1; this is the quota view):
  listing releases is `GET /repos/IKatsuba/chord/releases?per_page=100`,
  following `Link: rel="next"` only while a page is full; today one page.
  `releases/latest` excludes pre-releases and is GitHub's "latest" flag,
  not the highest semver, so it cannot serve a channel build and should not
  decide a stable one (downgrade, T6). Downloads go to
  `https://github.com/IKatsuba/chord/releases/download/v<to>/<asset>`,
  which is not the REST API and does not count against the 60/h limit;
  `--force --version <v>` therefore needs zero API reads.
- Per truth-table row the API reads are U2's registry reads, one listing
  each (bare already-latest 1; bare newer 2 under cliffy's check-then-
  resolve, or 1 if framework caches the listing for the run, which I
  recommend: same answer, half the quota), plus two non-API downloads
  (SHA256SUMS, archive).

### Token

Options: (a) no token ever; (b) `GH_TOKEN`/`GITHUB_TOKEN` sent to
`api.github.com` only, never to a redirect or the download host; (c) a
chord-specific variable. Recommendation **(a)**. The repository is public;
60 reads/h per IP is roughly 30 upgrades an hour behind one NAT, and the
failure names the limit and its reset. Reading a general token means
handling a credential that may belong to GitHub Enterprise or carry write
scopes, for a convenience nobody asked for; it also widens T8. If a later
owner wants (b), Dart already strips `authorization` on cross-origin hops,
but the client should still attach it only to requests whose host is the
API base's host.

### Headers

`User-Agent: chord/<version>` (GitHub refuses requests without one; Dart's
default `Dart/3.13 (dart:io)` works but says nothing), `Accept:
application/vnd.github+json` and `X-GitHub-Api-Version: 2022-11-28` on API
reads only. Downloads send only the User-Agent.

### Redirects

`browser_download_url` and `releases/download` answer 302 to
`release-assets.githubusercontent.com` (formerly
`objects.githubusercontent.com`; GitHub has changed it before).
Recommendation: `followRedirects = false` and follow by hand, at most 5
hops, refusing a hop whose scheme differs from the base's (so `https` never
drops to `http`, and the loopback tests, which are `http` throughout, use
the same rule). No host allow-list: integrity comes from the checks below,
not from where bytes came from, and an allow-list breaks on GitHub's next
rename. Each hop is said under `-v` only if interface wants it.

### Errors

- 403 or 429 with `x-ratelimit-remaining: 0`: "GitHub's rate limit for
  unauthenticated reads is used up until <reset as local HH:MM>" (words
  interface's); `retry-after` (secondary limit) named in seconds. Either
  way exit 1, binary unchanged.
- 404 on the listing: the repository is gone or renamed; 404 on an asset:
  the release has no `chord-<machine>.tar.gz` or no SHA256SUMS (framework's
  Q1 decides whether such a release is listed at all).
- Other non-2xx, transport, TLS: as `RegistryReader` (`ClientException`,
  `TlsException`, `IOException` caught and named), with a `ReleaseError`
  prefix of its own.
- A JSON body that is not a list of releases: refused, not guessed.

### Timeouts

Q367 settled no timeout on the npm read. Options for GitHub: (a) the same,
nothing timed, Ctrl+C is the person's timeout; (b) an idle timeout (no
byte for 60 s) on reads and the download, no total limit; (c) a total
limit. (c) is wrong for an 8 MB download on a slow link. Recommendation
**(a)** for consistency with Q367, with (b) as the alternative if the
owner wants one: it is the only timer that cannot fail a slow but live
download. Whether Q367 carries over is the owner's (**OWNER**, light). The
smoke run (Q10) is the exception: it is a local child chord starts, and it
gets a bound.

### Proxy

Dart honours `HTTPS_PROXY`; TLS stays end to end through `CONNECT`, so a
proxy sees host names only. Keep it: people behind proxies need it. Tests
must not inherit it (see Tests).

## Q9. Threat model

Assets: the person's chord binary and everything it later runs with their
privileges. Adversaries: a network attacker; someone with write access to
the GitHub release (stolen token or account, a malicious collaborator,
GitHub-side storage compromise); a local user who can write the install
directory; a hostile environment of the invoking process.

| # | Threat | What the design does | Residual |
| --- | --- | --- | --- |
| T1 | MITM on any request | `https` bases compiled in; Dart's TLS with the system roots; redirect scheme never changes; no `http` fallback | a CA mis-issuance; the same as every package manager |
| T2 | Corrupt or truncated download | `Content-Length` (when given) checked against bytes received; sha256 of the archive against SHA256SUMS before decompressing; any mismatch deletes the temp dir, binary unchanged | none |
| T3 | Release writer replaces archive and SHA256SUMS together | SHA256SUMS cannot help (same origin). darwin: pinned code requirement (Developer ID anchor, Team ID `YQ8ZD2KZ3T`, identifier `dev.katsuba.chord`) refuses anything not signed by the owner's key, which lives in the owner's keychain, not GitHub. Linux: **nothing** without O1 | Linux fully exposed to a GitHub account compromise; darwin exposed only if the Developer ID key is stolen |
| T4 | An old genuine release re-tagged as new (replay) | the smoke run must print `chord <to>`; a version mismatch is refused. A signed SHA256SUMS (O1) must carry the tag in its trusted comment, since archive names are unversioned and an old signed SUMS would otherwise verify | with O1 and the smoke run, none |
| T5 | Downgrade | bare `upgrade` takes the highest valid semver of its channel from the listing, never GitHub's `latest` flag, and never moves below the running version (framework/interface: say "already latest" when the highest listed is lower); only an explicit `--version` goes down, as the person asked | the person's explicit choice |
| T6 | Draft or pre-release taken for stable | drafts are invisible unauthenticated; a stable build ignores every release with `prerelease: true` **and** every version with a channel (both must agree, else the release is skipped, not trusted on one flag) | none |
| T7 | Binary for the wrong platform | asset name from `runningMachine()`; the smoke run fails with `ENOEXEC`/bad CPU type before any swap | none |
| T8 | Archive path traversal, symlink, hardlink, device members | nothing is extracted by name: members are read as a stream, exactly `chord`, `LICENSE`, `NOTICES`, regular files, each once, any other entry type or name refuses the archive; only the `chord` member's bytes are written, into a file chord names | none |
| T9 | Decompression bomb | sha256 is checked before decompressing, so a bomb needs T3; still: download cap 64 MiB compressed, `chord` member cap 256 MiB, total decompressed cap 320 MiB, all streamed and aborted on crossing | none |
| T10 | TOCTOU in the install directory | temp created with `File.create(exclusive: true)` under an unguessable name (`.chord-upgrade-<pid>-<random>`); its sha256 re-read and compared just before rename; a directory writable by others (mode `o+w`) is refused | a user who can write the directory can replace chord anyway; outside the model |
| T11 | Hostile environment (`GH_HOST`, `GITHUB_API_URL`, `GITHUB_TOKEN`, a variable that redirects the base) | none of them is read; there is no run-time override of the bases at all (tests use compile-time defines and constructor injection); the smoke run gets a minimal environment (`PATH`, `HOME`) | `HTTPS_PROXY` (T1 still holds); a `PATH` that shadows `codesign` (use `/usr/bin/codesign` absolutely) |
| T12 | Interrupted upgrade (Ctrl+C, SIGTERM, crash, full disk) | everything before the rename touches only temp files; the rename is atomic; a SIGINT/SIGTERM handler during the swap window removes the temp file and exits by the signal; a crash leaves at most one hidden temp file, which the next upgrade removes if its pid is dead | a hidden file after SIGKILL |
| T13 | Running a downloaded binary (the smoke run) before trust | it runs only after sums, signature (O1) and codesign pass, i.e. only code as trusted as what is about to be installed and run anyway | Linux without O1: T3's exposure, one step earlier |

### Is SHA256SUMS alone enough?

No, not as a security check: it proves the archive is the one the release
page lists, and nothing about who made the page. It is enough against T1
(with TLS) and T2. On darwin the code requirement is a real second factor
at no cost to the release. On Linux it is the only check.

### What more is possible

- **macOS code requirement** (recommended, no release change): `/usr/bin/
  codesign --verify --strict -R='identifier "dev.katsuba.chord" and anchor
  apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists
  and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and
  certificate leaf[subject.OU] = "YQ8ZD2KZ3T"' <new>`, Team ID and
  identifier taken from `tool/release/sign.dart`'s constants (shared, not
  retyped). Also compare entitlements? Not needed: the requirement pins
  the signer, and the signer chose them. Measured: 0 / 1 / 3 as above,
  under 0.5 s.
- **`spctl` / `--check-notarization`**: not recommended as a gate. The
  binary is not stapled, so the check is an online ticket lookup that fails
  offline or behind a filtering proxy, and Gatekeeper's assessment can be
  disabled by the person, making its answer about the machine, not the
  file. Chord's HTTP download sets no quarantine attribute, so Gatekeeper
  never assesses the new binary on its own; the code requirement is the
  substitute. `--check-notarization` could be an extra, non-fatal `-v`
  note; I recommend leaving it out.
- **GitHub artifact attestations**: need the build to run in GitHub
  Actions with OIDC (the release builds on the owner's Mac, Q362/Q363), and
  verification needs a Sigstore client: none maintained for Dart; shelling
  out to `gh attestation verify` needs `gh` installed and logged in. Does
  not fit.
- **Immutable releases** (a repository setting): once published, a
  release's assets and tag cannot change. Protects against T3 by
  replacement of an existing release, not against a new malicious release.
  The release JSON carries `immutable`; the client could require it.
- **minisign (ed25519) over SHA256SUMS, key pinned in the binary**: closes
  T3 on Linux and T4 (with the tag in the trusted comment). Verification in
  Dart: `package:cryptography` (maintained, pure Dart Ed25519, works under
  AOT; to be tried) or `pinenacl`; the minisign file format is two base64
  lines and a trusted comment, parsed in a few lines (the format, not
  crypto, is ours). Signing: `minisign -Sm SHA256SUMS -t "chord v<to>
  SHA256SUMS"` on the owner's Mac, or a release-tool stage doing the same
  with the same Dart package and a key in the login keychain.

### O1, **OWNER**: a signature the GitHub account alone cannot forge

Each option below except (a) changes the release.

- (a) Nothing more: SHA256SUMS on both, code requirement on darwin. Linux
  binaries are as safe as the GitHub account.
- (b) Enable immutable releases on IKatsuba/chord, and chord refuses a
  release whose JSON lacks `immutable: true`. One repository setting, no
  new artifact; protects published releases from later tampering only.
- (c) **Recommended**: (b) plus a new asset `SHA256SUMS.minisig`, an
  ed25519 signature in minisign format whose trusted comment is `chord
  v<version> SHA256SUMS`; the public key compiled into chord (a constant
  in `distribution.dart`), a release-tool stage signs after `archive`, and
  `chord upgrade` refuses an unsigned or mis-signed SUMS or a comment
  naming another tag. Costs: one key to keep offline and back up, a key
  rotation story (a new key ships in a release signed by the old), one
  package to try.
- (d) (c) without (b).

Key loss under (c) stops self-upgrade for old binaries until they are
upgraded by hand; that is the price of the guarantee and must be in the
owner's decision.

## Q10. Smoke run before the swap

Options: none; `--version` before the swap; `--version` after the swap
with rollback. Recommendation: **before**, on the exact file that will be
renamed (the in-directory temp), after every integrity check has passed.

- Worth it: it catches the wrong platform (T7), the hardened-runtime kill
  of a Dart binary signed without `allow-unsigned-executable-memory`
  (CTUI-102 measured SIGKILL), a truncated or broken AOT snapshot, and a
  replay (T4). On macOS it also performs the first-exec assessment of that
  vnode, which the rename then keeps.
- Risk: running downloaded code. Bounded by order (after trust, T13); it
  runs as the same user the binary will run as minutes later.
- How: `Process.start(<temp>, ['--version'], environment: {PATH, HOME},
  includeParentEnvironment: false)`, stdout and stderr captured, stdin
  closed. Bound 30 s (measured 0.57 s): on expiry SIGKILL to that pid
  (ours) and refuse. Pass only exit 0 with stdout exactly `chord <to>\n`.
  Any other outcome names what was seen (exit code, signal, first line of
  output) and says the installed binary is unchanged.
- Not through `Runner.inherit` (that has no bound and inherits the
  terminal); a small `capture` with a bound, or `Runner.capture` gaining
  an optional timeout. Framework's call.

## Q11. Concurrency and interruption

Run-time order of one upgrade (framework owns the file details; this is
the ordering contract):

1. Read the listing; pick `to` (pure).
2. Create a private temp dir (`Directory.systemTemp.createTemp`, 0700).
3. Download SHA256SUMS (and O1's signature), verify, parse.
4. Stream the archive to the temp dir, hashing and capping; compare.
5. Stream-decompress; check members; keep the `chord` bytes in the temp
   dir.
6. Resolve the target (`resolveSymbolicLinksSync` of the executable, so a
   link is kept and its target replaced); refuse a directory that is
   `o+w` or not writable (interface's words).
7. Create `<dir>/.chord-upgrade-<pid>-<random>` exclusively, copy the
   bytes, set the old file's mode (and owner when running as root), fsync
   the file; re-hash and compare.
8. darwin: code requirement on that file. All: smoke run on it.
9. Note its inode; `rename` it over the target; fsync the directory.
10. `stat` the target: inode must be ours, else another upgrade won the
    race (see below).
11. Delete the private temp dir; print.

Steps 7 to 9 run with SIGINT and SIGTERM watched: on either, delete the
temp file and exit by re-raising (as `platform/signals.dart` does). Before
step 7 no handler is needed: only the private temp dir exists, removed in
a `finally`, and a crash leaves it in the system temp only.

| Scenario | Expected outcome |
| --- | --- |
| Two upgrades at once, same target | each writes its own temp, each renames; last rename wins; both installed files passed every check, so the binary is a verified release either way. The loser sees step 10 fail and says the path now holds another upgrade's file, without claiming success (exit 1) |
| A lock instead | rejected: a lock file beside the binary is a marker file (no, Q365 spirit), and an fcntl lock on the binary needs it open for writing, which Linux refuses for a running text file (`ETXTBSY`) |
| Upgrade while chord windows run | the rename leaves their inode in place (measured); they keep running the old code. The "A chord already running keeps <from> until it is started again." line stays true |
| A running old window starts a new agent after the upgrade | it execs `Platform.resolvedExecutable --chord-group-exec <nonce> <path> --` (`platform/process.dart` `defaultLauncher`), which is now the **new** binary. The launcher contract (flag, argv, nonce handshake) must therefore be stable across versions. Pre-existing for npm and Homebrew upgrades too; recommend a test pinning `groupExecFlag` and the handshake bytes, and a decisions entry naming them a cross-version interface |
| ACP servers or `chord acp` started from the path later | get the new binary: intended |
| Upgrade run by a window's own agent (a tool runs `chord upgrade`) | same as any process; the window keeps its inode |
| Ctrl+C during download | `finally` removes the private temp dir; binary unchanged; dies by SIGINT |
| Ctrl+C during steps 7 to 9 | handler removes the in-dir temp; if the rename already happened the upgrade is complete and the message says so before exiting |
| SIGKILL, power loss | at most `.chord-upgrade-<pid>-*` left; the next upgrade deletes such files whose pid is not running (kill 0 → ESRCH). After power loss before the directory fsync, the old or the new file, never a mix (rename atomicity, file fsynced first) |
| Disk full during copy | write fails, temp deleted, binary unchanged |
| Target on a read-only or root-owned directory | refused at step 6, nothing written, binary unchanged; never escalates (interface's Q6 words) |
| Target directory on another filesystem than the temp dir | irrelevant: the cross-device boundary is only between steps 5 and 7, crossed by a copy, never a rename; the rename is within one directory |
| Target replaced between step 6 and 9 | the rename replaces whatever is there; step 10 is only about our inode. Acceptable: the directory is ours to write |

Memory: streaming keeps it at a few buffers; holding the decompressed
`chord` (20 MB) in memory is also acceptable for a CLI, framework's choice.
No isolate: nothing draws.

## Failure states the person is told

Every failure before step 9 leaves the installed binary byte-identical and
says so. Only two states are not "unchanged": step 9 succeeded but step 10
found another inode (the path holds a different verified upgrade), and a
signal arriving after the rename (the upgrade happened). Interface words
both; the design must not have a third.

## Q12. Test plan (loopback only)

Common rules, binding for every test here:

- No test reads `api.github.com` or `github.com`; bases come from the
  constructor, or (compiled tests) from compile-time defines whose
  defaults are the real hosts. A test-only guard: the production
  `GithubReleases` factory is never called in tests; a lint-free check
  greps the test tree for the real host names outside constant tests.
- One fake GitHub per test: `HttpServer.bind(InternetAddress.loopbackIPv4,
  0)` serving `/repos/IKatsuba/chord/releases`, a `/releases/download/…`
  path that 302s to `/assets/…` on the same server (and, for the scheme
  rule, to an `https://` URL that must be refused), with a request log;
  closed with `force: true` in `tearDown`, as `upgrade_test.dart` does.
- Clients built with `HttpClient()..findProxy = (_) => 'DIRECT'`, since
  Dart routes `127.0.0.1` through `http_proxy` when set.
- Archives built in the test with the system `tar` (as `archive.dart`
  does, `--uid 0 … --no-mac-metadata`), plus hostile ones built with
  `package:archive`'s encoder or hand-written tar headers: `../chord`,
  `/chord`, `./chord` (decide: refuse), a symlink `chord`, a hardlink, a
  FIFO, a duplicate `chord`, an extra member, a missing `NOTICES`, a
  member over the cap, a gzip bomb (small compressed, huge `chord`, with a
  SUMS that matches so the cap, not the sum, must stop it).
- Install directories under `Directory.systemTemp.createTemp`, deleted in
  `tearDown`; never the person's PATH or install.

Pure modules (no I/O), tests mirroring sources:

- release picking: stable vs channel, prerelease flag vs channel
  disagreement (T6), invalid semver tags, tags without `v`, a release
  missing this machine's asset, highest-lower-than-running (T5), paging
  boundary at exactly 100.
- SHA256SUMS: one line per name, `*` and space forms, duplicates refused,
  missing name, uppercase hex refused (as `archive.dart`'s rule).
- O1 (if chosen): minisign parse, good signature, wrong key, comment with
  another tag, trailing garbage; vectors generated once by the release
  tool's own signer with a test key.
- rate-limit and error mapping from status and headers to `ReleaseError`.
- the code requirement string built from `sign.dart`'s constants.

I/O through seams:

- Reader over the loopback fake: per truth-table row, the number of API
  requests and download requests (U2 style counts); 403 with
  `x-ratelimit-remaining: 0` and `x-ratelimit-reset`; 429 with
  `retry-after`; 404 listing; 404 asset; non-JSON; a closed port; a server
  that sends half the archive then closes (T2); a `Content-Length` larger
  than sent; six redirects (refused); a redirect to another scheme
  (refused); a `User-Agent` and API headers asserted on API requests and
  absent on downloads; no `authorization` header ever.
- Swap on real files: plain file; a symlink to the binary (link kept,
  target replaced, mode kept); a read-only directory (refused, unchanged,
  skipped when running as root); an `o+w` directory (refused); a stale
  `.chord-upgrade-<dead pid>-x` removed; two concurrent swaps through a
  barrier in the filesystem seam (one wins, the other reports step 10's
  state); the step-10 check with a seam that renames something else in
  between. Cross-device: not reproducible in a test; covered by design
  (no rename ever crosses directories) and a test that the temp file's
  directory equals the target's directory.
- Interrupt: the filesystem seam throws at each step boundary (after temp
  create, after copy, before rename, after rename); each asserts the
  target bytes and the leftover files. The signal handler itself runs in
  a child Dart process sent SIGINT at a seam-signalled point (as
  `run_app_signal*_test.dart`), not in the test isolate.
- Smoke run with scripted executables in the temp install dir (shell
  scripts, real processes): prints the right version; prints another
  version (T4); exits 1; kills itself with SIGKILL (the entitlement case);
  sleeps past a bound injected as 1 s (killed, its pid reaped in
  `finally`); not executable (`EACCES`); an ELF on macOS / Mach-O on Linux
  (`ENOEXEC`, T7) where cheap to provide.
- codesign (darwin, `@TestOn('mac-os')`): copy the
  test's own compiled fixture or `/usr/bin/true`-style ad-hoc binary,
  `codesign -s - --identifier dev.katsuba.chord`; requirement refuses it
  (exit 3 mapped to its message); a byte appended refuses it (exit 1);
  the matching path is proven with the compile-test requirement below.
  Through `Runner`, so a recording runner covers the argv on Linux.
- The command through `runCli` with a fake `ReleaseSource` and recording
  filesystem for every truth-table row (U2's table, release column), and
  the detection order (npm row and Cellar row still win over the stamp).

`compile` tag (`--run-skipped`, like `build_compile_test.dart`), file
`test/upgrade_release_compile_test.dart`:

1. Bind the loopback fake first, then compile the "old" chord with
   `--define=chord.official=true`, the release bases as defines pointing
   at the fake (`-Dchord.releaseApi=http://127.0.0.1:<port>/`,
   `-Dchord.releaseDownload=…`), a version define for `0.0.1-test` if the
   version is defined that way (else the real version and a fake newer
   release), and on darwin `-Dchord.codeRequirement=identifier
   "dev.katsuba.chord"` (measured: an ad-hoc signature with that
   identifier satisfies it; the real Developer ID requirement cannot be
   met without the owner's key).
2. Compile the "new" chord likewise, version newer; on darwin sign it ad
   hoc with `--options runtime --entitlements chord.entitlements
   --identifier dev.katsuba.chord`, so the hardened-runtime path runs as
   shipped; archive it with the real `archive.dart` layout and write
   SHA256SUMS (and O1's signature with a test key, if chosen, its public
   key as a define too).
3. Install the old one into a temp dir through a symlink; run `<link>
   upgrade` with a minimal environment (no proxy variables, `HOME` a temp
   dir); assert exit 0, the two success lines, the link still a link, the
   target's bytes equal the new binary, mode 0755, `<link> --version`
   prints the new version, and the fake's request log matches the truth
   table.
4. darwin: a second case built without the requirement define (the real
   pinned requirement) must refuse the ad-hoc new binary with the
   requirement message and leave the old bytes in place, proving the
   check is compiled in.
5. A guard test (not compile-tagged): `compileArgv` for every target adds
   no define but `officialDefine`, so a release build always has the real
   bases and the real requirement.

Every process started is reaped in `finally`; nothing kills by pattern.

## What I need from the others

- framework: the listing shape and caching per run (so a bare upgrade is
  one API read, not two); the defines for the bases and the code
  requirement (names above are proposals); streaming extraction with caps
  rather than whole-file decode if `package:archive` allows it under AOT;
  `File.create(exclusive: true)` and directory fsync in the seam; whether
  `./chord` member names are accepted.
- interface: words for rate limit with reset, every refusal stating
  "unchanged", the step-10 lost-race state, the smoke-run failures, the
  `o+w` and read-only refusals, and the after-rename interrupt.
- lead: carry O1 and the Q367 carry-over to the owner; record the
  `--chord-group-exec` contract as cross-version if agreed.

## Open questions

1. **OWNER** O1: (a) / (b) / (c, recommended) / (d) above.
2. **OWNER** (light): do Q367's "no timeout" words cover GitHub reads and
   the download? Recommended yes; alternative an idle timeout of 60 s.
3. Token: none (recommended) vs `GH_TOKEN` to the API host only. Owner
   only if the lead thinks a person will hit 60/h.
4. Should a bare upgrade refuse to go below the running version (T5)?
   cliffy's table would install the lower `latest`; recommended: refuse
   ("already latest"), as a departure listed in the design.
5. The `--chord-group-exec` launcher as a cross-version interface: a test
   and a decisions entry now, or a separate task (it predates this one).

## Revision after critic

Answers the lead's send-back of critic findings 12 (O1's verifier and key
rotation) and 9 (the smoke run's contract). The lead's decisions taken
since (no signal handler as U2, temp leftovers documented not swept,
last writer wins with no post-rename inode check, no token, Q367 carried
over, a lower `latest` follows cliffy, compile test from temp copies of
`example/chord`, fixtures by `package:archive`'s encoder, TLS not proven by
loopback) supersede the matching lines above; the rest above stands.

### F12. Ed25519 verification of minisign signatures, trialled

Vectors were made by the real minisign 0.12 (the upstream macOS release
binary, itself verified against minisign's published key), in a scratch
directory outside the repository, then deleted. Two key pairs A and B,
generated without a password (`minisign -GW`), a SHA256SUMS of two lines,
trusted comment `chord v1.2.3 SHA256SUMS`:

| Vector | How made | minisign's own verdict |
| --- | --- | --- |
| legacy `Ed` | `minisign -S -l -s a.key -m sums -t …` | ok |
| prehashed `ED` | `minisign -S -H -s a.key -m sums -t …` | ok |
| tampered trusted comment | `v1.2.3` → `v9.9.9` in line 3 | "Comment signature verification failed" |
| wrong key | `ED` file checked against `b.pub` | "Signature key id … but the key id in the public key is …" |
| forged key id | signed by B, key id bytes rewritten to A's | "Signature verification failed" |
| tampered file | one byte appended to SUMS | (not asked; the Dart trial refuses) |
| comment names another tag | good file, client wants `chord v1.2.4 SHA256SUMS` | (a chord check, not minisign's) |

Measured: minisign 0.12's `-S` without `-H` wrote a legacy `Ed`
signature for this small file, the same as `-l`; only `-H` wrote `ED`. The
release stage must pass `-H` explicitly if chord accepts `ED` only.

A Dart trial program (one verifier function, three back ends), built with
`dart compile exe` (Dart 3.13.5, darwin-arm64), run on those vectors:

| Package (version, last published) | `Ed` | `ED` | tampered comment | wrong key | forged key id | tampered file | other tag |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `cryptography` 2.9.0, 2025-11 (`DartEd25519`, `DartBlake2b`) | ok | ok | refused (comment signature) | refused (key id) | refused (signature) | refused (signature) | refused (comment) |
| `pinenacl` 0.6.0, 2024-05 (`VerifyKey`, `Hash.blake2b`) | ok | ok | refused | refused | refused | refused | refused |
| `ed25519_edwards` 0.3.2, 2026-08 (`verify`; no BLAKE2b, borrowed `cryptography`'s) | ok | ok | refused | refused | refused | refused | refused |

All three agree with minisign on every vector, and all run under AOT (the
whole trial, all three linked, 0.05 s user). Recommendation:
**`package:cryptography`**, imported as `package:cryptography/dart.dart`
so the pure-Dart implementations are named, not a platform plug-in: it is
the maintained one, and it has both Ed25519 and BLAKE2b-512, so one
package covers `Ed` and `ED`. Its new transitive packages: `ffi`,
`fixnum`, `meta`, `typed_data` (`crypto` and `collection` are already in
the port). Binary growth was not isolated (the trial binary with all three
is 6.1 MB, mostly the Dart runtime); the ship team measures it.

What is ours and what is the package's:

- **Ours** (the minisign format, a few dozen lines, tested on the vectors
  above checked into the test tree with a test key pair): the public key
  line (base64, 42 bytes, `Ed` + 8-byte key id + 32-byte key); the
  signature file's four lines (untrusted comment ignored; base64 74 bytes,
  algorithm `Ed` or `ED` + key id + 64-byte signature; `trusted comment: `
  prefix; base64 64-byte global signature); the key id compared before
  any crypto; the message being the file for `Ed` and its BLAKE2b-512 for
  `ED`; the global signature checked over signature bytes followed by the
  comment's UTF-8 bytes; the comment compared exactly with `chord
  v<to> SHA256SUMS`; which keys are pinned and which files are fetched.
  Any other length, prefix or algorithm refuses. Key ids and signatures
  are public, so no constant-time compare is needed.
- **The package's**: Ed25519 verification and BLAKE2b-512, nothing else.

Signing on the release side: minisign is not installed on the owner's Mac.
Options: the owner installs minisign and the release stage runs `minisign
-S -H -s <key> -m SHA256SUMS -t "chord v<v> SHA256SUMS" -x <file>` (key
file password-encrypted by minisign); or a Dart signer in the release tool
with `cryptography` and a key in the login keychain (more code of ours,
and a key format of ours). Recommended: minisign itself. **OWNER** as part
of O1.

### F12. Key rotation that survives a skipped bridge

Terms: the binary pins a **key list**; a release carries one signature
file **per signing key**, named `SHA256SUMS.<KEYID>.minisig` (16 hex
digits, as minisign prints them), so adding a key never renames a file.

Policy proposed for the owner:

1. **Two keys from the first signed release.** A primary P (used every
   release) and a spare S (generated at the same time, kept offline in a
   separate place, never used until needed). Every binary pins `[P, S]`;
   every release is signed by P. Loss of P alone is then survivable with
   no bridge: the next release is signed by S, which every binary in the
   field already trusts.
2. **Verification rule.** chord tries, in pinned order, the signature file
   of each pinned key; a 404 moves on; the first file that verifies
   (signature, comment signature, tag) accepts SUMS. A file that exists
   but fails is a refusal, not a reason to try the next key (a tampered
   release is not retried into acceptance by a weaker path).
3. **Planned rotation** (P to a new P2, e.g. on a schedule or a
   maintainer change): release R signs with P and P2 and its binaries pin
   `[P, P2, S]`. Every release is signed by both for an **overlap window
   of at least 12 months and at least 10 releases, whichever is longer**;
   then P is dropped from signing and from the pins.
4. **Skipped-bridge fallback** (so a client older than the overlap still
   gets home): when the newest eligible release has no signature file for
   any pinned key, chord takes the newest release above the running
   version that does, installs it, and says that it is a step and that
   `chord upgrade` run again reaches `<latest>`. Every release inside an
   overlap pins the next key, so the chain always has a link as long as
   one release signed by the old key exists. Cost: one extra 404 per
   pinned key per candidate, in the fallback only. Never below the running
   version.
5. **Compromise of a key** (emergency): an emergency release signed by
   **every** key still pinned in the field (the compromised one included,
   so clients pinning it move off it) whose binaries drop the compromised
   key. Until a client takes that release, an attacker holding the key can
   sign releases that client accepts; no revocation list is fetched, as
   one would have to be trusted by the same key. That limit is stated, not
   solved.
6. **Loss of every pinned key**: binaries that pin only lost keys cannot
   upgrade themselves; their refusal names the manual install from the
   releases page. The spare (1) is what makes this need two separate
   losses.

What the owner decides with O1: whether (c) at all; minisign or a Dart
signer; the overlap numbers; and where P and S are kept.

### F9. The smoke run's contract

Reuse: `spawnGroup` (`example/chord/lib/platform/process.dart`) fits as it
is: `spawnGroup(<temp file>, ['--version'], cwd: <private temp dir>, env:
{'PATH': …, 'HOME': …}, ownEnvironment: true)`. The launcher is the running
chord (`--chord-group-exec`: `setsid`, then `execv` of the new binary), so
the child leads a session and group of its own and keeps the pid and
pipes; `GroupProcess.signal` reaches the group, `alive` asks `kill(-pid,
0)`, the launcher's frames are taken out of stderr, a failed `execv`
(wrong platform, `ENOEXEC`, `EACCES`) arrives as `CannotStart` with the
launcher's 126/127. Under `dart run` the launcher is `group_exec.dart`,
which the tests use. The smoke run passes its own `ProcessGroups` so it
does not join the window registry.

Contract (the numbers are proposals, each injectable for tests):

- **One deadline, 30 s, from before `spawnGroup` until all three of: the
  exit settled, stdout's end, stderr's end.** Launch, handshake, exit and
  pipe drain all count. A program that exits but leaves a descendant
  holding a pipe has not finished.
- **Output cap: 64 KiB of stdout and stderr together**, counted as bytes
  arrive; stdout is kept only up to the cap, stderr only its first 4 KiB
  for the message. Crossing the cap is a failure at once.
- **stdin closed** right after the start.
- **On deadline or cap**: SIGKILL to the group (`GroupProcess.signal`),
  then cancel both subscriptions so a descendant outside the group (one
  that called `setsid` itself) cannot keep chord waiting; then wait up to
  2 s for the exit to settle (Dart reaps the direct child). A descendant
  that left the group is not chord's to find; it is reparented and
  reaped by init. The failure says which bound was hit.
- **Pass** only when: started, exit 0 with no signal, both pipes ended,
  inside the deadline, under the cap, stdout exactly `chord <to>\n`.
  Anything else refuses the upgrade, names what was seen (exit code or
  signal, the first line of output, or the bound), and the installed
  binary is untouched (the smoke run precedes the rename).
- **After any outcome**: `kill(-pid, 0)` must answer ESRCH before the
  upgrade continues or reports; if the group still holds a process after
  the SIGKILL and the 2 s wait, say so and stop.
- **Ctrl+C**: with no signal handler (the lead's decision), the child is
  in its own session, so the terminal's SIGINT reaches chord but not the
  child; chord dies and a hung child lives until it exits by itself. The
  window is at most 30 s of a binary that has passed every check. Options
  for the lead: accept and document (consistent with the decision), or a
  handler watched only during the smoke run that SIGKILLs the group and
  re-raises. Recommended: the narrow handler; the decision is the lead's.

Tests (scripted executables in a temp dir, started through the real
`spawnGroup` with the JIT launcher; every pid a script starts is written to
a file and checked with `kill(pid, 0)`; only those pids are ever killed,
in `tearDown`):

- prints `chord <to>` and exits 0: passes; another version: refused with
  it named; exits 3: refused; `kill -KILL $$`: refused naming SIGKILL (the
  entitlement case); not executable: `CannotStart`.
- **output flood**: `yes` (or `while :; do echo chord; done`), cap
  injected as 4 KiB: refused naming the cap within the deadline; the group
  is gone (`kill(-pid, 0)` is ESRCH); bytes kept never exceed the cap.
- **flood on stderr only**: same, so the cap counts both pipes.
- **hang before exit**: `sleep 600`, deadline injected as 1 s: refused
  naming the deadline; group gone.
- **exited parent, descendant holds the pipe**: `(sleep 600) & echo
  "chord <to>"; exit 0`. The exit is 0 and stdout is right, but stdout
  never ends: refused at the 1 s deadline, the group SIGKILLed, the
  `sleep`'s recorded pid gone (it stayed in the group).
- **descendant escapes the group**: the same with the descendant calling
  `setsid` first (`perl -MPOSIX -e 'setsid; sleep 600'`, perl being on
  both platforms' CI images; skipped with a reason if absent): refused at
  the deadline, chord returns within deadline plus 2 s because the
  subscriptions are cancelled; the escaped pid, recorded by the test, is
  killed by the test itself in `tearDown`.
- the deadline covers the drain: a script that prints the right line,
  closes nothing, and exits after 0.5 s while its descendant writes one
  more byte at 1.5 s, deadline 1 s: refused.

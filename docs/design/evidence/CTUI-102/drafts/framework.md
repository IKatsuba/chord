# CTUI-102 framework draft: versions, channels, where code sits

Answers F1 to F3 of the brief. Everything below was tried on this machine
with Dart 3.13.5 (macos_arm64) and the original's own `semver` 7.8.6 from
`../chord/node_modules`, through throwaway programs under the worktree's
ignored `build/`; nothing was fetched from a registry.

## Summary

- pub_semver (2.2.1, already in the port's lock as a transitive
  dependency) compares pre-releases as `semver` does, but it does not
  validate as `semver` does and has no range check that matches npm's:
  `channelOf` cannot be built on it alone. Twelve differences are listed
  below.
- The smallest faithful port: a small file `example/chord/lib/node_semver.dart`
  that mirrors exactly the four `semver` functions the original imports for
  channels (`valid`, `prerelease`, `validRange` as far as a channel name can
  reach it, `inc` for a pre-release), written against `semver`'s grammar, and
  pub_semver for ordering (`compare`, `gt`, major/minor/patch bumps) with
  build metadata dropped first. Since this is our own code where a package
  exists, it is an owner question (Q1).
- Version source of truth: two sound options (pubspec plus a held constant,
  as now; or a generated file), one sound with a hole (`--define`). Owner
  question Q2.
- Nothing belongs in `lib/`.

## F1. pub_semver against channel.ts

### How the original uses semver

`src/channel.ts` uses `valid`, `prerelease` and `validRange`;
`scripts/dev/release/version.ts` and `select.ts` add `gt` and `inc`
(`major`, `minor`, `patch`, and `prerelease` with the channel as
identifier). cliffy's `printVersions` (for `chord upgrade -l`) sorts with
`@std/semver`'s `compare`, unparseable entries last by `localeCompare`.
`isOutdated` compares strings, not versions.

`channelOf(v)` in words: `valid(v)` null → "no version"; no pre-release →
stable (null); otherwise the input must equal `valid(v)` (so no leading
`v`, no surrounding whitespace, no build metadata), the label must be
exactly `[string, number]`, and the string must pass `checkChannel`.

### What was tried

`Version.parse` from pub_semver 2.2.1 on 47 inputs (every case of
`tests/channel_test.ts` plus boundaries), side by side with `semver.valid`
and `semver.prerelease`; `Version.compareTo` against `semver.compare` on 12
pairs; `VersionConstraint.parse` on channel names; the probe built with
`dart compile exe` and run (it works; pub_semver is pure Dart).

### Where they agree

- Pre-release identifiers: both give a list of ints and strings, numeric
  where the identifier is all digits (`["next", 12]`, `[1, 0]`, `["next",
  "1a"]`, `["next", "-1"]`, `["next", "0-1"]`).
- Every rejected shape in the original's tests that is malformed syntax
  (`latest`, `''`, `1.0`, `1.0.0-next.`, `1.0.0-`, `1.0.0-next..0`,
  `1.0.0-next.0+`, `=1.0.0`, `vv1.0.0`) is rejected by both.
- Precedence of pre-releases: identical on all pairs without build
  metadata (`next.2 < next.10`, `1-… < next`, `alpha < alpha.1`,
  `beta.11 > beta.2`, `rc.1 > next.5`, `next.0 < 1.0.0`).
- `Version.toString()` keeps the text as given, so `valid(v) !== v` can be
  asked, but not answered, by pub_semver (see 4 to 6).

### Where they differ

| # | Input | semver | pub_semver | Effect on a pub_semver-only `channelOf` |
|---|-------|--------|------------|-----------------------------------------|
| 1 | `1.0.0-next.01`, `1.0.0-next.00` | not valid | valid, `["next", 1]` / `["next", 0]` | answers `next` where the original says "no version"; the original's own test fails |
| 2 | `01.0.0`, `1.00.0` | not valid | valid | stable instead of "no version" |
| 3 | `9007199254740992.0.0` (above 2^53−1) | not valid | valid (64-bit int) | stable instead of "no version" |
| 4 | `1.0.0-next.9007199254740991` and above | valid, identifier is the *string* `"9007199254740991"` (numbers only below `MAX_SAFE_INTEGER`) | int | answers `next` where the original says "not a release of a channel" |
| 5 | `v1.0.0-next.0`, ` 1.0.0-next.0`, `1.0.0-next.0\t` | valid, normalised (`v` and JS whitespace stripped) | not valid | "no version" where the original says "not a release of a channel"; wording differs, both refuse |
| 6 | `v1.0.0`, ` 1.0.0`, `1.0.0\n`, `﻿1.0.0` | valid → **stable (null)** | not valid | refuses what the original takes as stable |
| 7 | `1.0.0-next.0+build` | valid, normalised drops build, so ≠ input → "not a release" | valid, build kept, `toString` equals input | needs its own build check, or answers `next` |
| 8 | length over 256 | not valid (`MAX_LENGTH`) | valid | stable/channel instead of "no version" |
| 9 | `compare(1.0.0, 1.0.0+build)`, `+a`/`+b`, `+2`/`+10` | 0 (build ignored) | −1 (build ordered) | `gt('1.2.3+build', '1.2.3')` true; release would take a version the original refuses as "not above" |
| 10 | `validRange(name)` | see below | `VersionConstraint.parse` takes `any` and refuses `x`, `v1` | wrong both ways: refuses `any`, admits `x` and `v1` |
| 11 | `inc(v, 'prerelease', channel)` | `1.0.0-next.3` → `1.0.0-next.4` | no such operation | needs our own (one line, given `channelOf`'s shape) |
| 12 | `inc` major/minor/patch | | `nextMajor`/`nextMinor`/`nextPatch` | agree on stable input, the only input version.ts bumps (`bumpStable` refuses a pre-release, and `releaseVersion` refuses a bump of one) |

Case 6 is worth the lead's eye: the original's `channelOf('v1.0.0')` is
`null`, a stable version, though `isVersionArgument` refuses `v1.2.3` and
`channelOf('v1.0.0-next.0')` refuses. It is reached only if package.json
(here pubspec.yaml) holds such a version, which pub itself refuses for
pubspec (`dart pub get` would fail), so in the port it cannot happen through
pubspec. I propose following the original exactly and pinning it with a
test; if the lead calls it a slip of the original, the fix is to refuse
whenever `valid(v) !== v`, stable or not.

### npm's range check on channel names

`checkChannel` first requires `^[a-z][a-z0-9-]*$`, then refuses a name
`semver.validRange` accepts. Within that alphabet, `validRange` was
evaluated on every name of up to five characters (about 1.3 million) and on
a million random names of up to twenty characters biased to `v`, `x`,
digits and hyphens: it accepts exactly

```text
^v*(x|0|[1-9][0-9]{0,15})$   with the number at most 9007199254740990
```

(zero mismatches). So `x`, `vx`, `vvx`, `v0`, `v1`, `vvvv12` are ranges;
`v`, `v01`, `v1-beta`, `x-1`, `any`, `next`, `latest` are not. The upper
bound is because `vN` means `>=N.0.0 <N+1.0.0-0` and `N+1` must still be a
safe integer. This predicate is the whole of `validRange` a channel name can
reach, and it is what the port needs; a general node range parser is not.

### Smallest faithful port

`example/chord/lib/node_semver.dart`, named for what it mirrors as
`js_trim.dart` and `closest_string.dart` are:

```dart
/// What `semver.valid` answers: the version normalised (JS-trimmed, one
/// leading `v` dropped, build metadata dropped), or null when it is not a
/// version under semver's strict grammar: no leading zeros, components at
/// most 2^53 - 1, at most 256 characters.
String? valid(String version);

/// What `semver.prerelease` answers: the identifiers of a valid version,
/// an int where all digits and below 2^53 - 1, else a String; null when
/// stable. Throws ArgumentError when [version] is not [valid].
List<Object>? prerelease(String version);

/// Whether npm takes [name], already shaped `^[a-z][a-z0-9-]*$`, for a
/// version range, as `semver.validRange(name) !== null` does.
bool isRangeName(String name);

/// `semver.compare`: precedence, build metadata ignored. Throws on an
/// invalid version.
int compare(String a, String b);

/// `semver.gt`.
bool gt(String a, String b);

/// The parts of a stable version a bump raises.
enum Part { major, minor, patch }

/// `semver.inc` for `major`, `minor` and `patch` of a stable version.
String incStable(String version, Part part);

/// `semver.inc(version, 'prerelease', channel)` for a version [channelOf]
/// has already placed on [channel]: its counter plus one.
String incChannel(String version, String channel);
```

`valid` and `prerelease` are written against semver's strict regular
expression (`src/internal/re.js`, `FULL`), with `jsTrim` from
`lib/js_trim.dart`; `compare`, `gt` and `incStable` parse with pub_semver
and drop build metadata before comparing (`Version(major, minor, patch, pre:
…)`), which closes difference 9. About 80 lines with comments.

Why not "pub_semver plus guards": the guards that close 1 to 8 (leading
zeros, the safe-integer bound on components and on numeric identifiers,
the length, the `v` and whitespace normalisation, build metadata) are
semver's grammar restated, and after them pub_semver contributes nothing to
`valid` or `prerelease`. That is also an option (Q1, b).

### channel.dart

`example/chord/lib/channel.dart`, file for file with `src/channel.ts`:

```dart
/// Why a version cannot be released, said as the release dies with it.
final class VersionError implements Exception {
  const VersionError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Refuses a name that cannot be a channel, which is an npm tag and a
/// branch. Throws [VersionError] with the original's four messages.
void checkChannel(String name);

/// The channel of [version], its first pre-release identifier; null for a
/// stable version. Throws [VersionError]: "<v> is no version", or "<v> is
/// not a release of a channel: a pre-release is written
/// <x.y.z>-<channel>.<n>", or [checkChannel]'s refusal.
String? channelOf(String version);
```

The checks run in the original's order (format, range, `latest`, `main`),
so the same input gets the same first message. The regular expression
`^[a-z][a-z0-9-]*$` is the same in Dart; Dart's `$` does not match before a
trailing newline in non-multiline mode, as in JS, so `'next\n'` is refused
(a tester case of the original).

Tests, `example/chord/test/channel_test.dart`: every case of
`tests/channel_test.ts`, same groups and names, plus the twelve rows above
as boundaries (each would fail on a pub_semver-only build), plus a parity
test in the shape of `registry_test.dart`: when `../chord` (or
`CHORD_SOURCE`) has `node_modules/semver` and bun is found, it runs one bun
process over a fixed list of a few hundred versions and names and compares
`valid`, `prerelease`, `compare` and `validRange` with the Dart answers;
skipped with a reason otherwise. No network.

## F2. Version source of truth

The original has one: `package.json`'s `version`, imported by `main.tsx`
and baked into the bun binary; the release bump writes package.json (and
bun.lock) in one commit, every stage reads it back. The port today has
`version: 0.0.1` in `example/chord/pubspec.yaml` and `const version =
'0.0.1'` in `lib/version.dart`, held together by `test/version_test.dart`.
A Dart AOT binary cannot read its pubspec at run time (it is not shipped),
so reading pubspec at start is not sound.

Sound options:

- **A. pubspec plus a held constant (as now).** The release's bump writes
  both `pubspec.yaml` and `lib/version.dart` in its one version commit, and
  reads the version back from pubspec as the original reads package.json;
  the existing test refuses a tree where they disagree, and the release's
  preflight runs it. No tool, no dependency. Cost: two files written by one
  function, the test as the guard.
- **B. Generated file.** `lib/version.g.dart` written from pubspec by a
  tool: `build_runner` (in the local cache, 2.17.1) with the `build_version`
  generator (not tried: it is not in the local cache and the brief forbids
  a registry), or a ten-line `tool/` script. Still two files in the tree, a
  test still checks them, plus a generation step every bump and a dev
  dependency for build_runner. Over A it saves only the hand edit.
- **C. `--define` at compile time.** `const version =
  String.fromEnvironment('CHORD_VERSION', defaultValue: '<pubspec>')`;
  the release compiles with `-DCHORD_VERSION=<pubspec's>`. Tried: `dart
  compile exe -D…` bakes it in, `dart run` without it gives the default,
  `dart run -D…` overrides. The default must still equal pubspec (the same
  test), so it keeps A's two places and adds a third: a binary can be built
  claiming a version the tree does not hold, which the original cannot do,
  and `dart test` only ever sees the default. Sound only with that hole.

npm `package.json` versions (shim and platform packages) and the Homebrew
formula are written by the release from the same version at pack time, as
`scripts/dev/npm.ts` does from package.json; none of them is a source.

`chord --version` needs nothing new: a channel build's version is
`1.0.0-next.3`, which already names its channel, and the original prints
`manifest.version` as is. Its exact wording is interface's.

## F3. What belongs in lib/

Nothing. Versions, channels, npm tags, package managers and releases are
about distributing one program, not about drawing a terminal; AGENTS.md
keeps `lib/` ignorant of chord, and no other program in the tree needs a
version model. The pieces stay in the port: `lib/node_semver.dart`,
`lib/channel.dart`, `lib/version.dart`, `lib/upgrade.dart`, and the release
under `example/chord/tool/`. If a second program here ever needs `chord
upgrade`'s shape, that is the time to move it, as a separate package, still
not into `chorded_tui`.

## Units

- **CTUI-130 channels and versioning**: `node_semver.dart`, `channel.dart`
  and their tests (above); pub_semver becomes a direct dependency of
  `example/chord` (`^2.2.1`, the locked version); the version source per
  Q2. I would also put here the pure release version logic,
  `example/chord/tool/release/version.dart` (`releaseVersion`,
  `isVersionArgument`, `Bump`, ported from `scripts/dev/release/version.ts`
  and `select.ts`), tested in `test/tool/release_version_test.dart` from
  `../chord/tests` cases: it is the only other user of `channelOf` and of
  the semver differences, so all of them land in one unit with one test
  set. If the lead prefers it with the release, it moves to CTUI-132 as is.
- **CTUI-131 upgrade**: uses `channelOf(version)` for the dist-tag to
  follow, asked lazily as the original does (a refused running version
  fails only the upgrade, not `--help`); `-l` sorts with
  `node_semver.compare`, unparseable entries last by string order (Dart's
  `compareTo` for `localeCompare`: a difference only for non-ASCII version
  strings, which npm does not publish).
- **CTUI-132 release**: the bump writes the version per Q2 and reads it from
  pubspec; branch and npm tag from `channelOf(version) ?? 'main'`; GitHub
  `--prerelease` from `channelOf(version) != null`.
- CTUI-133, CTUI-134: no framework part; they take the version and channel
  from the release.

No new unit.

## Packages tried

| Package | Result |
|---------|--------|
| pub_semver 2.2.1 | Works under `dart compile exe`. Ordering of pre-releases matches semver. Validation differs (rows 1 to 8), build metadata is ordered (9), no node-style range check (10), no pre-release increment (11). Used for ordering and stable bumps only. |
| `VersionConstraint.parse` (pub_semver) | Pub's constraint grammar, not npm's: takes `any`, refuses `x` and `v1`. Not used. |
| build_runner 2.17.1 | In the local cache; relevant only to option B. Not run. |
| build_version, other pub.dev semver packages | Not tried: not in the local cache, and the brief forbids reaching a registry. If the owner wants them weighed before Q1, that needs a fetch. |

## Differences from the original, with reasons

- Semver from two places, our grammar file and pub_semver, instead of one
  npm package: no Dart package validates as `semver` does (rows 1 to 8, 10).
  Pending Q1.
- `VersionError` implements `Exception` instead of extending `Error`:
  Dart's convention for a failure a caller is expected to catch; messages
  and `toString` are the same text.
- `-l` fallback order uses `compareTo`, not `localeCompare` (see CTUI-131).
- The version lives in pubspec.yaml (and version.dart per Q2) instead of
  package.json: the Dart build.

## Owner questions

- **Q1. How the port matches `semver`.**
  - (a) Our own `node_semver.dart` for `valid`, `prerelease` and the
    channel-name range check, written against semver's strict grammar;
    pub_semver for compare, `gt` and stable bumps with build metadata
    dropped. Recommended: smallest code that matches every case above,
    pinned by a parity test against the original's semver.
  - (b) pub_semver's `Version.parse` for everything, wrapped in guards for
    rows 1 to 8 and our own range check and pre-release increment: same
    behaviour, more code, the guards restate semver's grammar.
  - (c) pub_semver alone, accepting rows 1 to 12 as differences: changes
    what the original's own tests require (`1.0.0-next.01` must be refused
    as no version), so not faithful.
- **Q2. Where the version is held.** (A) pubspec plus `version.dart`,
  both written by the bump, a test holding them; (B) a generated
  `version.g.dart`; (C) `--define` at compile time with a held default.
  A and B are sound; C is sound only if a binary claiming a version the
  tree does not hold is acceptable. I would take A.
- **Q3 (for the lead, maybe a slip of the original).** `channelOf('v1.0.0')`
  is stable in the original while `v1.0.0-next.0` is refused. Follow it
  (proposed, unreachable through pubspec anyway) or refuse any input that
  is not its own normalised form.

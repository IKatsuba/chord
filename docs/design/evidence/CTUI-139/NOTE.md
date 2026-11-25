# CTUI-139 evidence

## U3: example/main.dart (pub.dev's Example tab)

The example now lives at `packages/chord_tui/example/main.dart` (U9);
these captures were taken before the move, when it was at the root.

Captured 2026-11-23 at commit 3680bade (example unchanged at 56413480),
`dart run example/main.dart` in tmux at 120x40 and 80x24.

- `example-closed-<size>.txt`: on start, the fold closed, KeyHelp on the
  last row.
- `example-open-<size>.txt` and `.ansi`: after ctrl+o, the shell code
  highlighted under the open fold.

A second ctrl+o closed the fold again and ctrl+q restored the shell at both
sizes. The example is the README's "The idea" app, line for line.

## U6: pana, publish dry run and API docs (superseded)

Superseded by the U9 run below, which is the report of record. These
files are kept for the documentation and platform progress they show.

Run 2026-11-23 at commit 19165b56 on a clean `git archive` export of that
commit, with pana 0.23.19 (dartdoc as pana activates it, latest at run time)
and Dart SDK 3.13.5 stable, macos_arm64. Temporary directories in the
outputs are relabelled `<tmp>`.

- `pana-19165b56.txt`: `pana --no-warning <export>`, **150/160**.
- `publish-dry-run-19165b56.txt`: `dart pub publish --dry-run` in the
  export, "Package has 0 warnings", 243 KB compressed.
- `dart-doc-19165b56.txt`: `dart doc --dry-run` in the export, 0 warnings
  and 0 errors.

What the score says:

- The 10 missing points are "Provide a valid `pubspec.yaml`": pana clones
  `repository` (github.com/IKatsuba/chord) and finds no pubspec named
  `chord_tui` in it. Expected: the check passes once the sources move into
  that repository.
- Documentation: 1901 of 1901 API elements documented (100.0 %); the
  earlier run at 4c9c2444 had 1888 of 1901, the gap being implicit
  constructors.
- Platforms: 20/20, 2 of 6 (macOS, Linux), as `platforms:` in pubspec.yaml
  now declares; the earlier run, with no declaration, inferred Android, iOS,
  Windows, macOS and Linux from imports alone. Web is unsupported because of
  `dart:io` and `dart:ffi`; this is expected.
- Static analysis 50/50 (errors, warnings, lints and formatting).
- Dependencies 40/40. "Compatible with dependency constraint lower bounds"
  passed: pana ran `dart pub downgrade` and `dart analyze` with no error, so
  every dependency's lower bound resolves and analyzes on SDK 3.13.5.
- Not covered: the SDK floor `^3.9.0`. pana checks only the latest stable
  SDK, and no older SDK was run here, so the floor is declared, not tested.
  A lower-bound resolution with an older SDK needs that SDK installed; pub
  has no option to resolve as an older SDK would.

## U9: final run from packages/chord_tui (report of record)

Run 2026-11-23 at commit 733dd975, after the framework moved to
`packages/chord_tui/` with the app at the root. The commands ran in
`<export>/packages/chord_tui` of a clean `git archive` export of that
commit. Tools as for U6: pana 0.23.19, Dart SDK 3.13.5 stable,
macos_arm64. Temporary directories are relabelled `<tmp>`, and the export
`<export>`.

- `pana-733dd975.txt`: `pana --no-warning <export>/packages/chord_tui`,
  **150/160**, with the same categories as U6: conventions 20/30,
  documentation 20/20 (1901 of 1901, 100.0 %, example found), platforms
  20/20 (macOS, Linux), static analysis 50/50, dependencies 40/40
  (lower bounds passed). dartdoc: 0 warnings, 0 errors.
- `publish-dry-run-733dd975.txt`: `dart pub publish --dry-run`, "Package
  has 0 warnings", 238 KB compressed.
- `dart-doc-733dd975.txt`: `dart doc --dry-run`, 0 warnings and 0 errors.

The repository check with the subpath URL
(`https://github.com/IKatsuba/chord/tree/main/packages/chord_tui`): pana
read the URL as repository `github.com/IKatsuba/chord` on branch `main`,
fetched that branch and listed its tree, and reported "Could not find any
`pubspec.yaml` in the repository". That repository has no pubspec at all
yet. A second note says the subpath URL was unreachable on a `HEAD` request
(it is a 404 until the directory exists). Both fail only because the
destination repository lacks the sources. Neither says anything against the
URL's form, and both should clear once `packages/chord_tui/pubspec.yaml`
(name `chord_tui`, a version, no `publish_to`) is on `main` there.

Still not covered: the SDK floor `^3.9.0` (pana checks only the latest
stable SDK), as noted under U6.

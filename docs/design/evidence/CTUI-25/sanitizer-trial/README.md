# Sanitizer package trial

Developer supplied this trial before the separate framework sanitizer unit.
Package: ansi_escape_codes 4.0.1, with its resolved lockfile retained.
Upstream fixture: strip-ansi 7.2.0 test.js, retained as strip-ansi-test.js;
cases.json contains its eight exact input/expected-output pairs.
The supplied result.log reports 7/8 passing under AOT. The failing case is
8-bit CSI: the package leaves U+009B sequences in the result.

Commands, from this trial directory:

```sh
cp probe.dart.txt probe.dart
dart pub get
dart compile exe probe.dart -o probe
./probe > result.log
```

Developer reported compilation succeeded. The generated binary and the raw
compile log are omitted because the latter contains a generated private path.
probe.dart.txt retains the Dart-formatted trial source without entering root
analysis; fixtures and result log are unchanged. Reproduce in a temporary
copy of this trial directory so generated package state stays outside evidence. Designer retained the trial evidence and did not rerun its
compile or review sanitizer implementation.

Main approved the exact published nested ansi-regex 6.4.0 pattern port and
MIT notice as the next option. Developer owns that framework unit, tests and
the package-choice entry in docs/decisions.md. This package failure does not
claim acceptance of the replacement implementation.

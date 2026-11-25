# CTUI-26 framework primitive evidence

These are the actual minimal probe sources and resolved dependency lock from
the completed framework trial, retained as text so they do not join repository
analysis or dependency resolution. `output.txt` transcribes the observed tool
output with private locations replaced by role placeholders. No probe was
rerun while assembling this bundle. No generated executable or package config
containing cache locations is retained.

The SDK source, package source, pubspec and lock are verbatim. The original
oracle is the same evaluated JavaScript formatted on multiple lines; the
comparison runner is the same cases and subprocess calls with its original
checkout supplied as an argument instead of a machine-specific literal.

## Reproduce

Use a disposable scratch directory with a writable Dart package cache. Copy
`pubspec.yaml.txt`, `pubspec.lock.txt`, `sdk_probe.dart.txt`, `probe.dart.txt`,
`original_oracle.mjs.txt` and `compare.py.txt` there with their final `.txt`
suffix removed. These commands run from that scratch directory:

```sh
dart --suppress-analytics pub get --offline
dart --suppress-analytics compile exe sdk_probe.dart -o sdk_probe
./sdk_probe
dart --suppress-analytics compile exe probe.dart -o probe
python3 compare.py <original-checkout>
```

`<original-checkout>` means the read-only original `../chord` checkout as
resolved from the repository, with its existing Bun dependencies installed.
The runner executes Bun there but writes no file there. The source trial used
its installed xdg-basedir 5.1.0. The offline command requires the exact locked
packages already cached; a normal pub get may fetch them when authorized.
No repository dependency files need changing to run these probes.

The XDG comparison intentionally unsets HOME only in its child environment;
it never changes the shell's HOME. The first four cases assume the launching
environment has nonempty HOME. Output reveals only boolean path properties,
not account-home values. The SDK executable creates and deletes its own
scratch record directory.

## Interpretation

SDK append/UTF-8 line-stream/JSON round trip/flush/close work under native
compilation. uuid 4.6.0 produced 10,000 distinct canonical v4 values per case.
xdg_directories 1.1.0 matches the original for the tested absolute, relative,
empty and missing override cases when HOME is present. Both packages accept
a relative override. Without both HOME and XDG_STATE_HOME, the candidate
throws StateError while the original resolves the OS account home on this
host. Main accepted requiring a nonempty HOME or XDG_STATE_HOME with a clear
error otherwise; no workaround was implemented.

Package provenance: [uuid 4.6.0](https://pub.dev/packages/uuid/versions/4.6.0),
[xdg_directories 1.1.0](https://pub.dev/packages/xdg_directories/versions/1.1.0).
The lock retains all six resolved versions and hosted archive checksums.
The xdg package advertises Linux; only its pure-Dart stateHome surface was
exercised on macOS arm64. Production lifecycle, crash durability, concurrent
append atomicity, performance and screen parity are separate ship gates.

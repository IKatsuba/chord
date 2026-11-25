# File discovery package and production trials

Developer supplied these artifacts for retention. Designer copied/inspected
trial material only, did not rerun a compile/oracle or inspect unhanded
production implementation. No production commit was named for these probes,
so these are trial results, not exact-commit QA or a reviewer/tester handover.

## Package trial

package/probe.dart.txt uses the published serverpod_cloud_cli1.3.1 public
Ignore.listFiles helper. listDir uses Directory.listSync(followLinks:false),
relative paths and basename.git exclusion; ignoreForDir reads .gitignore lines;
isDir uses Directory.existsSync. It checks root/nested ignore rules, child
negation, anchoring, dotfiles, nonrepository operation and file-only discovery.
The supplied pub log resolves75 dependencies including nocterm, so main chose
the narrow exact BSD helper port rather than adding the full CLI dependency.
The initial package AOT run was reported passing by developer; the retained
package aot.log records compilation only, not separate runtime stdout.

Pinned pubspec/lock, dependency log and selected immutable package metadata,
original license/header and dart-lang/pub e9ad2bc source pointer are retained.
No binary or generated package_config is retained. probe sources are .dart.txt
so they do not enter root analysis. Generated paths in logs are normalized to
relative executable names or the trial directory; test/result content is not
changed. The initial helper source is also retained, not silently overwritten.

Reproduce from a temporary copy of package (outside the checkout):

```sh
cp probe.dart.txt probe.dart
dart pub get
dart compile exe probe.dart -o probe
./probe
```

## Original discovery oracle

production/initial-result.json retains the first oracle:16 original paths,
17 helper paths, with only the broken symlink extra. production/result.json
retains the later supplied result:16 paths on each side, no differences after
the owner-approved broken-link filter. The fixture covers nested ignore and
negation, .git exclusion, dotfiles, file and directory symlinks, external links
and a broken link. Array sorting here compares membership, not locale order;
the separately approved depth/lowercase/original codepoint ordering contract
still needs its own tests. Fixture trees were cleaned in the supplied probe.

The production Dart adapter is retained unchanged except its .txt extension.
The Python fixture logic/results are unchanged; only hard-coded script paths
are relative to the retained script, and CHORD_SOURCE must be supplied by the
caller. original-discovery.ts calls the read-only original files module.

For reproduction, run from this repository root with the port's generated
package_config available. Set CHORD_SOURCE to the actual read-only original
checkout (the canonical primary-checkout location is ../chord). Copy production
to a temporary directory and restore .dart filenames there:

```sh
trial_dir=$(mktemp -d)
cp -R docs/design/evidence/CTUI-24/walker-trial/production/. "$trial_dir/"
cp "$trial_dir/discovery.dart.txt" "$trial_dir/discovery.dart"
python3 "$trial_dir/oracle.py"
```

## Production AOT core probe

core-aot.dart.txt/core-aot.log retain the supplied production probe and output:
nested ignore/dotfiles/nonrepository, broken links, ordered/deduplicated URI
links, cancellable-isolate discovery, cancelled links and fixture cleanup.
The log reports both PASS lines. It is developer-supplied runtime evidence,
not a designer rerun or attribution to a handed implementation commit.

From the same temporary production copy and repository-root working directory:

```sh
cp "$trial_dir/core-aot.dart.txt" "$trial_dir/core-aot.dart"
dart compile exe --packages=example/chord/.dart_tool/package_config.json "$trial_dir/core-aot.dart" -o "$trial_dir/core-aot"
"$trial_dir/core-aot"
rm -rf "$trial_dir"
```

No production dependency or analyzer exclusion was changed by this retention.
Developer retains ownership of the original trial files and decisions entry.
Reviewer/tester must receive the eventual signed implementation separately.

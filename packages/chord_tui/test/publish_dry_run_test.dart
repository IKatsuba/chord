@Tags(['publish'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// The warnings `dart pub publish --dry-run` may report; none.
const expectedWarnings = 0;

/// The archive's paths, read from the tree the dry run prints.
List<String> archived(String output) {
  final paths = <String>[];
  final parents = <String>[];
  final entry = RegExp(r'^((?:│   |    )*)[├└]── (.+?)(?: \([^)]*\))?$');
  for (final line in output.split('\n')) {
    final match = entry.firstMatch(line);
    if (match == null) continue;
    final depth = match.group(1)!.length ~/ 4;
    parents
      ..length = depth
      ..add(match.group(2)!);
    paths.add(parents.join('/'));
  }
  return paths;
}

void main() {
  late Directory place;

  setUp(() => place = Directory.systemTemp.createTempSync('chord_tui_pub'));
  tearDown(() => place.deleteSync(recursive: true));

  test('the published archive holds the framework alone and validates with '
      'no warnings', () async {
    // HEAD's packages/chord_tui (git archive from here exports only this
    // folder), outside git: the dry run warns about uncommitted changes,
    // and a shared tree has others' work in progress.
    final tar = '${place.path}/head.tar';
    final archive = await Process.run('git', [
      'archive',
      '--format=tar',
      '-o',
      tar,
      'HEAD',
    ]);
    expect(archive.exitCode, 0, reason: '${archive.stderr}');
    final tree = Directory('${place.path}/chord_tui')..createSync();
    final unpacked = await Process.run('tar', ['-xf', tar, '-C', tree.path]);
    expect(unpacked.exitCode, 0, reason: '${unpacked.stderr}');

    final dry = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'publish',
      '--dry-run',
    ], workingDirectory: tree.path);
    final output = '${dry.stdout}\n${dry.stderr}';

    expect(output, contains('Package has $expectedWarnings warnings.'));
    expect(dry.exitCode, 0, reason: output);
    final paths = archived('${dry.stdout}');
    expect(
      paths,
      containsAll([
        'lib/chord_tui.dart',
        'lib/testing.dart',
        'example/main.dart',
        'README.md',
        'CHANGELOG.md',
        'LICENSE',
        'pubspec.yaml',
      ]),
    );
    for (final left in [
      'test',
      'benchmark',
      'dart_test.yaml',
      'pubspec.lock',
    ]) {
      expect(
        paths.where((path) => path == left || path.startsWith('$left/')),
        isEmpty,
        reason: '$left is not published',
      );
    }
  });
}

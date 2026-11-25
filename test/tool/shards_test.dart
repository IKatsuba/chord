// The shards CI splits the suites into: every test file of both packages
// in exactly one shard, whatever the count.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/shards.dart';
import '../fixtures/fake.dart' show portPackageDir;

void main() {
  final root = portPackageDir();

  group('tester: CTUI-146 sparse shards and input boundaries', () {
    test(
      'zero and one file leave the extra shards empty without mutating input',
      () {
        const files = ['test/only_test.dart'];
        for (var k = 1; k <= 4; k++) {
          expect(shardOf(const [], k, 4), isEmpty);
          expect(shardOf(files, k, 4), k == 1 ? files : isEmpty);
        }
        expect(files, ['test/only_test.dart']);
      },
    );

    test('nondecimal, whitespace and overflowing shard words are refused', () {
      for (final text in [
        ' 1/2',
        '1/2 ',
        '1/2\n',
        '1/2\r',
        '１/２',
        '1/2\u001b[31m',
        '999999999999999999999/2',
      ]) {
        expect(() => parseShard(text), throwsFormatException, reason: text);
      }
      for (final (k, n) in [(1, 0), (1, -1), (2, 1), (-1, 2)]) {
        expect(() => shardOf(const ['one'], k, n), throwsArgumentError);
      }
    });

    test(
      'file and directory links cannot duplicate or recurse through tests',
      () {
        final directory = Directory.systemTemp.createTempSync(
          'chord-shard-links-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File(
          p.join(directory.path, 'test', 'nested', 'a_test.dart'),
        )..createSync(recursive: true);
        Link(
          p.join(directory.path, 'test', 'alias_test.dart'),
        ).createSync(file.path);
        Link(
          p.join(directory.path, 'test', 'alias'),
        ).createSync(file.parent.path);
        Link(
          p.join(directory.path, 'test', 'cycle'),
        ).createSync(p.join(directory.path, 'test'));
        expect(testFiles(directory.path), ['test/nested/a_test.dart']);
      },
    );

    test(
      'an empty package prints no newline or accidental whole-suite argument',
      () {
        final directory = Directory.systemTemp.createTempSync(
          'chord-empty-shard-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        Directory(p.join(directory.path, 'test')).createSync();
        final result = Process.runSync(Platform.resolvedExecutable, [
          'run',
          p.join(root, 'tool', 'shards.dart'),
          '--package=${directory.path}',
          '--shard=3/4',
        ], workingDirectory: root);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, isEmpty);
        expect(result.stderr, isEmpty);
      },
    );
  });

  test('a package\'s test files are every *_test.dart under test/, sorted, '
      'relative and posix', () {
    final dir = Directory.systemTemp.createTempSync('chord-shards-');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final path in [
      'test/b_test.dart',
      'test/a/z_test.dart',
      'test/a/helper.dart',
      'test/fixtures/thing_test.dart',
      'lib/lib_test.dart',
    ]) {
      File(p.join(dir.path, path)).createSync(recursive: true);
    }
    expect(testFiles(dir.path), [
      'test/a/z_test.dart',
      'test/b_test.dart',
      'test/fixtures/thing_test.dart',
    ]);
    expect(testFiles(p.join(dir.path, 'none')), isEmpty);
  });

  for (final (name, package) in [
    ('the app', root),
    ('the framework', p.join(root, 'packages', 'chord_tui')),
  ]) {
    test('$name: every test file is in exactly one shard, for any count', () {
      final files = testFiles(package);
      expect(files, isNotEmpty);
      for (var n = 1; n <= 7; n++) {
        final seen = <String>[
          for (var k = 1; k <= n; k++) ...shardOf(files, k, n),
        ];
        expect(seen..sort(), files, reason: '$n shards');
        final sizes = [
          for (var k = 1; k <= n; k++) shardOf(files, k, n).length,
        ];
        expect(
          sizes.reduce((a, b) => a > b ? a : b) -
              sizes.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(1),
          reason: 'shards differ by one file at most',
        );
      }
    });
  }

  test('a shard is k/n with 1 <= k <= n', () {
    expect(parseShard('2/3'), (2, 3));
    for (final bad in ['0/3', '4/3', '1/0', '1', 'a/b', '-1/2', '1/2/3']) {
      expect(() => parseShard(bad), throwsFormatException, reason: bad);
    }
    expect(() => shardOf(const ['x'], 0, 1), throwsArgumentError);
  });

  group('the command line', () {
    final script = p.join(root, 'tool', 'shards.dart');
    ProcessResult shards(List<String> args) => Process.runSync(
      Platform.resolvedExecutable,
      ['run', script, ...args],
      workingDirectory: root,
    );

    test('prints shard k of n of a package, a file a line', () {
      final result = shards(['--package=.', '--shard=2/3']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        (result.stdout as String).trim().split('\n'),
        shardOf(testFiles(root), 2, 3),
      );
      final framework = shards(['--package=packages/chord_tui', '--shard=1/1']);
      expect(
        (framework.stdout as String).trim().split('\n'),
        testFiles(p.join(root, 'packages', 'chord_tui')),
      );
    });

    test('refuses what is not a shard or a package, exiting 2', () {
      for (final args in [
        <String>[],
        ['--package=.'],
        ['--package=.', '--shard=3/2'],
        ['--package=nowhere', '--shard=1/2'],
        ['--package=.', '--shard=1/2', '--other'],
      ]) {
        expect(shards(args).exitCode, 2, reason: '$args');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 1)));
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/bump.dart';
import '../../../tool/release/continue.dart' show manifestPath;
import '../../../tool/release/runner.dart';
import '../../../tool/release/version.dart';

void main() {
  group('tester: shared version transaction boundaries', () {
    late Directory root;
    late Map<String, String> before;
    late _NoCommitRunner runner;

    File file(String path) => File(p.join(root.path, path));

    setUp(() {
      root = Directory.systemTemp.createTempSync('shared_version_test');
      runner = _NoCommitRunner();
      before = {
        frameworkManifestPath: 'name: chord_tui\nversion: 1.2.0 # framework\n',
        manifestPath: 'name: chord\nversion: 1.2.0 # port\n',
        lockPath:
            'packages:\n  chord_tui:\n    source: path\n'
            '    version: "1.2.0"\n',
        heldVersionPath: "/// Shared version.\nconst version = '1.2.0';\n",
      };
      for (final entry in before.entries) {
        file(entry.key)
          ..createSync(recursive: true)
          ..writeAsStringSync(entry.value);
      }
    });

    tearDown(() => root.deleteSync(recursive: true));

    for (final failedPath in [
      frameworkManifestPath,
      manifestPath,
      lockPath,
      heldVersionPath,
    ]) {
      test(
        'a failed write to $failedPath restores every original byte',
        () async {
          await expectLater(
            commitVersion(
              runner,
              root.path,
              '1.3.0-next.0',
              write: (path, text) {
                file(path).writeAsStringSync(text);
                if (path == failedPath) {
                  throw const FileSystemException('partial write');
                }
              },
            ),
            throwsA(isA<FileSystemException>()),
          );
          for (final entry in before.entries) {
            expect(file(entry.key).readAsStringSync(), entry.value);
          }
          expect(runner.commits, 0);
        },
      );
    }

    test('a missing held version refuses before the first write', () async {
      before[heldVersionPath] = 'const other = 1;\n';
      file(heldVersionPath).writeAsStringSync(before[heldVersionPath]!);
      await expectLater(
        commitVersion(
          runner,
          root.path,
          '1.3.0',
          write: (_, _) => fail('no file may be written'),
        ),
        throwsA(isA<ReleaseError>()),
      );
      for (final entry in before.entries) {
        expect(file(entry.key).readAsStringSync(), entry.value);
      }
      expect(runner.commits, 0);
    });

    test('an incomplete framework lock entry cannot use its neighbor', () {
      const lock =
          'packages:\n  chord_tui:\n    source: path\n'
          '  other:\n    version: "1.2.0"\n';
      expect(withLockedVersion(lock, '1.3.0'), isNull);
    });
  });
}

final class _NoCommitRunner implements ReleaseRunner {
  var commits = 0;

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    if (command == 'git' && args.first == 'rev-parse') {
      return const Ran(0, stdout: 'base\n');
    }
    commits++;
    fail('a refused transaction must not reach $command $args');
  }

  @override
  Future<Started> start(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  }) async => throw StateError('no process may start');
}

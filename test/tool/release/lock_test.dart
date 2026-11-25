import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/lock.dart';
import '../../../tool/release/runner.dart';

Matcher dies(String text) =>
    throwsA(isA<ReleaseError>().having((e) => e.message, 'message', text));

final gitEnv = {
  ...Platform.environment,
  'GIT_CONFIG_GLOBAL': '/dev/null',
  'GIT_CONFIG_NOSYSTEM': '1',
  'GIT_AUTHOR_NAME': 'release test',
  'GIT_AUTHOR_EMAIL': 'release@test.invalid',
  'GIT_COMMITTER_NAME': 'release test',
  'GIT_COMMITTER_EMAIL': 'release@test.invalid',
};

void main() {
  late Directory place;
  late String work;
  late String file;

  Future<void> git(List<String> args, {String? cwd}) async {
    final ran = await Process.run(
      'git',
      args,
      workingDirectory: cwd ?? work,
      environment: gitEnv,
      includeParentEnvironment: false,
    );
    expect(ran.exitCode, 0, reason: '${ran.stderr}');
  }

  ReleaseRunner runnerIn(String root) =>
      ProcessReleaseRunner(root: root, env: gitEnv);

  setUp(() async {
    place = Directory.systemTemp.createTempSync('lock_test');
    work = p.join(place.path, 'work');
    await git(['init', '-q', '-b', 'main', work], cwd: place.path);
    File(p.join(work, 'a')).writeAsStringSync('a');
    await git(['add', '-A']);
    await git(['commit', '-q', '-m', 'start']);
    file = p.join(
      Directory(p.join(work, '.git')).resolveSymbolicLinksSync(),
      'chord-release',
    );
  });
  tearDown(() => place.deleteSync(recursive: true));

  test("the lock is beside a file in git's common directory", () async {
    expect(await lockFile(runnerIn(work), work), file);
  });

  test("a second release in the checkout is refused, naming the first's pid "
      'and the lock to remove', () async {
    final release = await holdRelease(runnerIn(work), work);
    expect(File(file).readAsStringSync(), '$pid\n');
    await expectLater(
      holdRelease(runnerIn(work), work),
      dies(
        'another release runs in this checkout (pid $pid); if it was killed, '
        'remove $file.lock',
      ),
    );
    await release();
    expect(File('$file.lock').existsSync(), isFalse);
    final again = await holdRelease(runnerIn(work), work);
    await again();
  });

  test('a worktree of the clone shares the lock', () async {
    final tree = p.join(place.path, 'tree');
    await git(['worktree', 'add', '-q', tree]);
    expect(await lockFile(runnerIn(tree), tree), file);
    final release = await holdRelease(runnerIn(work), work);
    await expectLater(
      holdRelease(runnerIn(tree), tree),
      dies(
        'another release runs in this checkout (pid $pid); if it was killed, '
        'remove $file.lock',
      ),
    );
    await release();
  });

  test('a lock a killed run left, however old, is never taken over: it is '
      'refused, naming its pid and the path', () async {
    File('$file.lock').writeAsStringSync('');
    File('$file.lock').setLastModifiedSync(DateTime(2000));
    File(file).writeAsStringSync('4242\n');
    await expectLater(
      holdRelease(runnerIn(work), work),
      dies(
        'another release runs in this checkout (pid 4242); if it was killed, '
        'remove $file.lock',
      ),
    );
    expect(File('$file.lock').existsSync(), isTrue);
  });

  test('a lock without a pid is refused as unknown', () async {
    File('$file.lock').writeAsStringSync('');
    await expectLater(
      holdRelease(runnerIn(work), work),
      dies(
        'another release runs in this checkout (pid unknown); if it was '
        'killed, remove $file.lock',
      ),
    );
  });

  test(
    'a release given up twice never removes a later holder\'s lock',
    () async {
      final first = await holdRelease(runnerIn(work), work);
      await first();
      final second = await holdRelease(runnerIn(work), work);
      await first();
      expect(File('$file.lock').existsSync(), isTrue);
      await second();
      expect(File('$file.lock').existsSync(), isFalse);
    },
  );

  test(
    'a pid that cannot be written lets the lock go before the error',
    () async {
      await expectLater(
        holdRelease(
          runnerIn(work),
          work,
          writePid: (_) => throw const FileSystemException('disk full'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File('$file.lock').existsSync(), isFalse);
      final release = await holdRelease(runnerIn(work), work);
      await release();
    },
  );

  test(
    'outside a git checkout, the lock is refused with what git said',
    () async {
      final outside = Directory(p.join(place.path, 'outside'))..createSync();
      await expectLater(
        holdRelease(runnerIn(outside.path), outside.path),
        throwsA(
          isA<ReleaseError>().having(
            (e) => e.message,
            'message',
            startsWith('git rev-parse --git-common-dir failed: '),
          ),
        ),
      );
    },
  );

  group('tester: simultaneous release locks', () {
    test('two concurrent acquisitions yield exactly one owner', () async {
      Future<Future<void> Function()?> attempt() async {
        try {
          return await holdRelease(runnerIn(work), work);
        } on ReleaseError {
          return null;
        }
      }

      final owners = await Future.wait([attempt(), attempt()]);
      try {
        expect(owners.where((owner) => owner != null), hasLength(1));
        expect(File('$file.lock').existsSync(), isTrue);
      } finally {
        for (final owner in owners) {
          if (owner != null) await owner();
        }
      }
      expect(File('$file.lock').existsSync(), isFalse);
    });
  });
}

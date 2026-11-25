import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/bump.dart';
import '../../../tool/release/continue.dart';
import '../../../tool/release/runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

final gitEnv = {
  ...Platform.environment,
  'GIT_CONFIG_GLOBAL': '/dev/null',
  'GIT_CONFIG_NOSYSTEM': '1',
  'GIT_AUTHOR_NAME': 'release test',
  'GIT_AUTHOR_EMAIL': 'release@test.invalid',
  'GIT_COMMITTER_NAME': 'release test',
  'GIT_COMMITTER_EMAIL': 'release@test.invalid',
};

const pubspec = 'name: chord\nversion: 1.2.0\npublish_to: none\n';
const framework = 'name: chord_tui\nversion: 1.2.0\n';
const lock = '''
packages:
  chord_tui:
    dependency: "direct main"
    description:
      path: "packages/chord_tui"
      relative: true
    source: path
    version: "1.2.0"
  path:
    dependency: "direct main"
    description:
      name: path
      url: "https://pub.dev"
    source: hosted
    version: "1.2.0"
sdks:
  dart: ">=3.9.0 <4.0.0"
''';
const held = "/// The port's version.\nconst version = '1.2.0';\n";

void main() {
  late Directory place;
  late String work;
  late ProcessReleaseRunner runner;
  late List<String> errs;

  Future<String> git(List<String> args) async {
    final ran = await Process.run(
      'git',
      args,
      workingDirectory: work,
      environment: gitEnv,
      includeParentEnvironment: false,
    );
    expect(ran.exitCode, 0, reason: '${ran.stderr}');
    return (ran.stdout as String).trim();
  }

  String read(String path) => File(p.join(work, path)).readAsStringSync();

  setUp(() async {
    place = Directory.systemTemp.createTempSync('bump_test');
    work = p.join(place.path, 'work');
    final origin = p.join(place.path, 'origin.git');
    await Process.run('git', [
      'init',
      '-q',
      '--bare',
      '-b',
      'main',
      origin,
    ], environment: gitEnv);
    await Process.run('git', [
      'init',
      '-q',
      '-b',
      'main',
      work,
    ], environment: gitEnv);
    (File(
      p.join(work, manifestPath),
    )..createSync(recursive: true)).writeAsStringSync(pubspec);
    (File(
      p.join(work, frameworkManifestPath),
    )..createSync(recursive: true)).writeAsStringSync(framework);
    File(p.join(work, lockPath)).writeAsStringSync(lock);
    (File(
      p.join(work, heldVersionPath),
    )..createSync(recursive: true)).writeAsStringSync(held);
    File(p.join(work, 'other.txt')).writeAsStringSync('other\n');
    await git(['add', '-A']);
    await git(['commit', '-q', '-m', 'start']);
    await git(['remote', 'add', 'origin', origin]);
    await git(['push', '-q', 'origin', 'main']);
    runner = ProcessReleaseRunner(root: work, env: gitEnv);
    errs = [];
  });
  tearDown(() => place.deleteSync(recursive: true));

  test('the version commit holds both pubspec.yaml files, the port lock and '
      'lib/version.dart alone, '
      'told by their sums before it is made', () async {
    final head = await git(['rev-parse', 'HEAD']);
    File(p.join(work, 'other.txt')).writeAsStringSync('changed\n');
    Map<String, String>? told;
    expect(
      await commitVersion(runner, work, '1.3.0', committing: (f) => told = f),
      head,
    );
    expect(read(manifestPath), pubspec.replaceFirst('1.2.0', '1.3.0'));
    expect(
      read(frameworkManifestPath),
      framework.replaceFirst('1.2.0', '1.3.0'),
    );
    // Only the framework's entry moves; another package at 1.2.0 stays.
    expect(
      read(lockPath),
      lock.replaceFirst('version: "1.2.0"', 'version: "1.3.0"'),
    );
    expect(read(heldVersionPath), held.replaceFirst('1.2.0', '1.3.0'));
    expect(await git(['log', '-1', '--format=%s']), 'chore: chord v1.3.0');
    expect(
      await git(['show', '--name-only', '--format=', 'HEAD']),
      // git lists them sorted by path.
      ([...versionFiles]..sort()).join('\n'),
    );
    expect(told, {
      for (final path in versionFiles)
        path: sha256.convert(utf8.encode(read(path))).toString(),
    });
    // A change elsewhere stays out of it.
    expect(await git(['status', '--porcelain']), 'M other.txt');
  });

  test('a commit that fails puts the files back', () async {
    final failing = _FailingCommit(runner);
    await expectLater(
      commitVersion(failing, work, '1.3.0'),
      dies(
        'git commit of $manifestPath, $frameworkManifestPath, $lockPath, '
        '$heldVersionPath failed',
      ),
    );
    expect(read(manifestPath), pubspec);
    expect(read(frameworkManifestPath), framework);
    expect(read(lockPath), lock);
    expect(read(heldVersionPath), held);
  });

  test(
    'dropped, the branch is back where it was, a tracked edit kept',
    () async {
      final head = await commitVersion(runner, work, '1.3.0');
      File(p.join(work, 'other.txt')).writeAsStringSync('stage edit\n');
      await dropVersion(runner, head);
      expect(await git(['rev-parse', 'HEAD']), head);
      expect(read('other.txt'), 'stage edit\n');
      expect(read(manifestPath), pubspec);
    },
  );

  test('held, a signal drops the commit and ends the run by it', () async {
    final head = await commitVersion(runner, work, '1.3.0');
    final hup = StreamController<ProcessSignal>.broadcast();
    final raised = Completer<ProcessSignal>();
    holdVersion(
      runner,
      head,
      err: errs.add,
      watch: (signal) =>
          signal == ProcessSignal.sighup ? hup.stream : const Stream.empty(),
      raise: raised.complete,
    );
    hup.add(ProcessSignal.sighup);
    expect(await raised.future, ProcessSignal.sighup);
    expect(await git(['rev-parse', 'HEAD']), head);
    expect(hup.hasListener, isFalse);
    await hup.close();
  });

  test('held, a drop is once, and kept means no signal drops it', () async {
    final head = await commitVersion(runner, work, '1.3.0');
    final made = await git(['rev-parse', 'HEAD']);
    final hup = StreamController<ProcessSignal>.broadcast();
    final kept = holdVersion(
      runner,
      head,
      err: errs.add,
      watch: (signal) =>
          signal == ProcessSignal.sighup ? hup.stream : const Stream.empty(),
      raise: (_) => fail('no signal is raised once kept'),
    );
    kept.keep();
    expect(hup.hasListener, isFalse);
    expect(await git(['rev-parse', 'HEAD']), made);
    await hup.close();
  });

  test('pushed to main for a stable version; a held commit dropped when the '
      'push fails', () async {
    final head = await commitVersion(runner, work, '1.3.0');
    await pushVersion(runner, '1.3.0');
    expect(
      await git(['rev-parse', 'origin/main']),
      await git(['rev-parse', 'HEAD']),
    );

    await commitVersion(runner, work, '1.4.0');
    final failing = _FailingPush(runner);
    final hold = holdVersion(
      failing,
      await git(['rev-parse', 'HEAD~1']),
      err: errs.add,
      watch: (_) => const Stream.empty(),
    );
    await expectLater(
      pushVersion(failing, '1.4.0', held: hold),
      dies('git push origin main failed, so chore: chord v1.4.0 is dropped'),
    );
    expect(read(manifestPath), contains('1.3.0'));
    expect(head, isNotEmpty);
  });

  test('a push that fails with a state keeps the commit, and says how to go '
      'on', () async {
    await commitVersion(runner, work, '1.3.0');
    await expectLater(
      pushVersion(_FailingPush(runner), '1.3.0'),
      dies(
        'git push origin main failed; chore: chord v1.3.0 stays committed, '
        'and `dart run tool/release.dart chord` pushes it',
      ),
    );
    expect(read(manifestPath), contains('1.3.0'));
  });

  test("a channel's version is pushed to the channel's branch", () async {
    final recording = _Recording(runner);
    await pushVersion(recording, '1.3.0-next.0').catchError((_) {});
    expect(recording.pushes.single, ['push', '-q', 'origin', 'next']);
  });

  test('a signal during a drop waits for that one rollback, then ends the '
      'run; the handlers stay until it has ended', () async {
    final head = await commitVersion(runner, work, '1.3.0');
    final gate = Completer<void>();
    final blocked = _BlockedReset(runner, gate.future);
    final hup = StreamController<ProcessSignal>.broadcast();
    final raised = <ProcessSignal>[];
    final hold = holdVersion(
      blocked,
      head,
      err: errs.add,
      watch: (signal) =>
          signal == ProcessSignal.sighup ? hup.stream : const Stream.empty(),
      raise: raised.add,
    );
    final dropping = hold.drop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hup.hasListener, isTrue, reason: 'handlers kept while resetting');
    hup.add(ProcessSignal.sighup);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(raised, isEmpty, reason: 'the signal waits for the rollback');
    gate.complete();
    await dropping;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(raised, [ProcessSignal.sighup]);
    expect(blocked.resets, 1);
    expect(await git(['rev-parse', 'HEAD']), head);
    expect(hup.hasListener, isFalse);
    await hup.close();
  });

  test('a committing step that throws puts every file back, HEAD where it '
      'was', () async {
    final head = await git(['rev-parse', 'HEAD']);
    await expectLater(
      commitVersion(
        runner,
        work,
        '1.3.0',
        committing: (_) => throw const FileSystemException('state full'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(read(manifestPath), pubspec);
    expect(read(frameworkManifestPath), framework);
    expect(read(lockPath), lock);
    expect(read(heldVersionPath), held);
    expect(await git(['rev-parse', 'HEAD']), head);
  });

  test("a framework pubspec.yaml without a version line is refused, nothing "
      'written or committed', () async {
    final head = await git(['rev-parse', 'HEAD']);
    File(
      p.join(work, frameworkManifestPath),
    ).writeAsStringSync('name: chord_tui\n');
    await expectLater(
      commitVersion(runner, work, '1.3.0'),
      dies('$frameworkManifestPath has no version line'),
    );
    expect(read(manifestPath), pubspec);
    expect(read(heldVersionPath), held);
    expect(await git(['rev-parse', 'HEAD']), head);
  });

  test('a port lock without chord_tui is refused, nothing written or '
      'committed', () async {
    final head = await git(['rev-parse', 'HEAD']);
    File(p.join(work, lockPath)).writeAsStringSync('packages: {}\n');
    await expectLater(
      commitVersion(runner, work, '1.3.0'),
      dies('$lockPath locks no chord_tui'),
    );
    expect(read(manifestPath), pubspec);
    expect(read(frameworkManifestPath), framework);
    expect(await git(['rev-parse', 'HEAD']), head);
  });

  test('after the version commit, the port still resolves with an enforced '
      'lockfile', () async {
    // A real framework and port resolved offline: neither has a hosted
    // dependency, so pub writes and checks the lock without a network.
    final tree = p.join(place.path, 'tree');
    const sdk = "environment:\n  sdk: '>=3.9.0 <4.0.0'\n";
    (File(p.join(tree, frameworkManifestPath))..createSync(recursive: true))
        .writeAsStringSync('name: chord_tui\nversion: 1.2.0\n$sdk');
    (File(
      p.join(tree, manifestPath),
    )..createSync(recursive: true)).writeAsStringSync(
      'name: chord\nversion: 1.2.0\npublish_to: none\n$sdk'
      'dependencies:\n  chord_tui:\n    path: packages/chord_tui\n',
    );
    (File(
      p.join(tree, heldVersionPath),
    )..createSync(recursive: true)).writeAsStringSync(held);
    Future<ProcessResult> pubGet([List<String> more = const []]) => Process.run(
      Platform.resolvedExecutable,
      ['pub', 'get', '--offline', ...more],
      workingDirectory: tree,
    );
    final got = await pubGet();
    expect(got.exitCode, 0, reason: '${got.stderr}');
    work = tree;
    await git(['init', '-q', '-b', 'main']);
    await git(['add', ...versionFiles]);
    await git(['commit', '-q', '-m', 'start']);

    await commitVersion(
      ProcessReleaseRunner(root: tree, env: gitEnv),
      tree,
      '1.3.0',
    );
    final enforced = await pubGet(['--enforce-lockfile']);
    expect(enforced.exitCode, 0, reason: '${enforced.stderr}');
    expect(await git(['status', '--porcelain', '--', lockPath]), isEmpty);
  });

  test(
    'a later file that cannot be written puts the ones before back',
    () async {
      var writes = 0;
      await expectLater(
        commitVersion(
          runner,
          work,
          '1.3.0',
          write: (path, text) {
            if (++writes == versionFiles.length) {
              throw const FileSystemException('disk full');
            }
            File(p.join(work, path)).writeAsStringSync(text);
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(read(manifestPath), pubspec);
      expect(read(frameworkManifestPath), framework);
      expect(read(lockPath), lock);
      expect(read(heldVersionPath), held);
    },
  );
}

/// A runner whose `git reset` waits for [gate], counting resets.
final class _BlockedReset extends _Through {
  _BlockedReset(super.inner, this.gate);

  final Future<void> gate;
  var resets = 0;

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    if (command == 'git' && args.first == 'reset') {
      resets++;
      await gate;
    }
    return super.run(command, args, loud: loud, cwd: cwd, env: env);
  }
}

/// A runner whose `git commit` fails.
final class _FailingCommit extends _Through {
  _FailingCommit(super.inner);

  @override
  bool fails(String command, List<String> args) =>
      command == 'git' && args.first == 'commit';
}

/// A runner whose `git push` fails.
final class _FailingPush extends _Through {
  _FailingPush(super.inner);

  @override
  bool fails(String command, List<String> args) =>
      command == 'git' && args.first == 'push';
}

/// A runner that records `git push` and answers it 0.
final class _Recording extends _Through {
  _Recording(super.inner);

  final pushes = <List<String>>[];

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    if (command == 'git' && args.first == 'push') {
      pushes.add(args);
      return const Ran(0);
    }
    return super.run(command, args, loud: loud, cwd: cwd, env: env);
  }
}

class _Through implements ReleaseRunner {
  _Through(this.inner);

  final ReleaseRunner inner;

  bool fails(String command, List<String> args) => false;

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async => fails(command, args)
      ? const Ran(1, stderr: 'refused\n')
      : inner.run(command, args, loud: loud, cwd: cwd, env: env);

  @override
  Future<Started> start(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  }) => inner.start(command, args, cwd: cwd, env: env);
}

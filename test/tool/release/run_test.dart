import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/archive.dart';
import '../../../tool/release/build.dart';
import '../../../tool/release/bump.dart';
import '../../../tool/release/continue.dart';
import '../../../tool/release/pack.dart';
import '../../../tool/release/preflight.dart';
import '../../../tool/release/run.dart';
import '../../../tool/release/runner.dart';
import '../../../tool/release/select.dart';
import '../../../tool/release/stages.dart';
import '../../../tool/release/state.dart';
import '../../../tool/targets.dart';

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

/// git for real in the scratch tree, origin said to be IKatsuba/chord; npm
/// and gh a world of the test's.
final class Machine implements ReleaseRunner {
  Machine(this.root);

  final String root;
  final onNpm = <String>{'@chorded/cursor-cloud-acp@0.2.0'};
  final log = <String>[];
  late final _git = ProcessReleaseRunner(root: root, env: gitEnv);

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    final line = [command, ...args].join(' ');
    log.add(line);
    switch ([command, ...args]) {
      case ['git', 'remote', 'get-url', ...]:
        return const Ran(0, stdout: 'git@github.com:IKatsuba/chord.git\n');
      case ['git', ...]:
        return _git.run(command, args, loud: false, cwd: cwd, env: env);
      case ['npm', 'whoami']:
        return const Ran(0, stdout: 'owner\n');
      case ['npm', 'view', final spec, 'version']:
        return onNpm.contains(spec)
            ? Ran(0, stdout: '${spec.split('@').last}\n')
            : const Ran(1, stderr: 'npm error code E404\n');
      case ['npm', 'view', _, 'dist-tags.latest']:
        return const Ran(0, stdout: '1.2.0\n');
      case ['npm', 'publish', _, _, final file, ...]:
        final base = p.basename(file);
        final name = npmNames.firstWhere(
          (n) => base.startsWith(
            '${n.replaceFirst('@', '').replaceFirst('/', '-')}-',
          ),
        );
        final version = base
            .substring(
              '${name.replaceFirst('@', '').replaceFirst('/', '-')}-'.length,
            )
            .replaceFirst(RegExp(r'\.tgz$'), '');
        onNpm.add('$name@$version');
        return const Ran(0);
      case ['gh', 'auth', 'status']:
        return const Ran(0);
      case ['gh', 'release', 'view', ...]:
        return const Ran(1);
      case ['gh', 'release', 'create', ...]:
        return const Ran(0, stdout: 'https://github.com/IKatsuba/chord/x\n');
    }
    throw StateError('unexpected $line');
  }

  @override
  Future<Started> start(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  }) => throw StateError('nothing starts');
}

void main() {
  late Directory place;
  late String work;
  late Machine machine;
  late List<String> said;
  late List<String> ran;
  late bool packFails;

  Future<String> git(List<String> args, {String? cwd}) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: cwd ?? work,
      environment: gitEnv,
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String).trim();
  }

  String version() => packageVersion(work);

  /// Two stages standing for chord's: compile leaves the binaries, pack the
  /// tarballs and archives with their sums.
  List<Stage> fakeStages() => [
    Stage(
      name: 'compile',
      about: 'binaries',
      versioned: true,
      outputs: (_) => [for (final t in targets) binaryOf(t)],
      run: (release, v, _) async {
        ran.add('compile $v');
        for (final t in targets) {
          (File(
            p.join(work, binaryOf(t)),
          )..createSync(recursive: true)).writeAsStringSync('$t $v');
        }
      },
    ),
    Stage(
      name: 'pack',
      about: 'tarballs',
      outputs: (v) => packOutputs(v, npmNames),
      run: (release, v, recorded) async {
        ran.add('pack $v');
        if (packFails) die('pack failed on purpose');
        final tgz = Directory(p.join(work, tgzFolder))
          ..createSync(recursive: true);
        for (final name in npmNames) {
          File(p.join(tgz.path, tarballName(name, v))).writeAsStringSync(name);
        }
        recordSums(tgz.path, [for (final n in npmNames) tarballName(n, v)]);
        final archives = Directory(p.join(work, archivesFolder))
          ..createSync(recursive: true);
        for (final t in targets) {
          File(p.join(archives.path, t.archive)).writeAsStringSync('$t');
        }
        recordSums(archives.path, [for (final t in targets) t.archive]);
      },
    ),
  ];

  Release release({String platform = 'darwin-arm64', List<Stage>? stages}) =>
      Release(
        root: work,
        runner: machine,
        out: said.add,
        err: said.add,
        sleep: (_) async {},
        tty: true,
        home: '/home/x',
        sdks: const Sdks(dart: 'dart', version: '3.13.5'),
        sdkDir: '/sdk',
        fake: () => 'fake',
        platform: platform,
        stages: stages ?? fakeStages(),
      );

  Future<void> releaseRun(
    List<String> stages, {
    ReleaseOptions options = const ReleaseOptions(),
    String? wanted,
    List<Stage>? using,
    String platform = 'darwin-arm64',
  }) => runRelease(
    release(platform: platform, stages: using),
    stages,
    options,
    wanted: wanted,
  );

  setUp(() async {
    place = Directory.systemTemp.createTempSync('run_test');
    work = p.join(place.path, 'work');
    final origin = p.join(place.path, 'origin.git');
    await git(['init', '-q', '--bare', '-b', 'main', origin], cwd: place.path);
    await git(['init', '-q', '-b', 'main', work], cwd: place.path);
    (File(p.join(work, manifestPath))..createSync(recursive: true))
        .writeAsStringSync('name: chord\nversion: 1.2.0\n');
    (File(p.join(work, frameworkManifestPath))..createSync(recursive: true))
        .writeAsStringSync('name: chord_tui\nversion: 1.2.0\n');
    File(p.join(work, lockPath)).writeAsStringSync(
      'packages:\n  chord_tui:\n    source: path\n    version: "1.2.0"\n',
    );
    (File(p.join(work, heldVersionPath))..createSync(recursive: true))
        .writeAsStringSync("const version = '1.2.0';\n");
    File(p.join(work, '.gitignore')).writeAsStringSync('build/\n.release/\n');
    await git(['add', '-A']);
    await git(['commit', '-q', '-m', 'start']);
    await git(['remote', 'add', 'origin', origin]);
    await git(['push', '-q', 'origin', 'main']);
    machine = Machine(work);
    said = [];
    ran = [];
    packFails = false;
  });
  tearDown(() => place.deleteSync(recursive: true));

  test("pubspec.yaml's version: built, packed, published in order, tagged "
      'and drafted, the state cleared, the version printed last', () async {
    await releaseRun(['compile', 'pack', 'publish']);
    expect(ran, ['compile 1.2.0', 'pack 1.2.0']);
    final publishes = [
      for (final line in machine.log)
        if (line.startsWith('npm publish')) line.split(' ')[4],
    ];
    expect(publishes.map(p.basename), [
      for (final n in npmNames) tarballName(n, '1.2.0'),
    ]);
    expect(
      await git(['ls-remote', '--tags', 'origin']),
      contains('refs/tags/v1.2.0'),
    );
    expect(machine.log.last, startsWith('gh release create v1.2.0 --draft'));
    expect(readState(work, 'chord'), isNull);
    expect(said.last, '1.2.0');
  });

  test('a bump that publishes commits the version alone and pushes it '
      'before any stage', () async {
    machine.onNpm.add('@chorded/chord@1.2.0');
    await releaseRun(['compile', 'pack', 'publish'], wanted: 'minor');
    expect(ran, ['compile 1.3.0', 'pack 1.3.0']);
    expect(version(), '1.3.0');
    expect(await git(['log', '-1', '--format=%s']), 'chore: chord v1.3.0');
    expect(
      await git(['rev-parse', 'origin/main']),
      await git(['rev-parse', 'HEAD']),
    );
    final pushIndex = machine.log.indexOf('git push -q origin main');
    expect(pushIndex, isNonNegative);
    expect(said.last, '1.3.0');
  });

  test('a dry run builds the new version, then drops its commit', () async {
    machine.onNpm.add('@chorded/chord@1.2.0');
    final head = await git(['rev-parse', 'HEAD']);
    await releaseRun(
      ['compile', 'pack'],
      options: const ReleaseOptions(dryRun: true),
      wanted: 'patch',
    );
    expect(ran, ['compile 1.2.1', 'pack 1.2.1']);
    expect(await git(['rev-parse', 'HEAD']), head);
    expect(version(), '1.2.0');
    expect(
      said.last,
      'dry run: @chorded/chord 1.2.1 is packed in build/release/tgz, not published',
    );
    expect(readState(work, 'chord'), isNull);
    expect(machine.log.where((l) => l.startsWith('npm publish')), isEmpty);
  });

  test('a dry run on a channel prints what would publish', () async {
    machine.onNpm.add('@chorded/chord@1.2.0');
    await git(['switch', '-q', '-c', 'next']);
    await releaseRun(
      ['compile', 'pack'],
      options: const ReleaseOptions(dryRun: true, channel: 'next'),
      wanted: 'major',
    );
    expect(said, contains('dry run: ran compile, pack'));
    expect(
      said,
      contains(
        'dry run: npm publish --access public build/release/tgz/'
        '${tarballName(npmNames.last, '2.0.0-next.0')} --tag next',
      ),
    );
  });

  test('publish without pack is refused before any stage, commit or '
      'publish', () async {
    final head = await git(['rev-parse', 'HEAD']);
    await expectLater(
      releaseRun(['compile', 'publish']),
      dies("publish needs pack's output; pack is not done in chord 1.2.0"),
    );
    expect(ran, isEmpty);
    expect(await git(['rev-parse', 'HEAD']), head);
    expect(readState(work, 'chord'), isNull);
  });

  test('a new version needs the compile stage', () async {
    await expectLater(
      releaseRun(['pack'], wanted: '1.3.0'),
      dies(
        "a new version needs the compile stage: 1.3.0 is not "
        "pubspec.yaml's 1.2.0",
      ),
    );
  });

  test(
    'signing anywhere but an arm64 Mac is refused before anything else',
    () async {
      await expectLater(
        releaseRun(['sign'], using: chordStages, platform: 'linux-x64'),
        dies('sign and notarise run only on an arm64 Mac; this is linux-x64'),
      );
      expect(machine.log.where((l) => l.startsWith('npm')), isEmpty);
    },
  );

  test('a stopped release keeps its state, and the next run goes on from '
      'it', () async {
    packFails = true;
    await expectLater(
      releaseRun(['compile', 'pack', 'publish']),
      dies('pack failed on purpose'),
    );
    final state = readState(work, 'chord')!;
    expect((state['stages']! as Map).keys, ['compile']);
    packFails = false;
    ran.clear();
    await releaseRun(['compile', 'pack', 'publish']);
    expect(ran, ['pack 1.2.0']);
    expect(said.last, '1.2.0');
    expect(readState(work, 'chord'), isNull);
  });

  test("a compile output changed since the state recorded it is refused, "
      'naming the way out', () async {
    packFails = true;
    await expectLater(
      releaseRun(['compile', 'pack', 'publish']),
      dies('pack failed on purpose'),
    );
    File(p.join(work, binaryOf(targets.first))).writeAsStringSync('tampered');
    packFails = false;
    await expectLater(
      releaseRun(['compile', 'pack', 'publish']),
      dies(
        '${binaryOf(targets.first)} is not what compile left: its sha256 is',
      ),
    );
  });

  test('a finished state is cleared and the run goes on without it', () async {
    writeState(work, {
      'format': 1,
      'package': 'chord',
      'version': '1.1.0',
      'channel': null,
      'branch': 'main',
      'base': 'a' * 40,
      'built': 'a' * 40,
      'stages': <String, Object?>{},
      'npm': {for (final n in npmNames) n: 'answered'},
      'tag': {'state': 'pushed'},
      'draft': {'state': 'made'},
    });
    await releaseRun(['compile']);
    expect(said.first, 'chord 1.1.0 is released');
    expect(ran, ['compile 1.2.0']);
  });

  test('a run that holds the lock is the only one', () async {
    File(p.join(work, '.git', 'chord-release.lock')).writeAsStringSync('');
    await expectLater(
      releaseRun(['compile']),
      dies('another release runs in this checkout'),
    );
    expect(ran, isEmpty);
  });

  test("a version npm's latest is counted from for a channel bump", () async {
    machine.onNpm.add('@chorded/chord@1.2.0');
    await git(['switch', '-q', '-c', 'next']);
    await releaseRun(
      ['compile'],
      options: const ReleaseOptions(dryRun: true, channel: 'next'),
      wanted: 'minor',
    );
    expect(ran, ['compile 1.3.0-next.0']);
    expect(machine.log, contains('npm view @chorded/chord dist-tags.latest'));
  });

  group('tester: release integration boundaries', () {
    test(
      'a channel publish keeps its branch, npm tag and draft flag together',
      () async {
        machine.onNpm.add('@chorded/chord@1.2.0');
        await git(['switch', '-q', '-c', 'next']);
        await git(['push', '-q', 'origin', 'next']);
        await releaseRun(
          ['compile', 'pack', 'publish'],
          options: const ReleaseOptions(channel: 'next'),
          wanted: 'minor',
        );
        expect(version(), '1.3.0-next.0');
        expect(
          await git(['rev-parse', 'origin/next']),
          await git(['rev-parse', 'HEAD']),
        );
        final published = machine.log
            .where((line) => line.startsWith('npm publish'))
            .toList();
        expect(published, hasLength(npmNames.length));
        expect(published.every((line) => line.endsWith('--tag next')), isTrue);
        expect(machine.log.last, contains('--draft --prerelease --verify-tag'));
        expect(said.last, '1.3.0-next.0');
        expect(readState(work, 'chord'), isNull);
      },
    );

    test(
      'a resumed publish refuses a redirected gh destination before authentication',
      () async {
        packFails = true;
        await expectLater(
          releaseRun(['compile', 'pack', 'publish']),
          dies('pack failed'),
        );
        final saved = File(p.join(work, stateDir('chord'), 'state.json'));
        final before = saved.readAsBytesSync();
        final logBefore = machine.log.length;
        packFails = false;
        final base = release();
        final redirected = Release(
          root: base.root,
          runner: base.runner,
          out: base.out,
          err: base.err,
          sleep: base.sleep,
          tty: base.tty,
          home: base.home,
          sdks: base.sdks,
          sdkDir: base.sdkDir,
          fake: base.fake,
          platform: base.platform,
          stages: base.stages,
          env: {'GH_REPO': 'other/repo'},
        );
        await expectLater(
          runRelease(redirected, [
            'compile',
            'pack',
            'publish',
          ], const ReleaseOptions()),
          dies('GH_REPO is other/repo'),
        );
        final later = machine.log.skip(logBefore);
        expect(
          later.where(
            (line) => line == 'npm whoami' || line.startsWith('npm publish'),
          ),
          isEmpty,
        );
        expect(saved.readAsBytesSync(), before);
        expect(
          File(p.join(work, '.git/chord-release.lock')).existsSync(),
          isFalse,
        );
      },
    );
  });
}

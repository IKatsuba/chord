import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/continue.dart';
import '../../../tool/release/preflight.dart';
import '../../../tool/release/runner.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

const head = 'abc123';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('preflight_test');
    (File(p.join(root.path, manifestPath))..createSync(recursive: true))
        .writeAsStringSync('name: chord\nversion: 1.2.0\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A machine with a clean tree on main level with origin, npm having
  /// [onNpm] (`name@version`) and every pin, and gh signed in, but for what
  /// [override] answers first.
  RecordingRunner machine({
    Set<String> onNpm = const {'@chorded/chord@1.2.0'},
    Ran? Function(List<String> argv)? override,
  }) => RecordingRunner((argv) {
    if (override?.call(argv) case final ran?) return ran;
    return switch (argv) {
      ['git', 'status', ...] => const Ran(0),
      ['git', 'remote', 'get-url', ...] => const Ran(
        0,
        stdout: 'git@github.com:IKatsuba/chord.git\n',
      ),
      ['git', 'symbolic-ref', ...] => const Ran(0, stdout: 'main\n'),
      ['git', 'rev-parse', _] => const Ran(0, stdout: '$head\n'),
      ['git', 'tag', '--list', _] => const Ran(0),
      ['git', 'ls-remote', ...] => const Ran(0),
      ['npm', 'view', '@chorded/cursor-cloud-acp@0.2.0', 'version'] =>
        const Ran(0, stdout: '0.2.0\n'),
      ['npm', 'view', final spec, 'version'] =>
        onNpm.contains(spec)
            ? Ran(0, stdout: '${spec.split('@').last}\n')
            : const Ran(1, stderr: 'npm error code E404\n'),
      _ => null,
    };
  });

  test(
    "pubspec.yaml's version is the one released when none is given",
    () async {
      final runner = machine(onNpm: const {});
      expect(await preflight(runner, root.path, publish: false), '1.2.0');
      expect(runner.argvs.first, [
        'git',
        'status',
        '--porcelain',
        '--untracked-files=all',
      ]);
    },
  );

  test('a new version needs pubspec.yaml\'s on npm first', () async {
    await expectLater(
      preflight(
        machine(onNpm: const {}),
        root.path,
        publish: false,
        version: '1.3.0',
      ),
      dies(
        '@chorded/chord@1.2.0 is not published yet; `dart run '
        'tool/release.dart chord` without --bump finishes it',
      ),
    );
    expect(
      await preflight(machine(), root.path, publish: false, version: '1.3.0'),
      '1.3.0',
    );
  });

  test('a version npm has is refused, the main package or any other', () async {
    await expectLater(
      preflight(machine(), root.path, publish: false),
      dies('@chorded/chord@1.2.0 is on npm already'),
    );
    await expectLater(
      preflight(
        machine(
          onNpm: const {
            '@chorded/chord@1.2.0',
            '@chorded/chord-linux-x64@1.3.0',
          },
        ),
        root.path,
        publish: false,
        version: '1.3.0',
      ),
      dies('@chorded/chord-linux-x64@1.3.0 is on npm already'),
    );
  });

  test('a registry failure other than a 404 stops it', () async {
    await expectLater(
      preflight(
        machine(
          override: (argv) => argv.first == 'npm'
              ? const Ran(1, stderr: 'npm error code ETIMEDOUT\n')
              : null,
        ),
        root.path,
        publish: false,
      ),
      dies('npm view @chorded/chord@1.2.0 failed: npm error code ETIMEDOUT'),
    );
  });

  test('a dirty tree is refused first', () async {
    final runner = machine(
      override: (argv) =>
          argv[1] == 'status' ? const Ran(0, stdout: '?? stray\n') : null,
    );
    await expectLater(
      preflight(runner, root.path, publish: false),
      dies('the tree is not clean:\n?? stray'),
    );
    expect(runner.calls, hasLength(1));
  });

  test('a pin npm lacks stops it, naming it and the way on', () async {
    await expectLater(
      preflight(
        machine(
          onNpm: const {},
          override: (argv) => argv.contains('@chorded/cursor-cloud-acp@0.2.0')
              ? const Ran(1, stderr: 'E404')
              : null,
        ),
        root.path,
        publish: false,
      ),
      dies(
        'npm has no @chorded/cursor-cloud-acp@0.2.0, which lib/chorded.dart '
        'pins: release @chorded/cursor-cloud-acp first, or pin a version npm '
        'has',
      ),
    );
  });

  test('every pin npm has passes, each asked by its exact version', () async {
    final runner = RecordingRunner(
      (argv) => Ran(0, stdout: '${argv[2].split('@').last}\n'),
    );
    await pinsOnNpm(
      runner,
      agents: const [
        (package: '@x/a', version: '1.0.0'),
        (package: '@x/b', version: '2.0.0'),
      ],
    );
    expect(runner.argvs, [
      ['npm', 'view', '@x/a@1.0.0', 'version'],
      ['npm', 'view', '@x/b@2.0.0', 'version'],
    ]);
  });

  group('publishing', () {
    test('a stable version runs from main, level with origin, untagged, '
        'with gh signed in', () async {
      final runner = machine(onNpm: const {});
      await preflight(runner, root.path, publish: true);
      expect(runner.argvs.where((argv) => argv.first != 'npm').skip(1), [
        ['git', 'remote', 'get-url', 'origin'],
        ['git', 'remote', 'get-url', '--push', '--all', 'origin'],
        ['git', 'symbolic-ref', '--short', 'HEAD'],
        ['git', 'fetch', 'origin'],
        ['git', 'rev-parse', 'main'],
        ['git', 'rev-parse', 'origin/main'],
        ['git', 'tag', '--list', 'v1.2.0'],
        ['git', 'ls-remote', '--tags', 'origin', 'refs/tags/v1.2.0'],
        ['gh', 'auth', 'status'],
      ]);
    });

    test('from another branch is refused', () async {
      await expectLater(
        preflight(
          machine(
            onNpm: const {},
            override: (argv) => argv[1] == 'symbolic-ref'
                ? const Ran(0, stdout: 'next\n')
                : null,
          ),
          root.path,
          publish: true,
        ),
        dies('a release that publishes runs from main; HEAD is next'),
      );
    });

    test("a channel's version publishes only from its branch", () async {
      await expectLater(
        preflight(machine(), root.path, publish: true, version: '1.3.0-next.0'),
        dies(
          'a release on channel next publishes only from branch next; HEAD '
          'is main',
        ),
      );
    });

    test('a branch not level with origin is refused', () async {
      await expectLater(
        preflight(
          machine(
            onNpm: const {},
            override: (argv) => argv.last == 'origin/main'
                ? const Ran(0, stdout: 'zzz\n')
                : null,
          ),
          root.path,
          publish: true,
        ),
        dies('main is not origin/main: main is $head, origin/main is zzz'),
      );
    });

    test('a tag of the version, here or on origin, is refused', () async {
      await expectLater(
        preflight(
          machine(
            onNpm: const {},
            override: (argv) =>
                argv[1] == 'tag' ? const Ran(0, stdout: 'v1.2.0\n') : null,
          ),
          root.path,
          publish: true,
        ),
        dies('v1.2.0 is a tag already'),
      );
      await expectLater(
        preflight(
          machine(
            onNpm: const {},
            override: (argv) => argv[1] == 'ls-remote'
                ? const Ran(0, stdout: 'abc\trefs/tags/v1.2.0\n')
                : null,
          ),
          root.path,
          publish: true,
        ),
        dies('v1.2.0 is a tag on origin already: abc\trefs/tags/v1.2.0'),
      );
    });

    // Slips of the original, fixed: a failed query certifies nothing.
    test(
      'a local tag query that fails is refused, whatever it printed',
      () async {
        await expectLater(
          preflight(
            machine(
              onNpm: const {},
              override: (argv) =>
                  argv[1] == 'tag' ? const Ran(null, stderr: 'killed\n') : null,
            ),
            root.path,
            publish: true,
          ),
          dies('git tag --list v1.2.0 failed: killed'),
        );
      },
    );

    test(
      'a local rev-parse that fails is refused, even with origin\'s sha',
      () async {
        await expectLater(
          preflight(
            machine(
              onNpm: const {},
              override: (argv) => argv.join(' ') == 'git rev-parse main'
                  ? const Ran(128, stdout: '$head\n', stderr: 'bad ref\n')
                  : null,
            ),
            root.path,
            publish: true,
          ),
          dies('git rev-parse main failed: bad ref'),
        );
      },
    );

    test('gh not signed in is refused', () async {
      await expectLater(
        preflight(
          machine(
            onNpm: const {},
            override: (argv) => argv.first == 'gh'
                ? const Ran(1, stderr: 'not logged in\n')
                : null,
          ),
          root.path,
          publish: true,
        ),
        dies(
          '`gh auth status` failed, and publishing makes a draft GitHub '
          'release with it: not logged in',
        ),
      );
    });
  });

  test('a pubspec.yaml without a version is refused', () {
    File(p.join(root.path, manifestPath)).writeAsStringSync('name: chord\n');
    expect(() => packageVersion(root.path), dies('has no version'));
  });

  test('the npm names are the platforms, then the main package', () {
    expect(npmNames, [
      '@chorded/chord-darwin-arm64',
      '@chorded/chord-darwin-x64',
      '@chorded/chord-linux-x64',
      '@chorded/chord-linux-arm64',
      '@chorded/chord',
    ]);
  });

  group('tester: preflight channel and manifest boundaries', () {
    test(
      'a matching channel branch reaches GitHub eligibility without login',
      () async {
        final runner = machine(
          override: (argv) =>
              argv[1] == 'symbolic-ref' ? const Ran(0, stdout: 'next\n') : null,
        );
        expect(
          await preflight(
            runner,
            root.path,
            publish: true,
            version: '1.3.0-next.0',
          ),
          '1.3.0-next.0',
        );
        expect(
          runner.argvs,
          contains(equals(['git', 'rev-parse', 'origin/next'])),
        );
        expect(runner.argvs.last, ['gh', 'auth', 'status']);
        expect(
          runner.argvs.where(
            (a) => a.contains('login') || a.contains('whoami'),
          ),
          isEmpty,
        );
      },
    );

    test('malformed and non-string manifest versions are refused', () {
      final file = File(p.join(root.path, manifestPath));
      for (final text in [
        'version: [',
        '[]',
        'version: 12',
        'version: null',
        'version: ""',
      ]) {
        file.writeAsStringSync(text);
        expect(() => packageVersion(root.path), dies('has no version'));
      }
    });
  });

  group("origin's repository", () {
    for (final url in [
      'git@github.com:IKatsuba/chord.git',
      'git@github.com:IKatsuba/chord',
      'https://github.com/IKatsuba/chord.git',
      'https://github.com/IKatsuba/chord',
      'ssh://git@github.com/IKatsuba/chord.git',
    ]) {
      test('$url is the release\'s', () async {
        await originIsRelease(RecordingRunner((_) => Ran(0, stdout: '$url\n')));
      });
    }

    for (final url in [
      'git@github.com:IKatsuba/chorded-tui.git',
      'https://github.com/someone/chord.git',
      'https://gitlab.com/IKatsuba/chord.git',
      '/local/origin.git',
    ]) {
      test('$url refuses a publish', () async {
        await expectLater(
          originIsRelease(RecordingRunner((_) => Ran(0, stdout: '$url\n'))),
          dies(
            'a release that publishes tags origin and drafts its GitHub '
            'release there, and chord is released from IKatsuba/chord; '
            'origin is $url',
          ),
        );
      });
    }

    test('no origin refuses a publish with what git said', () async {
      await expectLater(
        originIsRelease(
          RecordingRunner((_) => const Ran(2, stderr: 'No such remote\n')),
        ),
        dies('git remote get-url origin failed: No such remote'),
      );
    });

    test('preflight asks it before the branch when publishing, never '
        'otherwise', () async {
      final publishing = machine(
        onNpm: const {},
        override: (argv) => argv.take(3).join(' ') == 'git remote get-url'
            ? const Ran(0, stdout: 'git@github.com:x/y.git\n')
            : null,
      );
      await expectLater(
        preflight(publishing, root.path, publish: true),
        dies('origin is git@github.com:x/y.git'),
      );
      expect(publishing.argvs.last.take(2), ['git', 'remote']);
      final local = machine(onNpm: const {});
      await preflight(local, root.path, publish: false);
      expect(local.argvs.where((argv) => argv.contains('remote')), isEmpty);
    });
  });

  // Slips of the original, fixed: every way the publish could reach another
  // repository refuses.
  group('pushes and gh', () {
    const right = 'git@github.com:IKatsuba/chord.git\n';
    RecordingRunner urls({String push = right}) => RecordingRunner(
      (argv) => Ran(0, stdout: argv.contains('--push') ? push : right),
    );

    test('a push URL elsewhere refuses, naming it', () async {
      await expectLater(
        originIsRelease(urls(push: 'git@github.com:x/fork.git\n')),
        dies("origin's push is git@github.com:x/fork.git"),
      );
    });

    test('any of several push URLs elsewhere refuses', () async {
      await expectLater(
        originIsRelease(
          urls(push: '${right}https://github.com/x/mirror.git\n'),
        ),
        dies("origin's push is https://github.com/x/mirror.git"),
      );
    });

    test('a failed push URL query refuses', () async {
      await expectLater(
        originIsRelease(
          RecordingRunner(
            (argv) => argv.contains('--push')
                ? const Ran(1, stderr: 'bad\n')
                : const Ran(0, stdout: right),
          ),
        ),
        dies('git remote get-url --push --all origin failed: bad'),
      );
    });

    test(
      'GH_REPO of another repository refuses, the release\'s passes',
      () async {
        await expectLater(
          originIsRelease(urls(), env: {'GH_REPO': 'someone/else'}),
          dies(
            'GH_REPO is someone/else; a release drafts in IKatsuba/chord '
            'alone',
          ),
        );
        await originIsRelease(urls(), env: {'GH_REPO': 'IKatsuba/chord'});
      },
    );

    test('GH_HOST other than github.com refuses', () async {
      await expectLater(
        originIsRelease(urls(), env: {'GH_HOST': 'ghe.example.com'}),
        dies(
          'GH_HOST is ghe.example.com; a release drafts on github.com '
          'alone',
        ),
      );
      await originIsRelease(urls(), env: {'GH_HOST': 'github.com'});
    });

    test('preflight passes the environment on', () async {
      await expectLater(
        preflight(
          machine(onNpm: const {}),
          root.path,
          publish: true,
          env: {'GH_REPO': 'x/y'},
        ),
        dies('GH_REPO is x/y'),
      );
    });
  });
}

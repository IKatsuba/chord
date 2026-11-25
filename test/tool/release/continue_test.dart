import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/archive.dart';
import '../../../tool/release/continue.dart';
import '../../../tool/release/runner.dart';
import '../../../tool/release/state.dart';
import 'fixtures/recording_runner.dart';

const abandonChord = 'rm -r .release/chord abandons it';

/// git with no person's configuration, in a scratch repository of the test.
final gitEnv = {
  ...Platform.environment,
  'GIT_CONFIG_GLOBAL': '/dev/null',
  'GIT_CONFIG_NOSYSTEM': '1',
  'GIT_AUTHOR_NAME': 'release test',
  'GIT_AUTHOR_EMAIL': 'release@test.invalid',
  'GIT_COMMITTER_NAME': 'release test',
  'GIT_COMMITTER_EMAIL': 'release@test.invalid',
};

String pubspec(String version) => 'name: chord\nversion: $version\n';

void main() {
  late Directory place;
  late String work;
  late ProcessReleaseRunner runner;

  Future<String> git(List<String> args, {String? cwd}) async {
    final ran = await Process.run(
      'git',
      args,
      workingDirectory: cwd ?? work,
      environment: gitEnv,
      includeParentEnvironment: false,
    );
    expect(ran.exitCode, 0, reason: '${ran.stderr}');
    return (ran.stdout as String).trim();
  }

  void write(String path, String text) => (File(
    p.join(work, path),
  )..createSync(recursive: true)).writeAsStringSync(text);

  Future<String> commit(String message) async {
    await git(['add', '-A']);
    await git(['commit', '-q', '-m', message]);
    return git(['rev-parse', 'HEAD']);
  }

  late String base;

  setUp(() async {
    place = Directory.systemTemp.createTempSync('continue_test');
    final origin = p.join(place.path, 'origin.git');
    work = p.join(place.path, 'work');
    await git(['init', '-q', '--bare', '-b', 'main', origin], cwd: place.path);
    await git(['init', '-q', '-b', 'main', work], cwd: place.path);
    write(manifestPath, pubspec('1.2.0'));
    base = await commit('start');
    await git(['remote', 'add', 'origin', origin]);
    await git(['push', '-q', 'origin', 'main']);
    runner = ProcessReleaseRunner(root: work, env: gitEnv);
  });
  tearDown(() => place.deleteSync(recursive: true));

  ReleaseState state({
    String version = '1.2.0',
    String? built,
    Map<String, Object?> more = const {},
  }) => {
    'format': 1,
    'package': 'chord',
    'version': version,
    'channel': null,
    'branch': 'main',
    'base': base,
    'built': built ?? base,
    'stages': <String, Object?>{},
    'npm': <String, Object?>{},
    ...more,
  };

  Continuation at({
    String? built,
    bool building = false,
    bool publishing = false,
    List<String> kept = const [],
    bool rebuild = false,
  }) => (
    built: built ?? base,
    building: building,
    publishing: publishing,
    kept: kept,
    rebuild: rebuild,
  );

  Future<String> refused(Future<void> Function() run) async {
    try {
      await run();
    } on ReleaseError catch (error) {
      expect(error.message, endsWith('; $abandonChord'));
      return error.message;
    }
    fail('not refused');
  }

  group('a pending version commit', () {
    test('is none without one, or one made', () async {
      expect(await versionCommit(runner, state()), isA<NoVersionCommit>());
      expect(
        await versionCommit(
          runner,
          state(
            more: {
              'versionCommit': {'state': 'made', 'sha': base},
            },
          ),
        ),
        isA<NoVersionCommit>(),
      );
    });

    test('that never happened leaves HEAD at the base', () async {
      expect(
        await versionCommit(
          runner,
          state(
            more: {
              'versionCommit': {'state': 'pending'},
            },
          ),
        ),
        isA<VersionCommitAtBase>(),
      );
    });

    test('made before the kill holds exactly the recorded files', () async {
      final text = pubspec('1.3.0');
      write(manifestPath, text);
      final made = await commit('chore: chord v1.3.0');
      final found = await versionCommit(
        runner,
        state(
          version: '1.3.0',
          more: {
            'versionCommit': {
              'state': 'pending',
              'files': {
                manifestPath: sha256.convert(utf8.encode(text)).toString(),
              },
            },
          },
        ),
      );
      expect((found as VersionCommitMade).sha, made);
    });

    test('anything else is refused', () async {
      write(manifestPath, pubspec('1.3.0'));
      write('other.txt', 'x');
      final head = await commit('chore: chord v1.3.0 and more');
      final message = await refused(
        () => versionCommit(
          runner,
          state(
            more: {
              'versionCommit': {
                'state': 'pending',
                'files': {manifestPath: 'f' * 64},
              },
            },
          ),
        ),
      );
      expect(
        message,
        startsWith(
          'the version commit of chord 1.2.0 was left pending on $base, and '
          'HEAD $head is neither that commit nor it plus exactly the files '
          'the release recorded',
        ),
      );
    });
  });

  group('the guards', () {
    test('a clean tree at the built commit passes', () async {
      await guarded(
        runner,
        work,
        state(),
        at(building: true, publishing: true),
      );
    });

    test('a dirty tree is refused', () async {
      write('stray.txt', 'x');
      expect(
        await refused(() => guarded(runner, work, state(), at())),
        startsWith('the tree is not clean:\n?? stray.txt'),
      );
    });

    test('a built commit not in HEAD\'s history is refused', () async {
      expect(
        await refused(
          () => guarded(runner, work, state(), at(built: 'f' * 40)),
        ),
        contains("was built from ${'f' * 40}, which is not in HEAD"),
      );
    });

    test('a built commit of another version is refused', () async {
      expect(
        await refused(
          () => guarded(runner, work, state(version: '1.3.0'), at()),
        ),
        startsWith('$manifestPath at $base is 1.2.0, not chord 1.3.0'),
      );
    });

    test('HEAD moved while a stage before publish is left is refused, '
        'unless it may rebuild at the same version', () async {
      write('notes.txt', 'x');
      final head = await commit('notes');
      expect(
        await refused(() => guarded(runner, work, state(), at(building: true))),
        startsWith(
          'HEAD $head is not $base, which chord 1.2.0 is built from, and a '
          'stage before publish is left',
        ),
      );
      await guarded(runner, work, state(), at(building: true, rebuild: true));
      write(manifestPath, pubspec('1.4.0'));
      final moved = await commit('another version');
      expect(
        await refused(
          () =>
              guarded(runner, work, state(), at(building: true, rebuild: true)),
        ),
        startsWith(
          '$manifestPath at HEAD $moved is 1.4.0, not chord 1.2.0, so it '
          'cannot be built again from HEAD',
        ),
      );
    });

    test('publishing from another branch is refused', () async {
      await git(['switch', '-q', '-c', 'next']);
      expect(
        await refused(
          () => guarded(runner, work, state(), at(publishing: true)),
        ),
        startsWith('chord 1.2.0 publishes from main; HEAD is next'),
      );
    });

    test('publishing ahead of origin is refused', () async {
      write('notes.txt', 'x');
      final head = await commit('notes');
      expect(
        await refused(
          () => guarded(
            runner,
            work,
            state(built: head),
            at(built: head, publishing: true),
          ),
        ),
        startsWith(
          'main is not level with origin/main: main is $head, origin/main '
          'is $base',
        ),
      );
    });

    test('a version commit made and not pushed may be one ahead', () async {
      write(manifestPath, pubspec('1.3.0'));
      final made = await commit('chore: chord v1.3.0');
      await guarded(
        runner,
        work,
        state(
          version: '1.3.0',
          built: made,
          more: {
            'versionCommit': {'state': 'made', 'sha': made},
          },
        ),
        at(built: made, publishing: true),
      );
    });

    // A slip of the original, fixed: the exception holds only at the made
    // commit itself.
    test(
      'HEAD moved past a made, unpushed version commit is not level',
      () async {
        write(manifestPath, pubspec('1.3.0'));
        final made = await commit('chore: chord v1.3.0');
        write('one.txt', '1');
        await commit('one');
        write('two.txt', '2');
        final head = await commit('two');
        final at13 = state(
          version: '1.3.0',
          built: made,
          more: {
            'versionCommit': {'state': 'made', 'sha': made},
          },
        );
        expect(
          await refused(
            () =>
                guarded(runner, work, at13, at(built: made, publishing: true)),
          ),
          startsWith(
            'main is not level with origin/main: main is $head, origin/main '
            'is $base',
          ),
        );
        // Pushed through to the made commit only, still not level with HEAD.
        await git(['push', '-q', 'origin', '$made:main']);
        expect(
          await refused(
            () =>
                guarded(runner, work, at13, at(built: made, publishing: true)),
          ),
          startsWith('main is not level with origin/main: main is $head'),
        );
      },
    );

    test('a tag of the version the release did not make is refused', () async {
      await git(['tag', 'v1.2.0']);
      expect(
        await refused(
          () => guarded(runner, work, state(), at(publishing: true)),
        ),
        startsWith('v1.2.0 is a tag already, which this release did not make'),
      );
    });

    test('a tag the release made on another commit is refused, on its '
        'commit it passes', () async {
      write('notes.txt', 'x');
      final other = await commit('notes');
      await git(['push', '-q', 'origin', 'main']);
      await git(['tag', '-a', '-m', 'v1.2.0', 'v1.2.0', base]);
      final made = state(
        built: other,
        more: {
          'tag': {'state': 'made'},
        },
      );
      expect(
        await refused(
          () => guarded(runner, work, made, at(built: other, publishing: true)),
        ),
        startsWith(
          'v1.2.0 is on $base, not on $other, which chord 1.2.0 is built '
          'from',
        ),
      );
      await guarded(
        runner,
        work,
        state(
          more: {
            'tag': {'state': 'made'},
          },
        ),
        at(publishing: true),
      );
    });

    group('the recorded sums', () {
      late String sum;
      setUp(() async {
        write('.gitignore', 'build/\n');
        write('build/out', 'built');
        base = await commit('ignore build');
        await git(['push', '-q', 'origin', 'main']);
        sum = sha256Of(p.join(work, 'build/out'));
      });

      ReleaseState withOutputs(Map<String, Map<String, String>> outputs) =>
          state(
            more: {
              'stages': {
                for (final MapEntry(:key, :value) in outputs.entries)
                  key: {'at': 'now', 'outputs': value},
              },
            },
          );

      test('that hold pass', () async {
        await guarded(
          runner,
          work,
          withOutputs({
            'compile': {'build/out': sum},
          }),
          at(kept: ['compile']),
        );
      });

      test('a file gone is refused, naming the stage to rerun', () async {
        File(p.join(work, 'build/out')).deleteSync();
        expect(
          await refused(
            () => guarded(
              runner,
              work,
              withOutputs({
                'compile': {'build/out': sum},
              }),
              at(kept: ['compile']),
            ),
          ),
          startsWith(
            'build/out, which compile left, is gone; run compile again with '
            '--from compile',
          ),
        );
      });

      test('a file changed is refused, with both sums', () async {
        expect(
          await refused(
            () => guarded(
              runner,
              work,
              withOutputs({
                'compile': {'build/out': 'f' * 64},
              }),
              at(kept: ['compile']),
            ),
          ),
          startsWith(
            'build/out is not what compile left: its sha256 is $sum, the '
            'state recorded ${'f' * 64}; run compile again with --from compile',
          ),
        );
      });

      test(
        "a later stage's sum of the same file is the one that holds",
        () async {
          final states = withOutputs({
            'compile': {'build/out': 'f' * 64},
            'sign': {'build/out': sum},
          });
          await guarded(runner, work, states, at(kept: ['compile', 'sign']));
          expect(
            await refused(
              () => guarded(runner, work, states, at(kept: ['compile'])),
            ),
            contains('is not what compile left'),
          );
        },
      );
    });
  });

  test('a tag is found here and on origin, an annotated one peeled', () async {
    await git(['tag', '-a', '-m', 'v1.2.0', 'v1.2.0']);
    await git(['push', '-q', 'origin', 'v1.2.0']);
    final found = await tagAt(runner, 'v1.2.0');
    expect((found.here, found.origin), (base, base));
    final none = await tagAt(runner, 'v9.9.9');
    expect((none.here, none.origin), (null, null));
  });

  test('a draft on GitHub is its URL, none is null', () async {
    final some = RecordingRunner(
      (_) => const Ran(0, stdout: 'https://github.com/x/releases/tag/v1\n'),
    );
    expect(await draftAt(some, 'v1'), 'https://github.com/x/releases/tag/v1');
    expect(some.argvs.single, [
      'gh',
      'release',
      'view',
      'v1',
      '--json',
      'url',
      '--jq',
      '.url',
    ]);
    expect(await draftAt(RecordingRunner((_) => const Ran(1)), 'v1'), isNull);
  });

  group('tester: continuation provenance boundaries', () {
    test(
      'a pending commit with the right filenames but wrong bytes is refused',
      () async {
        write(manifestPath, pubspec('1.3.0'));
        await commit('version');
        expect(
          await refused(
            () => versionCommit(
              runner,
              state(
                version: '1.3.0',
                more: {
                  'versionCommit': {
                    'state': 'pending',
                    'files': {manifestPath: 'f' * 64},
                  },
                },
              ),
            ),
          ),
          contains('neither that commit nor it plus exactly the files'),
        );
      },
    );

    test(
      'a made commit pushed before state recorded it may continue',
      () async {
        write(manifestPath, pubspec('1.3.0'));
        final made = await commit('version');
        await git(['push', '-q', 'origin', 'main']);
        await guarded(
          runner,
          work,
          state(
            version: '1.3.0',
            built: made,
            more: {
              'versionCommit': {'state': 'made', 'sha': made},
            },
          ),
          at(built: made, publishing: true),
        );
      },
    );

    test('detached HEAD cannot publish even at the recorded commit', () async {
      await git(['checkout', '-q', '--detach', base]);
      expect(
        await refused(
          () => guarded(runner, work, state(), at(publishing: true)),
        ),
        contains('publishes from main; HEAD is $base'),
      );
    });
  });
}

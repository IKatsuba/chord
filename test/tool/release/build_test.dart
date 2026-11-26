import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/build.dart';
import '../../../tool/release/runner.dart';
import '../../../tool/release/x64_sdk.dart';
import '../../../tool/targets.dart';
import 'fixtures/recording_runner.dart';

const sdks = Sdks(dart: '/sdk/bin/dart', version: '3.13.5', cache: '/cache');

const x64 = '/x64/dart';

Target named(String name) => targets.firstWhere((t) => t.name == name);

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

const x64Version = Ran(
  0,
  stdout:
      'Dart SDK version: 3.13.5 (stable) (Tue Sep 29 01:00:52 2026 -0700) '
      'on "macos_x64"\n',
);

/// file(1)'s answer for each binary, as each target's build is.
Ran? goodBuild(List<String> argv) {
  if (argv case ['arch', '-x86_64', _, '--version']) return x64Version;
  if (argv case ['file', final binary]) {
    final target = targets.firstWhere((t) => binary == binaryOf(t));
    return Ran(0, stdout: '$binary: ${kinds[target.name]}, more\n');
  }
  return null;
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('build_test'));
  tearDown(() => root.deleteSync(recursive: true));

  group('targets', () {
    test("are the original's four, in its order, with Dart's names", () {
      expect(
        [for (final t in targets) '${t.name} ${t.dartOs}-${t.dartArch}'],
        [
          'darwin-arm64 macos-arm64',
          'darwin-x64 macos-x64',
          'linux-x64 linux-x64',
          'linux-arm64 linux-arm64',
        ],
      );
    });

    test('name their npm package and archive', () {
      expect(named('linux-arm64').package, '@chorded/chord-linux-arm64');
      expect(named('darwin-x64').archive, 'chord-darwin-x64.tar.gz');
    });

    test('each has a kind', () {
      expect(kinds.keys, [for (final t in targets) t.name]);
    });
  });

  group('compile argv', () {
    test('the host SDK builds its own platform', () {
      expect(compileArgv(named('darwin-arm64'), sdks), [
        '/sdk/bin/dart',
        'compile',
        'exe',
        '--define=chord.official=true',
        'bin/chord.dart',
        '-o',
        'build/release/darwin-arm64/chord',
      ]);
    });

    test('every release build is stamped official', () {
      for (final target in targets) {
        expect(
          compileArgv(target, sdks, x64Dart: x64),
          contains('--define=chord.official=true'),
          reason: target.name,
        );
      }
    });

    test('the x64 SDK builds Intel macOS under Rosetta', () {
      expect(compileArgv(named('darwin-x64'), sdks, x64Dart: x64), [
        'arch',
        '-x86_64',
        '/x64/dart',
        'compile',
        'exe',
        '--define=chord.official=true',
        'bin/chord.dart',
        '-o',
        'build/release/darwin-x64/chord',
      ]);
    });

    for (final arch in ['x64', 'arm64']) {
      test('the host SDK cross-compiles linux-$arch', () {
        expect(compileArgv(named('linux-$arch'), sdks), [
          '/sdk/bin/dart',
          'compile',
          'exe',
          '--target-os=linux',
          '--target-arch=$arch',
          '--define=chord.official=true',
          'bin/chord.dart',
          '-o',
          'build/release/linux-$arch/chord',
        ]);
      });
    }

    test('Intel macOS is not built without the x64 SDK', () {
      expect(() => compileArgv(named('darwin-x64'), sdks), throwsArgumentError);
    });

    test('the SDKs of this process keep the x64 SDK in the user cache', () {
      expect(Sdks.of({'XDG_CACHE_HOME': '/xdg'}, '/h').cache, '/xdg');
      expect(Sdks.of({}, '/h').cache, '/h/Library/Caches');
      expect(Sdks.of({}, '/h').version, Platform.version.split(' ').first);
    });
  });

  group('compile', () {
    late Sdks kept;
    late String x64Dart;
    setUp(() {
      kept = Sdks(
        dart: sdks.dart,
        version: sdks.version,
        cache: p.join(root.path, 'cache'),
        fetch: (url) => throw StateError('fetched $url'),
      );
      x64Dart = sdkDart(sdkFolder(kept.cache, kept.version));
      File(x64Dart).createSync(recursive: true);
    });

    test('takes the kept x64 SDK, builds every target loud, then checks '
        'each kind', () async {
      final said = <String>[];
      final runner = RecordingRunner(goodBuild);
      await compile(runner, kept, root.path, said.add);
      expect(said, isEmpty);
      expect(runner.calls.first.argv, [
        'arch',
        '-x86_64',
        x64Dart,
        '--version',
      ]);
      expect(
        [
          for (final call in runner.calls.skip(1).take(4))
            [...call.argv, if (call.loud) 'loud'],
        ],
        [
          for (final t in targets)
            [...compileArgv(t, kept, x64Dart: x64Dart), 'loud'],
        ],
      );
      expect(runner.argvs.skip(5), [
        for (final t in targets) ['file', binaryOf(t)],
      ]);
      for (final t in targets) {
        expect(
          Directory(p.join(root.path, 'build/release', t.name)).existsSync(),
          isTrue,
        );
      }
    });

    test('a failed build stops the release there', () async {
      final runner = RecordingRunner(
        (argv) =>
            argv.contains('--target-arch=x64') ? const Ran(1) : goodBuild(argv),
      );
      await expectLater(
        compile(runner, kept, root.path, (_) {}),
        dies('compile of linux-x64 failed'),
      );
      expect(runner.argvs.last, compileArgv(named('linux-x64'), kept));
    });

    test('a binary of the wrong kind is refused', () async {
      final runner = RecordingRunner((argv) {
        if (argv case ['file', 'build/release/linux-arm64/chord']) {
          return const Ran(
            0,
            stdout:
                'build/release/linux-arm64/chord: ELF 64-bit LSB pie '
                'executable, x86-64\n',
          );
        }
        return goodBuild(argv);
      });
      await expectLater(
        compile(runner, kept, root.path, (_) {}),
        dies(
          'build/release/linux-arm64/chord is build/release/linux-arm64/'
          'chord: ELF 64-bit LSB pie executable, x86-64',
        ),
      );
    });
  });

  group('the process runner', () {
    late ProcessReleaseRunner runner;
    setUp(() {
      File(p.join(root.path, 'script.sh')).writeAsStringSync(r'''
case "$1" in
  out) printf 'hello\n'; printf 'oops\n' >&2; exit 3 ;;
  env) printf '%s|%s|%s' "$MARK" "${HOME-unset}" "$PWD" ;;
  term) kill -TERM $$ ;;
esac
''');
      runner = ProcessReleaseRunner(
        root: root.path,
        env: {'MARK': 'only', 'PATH': '/usr/bin:/bin'},
      );
    });

    test('captures status and output', () async {
      final ran = await runner.run('sh', ['script.sh', 'out']);
      expect((ran.status, ran.stdout, ran.stderr), (3, 'hello\n', 'oops\n'));
    });

    test('runs in the root with exactly its environment', () async {
      final ran = await runner.run('sh', ['script.sh', 'env']);
      expect(ran.stdout, 'only|unset|${root.resolveSymbolicLinksSync()}');
    });

    test('a command ended by a signal has no status', () async {
      expect((await runner.run('sh', ['script.sh', 'term'])).status, isNull);
    });

    test('a command not found has no status and says why', () async {
      final ran = await runner.run('no-such-command-ctui', []);
      expect(ran.status, isNull);
      expect(ran.stderr, isNotEmpty);
    });

    test('a loud run shares the terminal and keeps its status', () async {
      final ran = await runner.run('sh', ['-c', 'exit 4'], loud: true);
      expect((ran.status, ran.stdout), (4, ''));
    });

    test('said drops trailing newlines only', () {
      expect(said('a\nb\n\n'), 'a\nb');
    });

    test('a command runs in a folder of the root, with variables laid over '
        'the environment', () async {
      Directory(p.join(root.path, 'sub')).createSync();
      final ran = await runner.run(
        'sh',
        ['-c', r'printf "%s|%s|%s" "$MARK" "$MORE" "${PWD##*/}"'],
        cwd: 'sub',
        env: {'MORE': 'laid'},
      );
      expect(ran.stdout, 'only|laid|sub');
    });

    test(
      'a started command is talked to line by line, and ends at EOF',
      () async {
        final started = await runner.start(
          'sh',
          [
            '-c',
            r'echo hello; read line; echo "got $line"; echo oops >&2; '
                r'read rest; exit 5',
          ],
          env: {'MORE': 'x'},
        );
        final lines = <String>[];
        final listening = started.lines.listen(lines.add);
        try {
          await started.lines
              .firstWhere((line) => line == 'hello')
              .timeout(const Duration(seconds: 10));
          started.write('ping');
          await started.lines
              .firstWhere((line) => line == 'got ping')
              .timeout(const Duration(seconds: 10));
          await started.close();
          expect(
            await started.exitCode.timeout(const Duration(seconds: 10)),
            5,
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(lines, ['hello', 'got ping']);
          expect(started.stderr, 'oops\n');
        } finally {
          started.kill();
          await listening.cancel();
        }
      },
    );

    test('a started command killed has no status', () async {
      final started = await runner.start('sh', ['-c', 'sleep 30']);
      started.kill();
      expect(
        await started.exitCode.timeout(const Duration(seconds: 10)),
        isNull,
      );
    });
  });

  group('tester: build failure boundaries', () {
    late Sdks kept;
    late String x64Dart;
    setUp(() {
      kept = Sdks(
        dart: sdks.dart,
        version: sdks.version,
        cache: p.join(root.path, 'cache'),
        fetch: (url) => throw StateError('fetched $url'),
      );
      x64Dart = sdkDart(sdkFolder(kept.cache, kept.version));
      File(x64Dart).createSync(recursive: true);
    });

    test(
      'a failed SDK preflight starts no compile and creates no output',
      () async {
        final runner = RecordingRunner((_) => const Ran(3, stderr: 'refused'));
        await expectLater(
          compile(runner, kept, root.path, (_) {}),
          dies('refused'),
        );
        expect(runner.calls, hasLength(1));
        expect(Directory(p.join(root.path, 'build')).existsSync(), isFalse);
      },
    );

    for (final target in targets) {
      test(
        'a signalled ${target.name} compile stops before the next command',
        () async {
          final command = compileArgv(target, kept, x64Dart: x64Dart);
          final runner = RecordingRunner(
            (argv) => argv.join('\u0000') == command.join('\u0000')
                ? const Ran(null)
                : goodBuild(argv),
          );
          await expectLater(
            compile(runner, kept, root.path, (_) {}),
            dies('compile of $target failed'),
          );
          expect(runner.argvs.last, command);
          expect(runner.argvs.where((a) => a.first == 'file'), isEmpty);
        },
      );
    }

    test(
      'a failed file command cannot certify a binary from its stdout',
      () async {
        final target = targets.first;
        final runner = RecordingRunner(
          (_) => Ran(1, stdout: '${binaryOf(target)}: ${kinds[target.name]}\n'),
        );
        await expectLater(
          checkKind(runner, target),
          throwsA(isA<ReleaseError>()),
        );
      },
    );

    test('an SDK path with spaces remains one argument', () {
      const sdk = Sdks(
        dart: '/sdk with spaces/dart',
        version: '3.13.5',
        cache: '/cache',
      );
      const spaced = '/x64 with spaces/dart';
      expect(compileArgv(named('darwin-arm64'), sdk).first, sdk.dart);
      expect(compileArgv(named('darwin-x64'), sdk, x64Dart: spaced)[2], spaced);
    });
  });
}

import 'dart:io';

import 'package:chord/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/ci.dart';
import '../../tool/release/build.dart';
import '../../tool/release/runner.dart';
import '../../tool/targets.dart';
import 'release/fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

Target named(String name) => targets.firstWhere((t) => t.name == name);

/// A root of the test's own, so a check may make its build folder there.
final root = Directory.systemTemp.createTempSync('ci_test').path;
final binary = p.join(root, 'build/release/linux-arm64/chord');

/// A machine where the build is good, but for what [override] answers.
RecordingRunner machine([Ran? Function(List<String> argv)? override]) =>
    RecordingRunner((argv) {
      if (override?.call(argv) case final ran?) return ran;
      return switch (argv) {
        ['file', final path] => Ran(
          0,
          stdout: '$path: ${kinds['linux-arm64']}, dynamically linked\n',
        ),
        [final path, '--version'] when path == binary => const Ran(
          0,
          stdout: 'chord $version\n',
        ),
        _ => null,
      };
    });

void main() {
  tearDownAll(() => Directory(root).deleteSync(recursive: true));

  group('the CI runner', () {
    for (final command in [
      'codesign',
      'xcrun',
      'npm',
      'gh',
      'git',
      'curl',
      'brew',
      '/usr/bin/security',
      '/elsewhere/build/release/darwin-arm64/chord',
    ]) {
      test('refuses $command before it runs', () async {
        final inner = RecordingRunner();
        final runner = CiRunner(inner, binary: binary);
        await expectLater(
          runner.run(command, ['x']),
          dies('CI runs only dart, file, tar and $binary, not $command'),
        );
        await expectLater(runner.start(command, ['x']), dies('CI runs only'));
        expect(inner.calls, isEmpty);
      });
    }

    for (final command in ['dart', '/sdk/bin/dart', 'file', 'tar', binary]) {
      test('lets $command through', () async {
        final inner = RecordingRunner();
        await CiRunner(inner, binary: binary).run(command, ['x']);
        expect(inner.argvs, [
          [command, 'x'],
        ]);
      });
    }
  });

  test('the host is the target the running Dart is built for', () {
    expect(
      hostTarget('3.13.5 (stable) (Tue Sep 29) on "linux_arm64"').name,
      'linux-arm64',
    );
    expect(hostTarget('3.13.5 on "macos_x64"').name, 'darwin-x64');
    expect(() => hostTarget('3.13.5 on "windows_x64"'), dies('no target is'));
  });

  group('a check', () {
    Future<List<String>> check_(RecordingRunner inner, {String? host}) async {
      final said = <String>[];
      await check(
        CiRunner(inner, binary: binary),
        named('linux-arm64'),
        host: named(host ?? 'linux-arm64'),
        dart: '/sdk/bin/dart',
        root: root,
        report: said.add,
      );
      return said;
    }

    test('compiles natively, checks the kind, and runs --version', () async {
      final inner = machine();
      final said = await check_(inner);
      expect(inner.calls.first.argv, [
        '/sdk/bin/dart',
        'compile',
        'exe',
        'bin/chord.dart',
        '-o',
        'build/release/linux-arm64/chord',
      ]);
      expect(inner.calls.first.loud, isTrue);
      expect(inner.argvs.skip(1), [
        ['file', 'build/release/linux-arm64/chord'],
        [binary, '--version'],
      ]);
      expect(said, [
        'linux-arm64: ELF 64-bit LSB pie executable, ARM aarch64, '
            'chord $version',
      ]);
    });

    test('of a Linux target on a Linux runner of another CPU, cross-compiles '
        'it and checks its kind, running nothing it built', () async {
      final inner = machine();
      final said = await check_(inner, host: 'linux-x64');
      expect(inner.argvs, [
        [
          '/sdk/bin/dart',
          'compile',
          'exe',
          '--target-os=linux',
          '--target-arch=arm64',
          'bin/chord.dart',
          '-o',
          'build/release/linux-arm64/chord',
        ],
        ['file', 'build/release/linux-arm64/chord'],
      ]);
      expect(said, [
        'linux-arm64: ${kinds['linux-arm64']}, cross-compiled on linux-x64, '
            'not run',
      ]);
    });

    test('of another OS than the runner is refused', () async {
      for (final (target, host) in [
        ('darwin-arm64', 'linux-x64'),
        ('linux-x64', 'darwin-arm64'),
      ]) {
        final inner = machine();
        await expectLater(
          check(
            CiRunner(inner, binary: binary),
            named(target),
            host: named(host),
            dart: '/sdk/bin/dart',
            root: root,
            report: (_) {},
          ),
          dies('$target is checked on its own runner, not on $host'),
        );
        expect(inner.calls, isEmpty);
      }
    });

    test('a failed compile fails it', () async {
      await expectLater(
        check_(
          machine((argv) => argv.contains('compile') ? const Ran(1) : null),
        ),
        dies('compile of linux-arm64 failed'),
      );
    });

    test('a binary of another kind fails it', () async {
      await expectLater(
        check_(
          machine(
            (argv) => argv.first == 'file'
                ? const Ran(
                    0,
                    stdout: 'x: ELF 64-bit LSB pie executable, x86-64',
                  )
                : null,
          ),
        ),
        dies('is x: ELF 64-bit LSB pie executable, x86-64'),
      );
    });

    test('a --version of another version fails it', () async {
      await expectLater(
        check_(
          machine(
            (argv) => argv.last == '--version'
                ? const Ran(0, stdout: 'chord 9.9.9\n')
                : null,
          ),
        ),
        dies('--version said chord 9.9.9'),
      );
    });

    test('a --version that fails fails it', () async {
      await expectLater(
        check_(
          machine(
            (argv) => argv.last == '--version'
                ? Ran(null, stdout: 'chord $version\n')
                : null,
          ),
        ),
        dies('--version said'),
      );
    });
  });

  group('tester: CI target and delegation boundaries', () {
    for (final target in targets) {
      test(
        '${target.name} uses its own native binary through the allowlist',
        () async {
          final binary = p.join(root, binaryOf(target));
          final inner = RecordingRunner(
            (argv) => switch (argv) {
              ['file', _] => Ran(0, stdout: kinds[target.name]!),
              [final path, '--version'] when path == binary => const Ran(
                0,
                stdout: 'chord $version\n',
              ),
              _ => null,
            },
          );
          final reports = <String>[];
          await check(
            CiRunner(inner, binary: binary),
            target,
            host: target,
            dart: '/sdk/bin/dart',
            root: root,
            report: reports.add,
          );
          expect(inner.argvs.last, [binary, '--version']);
          expect(inner.argvs.first, isNot(contains(startsWith('--target-'))));
          expect(reports, hasLength(1));
        },
      );
    }

    test(
      'allowed starts preserve arguments, directory and environment',
      () async {
        final child = ScriptedStarted((_) => []);
        final inner = RecordingRunner(null, (_) => child);
        final started = await CiRunner(
          inner,
          binary: binary,
        ).start('dart', ['--version'], cwd: 'project', env: {'MARK': 'value'});
        expect(identical(started, child), isTrue);
        expect(inner.calls.single.cwd, 'project');
        expect(inner.calls.single.env, {'MARK': 'value'});
        expect(inner.argvs.single, ['dart', '--version']);
        await child.close();
      },
    );

    test(
      'a signalled kind check starts no binary and reports no success',
      () async {
        final inner = machine(
          (argv) => argv.first == 'file'
              ? Ran(null, stdout: kinds['linux-arm64']!)
              : null,
        );
        final reports = <String>[];
        await expectLater(
          check(
            CiRunner(inner, binary: binary),
            named('linux-arm64'),
            host: named('linux-arm64'),
            dart: 'dart',
            root: root,
            report: reports.add,
          ),
          dies('file build/release/linux-arm64/chord failed'),
        );
        expect(inner.calls, hasLength(2));
        expect(reports, isEmpty);
      },
    );
  });
}

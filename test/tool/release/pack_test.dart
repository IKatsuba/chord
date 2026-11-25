import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/formula.dart';
import '../../../tool/release/archive.dart';
import '../../../tool/release/build.dart';
import '../../../tool/release/pack.dart';
import '../../../tool/release/preflight.dart';
import '../../../tool/release/runner.dart';
import '../../../tool/targets.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  late Directory root;
  late Map<String, String> notarised;
  late List<(String, String?)> selftested;
  late List<String> said;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pack_test');
    for (final target in targets) {
      (File(
        p.join(root.path, binaryOf(target)),
      )..createSync(recursive: true)).writeAsStringSync('binary of $target\n');
    }
    File(p.join(root.path, 'LICENSE')).writeAsStringSync('MIT\n');
    (File(
      p.join(root.path, 'README.md'),
    )..createSync(recursive: true)).writeAsStringSync('# chord\n');
    notarised = {
      for (final binary in darwinBinaries)
        binary: sha256Of(p.join(root.path, binary)),
    };
    selftested = [];
    said = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A machine where kinds, signatures and npm answer as a good release
  /// does: `npm pack` leaves its tarball, `npm install` leaves the
  /// installed copies, chmod and tar run for real; [override] first.
  RecordingRunner machine({
    String version = '1.2.3',
    Ran? Function(List<String> argv, String? cwd)? override,
    bool quarantined = false,
  }) {
    final runner = RecordingRunner(null, null, (argv, cwd) {
      if (override?.call(argv, cwd) case final ran?) return ran;
      switch (argv) {
        case ['file', final binary]:
          final target = targets.firstWhere((t) => binaryOf(t) == binary);
          return Ran(0, stdout: '$binary: ${kinds[target.name]}\n');
        case ['chmod' || 'tar', ...]:
          final ran = Process.runSync(
            argv.first,
            argv.sublist(1),
            workingDirectory: root.path,
          );
          return Ran(ran.exitCode, stderr: '${ran.stderr}');
        case ['npm', 'pack', '--pack-destination', final dest]:
          final package = p.basename(cwd!);
          File(
            p.join(dest, 'chorded-$package-$version.tgz'),
          ).writeAsStringSync('tarball of $package');
          return const Ran(0);
        case ['npm', 'install', ...final rest]:
          for (final tgz in rest.where((arg) => arg.endsWith('.tgz'))) {
            final name = RegExp(
              r'chorded-(chord(?:-(?:darwin|linux)-(?:arm64|x64))?)-\d.*\.tgz$',
            ).firstMatch(tgz)![1]!;
            if (name == 'chord') {
              (File(
                p.join(cwd!, 'node_modules', '.bin', 'chord'),
              )..createSync(recursive: true)).writeAsStringSync('shim');
              continue;
            }
            final target = targets.firstWhere((t) => 'chord-${t.name}' == name);
            File(p.join(root.path, binaryOf(target))).copySync(
              (File(
                p.join(cwd!, 'node_modules', '@chorded', name, 'bin', 'chord'),
              )..createSync(recursive: true)).path,
            );
          }
          return const Ran(0);
        case ['xattr', _]:
          return Ran(
            0,
            stdout: quarantined
                ? 'com.apple.quarantine\n'
                : 'com.apple.provenance\n',
          );
      }
      return null;
    });
    return runner;
  }

  Future<void> packWith(RecordingRunner runner, {String version = '1.2.3'}) =>
      pack(
        runner,
        root.path,
        version: version,
        npmNames: npmNames,
        notices: () => 'NOTICES\n',
        notarised: notarised,
        selftest: (binary, arch) async => selftested.add((binary, arch)),
        out: said.add,
      );

  test('the notarised bytes are archived, packed, installed, checked and '
      'summed, and a stable version gets its formula', () async {
    final runner = machine();
    await packWith(runner);
    final tgz = p.join(root.path, tgzFolder);
    for (final name in npmNames) {
      expect(
        File(p.join(tgz, tarballName(name, '1.2.3'))).existsSync(),
        isTrue,
      );
    }
    checkSum(p.join(tgz, tarballName(npmNames.last, '1.2.3')));
    for (final target in targets) {
      checkSum(p.join(root.path, archivesFolder, target.archive));
    }
    expect(File(p.join(root.path, formulaPath)).existsSync(), isTrue);
    expect(
      runner.calls
          .where((call) => call.argv.take(2).join(' ') == 'npm pack')
          .map((call) => call.cwd),
      [
        for (final name in npmNames)
          'build/release/npm/${name.split('/').last}',
      ],
    );
    expect(selftested, hasLength(2));
    expect(selftested.first.$1, endsWith('node_modules/.bin/chord'));
    expect(selftested.first.$2, isNull);
    expect(selftested.last.$1, endsWith('@chorded/chord-darwin-x64/bin/chord'));
    expect(selftested.last.$2, 'x86_64');
    expect(said.single, startsWith('packed '));
  });

  test('every npm install of another platform is forced, in a project of '
      'its own', () async {
    final runner = machine();
    await packWith(runner);
    final installs = [
      for (final call in runner.calls)
        if (call.argv.take(2).join(' ') == 'npm install') call,
    ];
    expect(installs, hasLength(4));
    expect(installs.first.argv, isNot(contains('--force')));
    for (final call in installs.skip(1)) {
      expect(call.argv, contains('--force'));
      expect(call.cwd, isNot(installs.first.cwd));
    }
  });

  test('a channel version is packed whole, and gets no formula', () async {
    const version = '1.3.0-next.0';
    await packWith(machine(version: version), version: version);
    final tgz = p.join(root.path, tgzFolder);
    for (final name in npmNames) {
      checkSum(p.join(tgz, tarballName(name, version)));
    }
    for (final target in targets) {
      checkSum(p.join(root.path, archivesFolder, target.archive));
    }
    expect(File(p.join(root.path, formulaPath)).existsSync(), isFalse);
    expect(selftested, hasLength(2));
  });

  group('the gate', () {
    test('a darwin binary changed since it was notarised is refused before '
        'anything is made', () async {
      File(p.join(root.path, darwinBinaries[1])).writeAsStringSync('rebuilt\n');
      final runner = machine();
      await expectLater(
        packWith(runner),
        dies(
          '${darwinBinaries[1]} is not the binary notarised: its sha256 is ',
        ),
      );
      expect(runner.calls, isEmpty);
      expect(
        Directory(p.join(root.path, archivesFolder)).existsSync(),
        isFalse,
      );
    });

    test('a darwin binary with no notarisation recorded is refused', () async {
      notarised.remove(darwinBinaries[0]);
      await expectLater(
        packWith(machine()),
        dies(
          '${darwinBinaries[0]} has no notarisation recorded; run notarise '
          'first',
        ),
      );
    });

    test('a darwin binary that no longer verifies is refused', () async {
      await expectLater(
        packWith(
          machine(
            override: (argv, _) => argv.first == 'codesign'
                ? const Ran(1, stderr: 'invalid\n')
                : null,
          ),
        ),
        dies('does not verify: invalid'),
      );
    });
  });

  group('the installed copies', () {
    test('a copy that differs from the build is refused', () async {
      final runner = machine(
        override: (argv, cwd) {
          if (argv case [
            'npm',
            'install',
            ...,
          ] when argv.any((a) => a.contains('linux-x64'))) {
            (File(
              p.join(cwd!, 'node_modules/@chorded/chord-linux-x64/bin/chord'),
            )..createSync(recursive: true)).writeAsStringSync('other');
            return const Ran(0);
          }
          return null;
        },
      );
      await expectLater(packWith(runner), dies('differs from'));
    });

    test('a quarantined macOS copy is refused', () async {
      await expectLater(
        packWith(machine(quarantined: true)),
        dies('npm quarantined'),
      );
    });

    test('a failed npm pack stops it', () async {
      await expectLater(
        packWith(
          machine(
            override: (argv, _) =>
                argv.take(2).join(' ') == 'npm pack' ? const Ran(1) : null,
          ),
        ),
        dies('npm pack of chord-darwin-arm64 failed'),
      );
    });
  });

  test('the outputs pack leaves', () {
    expect(packOutputs('1.2.3', npmNames), [
      for (final name in npmNames)
        'build/release/tgz/${tarballName(name, '1.2.3')}',
      'build/release/tgz/SHA256SUMS',
      for (final target in targets) 'build/release/archives/${target.archive}',
      'build/release/archives/SHA256SUMS',
    ]);
    expect(
      tarballName('@chorded/chord-linux-x64', '1.2.3'),
      'chorded-chord-linux-x64-1.2.3.tgz',
    );
  });

  group('tester: pack cleanup and gate boundaries', () {
    test(
      'a rejected notarisation gate does not read notices or erase output',
      () async {
        final previous = File(p.join(root.path, tgzFolder, 'previous'))
          ..createSync(recursive: true)
          ..writeAsStringSync('kept');
        notarised.clear();
        var noticeReads = 0;
        final runner = machine();
        await expectLater(
          pack(
            runner,
            root.path,
            version: '1.2.3',
            npmNames: npmNames,
            notices: () {
              noticeReads++;
              return 'notice';
            },
            notarised: notarised,
            selftest: (_, _) async {},
            out: said.add,
          ),
          dies('has no notarisation'),
        );
        expect(noticeReads, 0);
        expect(runner.calls, isEmpty);
        expect(previous.readAsStringSync(), 'kept');
      },
    );

    test(
      'a failed install removes its scratch project and records no sums',
      () async {
        final runner = machine(
          override: (argv, _) =>
              argv.take(2).join(' ') == 'npm init' ? const Ran(1) : null,
        );
        await expectLater(
          packWith(runner),
          dies('installing the tarballs failed'),
        );
        final scratch = runner.calls
            .firstWhere((c) => c.argv.take(2).join(' ') == 'npm init')
            .cwd!;
        expect(Directory(scratch).existsSync(), isFalse);
        expect(File(p.join(root.path, tgzFolder, sums)).existsSync(), isFalse);
        expect(said, isEmpty);
      },
    );

    test(
      'a failed installed self-test removes scratch and reports no pack',
      () async {
        final runner = machine();
        late String installed;
        await expectLater(
          pack(
            runner,
            root.path,
            version: '1.2.3',
            npmNames: npmNames,
            notices: () => 'notice',
            notarised: notarised,
            selftest: (binary, _) async {
              installed = binary;
              throw StateError('failed');
            },
            out: said.add,
          ),
          throwsStateError,
        );
        expect(File(installed).existsSync(), isFalse);
        expect(File(p.join(root.path, tgzFolder, sums)).existsSync(), isFalse);
        expect(File(p.join(root.path, formulaPath)).existsSync(), isFalse);
        expect(said, isEmpty);
      },
    );

    test(
      'a channel pack leaves no formula from an earlier stable pack',
      () async {
        File(p.join(root.path, formulaPath))
          ..createSync(recursive: true)
          ..writeAsStringSync('old stable formula');
        const version = '1.3.0-next.0';
        await packWith(machine(version: version), version: version);
        expect(File(p.join(root.path, formulaPath)).existsSync(), isFalse);
      },
    );
  });
}

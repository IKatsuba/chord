import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/runner.dart';
import '../../../tool/release/sign.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

const hash = '0123456789ABCDEF0123456789ABCDEF01234567';
const identities =
    '  1) $hash "Developer ID Application: Someone (YQ8ZD2KZ3T)"\n'
    '  2) FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF "Apple Development: '
    'Someone (OTHERTEAM1)"\n'
    '     2 valid identities found\n';
const json =
    '{"com.apple.security.cs.allow-unsigned-executable-memory":true}\n';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('sign_test');
    (File(
      p.join(root.path, 'build/release/darwin-arm64/chord'),
    )..createSync(recursive: true)).writeAsStringSync('bin');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// Answers codesign and plutil as a good signing does; [read] and
  /// [reference] override plutil's answers for the read-back and the file.
  RecordingRunner signing({
    Ran? verify,
    Ran? readBack,
    Ran? read,
    Ran? reference,
  }) => RecordingRunner((argv) {
    switch (argv) {
      case ['codesign', '--verify', ...]:
        return verify;
      case ['codesign', '-d', ...]:
        return readBack ?? const Ran(0, stdout: '<plist/>');
      case ['plutil', ..., final path] when path == entitlementsPath:
        return reference ?? const Ran(0, stdout: json);
      case ['plutil', ...]:
        return read ?? const Ran(0, stdout: json);
    }
    return null;
  });

  Future<List<String>> signArm(RecordingRunner runner) async {
    final said = <String>[];
    await sign(runner, root.path, hash, [
      'build/release/darwin-arm64/chord',
    ], out: said.add);
    return said;
  }

  test("the team's one identity is found by its hash", () async {
    final runner = RecordingRunner((_) => const Ran(0, stdout: identities));
    expect(await identity(runner, '/home/x'), hash);
    expect(runner.argvs.single, [
      'security',
      'find-identity',
      '-v',
      '-p',
      'codesigning',
      '/home/x/Library/Keychains/login.keychain-db',
    ]);
  });

  for (final (name, listed) in [
    ('no identity', '     0 valid identities found\n'),
    (
      'two identities',
      '$identities  3) $hash "Developer ID Application: Other (YQ8ZD2KZ3T)"\n',
    ),
  ]) {
    test('$name of the team dies with what security said', () async {
      final runner = RecordingRunner((_) => Ran(0, stdout: listed));
      await expectLater(
        identity(runner, '/home/x'),
        dies(
          'expected one Developer ID Application identity of team '
          'YQ8ZD2KZ3T, found ${name == 'no identity' ? 0 : 2}; security '
          'find-identity said:\n',
        ),
      );
    });
  }

  test('a binary is signed with the runtime and the entitlement, then '
      'checked', () async {
    final runner = signing();
    final said = await signArm(runner);
    const binary = 'build/release/darwin-arm64/chord';
    expect(runner.calls[0].argv, [
      'codesign',
      '--force',
      '--sign',
      hash,
      '--options',
      'runtime',
      '--timestamp',
      '--entitlements',
      'tool/macos/chord.entitlements',
      '--identifier',
      'dev.katsuba.chord',
      binary,
    ]);
    expect(runner.calls[0].loud, isTrue);
    expect(runner.calls[1].argv, [
      'codesign',
      '--verify',
      '--strict',
      '--verbose=2',
      binary,
    ]);
    expect(runner.calls[2].argv, [
      'codesign',
      '-d',
      '--entitlements',
      '-',
      '--xml',
      binary,
    ]);
    expect(runner.calls[3].argv.take(4), ['plutil', '-convert', 'json', '-o']);
    expect(runner.calls[4].argv.last, entitlementsPath);
    expect(said, ['signed $binary: ${json.trim()}']);
  });

  test('entitlements read back other than the file die with both', () async {
    await expectLater(
      signArm(signing(read: const Ran(0, stdout: '{"other":true}\n'))),
      dies(
        'entitlements of build/release/darwin-arm64/chord differ from '
        '$entitlementsPath: got {"other":true}, want ${json.trim()}',
      ),
    );
  });

  test('a binary that does not verify dies', () async {
    await expectLater(
      signArm(signing(verify: const Ran(1))),
      dies('build/release/darwin-arm64/chord does not verify'),
    );
  });

  test('a binary whose entitlements cannot be read back dies', () async {
    await expectLater(
      signArm(signing(readBack: const Ran(1))),
      dies(
        'the entitlements of build/release/darwin-arm64/chord could not '
        'be read back',
      ),
    );
  });

  test('a binary that is not there dies', () async {
    final runner = signing();
    await expectLater(
      sign(runner, root.path, hash, [
        'build/release/darwin-x64/chord',
      ], out: (_) {}),
      dies('no binary at build/release/darwin-x64/chord'),
    );
    expect(runner.calls, isEmpty);
  });

  test('entitlements plutil cannot read stop the signing, even when the '
      'read-back is as empty', () async {
    await expectLater(
      signArm(
        signing(
          read: const Ran(0),
          reference: const Ran(1, stderr: 'no such file\n'),
        ),
      ),
      dies('$entitlementsPath could not be read: no such file'),
    );
  });

  test('a read-back plutil fails on dies with what it said', () async {
    await expectLater(
      signArm(signing(read: const Ran(1, stderr: 'bad plist\n'))),
      dies(
        'the entitlements read back from build/release/darwin-arm64/chord '
        'could not be converted: bad plist',
      ),
    );
  });

  // Slips of the original, fixed: a failed command certifies nothing, even
  // when what it printed looks right.
  test(
    'a read-back plutil that fails but prints the right JSON dies',
    () async {
      await expectLater(
        signArm(
          signing(
            read: const Ran(1, stdout: json, stderr: 'odd\n'),
          ),
        ),
        dies('could not be converted: odd'),
      );
    },
  );

  test('a security that fails but lists the identity dies', () async {
    final runner = RecordingRunner(
      (_) => const Ran(1, stdout: identities, stderr: 'keychain locked\n'),
    );
    await expectLater(
      identity(runner, '/home/x'),
      dies('security find-identity failed: keychain locked'),
    );
  });

  test('the entitlements file is the one Dart needs', () {
    final file = File(p.join('tool', 'macos', 'chord.entitlements'));
    final text = file.readAsStringSync();
    expect(
      text,
      contains('com.apple.security.cs.allow-unsigned-executable-memory'),
    );
    expect(text, isNot(contains('allow-jit')));
  });

  group('tester: signing command and scratch boundaries', () {
    test('a failed or signalled signing starts no verification', () async {
      for (final status in [1, null]) {
        final runner = RecordingRunner((_) => Ran(status));
        await expectLater(signArm(runner), dies('codesign failed'));
        expect(runner.calls, hasLength(1));
      }
    });

    test(
      'a thrown plist conversion still removes the temporary file',
      () async {
        late String temporary;
        final good = signing();
        final runner = RecordingRunner((argv) {
          if (argv.first == 'plutil' && argv.last != entitlementsPath) {
            temporary = argv.last;
            expect(File(temporary).existsSync(), isTrue);
            throw StateError('converter stopped');
          }
          return good.answer!(argv);
        });
        await expectLater(signArm(runner), throwsStateError);
        expect(File(temporary).existsSync(), isFalse);
        expect(Directory(p.dirname(temporary)).existsSync(), isFalse);
      },
    );
  });
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/archive.dart';
import '../../../tool/release/build.dart';
import '../../../tool/release/runner.dart';
import '../../../tool/targets.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

const everyDarwin = {'darwin-arm64', 'darwin-x64'};

void main() {
  late Directory root;
  late ProcessReleaseRunner local;

  /// Records every command; file and codesign are answered by [codesign]
  /// and the kinds table, chmod and tar run for real in the temp tree.
  RecordingRunner runner({Ran Function(String binary)? codesign}) =>
      RecordingRunner((argv) {
        switch (argv) {
          case ['file', final binary]:
            final target = targets.firstWhere((t) => binaryOf(t) == binary);
            return Ran(0, stdout: '$binary: ${kinds[target.name]}\n');
          case ['codesign', '--verify', '--strict', final binary]:
            return codesign?.call(binary) ?? const Ran(0);
          case ['chmod' || 'tar', ...]:
            return null;
        }
        throw StateError('unexpected $argv');
      });

  setUp(() {
    root = Directory.systemTemp.createTempSync('archive_test');
    local = ProcessReleaseRunner(root: root.path, env: Platform.environment);
    for (final target in targets) {
      (File(
        p.join(root.path, binaryOf(target)),
      )..createSync(recursive: true)).writeAsStringSync('binary of $target\n');
    }
    File(p.join(root.path, 'LICENSE')).writeAsStringSync('MIT\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// Archives with a runner whose chmod and tar run for real, in order.
  Future<RecordingRunner> archiveAll({
    Set<String> notarised = everyDarwin,
    Ran Function(String binary)? codesign,
  }) async {
    final recording = runner(codesign: codesign);
    final real = _Interleaved(recording, local);
    await archive(
      real,
      root.path,
      notices: 'NOTICES text\n',
      notarised: notarised,
    );
    return recording;
  }

  test('every target is archived with its three members, and summed', () async {
    final recording = await archiveAll();
    final out = p.join(root.path, archivesFolder);
    expect(
      Directory(out).listSync().map((e) => p.basename(e.path)).toList()..sort(),
      [...targets.map((t) => t.archive), sums]..sort(),
    );
    for (final target in targets) {
      final listing = await Process.run('tar', [
        '-tzvf',
        p.join(out, target.archive),
      ]);
      final lines = (listing.stdout as String).trim().split('\n');
      expect([
        for (final line in lines) line.split(RegExp(r'\s+')).last,
      ], members);
      expect(
        [for (final line in lines) line.substring(0, 10)],
        ['-rwxr-xr-x', '-rw-r--r--', '-rw-r--r--'],
      );
      // From the headers, not the listing: bsdtar and GNU tar list owners
      // differently.
      expect(
        [
          for (final header in headersOf(p.join(out, target.archive)))
            header.owner,
        ],
        [for (final _ in members) ('0', '0', 'root', 'root')],
      );
      final extracted = Directory(p.join(root.path, 'x', target.name))
        ..createSync(recursive: true);
      await Process.run('tar', [
        '-xzf',
        p.join(out, target.archive),
        '-C',
        extracted.path,
      ]);
      expect(
        File(p.join(extracted.path, 'chord')).readAsStringSync(),
        'binary of $target\n',
      );
      expect(
        File(p.join(extracted.path, 'LICENSE')).readAsStringSync(),
        'MIT\n',
      );
      expect(
        File(p.join(extracted.path, 'NOTICES')).readAsStringSync(),
        'NOTICES text\n',
      );
      checkSum(p.join(out, target.archive));
    }
    final shasum = await Process.run('shasum', [
      '-a',
      '256',
      '-c',
      sums,
    ], workingDirectory: out);
    expect(shasum.exitCode, 0, reason: '${shasum.stdout}${shasum.stderr}');
    expect(recording.argvs.where((argv) => argv.first == 'codesign'), [
      for (final name in everyDarwin)
        ['codesign', '--verify', '--strict', 'build/release/$name/chord'],
    ]);
  });

  test(
    'no extended attribute and no pax header is archived (CTUI-151)',
    () async {
      // macOS gives every written file com.apple.provenance; one more is set
      // where xattr is, so the members surely carry some.
      for (final path in [binaryOf(targets.first), 'LICENSE']) {
        if (Platform.isMacOS) {
          await Process.run('xattr', [
            '-w',
            'com.example.probe',
            'x',
            p.join(root.path, path),
          ]);
        }
      }
      final recording = await archiveAll();
      final writes = recording.argvs.where(
        (argv) => argv.first == 'tar' && argv.contains('-czf'),
      );
      expect(writes, hasLength(targets.length));
      for (final argv in writes) {
        expect(argv, contains('--no-xattrs'));
      }
      for (final target in targets) {
        final raw = gzip.decode(
          File(
            p.join(root.path, archivesFolder, target.archive),
          ).readAsBytesSync(),
        );
        final kinds = <String>[];
        for (var at = 0; at + 512 <= raw.length; at += 512) {
          if (String.fromCharCodes(raw.sublist(at + 257, at + 262)) ==
              'ustar') {
            kinds.add(String.fromCharCode(raw[at + 156]));
          }
        }
        expect(kinds, ['0', '0', '0'], reason: target.archive);
        final text = String.fromCharCodes(raw);
        expect(text, isNot(contains('xattr')));
        expect(text, isNot(contains('com.apple')));
      }
    },
  );

  test('every binary is checked before any archive is written', () async {
    final recording = await archiveAll();
    final firstTar = recording.argvs.indexWhere((argv) => argv.first == 'tar');
    final lastCheck = recording.argvs.lastIndexWhere(
      (argv) => argv.first == 'file' || argv.first == 'codesign',
    );
    expect(lastCheck, lessThan(firstTar));
  });

  test(
    'a darwin binary that does not verify is refused, nothing written',
    () async {
      await expectLater(
        archiveAll(
          codesign: (binary) => binary.contains('darwin-x64')
              ? const Ran(1, stderr: 'invalid signature\n')
              : const Ran(0),
        ),
        dies(
          'build/release/darwin-x64/chord does not verify: invalid signature',
        ),
      );
      expect(
        Directory(p.join(root.path, archivesFolder)).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'a darwin binary whose notarisation is not recorded is refused',
    () async {
      await expectLater(
        archiveAll(notarised: {'darwin-arm64'}),
        dies(
          'build/release/darwin-x64/chord is not notarised: the release '
          'records no notarisation',
        ),
      );
      expect(
        Directory(p.join(root.path, archivesFolder)).existsSync(),
        isFalse,
      );
    },
  );

  test('a Linux binary is checked for its kind, never signed', () async {
    final recording = await archiveAll();
    expect(
      recording.argvs.where(
        (argv) => argv.first == 'codesign' && argv.last.contains('linux'),
      ),
      isEmpty,
    );
    expect(
      recording.argvs,
      anyElement(equals(['file', 'build/release/linux-arm64/chord'])),
    );
  });

  test('without LICENSE nothing runs', () async {
    File(p.join(root.path, 'LICENSE')).deleteSync();
    final recording = runner();
    await expectLater(
      archive(recording, root.path, notices: 'n', notarised: everyDarwin),
      dies('LICENSE is missing: every archive carries the licence'),
    );
    expect(recording.calls, isEmpty);
  });

  test('with an empty LICENSE nothing runs', () async {
    File(p.join(root.path, 'LICENSE')).writeAsStringSync(' \n');
    final recording = runner();
    await expectLater(
      archive(recording, root.path, notices: 'n', notarised: everyDarwin),
      dies('LICENSE is empty: every archive carries the licence'),
    );
    expect(recording.calls, isEmpty);
    expect(Directory(p.join(root.path, archivesFolder)).existsSync(), isFalse);
  });

  test('with empty NOTICES nothing runs', () async {
    final recording = runner();
    await expectLater(
      archive(recording, root.path, notices: ' \n\t', notarised: everyDarwin),
      dies('NOTICES is empty: every archive carries the notices'),
    );
    expect(recording.calls, isEmpty);
    expect(Directory(p.join(root.path, archivesFolder)).existsSync(), isFalse);
  });

  group('tar flavours', () {
    test('bsdtar and GNU tar are told apart by their version', () {
      expect(
        tarFlavourIn('bsdtar 3.5.3 - libarchive 3.7.4 zlib/1.2.12\n'),
        TarFlavour.bsd,
      );
      expect(
        tarFlavourIn('tar (GNU tar) 1.35\nCopyright (C) 2023\n'),
        TarFlavour.gnu,
      );
      expect(
        () => tarFlavourIn('tar (busybox) 1.36\n'),
        dies('tar is neither bsdtar nor GNU tar: tar (busybox) 1.36'),
      );
    });

    test("bsdtar's arguments are macOS's, unchanged", () {
      expect(tarArgs(TarFlavour.bsd, 'out.tar.gz', 'stage'), [
        '--uid',
        '0',
        '--gid',
        '0',
        '--uname',
        'root',
        '--gname',
        'root',
        '--no-mac-metadata',
        '--no-xattrs',
        '-czf',
        'out.tar.gz',
        '-C',
        'stage',
        'chord',
        'LICENSE',
        'NOTICES',
      ]);
    });

    test("GNU tar's arguments name root by name and id, in ustar", () {
      expect(tarArgs(TarFlavour.gnu, 'out.tar.gz', 'stage'), [
        '--owner=root:0',
        '--group=root:0',
        '--format=ustar',
        '--no-xattrs',
        '-czf',
        'out.tar.gz',
        '-C',
        'stage',
        'chord',
        'LICENSE',
        'NOTICES',
      ]);
    });

    test("the host's tar is asked once, after every check", () async {
      final recording = await archiveAll();
      final tars = [
        for (final argv in recording.argvs)
          if (argv.first == 'tar') argv,
      ];
      expect(tars.first, ['tar', '--version']);
      expect(tars.where((argv) => argv[1] == '--version'), hasLength(1));
      expect(tars, hasLength(targets.length + 1));
    });
  });

  group('sums', () {
    test("are written in sha256sum's format, names relative", () {
      File(p.join(root.path, 'a')).writeAsStringSync('a');
      recordSums(root.path, ['a']);
      expect(
        File(p.join(root.path, sums)).readAsStringSync(),
        'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb  a\n',
      );
    });

    test('a changed file is refused', () {
      final file = File(p.join(root.path, 'a'))..writeAsStringSync('a');
      recordSums(root.path, ['a']);
      file.writeAsStringSync('b');
      expect(() => checkSum(file.path), dies('has sha256 3e23e8160039594a'));
    });

    test('a file summed twice is refused, whichever sum is right', () {
      final file = File(p.join(root.path, 'a'))..writeAsStringSync('a');
      recordSums(root.path, ['a']);
      final sumsFile = File(p.join(root.path, sums));
      sumsFile.writeAsStringSync(
        '${sumsFile.readAsStringSync()}${'f' * 64}  a\n',
      );
      expect(() => checkSum(file.path), dies('records'));
      expect(() => checkSum(file.path), dies('more than once'));
    });

    test('a file with no sum is refused', () {
      File(p.join(root.path, 'a')).writeAsStringSync('a');
      expect(
        () => checkSum(p.join(root.path, 'a')),
        dies('SHA256SUMS has no sum for'),
      );
    });
  });

  group('tester: archive refusal and checksum boundaries', () {
    test('empty NOTICES stops packaging before commands or writes', () async {
      final recording = runner();
      await expectLater(
        archive(
          _Interleaved(recording, local),
          root.path,
          notices: ' \n\t',
          notarised: everyDarwin,
        ),
        throwsA(isA<ReleaseError>()),
      );
      expect(recording.calls, isEmpty);
      expect(
        Directory(p.join(root.path, archivesFolder)).existsSync(),
        isFalse,
      );
    });

    test('a signalled signature check preserves the previous output', () async {
      final previous = File(p.join(root.path, archivesFolder, 'previous'))
        ..createSync(recursive: true)
        ..writeAsStringSync('retained');
      await expectLater(
        archiveAll(codesign: (_) => const Ran(null, stderr: 'terminated')),
        dies('does not verify: terminated'),
      );
      expect(previous.readAsStringSync(), 'retained');
      expect(
        Directory(p.join(root.path, 'build/release/staging')).existsSync(),
        isFalse,
      );
    });

    test('a failed chmod stops before tar or checksums', () async {
      final checks = runner();
      final recording = RecordingRunner(
        (argv) => argv.first == 'chmod'
            ? const Ran(3, stderr: 'denied')
            : checks.answer!(argv),
      );
      await expectLater(
        archive(
          recording,
          root.path,
          notices: 'notice',
          notarised: everyDarwin,
        ),
        dies('failed: denied'),
      );
      expect(recording.argvs.where((a) => a.first == 'tar'), isEmpty);
      expect(
        File(p.join(root.path, archivesFolder, sums)).existsSync(),
        isFalse,
      );
    });

    test('checksums accept binary markers and names containing spaces', () {
      final file = File(p.join(root.path, 'an archive.tar.gz'))
        ..writeAsBytesSync([0, 255, 27, 10]);
      File(
        p.join(root.path, sums),
      ).writeAsStringSync('${sha256Of(file.path)} *an archive.tar.gz\n');
      expect(() => checkSum(file.path), returnsNormally);
    });
  });
}

/// Each ustar header in the gzipped tar at [path], in order: its type and
/// its owner as uid, gid, uname and gname.
List<({String type, (String, String, String, String) owner})> headersOf(
  String path,
) {
  final raw = gzip.decode(File(path).readAsBytesSync());
  String field(int at, int length) => String.fromCharCodes(
    raw.sublist(at, at + length).takeWhile((byte) => byte != 0),
  ).trim();
  return [
    for (var at = 0; at + 512 <= raw.length; at += 512)
      if (String.fromCharCodes(raw.sublist(at + 257, at + 262)) == 'ustar')
        (
          type: String.fromCharCode(raw[at + 156]),
          owner: (
            int.parse(field(at + 108, 8), radix: 8).toString(),
            int.parse(field(at + 116, 8), radix: 8).toString(),
            field(at + 265, 32),
            field(at + 297, 32),
          ),
        ),
  ];
}

/// Records through [recording], then runs chmod and tar for real.
final class _Interleaved implements ReleaseRunner {
  _Interleaved(this.recording, this.real);

  final RecordingRunner recording;
  final ReleaseRunner real;

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    final answer = await recording.run(command, args, loud: loud);
    return command == 'chmod' || command == 'tar'
        ? real.run(command, args, loud: loud)
        : answer;
  }

  @override
  Future<Started> start(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  }) => throw StateError('an archive starts nothing');
}

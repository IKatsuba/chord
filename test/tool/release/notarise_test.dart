import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/notarise.dart';
import '../../../tool/release/runner.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

const binaries = [
  'build/release/darwin-arm64/chord',
  'build/release/darwin-x64/chord',
];
const out = 'build/release/notarise';
final cdhashes = {binaries[0]: 'aaaa1111', binaries[1]: 'bbbb2222'};

void main() {
  late Directory root;
  late List<Duration> slept;
  late List<String> said;
  setUp(() {
    root = Directory.systemTemp.createTempSync('notarise_test');
    slept = [];
    said = [];
    for (final binary in binaries) {
      (File(
        p.join(root.path, binary),
      )..createSync(recursive: true)).writeAsStringSync(binary);
    }
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A notarytool and codesign that answer [submit], write [log] on the
  /// log fetch (failing the first [logFailures] fetches), and show each
  /// binary's cdhash.
  RecordingRunner apple({
    Ran submit = const Ran(
      0,
      stdout: '{"id":"sub-1","status":"Accepted"}\n',
      stderr: 'progress\n',
    ),
    List<String>? tickets,
    int logFailures = 0,
    Ran zipped = const Ran(0),
    int codesignStatus = 0,
  }) {
    var fetches = 0;
    return RecordingRunner((argv) {
      switch (argv) {
        case ['ditto', ...]:
          return zipped;
        case ['xcrun', 'notarytool', 'submit', ...]:
          return submit;
        case ['xcrun', 'notarytool', 'log', _, _, _, final log]:
          fetches++;
          if (fetches <= logFailures) {
            return const Ran(1, stderr: 'not yet\n');
          }
          File(p.join(root.path, log)).writeAsStringSync(
            jsonEncode({
              'ticketContents': [
                for (final cdhash in tickets ?? cdhashes.values)
                  {'cdhash': cdhash},
              ],
            }),
          );
          return const Ran(0);
        case ['codesign', '-dvvv', final binary]:
          return Ran(
            codesignStatus,
            stderr: 'Identifier=x\nCDHash=${cdhashes[binary]}\n',
          );
      }
      throw StateError('unexpected $argv');
    });
  }

  Future<Map<String, String>> run(RecordingRunner runner) => notarise(
    runner,
    root.path,
    out,
    binaries,
    sleep: (d) async => slept.add(d),
    report: said.add,
  );

  String kept(String name) =>
      File(p.join(root.path, out, name)).readAsStringSync();

  test('an accepted submission listing both binaries notarises them', () async {
    final runner = apple();
    expect(await run(runner), cdhashes);
    expect(runner.argvs.first.take(6), [
      'ditto',
      '-c',
      '-k',
      '--norsrc',
      '--noextattr',
      '--keepParent',
    ]);
    expect(runner.argvs.first.last, '$out/chord.zip');
    expect(runner.argvs[1], [
      'xcrun',
      'notarytool',
      'submit',
      '$out/chord.zip',
      '--keychain-profile',
      'roost-notary',
      '--wait',
      '--output-format',
      'json',
    ]);
    expect(runner.argvs[2], [
      'xcrun',
      'notarytool',
      'log',
      'sub-1',
      '--keychain-profile',
      'roost-notary',
      '$out/notarytool-log.json',
    ]);
    expect(kept('notarytool.json'), '{"id":"sub-1","status":"Accepted"}\n');
    expect(kept('notarytool-submit.stderr'), 'progress\n');
    expect(said, [
      'notarised ${binaries[0]}: aaaa1111',
      'notarised ${binaries[1]}: bbbb2222',
    ]);
  });

  test('the zip holds each binary named by its target', () async {
    late List<String> names;
    final recording = apple();
    final runner = RecordingRunner((argv) {
      if (argv case ['ditto', ..., final folder, _]) {
        names = [
          for (final entry in Directory(folder).listSync())
            p.basename(entry.path),
        ]..sort();
      }
      return recording.answer!(argv);
    });
    await run(runner);
    expect(names, ['darwin-arm64-chord', 'darwin-x64-chord']);
  });

  test('a verdict other than Accepted dies, with the log kept', () async {
    final runner = apple(
      submit: const Ran(0, stdout: '{"id":"sub-1","status":"Invalid"}'),
    );
    await expectLater(
      run(runner),
      dies('notarisation of $out/chord.zip ended Invalid'),
    );
    expect(
      File(p.join(root.path, out, 'notarytool-log.json')).existsSync(),
      isTrue,
    );
  });

  test('a submit that fails dies with what it said', () async {
    await expectLater(
      run(
        apple(
          submit: const Ran(2, stdout: 'oops', stderr: 'no auth\n'),
        ),
      ),
      dies('notarytool submit exited 2: oops no auth'),
    );
  });

  test('the log is asked for three times, 10 s apart, then dies', () async {
    await expectLater(
      run(apple(logFailures: 3)),
      dies('the notarisation log of sub-1 could not be fetched: not yet'),
    );
    expect(slept, [const Duration(seconds: 10), const Duration(seconds: 10)]);
  });

  test('a log fetched on the third try is enough', () async {
    expect(await run(apple(logFailures: 2)), cdhashes);
  });

  test(
    'a binary Apple has no ticket for dies, with what the log lists',
    () async {
      await expectLater(
        run(apple(tickets: ['aaaa1111'])),
        dies(
          "Apple's log has no ticket for ${binaries[1]} (cdhash bbbb2222); it "
          'lists: "cdhash":"aaaa1111"',
        ),
      );
    },
  );

  test(
    'a zip ditto could not make stops before anything is submitted',
    () async {
      final runner = apple(zipped: const Ran(1, stderr: 'disk full\n'));
      await expectLater(
        run(runner),
        dies('ditto could not make $out/chord.zip: disk full'),
      );
      expect(runner.argvs.where((argv) => argv.contains('submit')), isEmpty);
    },
  );

  // Slips of the original, fixed: an earlier run's answers never stand for
  // this one, and a failed command certifies nothing.
  test('an Accepted without a submission id dies, and an old log is not '
      'reused', () async {
    final old = File(p.join(root.path, out, 'notarytool-log.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'ticketContents': [
            for (final cdhash in cdhashes.values) {'cdhash': cdhash},
          ],
        }),
      );
    final runner = apple(submit: const Ran(0, stdout: '{"status":"Accepted"}'));
    await expectLater(
      run(runner),
      dies('notarytool accepted $out/chord.zip without a submission id'),
    );
    expect(old.existsSync(), isFalse);
    expect(runner.argvs.where((argv) => argv.contains('log')), isEmpty);
  });

  test('answers of an earlier run are removed before submitting', () async {
    for (final name in [
      'notarytool.json',
      'notarytool-submit.stderr',
      'notarytool-log.json',
    ]) {
      (File(
        p.join(root.path, out, name),
      )..createSync(recursive: true)).writeAsStringSync('old');
    }
    await expectLater(
      run(apple(zipped: const Ran(1))),
      dies('ditto could not make'),
    );
    expect(Directory(p.join(root.path, out)).listSync(), isEmpty);
  });

  test('a codesign that fails but shows the cdhash dies', () async {
    await expectLater(
      run(apple(codesignStatus: 1)),
      dies('codesign -dvvv ${binaries[0]} failed'),
    );
  });

  group('tester: notarisation fresh-answer boundaries', () {
    test(
      'Accepted from a failed submit cannot certify either binary',
      () async {
        final runner = apple(
          submit: const Ran(null, stdout: '{"id":"sub-1","status":"Accepted"}'),
        );
        await expectLater(
          run(runner),
          dies('notarytool submit exited without a status'),
        );
        expect(runner.argvs.where((a) => a.first == 'codesign'), isEmpty);
        expect(said, isEmpty);
      },
    );

    test(
      'a successful log command that writes no fresh log certifies nothing',
      () async {
        final old = File(p.join(root.path, out, 'notarytool-log.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'ticketContents': [
                for (final hash in cdhashes.values) {'cdhash': hash},
              ],
            }),
          );
        final good = apple();
        final runner = RecordingRunner(
          (argv) => argv.length > 2 && argv[2] == 'log'
              ? const Ran(0)
              : good.answer!(argv),
        );
        await expectLater(run(runner), dies("Apple's log has no ticket"));
        expect(old.existsSync(), isFalse);
        expect(said, isEmpty);
      },
    );
  });
}

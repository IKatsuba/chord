// Tester-owned cleanup and subsecond identity boundaries.
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures/expect_driver.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  final hasExpect =
      (Platform.isMacOS || Platform.isLinux) &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  group('tester CTUI-126: failed starts and identity rejection', () {
    test(
      'repeated failed starts clean separate directories then recover',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'expect-failure-tester-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final paths = <String>{};
        for (var i = 0; i < 2; i++) {
          await expectLater(
            runExpect([
              '-c',
              'exit 0',
            ], workingDirectory: '${dir.path}/missing'),
            throwsA(isA<ProcessException>()),
          );
          final records = lastExpectSpawns!;
          paths.add(records.path);
          expect(records.existsSync(), isFalse);
        }
        expect(paths, hasLength(2));
        expect((await runExpect(['-c', 'exit 9'])).exitCode, 9);
      },
    );

    test(
      'teardown leaves a spawn whose recorded identity is one unit older',
      () async {
        int? owned;
        Directory? records;
        // This runs after runExpect's teardown and always kills only our spawn.
        addTearDown(() async {
          final child = owned;
          try {
            expect(records?.existsSync(), isFalse);
            expect(child, isNotNull);
            expect(
              _alive(child!),
              isTrue,
              reason: 'a different identity must not be killed',
            );
          } finally {
            if (child != null && _alive(child)) await killTree(child);
          }
        });
        await runExpect([
          '-c',
          r'''log_user 0; spawn -noecho sh -c {trap '' HUP; echo up; exec sleep 600}; '''
              r'expect up; exec kill -KILL [pid]',
        ]).timeout(const Duration(seconds: 10));
        records = lastExpectSpawns!;
        final ledger = File('${records.path}/spawned');
        final fields = ledger.readAsStringSync().trim().split(' ');
        owned = int.parse(fields[0]);
        final identity = spawnIdentity(owned);
        expect(identity, isNotNull);
        // On macOS this changes only a microsecond, within the same second.
        expect(spawnedAs(identity!, identity - 1), isFalse);
        ledger.writeAsStringSync('$owned ${identity - 1}\n');
      },
    );
  }, skip: hasExpect ? false : 'macOS or Linux with expect is required');
}

import 'dart:convert';
import 'dart:io';

import 'package:chord/platform/process.dart';
import 'package:test/test.dart';

import '../fixtures/native_smoke_cleanup.dart';

void main() {
  test(
    'an already-exited driver still reaps two TERM-resistant owned groups',
    () async {
      final owned = <GroupProcess>[];
      final driver = await Process.start('sh', ['-c', 'exit 91']);
      expect(await driver.exitCode, 91);
      addTearDown(() async {
        for (final group in owned) {
          group.signal(ProcessSignal.sigkill);
        }
        await Future.wait(owned.map((group) => group.exit));
      });
      for (var i = 0; i < 2; i++) {
        final group = await spawnGroup('sh', [
          '-c',
          'trap "" TERM; echo ready; while :; do sleep 30; done',
        ], cwd: Directory.systemTemp.path);
        owned.add(group);
        await group.started;
        expect(
          await group.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first,
          'ready',
        );
      }
      final ids = owned.map((group) => group.pid).toSet();
      expect(await nativeSmokeGroups(ids), ids);
      await cleanupNativeSmoke(
        driver: driver,
        groupIds: () => ids,
        termBound: const Duration(milliseconds: 50),
      );
      expect(await nativeSmokeGroups(ids), isEmpty);
      expect(
        await driver.exitCode,
        91,
        reason: 'cleanup retains the early driver failure',
      );
      await Future.wait(owned.map((group) => group.exit));
    },
  );
  test('a live driver is reaped even when no native group started', () async {
    final driver = await Process.start('sh', ['-c', 'exec sleep 30']);
    await cleanupNativeSmoke(driver: driver, groupIds: () => const []);
    expect(await driver.exitCode, isNot(0));
    expect(await nativeSmokeGroups({driver.pid}), isEmpty);
  });

  group('tester: native smoke driver escalation', () {
    test(
      'a TERM-resistant live driver is killed and reaped without recorded groups',
      () async {
        final driver = await Process.start('sh', [
          '-c',
          'trap "" TERM; echo ready; exec sleep 30',
        ]);
        addTearDown(() async {
          driver.kill(ProcessSignal.sigkill);
          await driver.exitCode.timeout(const Duration(seconds: 3));
        });
        expect(
          await driver.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first,
          'ready',
        );
        await cleanupNativeSmoke(
          driver: driver,
          groupIds: () => const [],
          termBound: const Duration(milliseconds: 50),
        );
        expect(await driver.exitCode, -ProcessSignal.sigkill.signalNumber);
        final alive = await Process.run('kill', ['-0', '${driver.pid}']);
        expect(alive.exitCode, isNot(0));
      },
    );
  });
}

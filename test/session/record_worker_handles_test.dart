import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<void> checkProof(
  String mode,
  String executable,
  List<String> arguments,
) async {
  final root = await Directory.systemTemp.createTemp('record-handles-test-');
  final tmp = Directory('${root.path}/tmp')..createSync();
  final state = Directory('${root.path}/state')..createSync();
  try {
    final result = await Process.run(
      executable,
      arguments,
      environment: {'TMPDIR': tmp.path, 'XDG_STATE_HOME': state.path},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    final report = jsonDecode(result.stdout.toString()) as Map;
    final retained = Platform.environment['CHORD_RECORD_HANDLE_REPORTS'];
    if (retained != null) {
      await Directory(retained).create(recursive: true);
      await File('$retained/$mode.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
    final operations = report['operations'] as List;
    expect(operations, hasLength(8));
    for (final operation in operations.cast<Map>()) {
      expect(operation['immediatelyAfterFuture'], isEmpty);
      expect(operation['afterRootDeletion'], isEmpty);
      expect(operation['rootRemoved'], isTrue);
      expect(operation['sdkExitJoined'], isTrue);
      expect(operation['closedStreams'], 0);
      expect(operation['closedTasks'], 0);
      expect(operation['pendingFutures'], 0);
    }
    expect(tmp.listSync(), isEmpty);
    expect(state.listSync(), isEmpty);
  } finally {
    await root.delete(recursive: true);
  }
}

void main() {
  // Linux reads its own descriptors from /proc, macOS through lsof.
  final supported =
      Platform.isLinux ||
      Platform.isMacOS && File('/usr/sbin/lsof').existsSync();
  const unsupported = 'Own descriptor proof requires /proc or macOS lsof.';
  test('public record IO immediate owned descriptors under JIT', () async {
    if (!supported) return markTestSkipped(unsupported);
    await checkProof('jit', Platform.resolvedExecutable, [
      'run',
      'tool/record_worker_handles.dart',
    ]);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'public record IO immediate owned descriptors under AOT',
    () async {
      // In the body: the compile tag runs with --run-skipped.
      if (!supported) return markTestSkipped(unsupported);
      final root = await Directory.systemTemp.createTemp('record-handles-aot-');
      try {
        final executable = '${root.path}/proof';
        final build = await Process.run(
          'nice',
          [
            '-n',
            '19',
            Platform.resolvedExecutable,
            'compile',
            'exe',
            'tool/record_worker_handles.dart',
            '-o',
            executable,
          ],
          environment: {
            'TMPDIR': root.path,
            'XDG_STATE_HOME': '${root.path}/state',
          },
        );
        expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
        await checkProof('aot', executable, []);
      } finally {
        await root.delete(recursive: true);
      }
    },
    tags: ['compile'],
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

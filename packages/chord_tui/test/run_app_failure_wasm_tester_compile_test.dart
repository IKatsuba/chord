@Tags(['compile'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'run_app_failure_tester_test.dart' show expectedOutput;

void main() {
  group('tester: Wasm failure propagation', () {
    test(
      'cleanup finishes and the first error keeps its identity and stack',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'run-app-failure-wasm-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final build = await Process.start(Platform.resolvedExecutable, [
          'compile',
          'wasm',
          'test/fixtures/run_app_failure_tester.dart',
          '-o',
          '${dir.path}/failure.wasm',
        ]);
        final output = build.stdout.transform(systemEncoding.decoder).join();
        final errors = build.stderr.transform(systemEncoding.decoder).join();
        addTearDown(() => build.kill(ProcessSignal.sigkill));
        expect(
          await build.exitCode.timeout(const Duration(minutes: 2)),
          0,
          reason: '${await output}${await errors}',
        );
        final node = await Process.start('node', [
          'test/fixtures/run_app_wasm.mjs',
          '${dir.path}/failure.mjs',
          '${dir.path}/failure.wasm',
        ]);
        final out = node.stdout.transform(systemEncoding.decoder).join();
        final err = node.stderr.transform(systemEncoding.decoder).join();
        addTearDown(() => node.kill(ProcessSignal.sigkill));
        expect(
          await node.exitCode.timeout(const Duration(seconds: 20)),
          0,
          reason: await err,
        );
        expect(await out, expectedOutput('propagated'));
        expect(await err, contains('Bad state: tester secondary'));
      },
      skip: _hasNode() ? false : 'needs node on PATH',
    );
  });
}

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

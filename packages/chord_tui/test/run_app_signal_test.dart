// CTUI-127: runApp re-raises a terminating signal and waits for it to land
// before its fallback exit, which once raced the signal and often won.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  Future<int> terminate(String how) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'test/fixtures/run_app_signal.dart',
      how,
    ]);
    final err = process.stderr.transform(systemEncoding.decoder).join();
    // A run that never ends is the failure, and must not outlive it.
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    await process.stdout
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .firstWhere((line) => line == 'ready');
    process.kill(ProcessSignal.sigterm);
    final code = await process.exitCode.timeout(const Duration(seconds: 20));
    expect(await err, isEmpty);
    return code;
  }

  final skip = Platform.isWindows ? 'POSIX signals are required' : false;

  test('handling signals, a terminated app dies by SIGTERM', () async {
    expect(await terminate('self'), -ProcessSignal.sigterm.signalNumber);
  }, skip: skip);

  // Deterministic where the race is not: without the grace, runApp exits
  // before any other listener can see the re-raised signal.
  test(
    'another listener ending the process by the re-raised signal is waited for',
    () async {
      expect(await terminate('owner'), -ProcessSignal.sigterm.signalNumber);
    },
    skip: skip,
  );

  test(
    'a re-raised signal nobody ends the process by still exits 143',
    () async {
      expect(
        await terminate('ignored'),
        128 + ProcessSignal.sigterm.signalNumber,
      );
    },
    skip: skip,
  );
}

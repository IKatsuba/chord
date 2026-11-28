import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('tester: native embedded failure contract', () {
    test('cleanup and hook failures are reported without escaping', () async {
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        'test/fixtures/run_app_failure_tester.dart',
      ]);
      final out = process.stdout.transform(systemEncoding.decoder).join();
      final err = process.stderr.transform(systemEncoding.decoder).join();
      addTearDown(() => process.kill(ProcessSignal.sigkill));
      expect(
        await process.exitCode.timeout(const Duration(seconds: 30)),
        0,
        reason: await err,
      );
      expect(await out, expectedOutput('returned'));
      expect(await err, contains('Bad state: tester secondary'));
    });
  });
}

String expectedOutput(String outcome) => [
  'writes',
  'leaves',
  'hook',
  'enters and hook',
].map((how) => '$how: cleaned, $outcome\n').join();

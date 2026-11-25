// Tester-owned coverage of every supported signal and cleanup ordering.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('tester: re-raised signals follow asynchronous cleanup', () {
    for (final entry in {
      'hup': ProcessSignal.sighup,
      'int': ProcessSignal.sigint,
      'term': ProcessSignal.sigterm,
    }.entries) {
      for (final mode in ['owner', 'ignored']) {
        test('${entry.key} with $mode listener', () async {
          final process = await Process.start(Platform.resolvedExecutable, [
            'run',
            'test/fixtures/run_app_signal_tester.dart',
            entry.key,
            mode,
          ]);
          var ended = false;
          addTearDown(() async {
            if (!ended) {
              process.kill(ProcessSignal.sigkill);
              await process.exitCode;
            }
          });
          final lines = <String>[];
          final ready = Completer<void>();
          final outputDone = Completer<void>();
          process.stdout
              .transform(systemEncoding.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                lines.add(line);
                if (line == 'ready' && !ready.isCompleted) ready.complete();
              }, onDone: outputDone.complete);
          final errors = process.stderr
              .transform(systemEncoding.decoder)
              .join();
          await ready.future.timeout(const Duration(seconds: 20));
          expect(process.kill(entry.value), isTrue);
          final code = await process.exitCode.timeout(
            const Duration(seconds: 20),
          );
          ended = true;
          await outputDone.future;
          expect(await errors, isEmpty);
          expect(
            code,
            mode == 'owner'
                ? -entry.value.signalNumber
                : 128 + entry.value.signalNumber,
          );
          expect(lines, [
            'ready',
            'left',
            'cleanup started',
            'cleanup ended',
            'reraised after cleanup',
          ]);
        });
      }
    }
  }, skip: Platform.isWindows ? 'POSIX signals are required' : false);
}

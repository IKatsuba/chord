@Tags(['compile'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: platform under Wasm', () {
    test(
      'native operations refuse at runtime and errors retain numbers',
      () async {
        final dir = Directory.systemTemp.createTempSync('chord-platform-wasm-');
        addTearDown(() => dir.deleteSync(recursive: true));

        Future<String> run(String executable, List<String> args) async {
          final process = await Process.start(executable, args);
          addTearDown(() => process.kill(ProcessSignal.sigkill));
          final output = process.stdout
              .transform(systemEncoding.decoder)
              .join();
          final errors = process.stderr
              .transform(systemEncoding.decoder)
              .join();
          final code = await process.exitCode.timeout(
            const Duration(minutes: 2),
          );
          expect(code, 0, reason: '${await output}${await errors}');
          expect(await errors, isEmpty);
          return output;
        }

        await run(Platform.resolvedExecutable, [
          'compile',
          'wasm',
          'test/fixtures/platform_web_tester.dart',
          '-o',
          '${dir.path}/platform.wasm',
        ]);
        expect(
          await run('node', [
            'packages/chord_tui/test/fixtures/run_app_wasm.mjs',
            '${dir.path}/platform.mjs',
            '${dir.path}/platform.wasm',
          ]),
          'web platform refusals passed\n',
        );
      },
    );
  });
}

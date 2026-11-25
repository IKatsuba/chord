@Tags(['compile'])
// Covers setUpAll's build, which takes no timeout of its own.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';

// CTUI-114: runApp awaits its guarded body from outside that body's error
// zone, so a body that threw never resumed it and the process stayed alive,
// the terminal raw, beforeExit never run. The run_app_exit fixture, built
// with dart compile exe, must leave by beforeExit and exit 1 instead.
void main() {
  late Directory dir;
  late String exe;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('chorded_run_app_exit');
    exe = '${dir.path}/run_app_exit';
    final build = await Process.start('dart', [
      'compile',
      'exe',
      'test/fixtures/run_app_exit.dart',
      '-o',
      exe,
    ]);
    final output = build.stdout.transform(systemEncoding.decoder).join();
    final errors = build.stderr.transform(systemEncoding.decoder).join();
    // The build settles here whatever happens, and no compiler outlives it.
    final code = await build.exitCode.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        build.kill(ProcessSignal.sigkill);
        return build.exitCode;
      },
    );
    expect(code, 0, reason: '${await output}${await errors}');
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  for (final (how, said) in [
    ('enters', 'Bad state: enter failed'),
    ('writes', 'Bad state: write failed'),
  ]) {
    test(
      'the compiled app leaves and exits 1 when its body fails: $how',
      () async {
        final process = await Process.start(exe, [how]);
        final out = process.stdout.transform(systemEncoding.decoder).join();
        final err = process.stderr.transform(systemEncoding.decoder).join();
        // A run that never exits is the failure, and must not outlive it.
        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        expect(exitCode, 1);
        expect(await out, endsWith('left\nclosed\n'));
        expect(await err, startsWith(said));
      },
    );
  }
}

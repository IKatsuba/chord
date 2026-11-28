@Tags(['compile'])
// Covers setUpAll's builds, which take no timeout of their own.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';

// CHD-638: the framework compiles to Wasm, so a new dart:ffi or other
// native-only import fails here; and under Wasm runApp leaves without
// stderr or exit: a clean quit returns, a failure goes to the console and
// fails runApp's future.
void main() {
  late Directory dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('chorded_run_app_wasm');
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  Future<void> build(String source, String name) async {
    final build = await Process.start('dart', [
      'compile',
      'wasm',
      source,
      '-o',
      '${dir.path}/$name.wasm',
    ]);
    final output = build.stdout.transform(systemEncoding.decoder).join();
    final errors = build.stderr.transform(systemEncoding.decoder).join();
    // The build settles here whatever happens, and no compiler outlives it.
    final code = await build.exitCode.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        build.kill(ProcessSignal.sigkill);
        return build.exitCode;
      },
    );
    expect(code, 0, reason: '${await output}${await errors}');
  }

  test('the package example compiles to Wasm', () async {
    await build('example/main.dart', 'main');
  });

  test('under Wasm a clean quit returns and a failure fails runApp', () async {
    await build('test/fixtures/run_app_wasm.dart', 'run_app_wasm');
    final node = await Process.start('node', [
      'test/fixtures/run_app_wasm.mjs',
      '${dir.path}/run_app_wasm.mjs',
      '${dir.path}/run_app_wasm.wasm',
    ]);
    final out = node.stdout.transform(systemEncoding.decoder).join();
    final err = node.stderr.transform(systemEncoding.decoder).join();
    final code = await node.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        node.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    expect(code, 0, reason: await err);
    expect(await out, 'ok returned\nenters failed: Bad state: enter failed\n');
    // console.error, where runApp says what failed.
    expect(await err, startsWith('Bad state: enter failed\n'));
  }, skip: _hasNode() ? false : 'needs node on PATH');
}

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

@Tags(['compile'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

// The site runs chord's own screens compiled to Wasm, and dart2wasm has no
// dart:ffi: a library on the window's path that imports it unconditionally
// stops this build.
void main() {
  test(
    'chord\'s window, screens and platform libraries build for Wasm',
    () async {
      final entry = Isolate.resolvePackageUriSync(
        Uri.parse('package:chord/platform/process.dart'),
      )!.resolve('../../test/fixtures/wasm_entry.dart').toFilePath();
      final dir = Directory.systemTemp.createTempSync('chord-wasm-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final build = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'wasm',
        entry,
        '-o',
        '${dir.path}/main.wasm',
      ]);
      expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
      expect(File('${dir.path}/main.wasm').lengthSync(), greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

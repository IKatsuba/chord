@Tags(['compile'])
library;

import 'dart:io';

import 'package:test/test.dart';

// The live fixtures run in the page, so they must build for Wasm: chord's
// UI and dart:ffi split (P1) included, nothing that needs dart:io at build.
void main() {
  test('the live chord fixtures build for Wasm', () async {
    final dir = Directory.systemTemp.createTempSync('chord-site-live-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final build = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'wasm',
      'test/fixtures/live_entry.dart',
      '-o',
      '${dir.path}/live.wasm',
    ]);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
    expect(File('${dir.path}/live.wasm').lengthSync(), greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

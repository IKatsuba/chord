import 'dart:io';

import 'package:chord_tui/src/terminal/process_io.dart';
import 'package:test/test.dart';

// CHD-638: runApp reports failures and exits only through this seam, so
// that the web can swap it; on native it says them on stderr and exits.
void main() {
  test('the native seam has a process and its environment', () {
    expect(hostHasProcess, isTrue);
    expect(hostEnvironment, same(Platform.environment));
  });

  test('the native seam says failures on stderr and exits by code', () async {
    final run = await Process.run(Platform.resolvedExecutable, [
      'run',
      'test/fixtures/process_io.dart',
      'first',
      'second',
    ]);
    expect(run.exitCode, 3);
    expect(run.stderr, 'first\nsecond\n');
    expect(run.stdout, isEmpty);
  });
}

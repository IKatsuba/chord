import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> release(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'tool/release.dart', ...args],
);

void main() {
  test('the help is printed, exit 0', () async {
    final ran = await release(['--help']);
    expect(ran.exitCode, 0);
    expect(ran.stdout, startsWith('Usage: dart run tool/release.dart'));
  });

  test('a bare release releases nothing and says so, exit 1', () async {
    final ran = await release([]);
    expect(ran.exitCode, 1);
    expect(
      ran.stderr,
      'release: not clear which package to release: dart run '
      'tool/release.dart <package> (chord)\n',
    );
  });

  test('a refused option prints the help and the error, exit 2', () async {
    final ran = await release(['chord', '--skip', 'natives']);
    expect(ran.exitCode, 2);
    expect(ran.stdout, startsWith('Usage: '));
    expect(
      ran.stderr,
      startsWith('\n  error: Option "--skip" must be of type "stage"'),
    );
  });
}

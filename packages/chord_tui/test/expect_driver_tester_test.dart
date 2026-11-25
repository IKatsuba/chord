// Tester-owned bounded-drain edge cases; all children exit on their own.
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures/expect_driver.dart';

void main() {
  final hasExpect =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  group('tester CTUI-125: output after driver exit', () {
    test(
      'drains delayed stdout and stderr without losing exit status',
      () async {
        final result = await runExpect([
          '-c',
          r'exec sh -c {sleep 0.2; printf late-out; printf late-err >&2} '
              r'>@ stdout 2>@ stderr &; '
              r'puts -nonewline stdout early-out; flush stdout; '
              r'puts -nonewline stderr early-err; flush stderr; exit 7',
        ]).timeout(const Duration(seconds: 10));
        expect(result.exitCode, 7);
        expect(result.stdout, 'early-outlate-out');
        expect(result.stderr, 'early-errlate-err');
      },
    );

    test('malformed stderr is reported after the bounded drain', () async {
      await expectLater(
        runExpect([
          '-c',
          'fconfigure stderr -translation binary; '
              'puts -nonewline stderr [binary format c2 {-1 -2}]; '
              'flush stderr; exit 3',
        ]).timeout(const Duration(seconds: 10)),
        throwsA(isA<FormatException>()),
      );
    });
  }, skip: hasExpect ? false : 'POSIX and expect are required');
}

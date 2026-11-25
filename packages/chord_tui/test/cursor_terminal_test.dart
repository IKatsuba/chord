import 'dart:io';

import 'package:test/test.dart';
import 'fixtures/expect_driver.dart';

void main() {
  final hasExpect =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  test(
    'cursor resets on suspend release repeat ownership and cleanup failure',
    () async {
      final result = await runExpect([
        '-c',
        '''
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/cursor_terminal.dart
expect eof
catch wait result
exit [lindex \$result 3]
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('CURSOR_LIFECYCLE_PASS'));
    },
    skip: hasExpect ? false : 'POSIX and expect are required',
  );
}

import 'dart:io';

import 'package:test/test.dart';
import 'fixtures/expect_driver.dart';

// A terminal that has gone away never takes the output written to it; giving
// it back must not wait for that forever (CTUI-64).
void main() {
  final hasPty =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  for (final scenario in [
    'leave_hang',
    'leave_error',
    'suspend_hang',
    'suspend_error',
  ]) {
    test('StdioTerminal flush: $scenario', () async {
      final result = await runExpect([
        '-c',
        '''
set timeout 20
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_flush.dart $scenario
expect eof
catch wait result
exit [lindex \$result 3]
''',
      ]);
      final output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(output, contains('FLUSH_PASS=$scenario'));
    }, skip: hasPty ? false : 'POSIX and expect are required');
  }
}

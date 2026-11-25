import 'dart:io';

import 'package:test/test.dart';

import 'fixtures/expect_driver.dart';

void main() {
  final hasPty =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  group('tester: bounded flush completion and reuse', () {
    for (final (columns, rows) in [(120, 40), (80, 24)]) {
      for (final scenario in [
        'default_deadline',
        'late_error',
        'late_success',
      ]) {
        test('$scenario at ${columns}x$rows', () async {
          final run = await runExpect([
            '-c',
            '''
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_flush_tester.dart $scenario
stty rows $rows columns $columns < \$spawn_out(slave,name)
expect {
  eof {}
  timeout {close; catch wait; exit 10}
}
catch wait result
exit [lindex \$result 3]
''',
          ]);
          final output = '${run.stdout}${run.stderr}';
          expect(run.exitCode, 0, reason: output);
          expect(output, contains('TESTER_FLUSH_PASS=$scenario'));
        }, skip: hasPty ? false : 'POSIX and expect are required');
      }
    }
  });
}

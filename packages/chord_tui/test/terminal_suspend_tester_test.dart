import 'dart:io';

import 'package:test/test.dart';

import 'fixtures/expect_driver.dart';

void main() {
  final available =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  group('tester: suspension reuse and failed-child close race', () {
    for (final scenario in ['repeat', 'close_after_failure']) {
      test(scenario, () async {
        final result = await runExpect([
          '-c',
          '''
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_suspend_tester.dart $scenario
expect eof
catch wait result
exit [lindex \$result 3]
''',
        ]);
        final output = '${result.stdout}${result.stderr}';
        expect(result.exitCode, 0, reason: output);
        expect(output, contains('TESTER_SUSPEND_PASS=$scenario'));
      }, skip: available ? false : 'POSIX and expect are required');
    }
  });
}

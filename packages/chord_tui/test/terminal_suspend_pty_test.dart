import 'dart:io';

import 'package:test/test.dart';
import 'fixtures/expect_driver.dart';

void main() {
  final hasPty =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  test(
    'paused stdin gives the child its input without replay after resume',
    () async {
      final dir = Directory.systemTemp.createTempSync('stdin-probe-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final driver = File('${dir.path}/drive.exp')
        ..writeAsStringSync('''
set timeout 12
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/editor_stdin_probe.dart
expect {
  "APP_READY" {}
  timeout {exit 10}
  eof {exit 11}
}
send "app-before\\r"
expect {
  "CHILD_READY" {}
  timeout {exit 12}
  eof {exit 13}
}
send "child-only\\r"
expect {
  "APP_RESUMED" {}
  timeout {exit 14}
  eof {exit 15}
}
send "app-after\\r"
expect eof
catch wait result
exit [lindex \$result 3]
''');
      final result = await runExpect([driver.path]);
      final output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(output, contains('CHILD_GOT=child-only'));
      expect(output, contains('NO_REPLAY=true'));
      expect(output, contains('APP_INPUT=true'));
    },
    skip: hasPty ? false : 'POSIX and expect are required',
  );
  for (final scenario in [
    'normal',
    'actual_editor',
    'editor_fallback',
    'vi_fallback',
    'explicit',
    'launch_failure',
    'callback_failure',
    'overlap',
    'leave',
    'leave_race',
    'close',
    'restore_failure',
    'release_failure',
  ]) {
    test('StdioTerminal suspension: $scenario', () async {
      final result = await runExpect([
        '-c',
        '''
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_suspend.dart $scenario
expect eof
catch wait result
exit [lindex \$result 3]
''',
      ]);
      final output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(output, contains('SUSPEND_PASS=$scenario'));
    }, skip: hasPty ? false : 'POSIX and expect are required');
  }
}

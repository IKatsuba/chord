import 'dart:io';

import 'package:test/test.dart';
import 'fixtures/expect_driver.dart';

void main() {
  final hasExpect =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  final hasPty =
      hasExpect &&
      Process.runSync('expect', [
            '-c',
            'spawn -noecho sh -c exit; expect eof; wait',
          ]).exitCode ==
          0;
  for (final pending in [false, if (Platform.isMacOS) true]) {
    test(
      'restores exact termios and retains queued input, PENDIN: $pending',
      () async {
        final dir = Directory.systemTemp.createTempSync('terminal-restore-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final queued = '${dir.path}/queued';
        final script = File('${dir.path}/drive.exp')
          ..writeAsStringSync('''
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_restore.dart $queued ${pending ? 'pending' : 'clear'}
expect {
  "READY" {}
  timeout { exit 10 }
  eof { exit 11 }
}
send "kept\\n"
set marker [open "$queued" w]
close \$marker
expect eof
catch wait result
exit [lindex \$result 3]
''');
        final result = await runExpect([script.path]);
        final output = '${result.stdout}${result.stderr}';
        expect(result.exitCode, 0, reason: output);
        expect(output, contains('EXACT=true'));
        expect(output, contains('KEPT=true'));
      },
      skip: hasPty ? false : 'A usable POSIX pty and expect are required',
    );
  }

  group('tester: empty input and terminal reuse', () {
    for (final canonical in [true, false]) {
      for (final (columns, rows) in [(120, 40), (80, 24)]) {
        test(
          'restores twice without input, canonical: $canonical, ${columns}x$rows',
          () async {
            final result = await runExpect([
              '-c',
              """
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_restore_tester.dart ${canonical ? 'canonical' : 'raw'} $rows $columns
expect eof
catch wait result
exit [lindex \$result 3]
""",
            ]);
            final output = '${result.stdout}${result.stderr}';
            expect(result.exitCode, 0, reason: output);
            expect(output, contains('EXACT_TWICE=true'));
          },
          skip: Platform.isMacOS && hasPty
              ? false
              : 'The macOS restoration path requires a usable pty and expect',
        );
      }
    }
  });
}

import 'dart:io';

import 'package:test/test.dart';
import 'fixtures/expect_driver.dart';

void main() {
  final hasPty =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  for (final (columns, rows) in [(120, 40), (80, 24)]) {
    for (final failed in [false, true]) {
      test(
        'scripted service editor success=${!failed} at ${columns}x$rows cleans its file',
        () async {
          final dir = Directory.systemTemp.createTempSync('service-demo-pty-');
          addTearDown(() => dir.deleteSync(recursive: true));
          final temporary = Directory('${dir.path}/owned')..createSync();
          final driver = File('${dir.path}/drive.exp')
            ..writeAsStringSync('''
set timeout 15
spawn -noecho sh -c {stty rows $rows columns $columns; exec "\$CTUI_DART" run example/terminal_services.dart --scripted-editor ${failed ? '--editor-fails' : ''}}
expect {
  "Editor: ready" {}
  timeout {exit 10}
  eof {exit 11}
}
send "\\007"
expect {
  "SCRIPTED EDITOR OWNS TERMINAL" {}
  timeout {exit 12}
  eof {exit 13}
}
set owned [glob -nocomplain -directory \$env(TMPDIR) terminal-services-*]
if {[llength \$owned] != 1} {exit 20}
if {![file exists [file join [lindex \$owned 0] sample.md]]} {exit 21}
# An acquired app screen here would overwrite the scripted editor.
expect -timeout 1 {
  "\\033\\[?1049h" {exit 14}
  timeout {}
  eof {exit 15}
}
send "\\r"
expect {
  "Editor: exited ${failed ? 7 : 0}" {}
  timeout {exit 16}
  eof {exit 17}
}
expect {
  "${failed ? 'Second sample line' : 'Edited by scripted child'}" {}
  timeout {exit 18}
  eof {exit 19}
}
send "\\021"
expect eof
catch wait result
exit [lindex \$result 3]
''');
          final result = await runExpect(
            [driver.path],
            environment: {
              'CTUI_DART': Platform.resolvedExecutable,
              'TMPDIR': temporary.path,
            },
          );
          final output = '${result.stdout}${result.stderr}';
          expect(result.exitCode, 0, reason: output);
          final childAt = output.indexOf('SCRIPTED EDITOR OWNS TERMINAL');
          for (final mode in [1000, 1006]) {
            final enabled =
                '\x1b[?$mode'
                'h';
            final disabled =
                '\x1b[?$mode'
                'l';
            expect(
              RegExp(RegExp.escape(enabled)).allMatches(output),
              hasLength(2),
            );
            expect(
              RegExp(RegExp.escape(disabled)).allMatches(output),
              hasLength(2),
            );
            expect(output.indexOf(disabled), lessThan(childAt));
            expect(output.lastIndexOf(enabled), greaterThan(childAt));
          }
          expect(
            temporary.listSync(),
            isEmpty,
            reason: 'Demo-owned file and directory must be removed',
          );
        },
        skip: hasPty ? false : 'POSIX and expect are required',
      );
    }
  }
}

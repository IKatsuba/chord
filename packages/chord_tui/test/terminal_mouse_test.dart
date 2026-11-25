import 'dart:io';

import 'package:test/test.dart';
import 'fixtures/expect_driver.dart';

/// What the fixture's terminal wrote, taken and given back with the mouse
/// [on] or not. The fixture runs in a pty `expect` owns, so the terminal it
/// sets raw and restores is that one, never the one the tests run from.
Future<String> written(bool on) async {
  final dir = await Directory.systemTemp.createTemp('terminal-mouse-');
  addTearDown(() => dir.delete(recursive: true));
  final out = '${dir.path}/written';
  final tty = '${dir.path}/tty';
  final result = await runExpect([
    '-c',
    '''
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_mouse.dart ${on ? 'on' : 'off'} $out $tty
expect eof
catch wait result
exit [lindex \$result 3]
''',
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  // The fixture's controlling terminal was the pty, not ours.
  final ours = Process.runSync('sh', ['-c', 'tty']).stdout.toString().trim();
  final theirs = File(tty).readAsStringSync().trim();
  expect(theirs, startsWith('/dev/'));
  expect(theirs, isNot(ours));
  return File(out).readAsString();
}

void main() {
  final hasPty =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0 &&
      Process.runSync('expect', [
            '-c',
            'spawn -noecho sh -c exit; expect eof; wait',
          ]).exitCode ==
          0;
  final skip = hasPty ? false : 'A usable POSIX pty and expect are required';

  test('a terminal takes the mouse by default and gives it back', () async {
    final out = await written(true);
    for (final mode in ['1000', '1002', '1006']) {
      expect(out, contains('\x1b[?${mode}h'));
      expect(out, contains('\x1b[?${mode}l'));
    }
  }, skip: skip);

  test('without the mouse the terminal keeps it: no reports asked', () async {
    final out = await written(false);
    expect(out, contains('\x1b[?1049h'));
    for (final mode in ['1000', '1002', '1006']) {
      expect(out, isNot(contains('\x1b[?${mode}h')));
      expect(out, isNot(contains('\x1b[?${mode}l')));
    }
  }, skip: skip);
}

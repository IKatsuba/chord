import 'dart:io';

import 'package:test/test.dart';
import 'fixtures/expect_driver.dart';

void main() {
  final usable =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0 &&
      Process.runSync('expect', [
            '-c',
            'spawn -noecho sh -c exit; expect eof; wait',
          ]).exitCode ==
          0;
  group(
    'tester: mouse mode ownership lifecycle',
    skip: usable ? false : 'A usable POSIX pty and expect are required',
    () {
      for (final mouse in [true, false]) {
        test(
          'suspension and repeated ownership restore mouse=$mouse and tty modes',
          () async {
            final root = await Directory.systemTemp.createTemp(
              'mouse-lifecycle-',
            );
            addTearDown(() => root.delete(recursive: true));
            final out = '${root.path}/output', modes = '${root.path}/modes';
            final result = await runExpect([
              '-c',
              '''
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_mouse_lifecycle.dart ${mouse ? 'on' : 'off'} $out $modes
expect eof
catch wait result
exit [lindex \$result 3]
''',
            ]);
            expect(
              result.exitCode,
              0,
              reason: '${result.stdout}${result.stderr}',
            );
            final bytes = await File(out).readAsString();
            for (final mode in ['1000', '1002', '1006']) {
              for (final suffix in ['h', 'l']) {
                expect(
                  RegExp(RegExp.escape('\x1b[?$mode$suffix')).allMatches(bytes),
                  hasLength(mouse ? 3 : 0),
                );
              }
            }
            for (final suffix in ['h', 'l']) {
              expect(
                RegExp(RegExp.escape('\x1b[?1049$suffix')).allMatches(bytes),
                hasLength(3),
              );
              expect(
                RegExp(RegExp.escape('\x1b[?2004$suffix')).allMatches(bytes),
                hasLength(3),
              );
            }
            final states = await File(modes).readAsLines();
            expect(states.first, isNotEmpty);
            expect(states.last, states.first);
          },
        );
      }
    },
  );
}

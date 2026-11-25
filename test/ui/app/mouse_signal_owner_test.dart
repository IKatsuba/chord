import 'dart:io';
import 'package:test/test.dart';

import '../../fixtures/fake.dart';

void main() {
  final hasPty =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  // Each case started the fixture with `dart run`, compiling the app
  // again, which under load outlasted expect's 15 s wait for its first
  // line; it is compiled once, and kept, instead, in setUpAll, which is
  // bounded by the test runner's own setUpAll limit, not by a case's.
  group('the fixture', () {
    late List<String> fixture;
    setUpAll(() {
      if (hasPty) {
        fixture = fixtureCommand('test/fixtures/mouse_signal_owner.dart');
      }
    });
    for (final scenario in ['startup', 'window', 'suspended']) {
      for (final signal in ['HUP', 'INT', 'TERM']) {
        test(
          'port sole signal owner restores $scenario and dies by $signal',
          () async {
            final result = await Process.run(
              'expect',
              [
                '-c',
                '''
set timeout 15
spawn -noecho \$env(CTUI_DART) \$env(CTUI_FIXTURE) $scenario
expect -re {OWNED_PID=([0-9]+)}
set owned \$expect_out(1,string)
expect "${scenario == 'startup' ? 'Select agent' : '? for shortcuts'}"
${scenario == 'suspended' ? '''send "\\007"
expect "PORT_CHILD_READY"
''' : ''}
exec kill -$signal [exp_pid]
expect "OWNER_LEAVING"
${scenario == 'suspended' ? '''expect -timeout 1 {
  "OWNER_EXACT" {exit 20}
  "\\033\\[?1000h" {exit 21}
  timeout {}
  eof {exit 22}
}
send "child-only\\r"
expect "PORT_CHILD_GOT=child-only"
''' : ''}
expect "OWNER_EXACT=true"
expect eof
catch wait result
puts "WAIT_SIGNAL=[lindex \$result 5]"
if {[lindex \$result 5] ne "SIG$signal"} {exit 23}
if {![catch {exec kill -0 \$owned}]} {
  catch {exec kill -KILL -- -\$owned}
  exit 24
}
exit 0
''',
              ],
              environment: {
                'CTUI_DART': fixture.first,
                'CTUI_FIXTURE': fixture.last,
              },
            );
            final output = '${result.stdout}${result.stderr}';
            expect(result.exitCode, 0, reason: output);
            expect(output, contains('OWNED_CLOSED'));
            for (final mode in [1000, 1006]) {
              expect(
                RegExp(
                  RegExp.escape(
                    '\x1b[?$mode'
                    'h',
                  ),
                ).allMatches(output),
                hasLength(1),
              );
              expect(
                RegExp(
                  RegExp.escape(
                    '\x1b[?$mode'
                    'l',
                  ),
                ).allMatches(output),
                hasLength(1),
              );
            }
          },
          skip: hasPty ? false : 'POSIX and expect are required',
        );
      }
    }
  });
}

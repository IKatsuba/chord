import 'dart:io';
import 'package:test/test.dart';
import 'fixtures/expect_driver.dart';

void main() {
  final hasPty =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  for (final scenario in [
    'normal',
    'callback_failure',
    'restore_failure',
    'restore_1002_failure',
    'release_failure',
    'release_1002_failure',
    'leave_suspended',
    'close_suspended',
    'startup_1000',
    'startup_1002',
    'startup_1006',
  ]) {
    test('mouse modes balance with exact termios: $scenario', () async {
      final result = await runExpect(
        [
          '-c',
          '''
set timeout 15
spawn -noecho \$env(CTUI_DART) run test/fixtures/mouse_modes.dart $scenario
expect eof
catch wait result
exit [lindex \$result 3]
''',
        ],
        environment: {'CTUI_DART': Platform.resolvedExecutable},
      );
      final output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(output, contains('MOUSE_MODE_PASS=$scenario'));
    }, skip: hasPty ? false : 'POSIX and expect are required');
  }
  for (final (signal, scenario) in [
    ('HUP', 'active'),
    ('INT', 'active'),
    ('TERM', 'active'),
    ('TERM', 'repeat'),
    ('TERM', 'after_return'),
  ]) {
    test('signal $signal restores modes and re-raises, $scenario', () async {
      final dir = Directory.systemTemp.createTempSync('mouse-signal-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final driver = File('${dir.path}/drive.exp')
        ..writeAsStringSync('''
set timeout 15
spawn -noecho \$env(CTUI_DART) run test/fixtures/mouse_signals.dart $scenario
expect {
  "MOUSE_READY" {}
  timeout {exit 10}
  eof {exit 11}
}
${scenario == 'after_return' ? '''send "\\021"
expect "RETURNED"
exec kill -$signal [exp_pid]
''' : '''exec kill -$signal [exp_pid]
${scenario == 'repeat' ? '''expect "CLEANUP_START"
exec kill -HUP [exp_pid]
''' : ''}'''}
expect eof
catch wait result
puts "WAIT_SIGNAL=[lindex \$result 5]"
if {[lindex \$result 5] ne "SIG$signal"} {exit 12}
exit 0
''');
      final result = await runExpect(
        [driver.path],
        environment: {'CTUI_DART': Platform.resolvedExecutable},
      );
      final output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, 0, reason: output);
      expect(output, contains('EXACT=true'));
      expect(output, contains('CLEANUP_DONE'));
      for (final mode in [1000, 1002, 1006]) {
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
    }, skip: hasPty ? false : 'POSIX and expect are required');
  }
  test('raw Ctrl+C stays a key and performs normal cleanup', () async {
    final result = await runExpect(
      [
        '-c',
        '''
set timeout 15
spawn -noecho \$env(CTUI_DART) run test/fixtures/mouse_signals.dart active
expect "MOUSE_READY"
send "\\003"
expect eof
catch wait result
exit [lindex \$result 3]
''',
      ],
      environment: {'CTUI_DART': Platform.resolvedExecutable},
    );
    final output = '${result.stdout}${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('CLEANUP_DONE'));
    expect(output, contains('RETURNED'));
  }, skip: hasPty ? false : 'POSIX and expect are required');
  test(
    'termination during scripted editor leaves mouse off and cleans caller file',
    () async {
      final dir = Directory.systemTemp.createTempSync('mouse-editor-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final temporary = Directory('${dir.path}/owned')..createSync();
      final driver = File('${dir.path}/drive.exp')
        ..writeAsStringSync('''
set timeout 15
spawn -noecho \$env(CTUI_DART) run example/terminal_services.dart --scripted-editor
expect "Editor: ready"
send "\\007"
expect "SCRIPTED EDITOR OWNS TERMINAL"
set owned [glob -nocomplain -directory \$env(TMPDIR) terminal-services-*]
if {[llength \$owned] != 1} {exit 20}
exec kill -TERM [exp_pid]
send "\\r"
expect eof
catch wait result
puts "WAIT_SIGNAL=[lindex \$result 5]"
if {[lindex \$result 5] ne "SIGTERM"} {exit 21}
exit 0
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
      expect(temporary.listSync(), isEmpty);
      for (final mode in [1000, 1002, 1006]) {
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

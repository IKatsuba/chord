@Tags(['compile'])
// Covers setUpAll's build, which takes no timeout of its own.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';
import 'fixtures/expect_driver.dart';

// A compiled binary can fail where `dart run` works: the renderer once
// miscompiled under dart compile exe and crashed on the first frame
// (CTUI-38). This builds the demo and drives it in a pty with expect.
void main() {
  final hasExpect =
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;
  late Directory dir;
  late String exe;

  setUpAll(() async {
    if (!hasExpect) return;
    dir = Directory.systemTemp.createTempSync('chorded_smoke');
    exe = '${dir.path}/demo';
    final build = await Process.start('dart', [
      'compile',
      'exe',
      'example/demo.dart',
      '-o',
      exe,
    ]);
    final output = build.stdout.transform(systemEncoding.decoder).join();
    final errors = build.stderr.transform(systemEncoding.decoder).join();
    // The build settles here whatever happens, and no compiler outlives it.
    final code = await build.exitCode.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        build.kill(ProcessSignal.sigkill);
        return build.exitCode;
      },
    );
    expect(code, 0, reason: '${await output}${await errors}');
  });
  tearDownAll(() {
    if (hasExpect) dir.deleteSync(recursive: true);
  });

  test(
    'the compiled demo opens, draws, takes keys and quits',
    () async {
      final script = File('${dir.path}/drive.exp')
        ..writeAsStringSync('''
set timeout 20
spawn -noecho $exe
stty rows 12 columns 60 < \$spawn_out(slave,name)
expect "Toggle"
send "hi\\r"
expect "1 "
send "\\x11"
expect eof
catch wait result
exit [lindex \$result 3]
''');
      final run = await runExpect([script.path]);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      expect('${run.stdout}', contains('\x1b[?1049l'));
    },
    skip: hasExpect ? false : 'expect is not installed',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // A closed window hangs the pty up: the demo must not live on orphaned,
  // waiting to flush output nobody reads (CTUI-64).
  test(
    'the compiled demo dies by SIGHUP soon after its pty is closed',
    () async {
      final script = File('${dir.path}/hangup.exp')
        ..writeAsStringSync('''
set timeout 20
spawn -noecho $exe
stty rows 12 columns 60 < \$spawn_out(slave,name)
expect "Toggle"
set pid [exp_pid]
close
# Unreaped, the demo keeps its pid: polled until it is a zombie, and killed
# if it is still running after five seconds, which wait then shows in place
# of SIGHUP. Nothing is left running to signal a pid reused later.
for {set i 0} {\$i < 50} {incr i} {
  if {[string match Z* [exec ps -o stat= -p \$pid]]} break
  after 100
}
if {\$i == 50} {exec kill -9 \$pid}
puts "WAIT=[wait]"
''');
      final run = await runExpect([script.path]);
      final output = '${run.stdout}${run.stderr}';
      expect(run.exitCode, 0, reason: output);
      expect(output, contains('CHILDKILLED SIGHUP'));
    },
    skip: hasExpect ? false : 'expect is not installed',
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

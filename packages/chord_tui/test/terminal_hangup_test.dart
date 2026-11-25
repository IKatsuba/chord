import 'dart:io';

import 'package:test/test.dart';

// A terminal that hangs up is followed by its SIGHUP, and the process must
// end by that signal, not by runApp's own exit racing it (CTUI-73).
void main() {
  final hasPty =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v expect']).exitCode == 0;

  Future<(String, int)> hangUp(String scenario) async {
    final driver = await Process.start('expect', [
      '-c',
      '''
set timeout 20
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_hangup.dart $scenario
set pid [exp_pid]
puts "FIXTURE=\$pid"
flush stdout
expect {
  "HANGUP_READY" {}
  timeout {exit 90}
  eof {exit 91}
}
set started [clock milliseconds]
close
# Unreaped, the app keeps its pid: polled until it is a zombie, and killed
# if it still runs after ten seconds, which wait then shows.
for {set i 0} {\$i < 100} {incr i} {
  if {[string match Z* [exec ps -o stat= -p \$pid]]} break
  after 100
}
if {\$i == 100} {exec kill -9 \$pid}
puts "ELAPSED=[expr {[clock milliseconds] - \$started}]"
puts "WAIT=[wait]"
''',
    ]);
    final output = StringBuffer();
    final outDone = driver.stdout
        .transform(systemEncoding.decoder)
        .forEach(output.write);
    final errDone = driver.stderr.transform(systemEncoding.decoder).join();
    // The fixture leads a session of its own and, in `silent`, outlives its
    // pty's HUP: should the driver fail or the test time out before wait
    // reaps it, its group is killed here. Once reaped, its pid is no longer
    // its own.
    addTearDown(() async {
      driver.kill(ProcessSignal.sigkill);
      await driver.exitCode;
      await outDone.timeout(const Duration(seconds: 3), onTimeout: () {});
      final seen = '$output';
      final fixture = RegExp(r'FIXTURE=(\d+)').firstMatch(seen);
      if (fixture != null && !seen.contains('WAIT=')) {
        Process.killPid(-int.parse(fixture[1]!), ProcessSignal.sigkill);
      }
    });
    final code = await driver.exitCode;
    await outDone;
    final out = '$output';
    final err = await errDone;
    expect(code, 0, reason: '$out$err');
    final elapsed = int.parse(RegExp(r'ELAPSED=(\d+)').firstMatch(out)![1]!);
    return (RegExp(r'WAIT=([^\r\n]*)').firstMatch(out)![1]!, elapsed);
  }

  final skip = hasPty ? false : 'POSIX and expect are required';

  test(
    'an embedder slower than the flush still ends a hung-up app by SIGHUP',
    () async {
      final (wait, _) = await hangUp('owner');
      expect(wait, endsWith('CHILDKILLED SIGHUP hangup'));
    },
    skip: skip,
  );

  test('handling signals, a hung-up app dies by SIGHUP', () async {
    final (wait, _) = await hangUp('self');
    expect(wait, endsWith('CHILDKILLED SIGHUP hangup'));
  }, skip: skip);

  test(
    'with no one to end it, a hung-up app still exits after its grace',
    () async {
      final (wait, elapsed) = await hangUp('silent');
      // A normal exit 0: the hung-up flush is not reported as a failure.
      expect(wait, matches(RegExp(r'^\d+ \S+ 0 0$')));
      expect(elapsed, inInclusiveRange(2000, 6000));
    },
    skip: skip,
  );
}

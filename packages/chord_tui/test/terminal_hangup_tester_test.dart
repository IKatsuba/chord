import 'dart:io';

import 'package:test/test.dart';

void main() {
  final hasPty = !Platform.isWindows && File('/usr/bin/expect').existsSync();
  group('tester: hangup suppression requires own tty EOF', () {
    for (final scenario in [
      'supplied_error',
      'supplied_timeout',
      'open_error',
      'open_timeout',
    ]) {
      for (final (columns, rows) in [(80, 24), (120, 40)]) {
        test(
          '$scenario at ${columns}x$rows reports flush and restores modes',
          () async {
            final process = await Process.start('/usr/bin/expect', [
              '-c',
              """
set timeout 15
spawn -noecho ${Platform.resolvedExecutable} run test/fixtures/terminal_hangup_tester.dart $scenario
set pid [exp_pid]
puts "FIXTURE=\$pid"
stty rows $rows columns $columns < \$spawn_out(slave,name)
expect eof
catch wait result
puts "REAPED"
exit [lindex \$result 3]
""",
            ]);
            final output = StringBuffer();
            final out = process.stdout
                .transform(systemEncoding.decoder)
                .forEach(output.write);
            final err = process.stderr.transform(systemEncoding.decoder).join();
            addTearDown(() async {
              process.kill(ProcessSignal.sigkill);
              await process.exitCode;
              await out;
              final pid = RegExp(r'FIXTURE=(\d+)').firstMatch('$output');
              if (pid != null && !'$output'.contains('REAPED')) {
                Process.killPid(-int.parse(pid[1]!), ProcessSignal.sigkill);
              }
            });
            final code = await process.exitCode;
            await out;
            expect(code, 0, reason: '$output${await err}');
            expect('$output', contains('NARROW_PASS=$scenario'));
          },
          skip: hasPty ? false : 'POSIX and expect are required',
        );
      }
    }
    for (final scenario in ['pipe_error', 'pipe_timeout']) {
      test('$scenario reports flush after non-tty EOF', () async {
        final process = await Process.start(Platform.resolvedExecutable, [
          'run',
          'test/fixtures/terminal_hangup_tester.dart',
          scenario,
        ]);
        final out = process.stdout.transform(systemEncoding.decoder).join();
        final err = process.stderr.transform(systemEncoding.decoder).join();
        addTearDown(() async {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        });
        await process.stdin.close();
        expect(await process.exitCode, 0, reason: await err);
        expect(await out, contains('NARROW_PASS=$scenario'));
      });
    }
  });
}

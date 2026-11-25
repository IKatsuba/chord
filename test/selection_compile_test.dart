@Tags(['compile'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/dev.dart' show shellWord;
import 'fixtures/fake.dart';
import 'fixtures/native_smoke_cleanup.dart';

String _tcl(String value) =>
    '[encoding convertfrom utf-8 [binary format H* {${utf8.encode(value).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}}]]';
String _osc(String text) => '\x1b]52;c;${base64.encode(utf8.encode(text))}\x07';

void main() {
  final available = File('/usr/bin/expect').existsSync();
  group(
    'compiled selection integration',
    skip: !available ? 'expect is not installed' : fakeAgent.reason ?? false,
    () {
      late Directory directory;
      late String demo, chord, pending;
      setUpAll(() async {
        directory = Directory(
          'build/selection-native-$pid-${DateTime.now().microsecondsSinceEpoch}',
        ).absolute..createSync(recursive: true);
        Future<String> binary(String env, String source, String name) async {
          final supplied = Platform.environment[env];
          if (supplied != null) {
            expect(File(supplied).existsSync(), isTrue);
            return supplied;
          }
          final output = '${directory.path}/$name';
          final result = await Process.run('nice', [
            '-n',
            '19',
            Platform.resolvedExecutable,
            'compile',
            'exe',
            source,
            '-o',
            output,
          ]);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}${result.stderr}',
          );
          return output;
        }

        demo = await binary(
          'CTUI_SELECTION_DEMO_EXE',
          'packages/chord_tui/example/selection.dart',
          'selection-demo',
        );
        chord = await binary('CTUI_CHORD_EXE', 'bin/chord.dart', 'chord');
        pending = await binary(
          'CTUI_SELECTION_PENDING_EXE',
          'test/fixtures/selection_session.dart',
          'pending',
        );
      });
      tearDownAll(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      Future<String> drive(
        String name,
        int columns,
        int rows,
        List<String> command,
        String body, {
        File? agent,
      }) async {
        final before = File('${directory.path}/$name.before'),
            after = File('${directory.path}/$name.after');
        final group = File('${directory.path}/$name.group'),
            capture = File('${directory.path}/$name.ansi');
        final argv = [
          'sh',
          '-c',
          r'''
before=$1; after=$2; shift 2
stty -g > "$before"
"$@"
code=$?
stty -g > "$after"
exit "$code"
''',
          'selection',
          before.path,
          after.path,
          ...command,
        ];
        final script = File('${directory.path}/$name.exp')
          ..writeAsStringSync(
            r'''
set timeout 10
log_user 0
log_file -a -noappend @CAPTURE@
proc awaitText {text} {
  expect {
    -exact $text {return}
    timeout {exit 90}
    eof {exit 91}
  }
}
set command [list @ARGV@]
spawn -noecho {*}$command
set tracked [open @GROUP@ w]
puts $tracked [exp_pid]
close $tracked
stty rows @ROWS@ columns @COLS@ < $spawn_out(slave,name)
@BODY@
expect {
  eof {}
  timeout {exit 92}
}
if {[info exists started]} {
  puts "PENDING_EXIT_MS=[expr {[clock milliseconds]-$started}]"
}
catch wait result
exit [lindex $result 3]
'''
                .replaceAll('@CAPTURE@', _tcl(capture.path))
                .replaceAll('@ARGV@', argv.map(_tcl).join(' '))
                .replaceAll('@GROUP@', _tcl(group.path))
                .replaceAll('@ROWS@', '$rows')
                .replaceAll('@COLS@', '$columns')
                .replaceAll('@BODY@', body),
          );
        final process = await Process.start(
          '/usr/bin/expect',
          [script.path],
          workingDirectory: directory.path,
          environment: {'NO_COLOR': '1', 'TERM': 'xterm-256color'},
        );
        final stdoutText = process.stdout.transform(utf8.decoder).join(),
            stderrText = process.stderr.transform(utf8.decoder).join();
        Iterable<int> groups() => [
          for (final f in [group, ?agent])
            if (f.existsSync()) int.parse(f.readAsStringSync().trim()),
        ];
        Future<void> cleanup() =>
            cleanupNativeSmoke(driver: process, groupIds: groups);
        addTearDown(cleanup);
        final code = await process.exitCode.timeout(
          const Duration(seconds: 35),
        );
        // A failed driver can leave its PTY child holding inherited streams.
        // Reap owned groups before awaiting pipe EOF, even on a setup failure.
        if (code != 0) await cleanup();
        final output = '${await stdoutText}${await stderrText}';
        final bytes = capture.existsSync() ? capture.readAsStringSync() : '';
        File('build/ctui48_s7_native_$name.ansi').writeAsStringSync(bytes);
        expect(
          code,
          0,
          reason: '$output\n${bytes.replaceAll('\x1b', r'\x1b')}',
        );
        expect(before.readAsStringSync(), after.readAsStringSync());
        expect(bytes, contains('\x1b[?1049l'));
        return '$output\n$bytes';
      }

      String fakeCommand(File marker) => [
        'sh',
        '-c',
        r'echo $$ > "$1"; shift; exec "$@"',
        'fake',
        marker.path,
        ...fakeAgentCommand(null, ['--step-ms', '0']),
      ].map(shellWord).join(' ');

      for (final (columns, rows) in [(120, 40), (80, 24)]) {
        test(
          'public demo native mouse last-motion and snapshot at $columns x $rows',
          () async {
            final output = await drive(
              'demo-$columns',
              columns,
              rows,
              [demo],
              r'''
awaitText "Selection area"
send "\x1b\[<0;1;1M\x1b\[<32;9;1M\x1b\[<0;9;1m\x13"
awaitText "finalize"
exec /bin/kill -WINCH -- -[exp_pid]
awaitText "finalized: Selection"
send "\x11"
''',
            );
            expect(output, contains('finalized: Selection'));
            expect(output, contains('\x1b[?1002h'));
            expect(output, contains('\x1b[?1002l'));
          },
          timeout: const Timeout(Duration(seconds: 45)),
        );
        test(
          'production binary mouse auto-copy and code keys record OSC only at $columns x $rows',
          () async {
            final agent = File('${directory.path}/port-$columns.agent');
            final body =
                '''
awaitText "Fake Large"
send "markdowncode\\r"
awaitText "check"
exec /bin/kill -WINCH -- -[exp_pid]
awaitText "bun dev check"
awaitText "\\x1b\\[?2026l"
send "\\030bc"
awaitText ${_tcl(_osc('bun dev check'))}
send "drafttarget"
awaitText "drafttarget"
send "\\x1b\\[<0;5;${rows - 2}M\\x1b\\[<32;9;${rows - 2}M\\x1b\\[<0;9;${rows - 2}m"
awaitText ${_tcl(_osc('draft'))}
send "\\x03"
awaitText ${_tcl(_osc('draft'))}
send "\\x03\\x04"
''';
            final output = await drive(
              'port-$columns',
              columns,
              rows,
              [chord, 'fake', '--agent-command', fakeCommand(agent)],
              body,
              agent: agent,
            );
            expect(output, contains(_osc('bun dev check')));
            expect(
              RegExp(RegExp.escape(_osc('draft'))).allMatches(output),
              hasLength(2),
            );
          },
          timeout: const Timeout(Duration(seconds: 45)),
        );
        test(
          'production session exits without waiting for ignored pending copy at $columns x $rows',
          () async {
            final agent = File('${directory.path}/pending-$columns.agent'),
                journal = File('${directory.path}/pending-$columns.jsonl');
            final body =
                '''
awaitText "Fake Large"
send "markdowncode\\r"
awaitText "check"
exec /bin/kill -WINCH -- -[exp_pid]
awaitText "bun dev check"
awaitText "\\x1b\\[?2026l"
send "\\030bc"
set journal ${_tcl(journal.path)}
set deadline [expr {[clock milliseconds]+1000}]
while {![file exists \$journal]} {
  if {[clock milliseconds]>\$deadline} {exit 93}
  expect -timeout 0 {
    -re {.+} {}
    eof {exit 95}
    timeout {}
  }
  after 10
}
set started [clock milliseconds]
send "\\x04"
''';
            final output = await drive(
              'pending-$columns',
              columns,
              rows,
              [pending, fakeCommand(agent), journal.path],
              body,
              agent: agent,
            );
            final match = RegExp(r'PENDING_EXIT_MS=(\d+)').firstMatch(output);
            expect(match, isNotNull);
            expect(int.parse(match!.group(1)!), lessThan(1200));
            final attempts = journal
                .readAsLinesSync()
                .map((l) => jsonDecode(l) as Map<String, dynamic>)
                .toList();
            expect(attempts, [
              {'text': 'bun dev check', 'cancelled': false},
            ]);
          },
          timeout: const Timeout(Duration(seconds: 45)),
        );
      }
    },
  );
}

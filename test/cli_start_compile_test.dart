@Tags(['compile'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:chord/version.dart';

import '../tool/dev.dart' show shellWord;
import 'fixtures/fake.dart';
import 'fixtures/native_smoke_cleanup.dart';
import 'fixtures/native_resume_smoke.dart';

void main() {
  final hasExpect = File('/usr/bin/expect').existsSync();
  late Directory directory;
  late String executable;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('chord-start-native-');
    executable = '${directory.path}/chord';
    final build = await Process.run('nice', [
      '-n',
      '19',
      Platform.resolvedExecutable,
      'compile',
      'exe',
      'bin/chord.dart',
      '-o',
      executable,
    ]);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
    for (final available in [true, false]) {
      final path = Directory(
        '${directory.path}/${available ? 'found' : 'missing'}',
      )..createSync();
      for (final command in ['sh', 'stty']) {
        Link('${path.path}/$command').createSync('/bin/$command');
      }
      if (available) {
        File('${path.path}/npx').writeAsStringSync(
          '#!/bin/sh\necho invoked > "${directory.path}/agent-started"\nexit 99\n',
        );
        final chmod = await Process.run('/bin/chmod', [
          '+x',
          '${path.path}/npx',
        ]);
        expect(chmod.exitCode, 0);
      }
    }
  });
  tearDownAll(() => directory.deleteSync(recursive: true));

  test('compiled version and agents work outside the source tree', () async {
    for (final args in [
      <String>['--version'],
      <String>['agents'],
    ]) {
      final result = await Process.run(
        executable,
        args,
        workingDirectory: directory.path,
        environment: {
          'HOME': directory.path,
          'XDG_STATE_HOME': '${directory.path}/state',
          'NO_COLOR': '1',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, isEmpty);
      if (args.single == '--version') {
        expect(result.stdout, 'chord $version\n');
      } else {
        expect(result.stdout, contains('claude'));
        expect(result.stdout, contains('codex'));
      }
    }
  });

  test(
    'compiled -p prints the reply with piped input, text and JSON',
    () async {
      final agent = fakeAgentCommand(null, [
        '--step-ms',
        '0',
      ]).map(shellWord).join(' ');
      for (final json in [false, true]) {
        final process = await Process.start(
          executable,
          [
            'fake',
            '--agent-command',
            agent,
            '-p',
            '/echo one',
            if (json) ...['--output-format', 'json'],
          ],
          workingDirectory: directory.path,
          environment: {
            'HOME': directory.path,
            'XDG_STATE_HOME': '${directory.path}/state',
            'NO_COLOR': '1',
          },
        );
        process.stdin.write('two\n');
        await process.stdin.close();
        final out = process.stdout.transform(utf8.decoder).join();
        final err = process.stderr.transform(utf8.decoder).join();
        final code = await process.exitCode.timeout(
          const Duration(seconds: 30),
        );
        expect(code, 0, reason: await err);
        expect(await err, isEmpty);
        if (json) {
          final result = jsonDecode(await out) as Map<String, Object?>;
          expect(result['result'], 'one\ntwo');
          expect(result['is_error'], isFalse);
        } else {
          expect(await out, 'one\ntwo\n');
        }
      }
    },
    skip: fakeAgent.reason ?? false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'compiled -p reads piped bytes as the original does: a split character '
    'whole, a malformed byte replaced',
    () async {
      final process = await Process.start(
        executable,
        [
          'fake',
          '--agent-command',
          fakeAgentCommand(null, ['--step-ms', '0']).map(shellWord).join(' '),
          '-p',
          '/echo one',
        ],
        workingDirectory: directory.path,
        environment: {
          'HOME': directory.path,
          'XDG_STATE_HOME': '${directory.path}/state',
          'NO_COLOR': '1',
        },
      );
      final out = process.stdout.expand((chunk) => chunk).toList();
      final err = process.stderr.transform(utf8.decoder).join();
      // é split across two writes, then 0xff, which is no UTF-8.
      process.stdin.add([0xc3]);
      await process.stdin.flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      process.stdin.add([0xa9, 0xff, 0x78, 0x0a]);
      await process.stdin.close();
      final code = await process.exitCode.timeout(const Duration(seconds: 30));
      // What the original printed for the same bytes, probed with bun.
      expect(code, 0, reason: await err);
      expect(await err, isEmpty);
      expect(utf8.decode(await out), 'one\né\ufffdx\n');
    },
    skip: fakeAgent.reason ?? false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'compiled fake session replies, quits and restores exact termios',
    () async {
      final before = File('${directory.path}/fake-before');
      final after = File('${directory.path}/fake-after');
      final windowGroup = File('${directory.path}/fake-window.pgid');
      final agentPid = File('${directory.path}/fake-agent.pid');
      final command = [
        'sh',
        '-c',
        r'echo $$ > "$1"; shift; exec "$@"',
        'fake',
        agentPid.path,
        ...fakeAgentCommand(null, ['--step-ms', '0']),
      ].map(shellWord).join(' ');
      final argv = [
        'sh',
        '-c',
        r'''
before=$1; after=$2; shift 2
stty -g > "$before"
"$@"
run_code=$?
stty -g > "$after"
exit "$run_code"
''',
        'session',
        before.path,
        after.path,
        executable,
        'fake',
        '--agent-command',
        command,
      ];
      String tcl(String value) =>
          '[encoding convertfrom utf-8 [binary format H* {${utf8.encode(value).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}}]]';
      // The fake streams "Hello", ", world", ". This reply" and " came in
      // chunks." as four updates, which may land in one frame or several;
      // the renderer moves the cursor over unchanged blanks and between
      // frames, so only text inside one chunk and free of spaces is
      // contiguous in the output. The four words, in order, prove the whole
      // reply arrived.
      final script = File('${directory.path}/fake-session.exp')
        ..writeAsStringSync('''
set timeout 20
proc awaitText {text} {
  expect {
    -exact \$text {return}
    timeout {exit 90}
    eof {exit 91}
  }
}
set command [list ${argv.map(tcl).join(' ')}]
spawn -noecho {*}\$command
set groupfile [open ${tcl(windowGroup.path)} w]
puts \$groupfile [exp_pid]
close \$groupfile
stty rows 24 columns 80 < \$spawn_out(slave,name)
awaitText "Fake Large"
send "text\\r"
awaitText "Hello"
awaitText "world"
awaitText "reply"
awaitText "chunks."
send "\\x04"
expect {
  eof {}
  timeout {exit 92}
}
catch wait result
exit [lindex \$result 3]
''');
      final process = await Process.start(
        '/usr/bin/expect',
        [script.path],
        workingDirectory: directory.path,
        environment: {
          'HOME': directory.path,
          'XDG_STATE_HOME': '${directory.path}/state',
          'NO_COLOR': '1',
          'TERM': 'xterm-256color',
        },
      );
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      addTearDown(
        () => cleanupNativeSmoke(
          driver: process,
          groupIds: () => [
            for (final file in [windowGroup, agentPid])
              if (file.existsSync()) int.parse(file.readAsStringSync().trim()),
          ],
        ),
      );
      final code = await process.exitCode.timeout(const Duration(seconds: 40));
      final transcript = '${await output}${await errors}';
      expect(code, 0, reason: transcript);
      expect(
        transcript,
        stringContainsInOrder(['Hello', 'world', 'reply', 'chunks.']),
      );
      expect(transcript, contains('\x1b[?1049l'));
      expect(before.readAsStringSync(), after.readAsStringSync());
      final pid = int.parse(agentPid.readAsStringSync().trim());
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        final groups = await Process.run('ps', ['-A', '-o', 'pgid=']);
        if (groups.stdout
            .toString()
            .split('\n')
            .every((line) => line.trim() != '$pid')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final groups = await Process.run('ps', ['-A', '-o', 'pgid=']);
      expect(
        groups.stdout
            .toString()
            .split('\n')
            .any((line) => line.trim() == '$pid'),
        isFalse,
        reason: 'the fake process group survived compiled quit',
      );
    },
    skip: !hasExpect ? 'expect is not installed' : fakeAgent.reason ?? false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // A closed window hangs the pty up. As the original, chord gives the
  // terminal back within its second, closes the agent, and dies by SIGHUP;
  // it must not live on orphaned, nor leave the agent behind (CTUI-64).
  test(
    'compiled fake session dies by SIGHUP with its agent when the pty closes',
    () async {
      final windowGroup = File('${directory.path}/hangup-window.pgid');
      final agentPid = File('${directory.path}/hangup-agent.pid');
      final command = [
        'sh',
        '-c',
        r'echo $$ > "$1"; shift; exec "$@"',
        'fake',
        agentPid.path,
        ...fakeAgentCommand(null, ['--step-ms', '0']),
      ].map(shellWord).join(' ');
      String tcl(String value) =>
          '[encoding convertfrom utf-8 [binary format H* {${utf8.encode(value).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}}]]';
      final argv = [executable, 'fake', '--agent-command', command];
      final script = File('${directory.path}/hangup.exp')
        ..writeAsStringSync('''
set timeout 20
set command [list ${argv.map(tcl).join(' ')}]
spawn -noecho {*}\$command
set pid [exp_pid]
set groupfile [open ${tcl(windowGroup.path)} w]
puts \$groupfile \$pid
close \$groupfile
stty rows 24 columns 80 < \$spawn_out(slave,name)
expect {
  -exact "Fake Large" {}
  timeout {exit 90}
  eof {exit 91}
}
close
# Unreaped, chord keeps its pid: polled until it is a zombie, and killed if
# it still runs after ten seconds, which wait then shows in place of SIGHUP.
for {set i 0} {\$i < 100} {incr i} {
  if {[string match Z* [exec ps -o stat= -p \$pid]]} break
  after 100
}
if {\$i == 100} {exec kill -9 \$pid}
puts "WAIT=[wait]"
''');
      final process = await Process.start(
        '/usr/bin/expect',
        [script.path],
        workingDirectory: directory.path,
        environment: {
          'HOME': directory.path,
          'XDG_STATE_HOME': '${directory.path}/state',
          'NO_COLOR': '1',
          'TERM': 'xterm-256color',
        },
      );
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      addTearDown(
        () => cleanupNativeSmoke(
          driver: process,
          groupIds: () => [
            for (final file in [windowGroup, agentPid])
              if (file.existsSync()) int.parse(file.readAsStringSync().trim()),
          ],
        ),
      );
      final code = await process.exitCode.timeout(const Duration(seconds: 40));
      final transcript = '${await output}${await errors}';
      expect(code, 0, reason: transcript);
      expect(transcript, contains('CHILDKILLED SIGHUP'));
      final agent = int.parse(agentPid.readAsStringSync().trim());
      final window = int.parse(windowGroup.readAsStringSync().trim());
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      var alive = await nativeSmokeGroups({agent, window});
      while (alive.isNotEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        alive = await nativeSmokeGroups({agent, window});
      }
      expect(alive, isEmpty, reason: 'groups outlived the closed pty');
    },
    skip: !hasExpect ? 'expect is not installed' : fakeAgent.reason ?? false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final scenario in ['pick', 'esc', 'ctrl-c', 'refusal', 'named']) {
    test(
      'compiled startup $scenario exits promptly and restores the terminal',
      () async {
        final marker = File('${directory.path}/agent-started');
        if (marker.existsSync()) marker.deleteSync();
        final pick = scenario == 'pick' || scenario == 'refusal';
        final named = scenario == 'named';
        final missing = scenario == 'refusal';
        final steps = <String>[
          if (!named) 'awaitText "Select agent"',
          if (pick) 'send "\\r"',
          if (scenario == 'esc') 'send "\\x1b"',
          if (scenario == 'ctrl-c') 'send "\\x03"',
          if (missing) 'awaitText "npx"',
          if (named || scenario == 'pick') ...[
            // CTUI-52's words, 'claude did not start: it exited with code 99
            // before answering initialize.', redrawn word by word.
            'awaitText "initialize."',
            'send "\\x03\\x03"',
          ],
        ].join('\n');
        final script = File('${directory.path}/$scenario.exp')
          ..writeAsStringSync('''
set timeout 10
proc stop {code} {
  catch {exec /bin/kill -TERM [exp_pid]}
  catch {expect eof}
  catch wait
  exit \$code
}
proc awaitText {text} {
  expect {
    -exact \$text {return}
    timeout {stop 90}
    eof {stop 91}
  }
}
trap {stop 92} SIGTERM
spawn -noecho {$executable} ${named ? 'claude' : ''}
puts "CHORD_PID=[exp_pid]"
set pidfile [open {${directory.path}/$scenario.pid} w]
puts \$pidfile [exp_pid]
close \$pidfile
stty rows 24 columns 80 < \$spawn_out(slave,name)
$steps
expect {
  eof {}
  timeout {stop 93}
}
catch wait result
exit [lindex \$result 3]
''');
        final process = await Process.start(
          '/usr/bin/expect',
          [script.path],
          environment: {
            'PATH': '${directory.path}/${missing ? 'missing' : 'found'}',
            'HOME': directory.path,
            'XDG_STATE_HOME': '${directory.path}/state',
            'NO_COLOR': '1',
            'TERM': 'xterm-256color',
          },
          includeParentEnvironment: false,
        );
        final stdout = process.stdout.transform(utf8.decoder).join();
        final stderr = process.stderr.transform(utf8.decoder).join();
        late ProcessResult run;
        try {
          final code = await process.exitCode.timeout(
            const Duration(seconds: 30),
          );
          run = ProcessResult(process.pid, code, await stdout, await stderr);
        } finally {
          final pidfile = File('${directory.path}/$scenario.pid');
          if (pidfile.existsSync()) {
            final childPid = int.parse(pidfile.readAsStringSync().trim());
            Process.killPid(childPid, ProcessSignal.sigterm);
          }
          try {
            await process.exitCode.timeout(const Duration(seconds: 2));
          } on Object {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode;
          }
          if (pidfile.existsSync()) {
            final childPid = int.parse(pidfile.readAsStringSync().trim());
            final alive = await Process.run('/bin/kill', ['-0', '$childPid']);
            if (alive.exitCode == 0) {
              Process.killPid(childPid, ProcessSignal.sigkill);
            }
          }
        }
        final output = '${run.stdout}${run.stderr}';
        final child = RegExp(r'CHORD_PID=(\d+)').firstMatch(output);
        expect(child, isNotNull, reason: output);
        final gone = await Process.run('/bin/kill', ['-0', child!.group(1)!]);
        expect(
          gone.exitCode,
          isNot(0),
          reason: 'the owned binary must be reaped',
        );
        expect(run.exitCode, missing ? 1 : 0, reason: output);
        expect(output, contains('\x1b[?1049l'));
        expect(
          File('${directory.path}/agent-started').existsSync(),
          named || scenario == 'pick',
        );
        if (scenario == 'pick') {
          expect(
            RegExp(RegExp.escape('\x1b[?1049h')).allMatches(output).length,
            2,
          );
          expect(
            RegExp(RegExp.escape('\x1b[?1049l')).allMatches(output).length,
            2,
          );
        }
      },
      skip: hasExpect ? false : 'expect is not installed',
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
  for (final route in [
    'continue',
    'id',
    'picker',
    'overlay',
    'cancel',
    'refusal',
  ]) {
    test(
      'compiled resume $route preserves records and restores terminal',
      () => nativeResumeSmoke(executable, directory, route),
      skip: !hasExpect ? 'expect is not installed' : fakeAgent.reason ?? false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

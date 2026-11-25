// `chord acp` as the compiled binary on real stdio: usage errors with stdout
// empty, EOF, a closed stdout, each signal with an agent's group left
// behind by none, the by-hand note in a terminal alone, and nothing on
// stdout but JSON lines.
@Tags(['compile'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/dev.dart' show shellWord;
import 'fixtures/fake.dart';

/// The lines of [text] that have ended: a read can stop inside one.
List<String> completeLines(String text) =>
    const LineSplitter().convert(text.substring(0, text.lastIndexOf('\n') + 1));

void main() {
  test('only ended lines are read', () {
    expect(completeLines('{"a":1}\n{"b":'), ['{"a":1}']);
    expect(completeLines('{"b":'), isEmpty);
    expect(completeLines('{"a":1}\n{"b":2}\n'), ['{"a":1}', '{"b":2}']);
  });

  final hasExpect = File('/usr/bin/expect').existsSync();
  late Directory directory;
  late String chord;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('chord-acp-native-');
    chord = '${directory.path}/chord';
    final build = await Process.run('nice', [
      '-n',
      '19',
      Platform.resolvedExecutable,
      'compile',
      'exe',
      'bin/chord.dart',
      '-o',
      chord,
    ]);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
  });
  tearDownAll(() => directory.deleteSync(recursive: true));

  Map<String, String> env() => {
    'HOME': directory.path,
    'PATH': Platform.environment['PATH']!,
    'XDG_STATE_HOME': '${directory.path}/state',
    'XDG_CONFIG_HOME': '${directory.path}/config',
  };

  String agentCommand() => fakeAgentCommand('text').map(shellWord).join(' ');

  /// Every line on [stdout] is one JSON message.
  void onlyJson(String stdout) {
    for (final line in const LineSplitter().convert(stdout)) {
      expect(() => jsonDecode(line) as Map, returnsNormally, reason: line);
    }
  }

  /// [chord] started for this test, and killed with any agent group it
  /// leads should the test fail before it ends.
  Future<Process> start(List<String> args) async {
    final process = await Process.start(
      chord,
      args,
      workingDirectory: directory.path,
      environment: env(),
      includeParentEnvironment: false,
    );
    addTearDown(() async {
      final children = await Process.run('pgrep', ['-P', '${process.pid}']);
      for (final child in (children.stdout as String).trim().split('\n')) {
        if (child.isNotEmpty) {
          await Process.run('kill', ['-KILL', '--', '-$child']);
        }
      }
      process.kill(ProcessSignal.sigkill);
    });
    return process;
  }

  test('a usage error: exit 2, stdout empty', () async {
    for (final (args, said) in [
      (['acp', '--nope'], 'chord: Could not find an option named "--nope".\n'),
      (
        ['acp', 'no-such-agent'],
        'chord: Unknown agent "no-such-agent". `chord agents` lists them.\n',
      ),
    ]) {
      final result = await Process.run(
        chord,
        args,
        workingDirectory: directory.path,
        environment: env(),
        includeParentEnvironment: false,
      );
      expect(result.exitCode, 2);
      expect(result.stdout, isEmpty);
      expect(result.stderr, said);
    }
  });

  test('EOF with nothing open: exit 0, no note to a client, only JSON on '
      'stdout', () async {
    final process = await start(['acp', 'x', '--agent-command', 'true']);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': 1},
      }),
    );
    await process.stdin.close();
    expect(await process.exitCode.timeout(const Duration(seconds: 30)), 0);
    final out = await stdout;
    expect(out, contains('"protocolVersion":1'));
    onlyJson(out);
    expect(await stderr, isEmpty);
  });

  test('a stdout nobody reads any more: exit 1, a stderr line', () async {
    final process = await start(['acp', 'x', '--agent-command', 'true']);
    final stderr = process.stderr.transform(utf8.decoder).join();
    // The read end closed: chord's next write finds no reader.
    await process.stdout.listen((_) {}).cancel();
    for (var id = 1; id <= 50; id++) {
      try {
        process.stdin.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'method': 'session/list',
            'params': <String, Object?>{},
          }),
        );
        await process.stdin.flush();
      } on Object {
        break;
      }
    }
    expect(await process.exitCode.timeout(const Duration(seconds: 30)), 1);
    expect(await stderr, contains('chord: '));
  });

  /// [process]'s stdout read as the client reads it: [send] a message, and
  /// [answer] waits for the one to an id.
  ({
    StringBuffer out,
    void Function(Map<String, Object?>) send,
    Future<Map<String, Object?>> Function(int id) answer,
  })
  client(Process process) {
    final out = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(out.write);
    Future<Map<String, Object?>> answer(int id) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        for (final line in completeLines('$out')) {
          if (line.isEmpty) continue;
          final message = jsonDecode(line) as Map<String, Object?>;
          if (message['id'] == id && !message.containsKey('method')) {
            return message;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('no answer to $id');
    }

    return (
      out: out,
      send: (message) => process.stdin.writeln(jsonEncode(message)),
      answer: answer,
    );
  }

  /// Initializes and opens a session on the fake; its id.
  Future<String> open(
    ({
      StringBuffer out,
      void Function(Map<String, Object?>) send,
      Future<Map<String, Object?>> Function(int id) answer,
    })
    on,
  ) async {
    on.send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': 1},
    });
    await on.answer(1);
    on.send({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'session/new',
      'params': {'cwd': directory.path, 'mcpServers': <Object?>[]},
    });
    final opened = await on.answer(2);
    return ((opened['result'] as Map?)?['sessionId'] ?? fail('$opened'))
        as String;
  }

  // As the original's: a stderr pipe nobody reads, which these few lines
  // do not fill. One that fills blocks chord in the write, as it blocks the
  // original, whose stderr writes to a pipe are synchronous.
  test('a stderr nobody reads: a prompt still answered, and EOF exits 0 '
      'within the drain bound', () async {
    final process = await start([
      'acp',
      'fake',
      '--agent-command',
      agentCommand(),
    ]);
    final on = client(process);
    final sessionId = await open(on);
    on.send({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'session/prompt',
      'params': {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': 'text'},
        ],
      },
    });
    expect(((await on.answer(3))['result'] as Map)['stopReason'], 'end_turn');
    await process.stdin.close();
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
    onlyJson('${on.out}');
  }, skip: fakeAgent.reason);

  for (final signal in [
    ProcessSignal.sigterm,
    ProcessSignal.sigint,
    ProcessSignal.sighup,
  ]) {
    test('$signal with a session open: dies by it, the agent\'s group '
        'gone', () async {
      final process = await start([
        'acp',
        'fake',
        '--agent-command',
        agentCommand(),
      ]);
      final on = client(process);
      final stderr = process.stderr.transform(utf8.decoder).join();
      await open(on);
      // The agent's group leader is chord's own child, its launcher.
      final children = await Process.run('pgrep', ['-P', '${process.pid}']);
      final group = int.parse(
        (children.stdout as String).trim().split('\n').first,
      );
      process.kill(signal);
      final code = await process.exitCode.timeout(const Duration(seconds: 30));
      expect(code, -signal.signalNumber, reason: await stderr);
      // After --: procps-ng kill, Linux's, takes a bare -<pgid> for an
      // option, and then signals nothing and exits 0.
      final alive = await Process.run('kill', ['-0', '--', '-$group']);
      expect(alive.exitCode, isNot(0), reason: 'the agent group is running');
      onlyJson('${on.out}');
    }, skip: fakeAgent.reason);
  }

  test('the by-hand note goes to a terminal', () async {
    // On Linux dart:io never ends a terminal's stdin at Ctrl-D, so the
    // note names Ctrl-C there, and Ctrl-C ends chord by its signal.
    final linux = Platform.isLinux;
    final leave = linux ? r'\003' : r'\004';
    final verdict = linux
        ? r'exit [expr {[lindex $result 4] eq "CHILDKILLED" && '
              r'[lindex $result 5] eq "SIGINT" ? 0 : 1}]'
        : r'exit [lindex $result 3]';
    final script = File('${directory.path}/note.exp')
      ..writeAsStringSync('''
set timeout 20
spawn $chord acp x --agent-command true
expect "nothing to press here"
send "$leave"
expect eof
catch wait result
$verdict
''');
    final result = await Process.run(
      '/usr/bin/expect',
      [script.path],
      workingDirectory: directory.path,
      environment: env(),
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(
      result.stdout,
      contains(
        'chord: acp serves ACP on stdin and stdout, for a client that starts '
        'it.',
      ),
    );
    expect(
      result.stdout,
      contains(
        linux
            ? 'chord: nothing to press here. Ctrl-C leaves; `chord` opens a '
                  'window.'
            : 'chord: nothing to press here. Ctrl-D or Ctrl-C leaves; `chord` '
                  'opens a window.',
      ),
    );
  }, skip: hasExpect ? false : '/usr/bin/expect is not installed');

  group('tester U14 native ACP shutdown boundaries', () {
    for (final signal in [
      ProcessSignal.sighup,
      ProcessSignal.sigterm,
      ProcessSignal.sigint,
    ]) {
      test(
        '$signal with the client stdout already gone kills ACP and its agent group',
        () async {
          final process = await start([
            'acp',
            'fake',
            '--agent-command',
            agentCommand(),
          ]);
          final out = StringBuffer();
          final reading = process.stdout
              .transform(utf8.decoder)
              .listen(out.write);
          final errors = process.stderr.transform(utf8.decoder).join();
          Future<Map<String, Object?>> answer(int id) async {
            final deadline = DateTime.now().add(const Duration(seconds: 20));
            while (DateTime.now().isBefore(deadline)) {
              for (final line in completeLines('$out')) {
                final message = jsonDecode(line) as Map<String, Object?>;
                if (message['id'] == id && !message.containsKey('method')) {
                  return message;
                }
              }
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            throw TimeoutException('no native answer to $id');
          }

          await open((
            out: out,
            send: (m) => process.stdin.writeln(jsonEncode(m)),
            answer: answer,
          ));
          final children = await Process.run('pgrep', ['-P', '${process.pid}']);
          final groups = (children.stdout as String)
              .trim()
              .split('\n')
              .where((s) => s.isNotEmpty)
              .map(int.parse)
              .toList();
          expect(groups, isNotEmpty);
          addTearDown(() async {
            for (final group in groups) {
              await Process.run('kill', ['-KILL', '--', '-$group']);
            }
          });
          await reading.cancel();
          expect(process.kill(signal), isTrue);
          final code = await process.exitCode.timeout(
            const Duration(seconds: 20),
          );
          expect(code, -signal.signalNumber, reason: await errors);
          expect(
            (await Process.run('kill', ['-0', '${process.pid}'])).exitCode,
            isNot(0),
          );
          for (final group in groups) {
            expect(
              (await Process.run('kill', ['-0', '--', '-$group'])).exitCode,
              isNot(0),
              reason: 'native agent group survived',
            );
          }
        },
        skip: fakeAgent.reason,
      );

      test(
        '$signal on a PTY ends native ACP by that signal with no agent group',
        () async {
          final script =
              File('${directory.path}/tester-${signal.signalNumber}.exp')
                ..writeAsStringSync('''
set timeout 5
spawn -noecho {$chord} acp fake --agent-command {${agentCommand()}}
set owner [exp_pid]
proc abort {code} {
 global owner
 catch {set children [split [string trim [exec pgrep -P \$owner]] "\\n"]; foreach child \$children {catch {exec kill -KILL -- -\$child}}}
 catch {exec kill -KILL \$owner}
 exit \$code
}
set init {${jsonEncode({
                  'jsonrpc': '2.0',
                  'id': 1,
                  'method': 'initialize',
                  'params': {'protocolVersion': 1},
                })}}
send -- "\$init\\r"
expect {
 -re {"id":1,"result":} {}
 timeout { abort 91 }
 eof { abort 91 }
}
set request {${jsonEncode({
                  'jsonrpc': '2.0',
                  'id': 2,
                  'method': 'session/new',
                  'params': {'cwd': directory.path, 'mcpServers': <Object?>[]},
                })}}
send -- "\$request\\r"
expect {
 -re {"id":2,"result":.*sessionId} {}
 timeout { abort 92 }
 eof { abort 92 }
}
set groups [split [string trim [exec pgrep -P \$owner]] "\\n"]
exec kill -${signal.signalNumber} \$owner
expect {
 eof {}
 timeout { abort 93 }
}
catch wait result
if {[lindex \$result 4] ne "CHILDKILLED" || [lindex \$result 5] ne "$signal"} {puts "WRONG_EXIT \$result"; abort 94}
foreach group \$groups {
 if {![catch {exec kill -0 -- -\$group}]} {catch {exec kill -KILL -- -\$group}; abort 95}
}
puts "TESTER_SIGNAL_OK $signal"
exit 0
''');
          final result = await Process.run(
            '/usr/bin/expect',
            [script.path],
            workingDirectory: directory.path,
            environment: env(),
            includeParentEnvironment: false,
          ).timeout(const Duration(seconds: 30));
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}${result.stderr}',
          );
          expect(result.stdout, contains('TESTER_SIGNAL_OK $signal'));
        },
        skip:
            fakeAgent.reason ??
            (hasExpect ? false : '/usr/bin/expect is not installed'),
      );
    }
  });
}

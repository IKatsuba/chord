// CTUI-114: chord built with CHORD_AGENT_CLOSE_FAILS, so every agent's
// close fails once its agent has stopped, as one whose exit went unseen.
// A close begun in one error zone and awaited by the way out in another
// would never resume it: the window would outlive its closed pty, and
// `chord acp` would sit out its whole deadline. Each way out here must
// settle by its own means instead.
@Tags(['compile'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/dev.dart' show shellWord;
import 'fixtures/fake.dart';
import 'fixtures/native_smoke_cleanup.dart';

void main() {
  final hasExpect = File('/usr/bin/expect').existsSync();
  late Directory directory;
  late String chord;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('chord-leave-zones-');
    chord = '${directory.path}/chord';
    final build = await Process.run('nice', [
      '-n',
      '19',
      Platform.resolvedExecutable,
      'compile',
      'exe',
      '-DCHORD_AGENT_CLOSE_FAILS=true',
      'bin/chord.dart',
      '-o',
      chord,
    ]);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
  });
  tearDownAll(() => directory.deleteSync(recursive: true));

  Map<String, String> env({String state = 'state'}) => {
    'HOME': directory.path,
    'PATH': Platform.environment['PATH']!,
    'XDG_STATE_HOME': '${directory.path}/$state',
    'XDG_CONFIG_HOME': '${directory.path}/config',
    'NO_COLOR': '1',
    'TERM': 'xterm-256color',
    // The fake's children default to codex, which must never start.
    'CHORD_FAKE_CHILD_RUNTIME': 'fake',
  };

  // The records under [state], by path.
  Set<String> recordsIn(Directory state) => state.existsSync()
      ? {
          for (final file in state.listSync(recursive: true))
            if (file is File && file.path.endsWith('.jsonl')) file.path,
        }
      : {};

  // Waits until a record under [state] that is not one of [stale] is the
  // child [name]'s and holds its first prompt, and gives its path; fails,
  // saying [said], if none does within 30 s.
  Future<String> childPrompted(
    Directory state,
    String name,
    Set<String> stale,
    String Function() said,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      for (final path in recordsIn(state).difference(stale)) {
        final lines = const LineSplitter()
            .convert(File(path).readAsStringSync())
            .map((line) {
              try {
                return jsonDecode(line);
              } on FormatException {
                return null;
              }
            })
            .whereType<Map<String, Object?>>()
            .toList();
        if (lines.any((l) => l['type'] == 'session' && l['name'] == name) &&
            lines.any((l) => l['type'] == 'prompt')) {
          return path;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('child $name never started within 30 s: ${said()}');
  }

  group('tester CTUI-115: current record readiness', () {
    test(
      'stale, split and partial records wait for one complete child',
      () async {
        final state = Directory('${directory.path}/tester-readiness')
          ..createSync();
        final staleFile = File('${state.path}/old.jsonl')
          ..writeAsStringSync(
            '${jsonEncode({'type': 'session', 'name': 'parser'})}\n'
            '${jsonEncode({'type': 'prompt'})}\n',
          );
        final stale = {staleFile.path};
        File(
          '${state.path}/prompt-only.jsonl',
        ).writeAsStringSync('${jsonEncode({'type': 'prompt'})}\n');
        final current = File('${state.path}/current.jsonl')
          ..writeAsStringSync(
            '${jsonEncode({'type': 'session', 'name': 'parser'})}\n'
            '{"type":"prompt"',
          );
        var completed = false;
        final timer = Timer(const Duration(milliseconds: 60), () {
          current.writeAsStringSync(
            '${jsonEncode({'type': 'session', 'name': 'parser'})}\n'
            '${jsonEncode({'type': 'prompt'})}\n',
          );
          completed = true;
        });
        addTearDown(timer.cancel);
        final found = await childPrompted(
          state,
          'parser',
          stale,
          () => 'fixture',
        );
        expect(completed, isTrue);
        expect(found, current.path);
      },
    );
  });

  // The clear retires main's first session in the window's zone, and its
  // close fails there; the signal's leave closes that acquisition from
  // chord's zone (the _OwnedAgent close it awaits, which the session's,
  // the conversation's and the clear's retirement all lead to).
  test(
    'the window dies by SIGHUP when its pty closes after a clear whose '
    'close failed',
    () async {
      final windowGroup = File('${directory.path}/clear-window.pgid');
      String tcl(String value) =>
          '[encoding convertfrom utf-8 [binary format H* {${utf8.encode(value).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}}]]';
      final argv = [
        chord,
        'fake',
        '--agent-command',
        fakeAgentCommand(null, ['--step-ms', '0']).map(shellWord).join(' '),
      ];
      final script = File('${directory.path}/clear.exp')
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
send "/clear\\r"
# The retired session's agent stops (stdin ended) and its close fails.
after 3000
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
        environment: env(),
        includeParentEnvironment: false,
      );
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      addTearDown(
        () => cleanupNativeSmoke(
          driver: process,
          groupIds: () => [
            if (windowGroup.existsSync())
              int.parse(windowGroup.readAsStringSync().trim()),
          ],
        ),
      );
      final code = await process.exitCode.timeout(const Duration(seconds: 50));
      final transcript = '${await output}${await errors}';
      expect(code, 0, reason: transcript);
      expect(transcript, contains('CHILDKILLED SIGHUP'));
    },
    skip: !hasExpect ? 'expect is not installed' : fakeAgent.reason ?? false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // A child's tool call comes through chord's server, in chord's zone; the
  // way out, in this server's own, waits for what it began. close_agent: the
  // child's close (OpenAgents' and the session entry's), a monitor's stop
  // beside it; unkept, the stray failure crashed chord before main's close
  // was said. clear_agent: the child's retirement, which its close at the
  // way out waits for; unkept, the way out was held to its deadline, said
  // as "not settled".
  for (final (tool, prompts, failures) in [
    ('close_agent', ['agentcost', 'agentclose', 'monitor'], equals(2)),
    ('clear_agent', ['agentfail', 'agentclearonly'], greaterThanOrEqualTo(2)),
  ]) {
    test(
      'chord acp leaves at EOF well inside its deadline after $tool '
      'on a child whose close failed',
      () async {
        // A state of the case's own, and a parser record from before it
        // there, which must not pass for its child's start.
        final state = Directory('${directory.path}/state-$tool')
          ..createSync(recursive: true);
        final planted = File('${state.path}/stale.jsonl')
          ..writeAsStringSync(
            '${[
              {'type': 'session', 'name': 'parser'},
              {'type': 'prompt', 'prompt': 'before'},
            ].map(jsonEncode).join('\n')}\n',
          );
        final stale = recordsIn(state);
        expect(stale, {planted.path});
        final process = await Process.start(
          chord,
          [
            'acp',
            'fake',
            '--agent-command',
            fakeAgentCommand(null, ['--step-ms', '0']).map(shellWord).join(' '),
          ],
          workingDirectory: directory.path,
          environment: env(state: 'state-$tool'),
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
        final out = StringBuffer();
        final stderr = StringBuffer();
        process.stdout.transform(utf8.decoder).listen(out.write);
        process.stderr.transform(utf8.decoder).listen(stderr.write);
        void send(Map<String, Object?> message) =>
            process.stdin.writeln(jsonEncode(message));
        Future<Map<String, Object?>> answer(int id) async {
          final deadline = DateTime.now().add(const Duration(seconds: 40));
          while (DateTime.now().isBefore(deadline)) {
            final text = '$out';
            final ended = text.substring(0, text.lastIndexOf('\n') + 1);
            for (final line in const LineSplitter().convert(ended)) {
              if (line.isEmpty) continue;
              final message = jsonDecode(line) as Map<String, Object?>;
              if (message['id'] == id && !message.containsKey('method')) {
                return message;
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          fail('no answer to $id: $out $stderr');
        }

        send({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': 1},
        });
        await answer(1);
        send({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'session/new',
          'params': {'cwd': directory.path, 'mcpServers': <Object?>[]},
        });
        final sessionId =
            ((await answer(2))['result'] as Map?)?['sessionId'] as String? ??
            fail('no session: $out $stderr');
        var id = 3;
        for (final prompt in prompts) {
          send({
            'jsonrpc': '2.0',
            'id': id,
            'method': 'session/prompt',
            'params': {
              'sessionId': sessionId,
              'prompt': [
                {'type': 'text', 'text': prompt},
              ],
            },
          });
          await answer(id++);
          // open_agent answers before the child's session is up; a child
          // closed while it starts gives up its start, whose failure is the
          // start's, not the close's. Its record has its first prompt only
          // once its session/new was answered and that prompt went out.
          if (prompt == prompts.first) {
            final record = await childPrompted(
              state,
              'parser',
              stale,
              () => '$out $stderr',
            );
            expect(record, isNot(planted.path));
          }
          // The cleared session's close is under way, and fails, before EOF.
          if (prompt == 'agentclearonly') {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
        await process.stdin.close();
        final started = DateTime.now();
        final code = await process.exitCode.timeout(
          const Duration(seconds: 30),
        );
        final took = DateTime.now().difference(started);
        // The closes failed, so the way out is unclean, and says so.
        expect(code, 1, reason: '$stderr');
        // Main's close and the child's both failed, and both are said.
        expect(
          'did not exit after SIGKILL'.allMatches('$stderr').length,
          failures,
          reason: '$stderr',
        );
        expect('$stderr', isNot(contains('not settled')));
        expect(took, lessThan(const Duration(seconds: 10)), reason: '$stderr');
      },
      skip: fakeAgent.reason ?? false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

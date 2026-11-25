import 'dart:convert';
import 'dart:io';

import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/dev.dart' show shellWord;
import 'fake.dart';
import 'native_smoke_cleanup.dart';

const _id = '22222222-2222-4222-8222-222222222222';

String _tcl(String value) =>
    '[encoding convertfrom utf-8 [binary format H* {${utf8.encode(value).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}}]]';

/// Drives the native launcher through a real PTY with only an owned fake.
Future<void> nativeResumeSmoke(
  String executable,
  Directory parent,
  String route,
) async {
  // The launcher's working directory is the real path (/private/var on
  // macOS), so the record names it as the process will see it.
  final root = Directory(
    (await Directory(
      parent.path,
    ).createTemp('resume-$route-')).resolveSymbolicLinksSync(),
  );
  final cwd = await Directory(p.join(root.path, 'project')).create();
  final state = p.join(root.path, 'state', 'chord');
  final record = File(p.join(recordsDir(state), 'earlier.jsonl'));
  await record.parent.create(recursive: true);
  final prefix = [
    {
      'type': 'session',
      'version': 1,
      'sessionId': _id,
      'agent': 'fake',
      'cwd': cwd.path,
      'at': 1.25,
    },
    {
      'type': 'prompt',
      'turnId': 'past',
      'prompt': 'Earlier saved native request',
      'images': 0,
      'at': 2.5,
    },
    {
      'type': 'update',
      'turnId': 'past',
      'update': {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Local native history.'},
      },
    },
    {
      'type': 'result',
      'turnId': 'past',
      'result': {'status': 'completed', 'stopReason': 'end_turn'},
    },
  ].map(encodeRecord).join();
  await record.writeAsString(prefix);
  final before = File(p.join(root.path, 'before'));
  final after = File(p.join(root.path, 'after'));
  final windowGroup = File(p.join(root.path, 'window.pgid'));
  final agentGroups = File(p.join(root.path, 'agents.pgid'));
  final command = [
    'sh',
    '-c',
    r'echo $$ >> "$1"; log="$2/requests-$$.jsonl"; shift 2; tee "$log" | "$@"',
    'fake',
    agentGroups.path,
    root.path,
    ...fakeAgentCommand(null, ['--step-ms', '0']),
  ].map(shellWord).join(' ');
  final argv = [
    'sh',
    '-c',
    r'''before=$1; after=$2; shift 2
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
    ...switch (route) {
      'continue' => ['-c'],
      'id' || 'refusal' => ['-r', _id],
      'picker' || 'cancel' => ['-r'],
      _ => <String>[],
    },
  ];
  final steps = switch (route) {
    'cancel' => 'awaitText "Resume a session"\nsend "\\x03"',
    // One word: the failure line breaks the id after a hyphen at 80
    // columns, as the original's does, and the renderer's diff paint moves
    // the cursor between the words of a row, so no phrase or whole id comes
    // as one run of bytes.
    'refusal' => 'awaitText "found:"\nsend "\\x03\\x03"',
    _ => [
      if (route == 'picker') ...['awaitText "Resume a session"', 'send "\\r"'],
      if (route == 'overlay') ...[
        'awaitText "Fake Large"',
        'send "/resume\\r"',
        'awaitText "Resume a session"',
        'send "\\r"',
      ],
      'awaitText "history."',
      'send "opened\\r"',
      'awaitText "session/load"',
      'send "\\x04"',
    ].join('\n'),
  };
  final script = File(p.join(root.path, 'drive.exp'));
  await script.writeAsString('''
set timeout 20
proc awaitText {text} {
  expect {
    -exact \$text {return}
    timeout {exit 90}
    eof {exit 91}
  }
}
set command [list ${argv.map(_tcl).join(' ')}]
spawn -noecho {*}\$command
set groupfile [open ${_tcl(windowGroup.path)} w]
puts \$groupfile [exp_pid]
close \$groupfile
stty rows 24 columns 80 < \$spawn_out(slave,name)
$steps
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
    workingDirectory: cwd.path,
    environment: {
      'HOME': root.path,
      'XDG_STATE_HOME': p.join(root.path, 'state'),
      'TMPDIR': root.path,
      'NO_COLOR': '1',
      'TERM': 'xterm-256color',
      if (route == 'refusal') 'CHORD_FAKE_REFUSE_LOAD': '1',
    },
  );
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  List<int> groups() => [
    for (final file in [windowGroup, agentGroups])
      if (file.existsSync())
        for (final line in file.readAsLinesSync()) int.parse(line.trim()),
  ];
  try {
    final code = await process.exitCode.timeout(const Duration(seconds: 45));
    if (code != 0) {
      await cleanupNativeSmoke(driver: process, groupIds: groups);
    }
    final transcript =
        '${await output.timeout(const Duration(seconds: 3))}${await errors.timeout(const Duration(seconds: 3))}';
    expect(code, 0, reason: transcript);
    expect(before.readAsStringSync(), after.readAsStringSync());
    expect(transcript, contains('\x1b[?1049l'));
    final bytes = await record.readAsString();
    expect(bytes, startsWith(prefix));
    if (route == 'cancel' || route == 'refusal') {
      expect(bytes, prefix);
      expect(agentGroups.existsSync(), route == 'refusal');
    } else {
      // The quit line names chord's own record id (CTUI-176), the file's
      // name, not the agent's session id.
      expect(transcript, contains('--resume ${recordId(record.path)}'));
      expect(bytes.substring(prefix.length), contains('"prompt":"opened"'));
      final summaries = await readRecords(state);
      expect(summaries, hasLength(1));
      expect(summaries.single.sessionId, _id);
      expect(summaries.single.cwd, cwd.path);
    }
    final requests = <Map<String, Object?>>[
      for (final file in root.listSync().whereType<File>())
        if (p.basename(file.path).startsWith('requests-'))
          for (final line in file.readAsLinesSync())
            jsonDecode(line) as Map<String, Object?>,
    ];
    final loads = requests.where((r) => r['method'] == 'session/load');
    if (route == 'cancel') {
      expect(requests, isEmpty);
    } else {
      expect(loads.single['params'], {
        'sessionId': _id,
        'cwd': cwd.path,
        // chord's own server, the window's main admitted to it.
        'mcpServers': [
          allOf(
            containsPair('type', 'http'),
            containsPair('name', 'chord'),
            containsPair(
              'url',
              matches(RegExp(r'^http://127\.0\.0\.1:\d+/mcp$')),
            ),
          ),
        ],
      });
      final prompts = requests.where((r) => r['method'] == 'session/prompt');
      if (route == 'refusal') {
        expect(prompts, isEmpty);
      } else {
        expect((prompts.single['params'] as Map)['sessionId'], _id);
      }
    }
    expect(await nativeSmokeGroups(groups().toSet()), isEmpty);
  } finally {
    await cleanupNativeSmoke(driver: process, groupIds: groups);
    await root.delete(recursive: true);
  }
}

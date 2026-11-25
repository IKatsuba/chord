// chord's server from an AOT binary answers as it does under `dart run`.
@Tags(['compile'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'mcp_wire.dart';

void main() {
  late Directory directory;
  late Process served;
  late Map<String, Object?> said;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('chord-serve-native-');
    final binary = '${directory.path}/serve_chord';
    final build = await Process.run('nice', [
      '-n',
      '19',
      Platform.resolvedExecutable,
      'compile',
      'exe',
      'test/fixtures/serve_chord.dart',
      '-o',
      binary,
    ]);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
    served = await Process.start(binary, []);
    said =
        jsonDecode(
              await served.stdout
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .first,
            )
            as Map<String, Object?>;
  });

  tearDownAll(() async {
    await served.stdin.close();
    expect(await served.exitCode, 0);
    directory.deleteSync(recursive: true);
  });

  test('admission, per-token tools, a refusal and an answer, from the '
      'binary', () async {
    final url = said['url'] as String;
    final person = said['person'] as String;
    final task = said['task'] as String;
    expect((await post(url, initialize(), token: 'nobody')).status, 401);
    final main = await open(url, person);
    expect((main.result['capabilities'] as Map)['tools'], {
      'listChanged': true,
    });
    final mains = await call(url, person, main.session, 'tools/list');
    expect(
      [for (final t in mains['tools'] as List) (t as Map)['name']],
      [
        'list_agents',
        'get_budgets',
        'list_sessions',
        'list_teams',
        'spawn_task',
        'open_agent',
        'run_team',
        'propose_team',
        'settings',
        'send_message',
        'close_agent',
        'clear_agent',
        'monitor',
        'stop_monitor',
        'list_monitors',
      ],
    );
    final tasks = await open(url, task);
    final listed = await call(url, task, tasks.session, 'tools/list');
    expect(
      [for (final t in listed['tools'] as List) (t as Map)['name']],
      ['send_message'],
    );
    final refused = await call(url, task, tasks.session, 'tools/call', {
      'name': 'send_message',
      'arguments': {'text': 'done'},
    });
    expect(refused['isError'], isTrue);
    expect(refused['content'], [
      {'type': 'text', 'text': 'no children here'},
    ]);
    final ended = await call(url, person, main.session, 'tools/call', {
      'name': 'close_agent',
      'arguments': {'to': 'scan'},
    });
    expect(ended['structuredContent'], {'ended': 'scan'});
  });
}

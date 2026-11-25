// chord's `settings` tool over `chord acp`, on the fake, as the original's
// acp_agent.ts wires it: each session reads chord's checked settings, and a
// change is asked of the client as session/request_permission, its detail
// as the call's text, one box shared by every session.
@Tags(['fake_agent'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord/server/server.dart' show serveChord;
import 'package:chord/server/tools.dart' show settingsBoxHeld;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'acp_client.dart';
import 'fixtures/fake_harness.dart';

/// `chord acp` with chord's server, its user's file under a temporary home
/// holding [text].
Future<({AcpClient client, String file})> _client(String text) async {
  final home = Directory.systemTemp.createTempSync('chord-acp-settings-');
  addTearDown(() => home.deleteSync(recursive: true));
  final file = p.join(home.path, '.config', 'chord', 'settings.json');
  File(file)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  final server = await serveChord();
  addTearDown(server.close);
  final client = AcpClient(
    server: server,
    configHome: p.join(home.path, '.config'),
    home: home.path,
  );
  await client.initialize();
  return (client: client, file: file);
}

final _shownFile = '~${p.join('/', '.config', 'chord', 'settings.json')}';

/// What the fake said the settings call answered: the text of its call's
/// last update.
String _answered(AcpClient client) {
  final updates = [
    for (final message in client.lines.messages)
      if (message['method'] == 'session/update')
        (message['params'] as Map)['update'] as Map,
  ];
  final done = updates.lastWhere(
    (update) => update['sessionUpdate'] == 'tool_call_update',
  );
  final content = (done['content'] as List).single as Map;
  return (content['content'] as Map)['text'] as String;
}

Future<int> _prompt(AcpClient client, String session, String text) async =>
    client.ask('session/prompt', {
      'sessionId': session,
      'prompt': [
        {'type': 'text', 'text': text},
      ],
    });

void main() {
  final skip = fakeAgentSkip;

  test('a read answers the checked settings', () async {
    final (:client, :file) = await _client('{"theme":"dark","nope":1}');
    final session = await client.newSession();
    await client.answer(await _prompt(client, session, 'settingsread'));
    final answer = jsonDecode(_answered(client)) as Map;
    expect(answer['user'], {'theme': 'dark'});
    expect(answer['problems'], [
      {'file': _shownFile, 'message': '1 key ignored'},
    ]);
    expect(
      client.lines.messages.any(
        (m) => m['method'] == 'session/request_permission',
      ),
      isFalse,
    );
    expect(File(file).readAsStringSync(), '{"theme":"dark","nope":1}');
  }, skip: skip);

  for (final (pick, saved) in [('yes', true), ('no', false)]) {
    test('a set is asked of the client as request_permission and $pick '
        '${saved ? 'writes it' : 'writes nothing'}', () async {
      final (:client, :file) = await _client('{"theme":"dark"}');
      final session = await client.newSession();
      final turn = await _prompt(client, session, 'settingstheme');
      final asked = await client.until(
        () => client.lines.messages
            .where((m) => m['method'] == 'session/request_permission')
            .firstOrNull,
      );
      final params = asked['params'] as Map;
      expect(params['sessionId'], session);
      final toolCall = params['toolCall'] as Map;
      expect(toolCall['title'], 'Settings(theme)');
      expect(toolCall['content'], [
        {
          'type': 'content',
          'content': {
            'type': 'text',
            'text': 'In $_shownFile: "dark" becomes "light".',
          },
        },
      ]);
      expect(
        [
          for (final option in (params['options'] as List).cast<Map>())
            (option['optionId'], option['name'], option['kind']),
        ],
        [
          ('yes', 'Yes, in $_shownFile', 'allow_once'),
          ('no', 'No, tell fake what to change', 'reject_once'),
        ],
      );
      client.send({
        'jsonrpc': '2.0',
        'id': asked['id'],
        'result': {
          'outcome': {'outcome': 'selected', 'optionId': pick},
        },
      });
      await client.answer(turn);
      final answer = jsonDecode(_answered(client)) as Map;
      expect(
        (answer['saved'], answer['before'], answer['after']),
        (saved, 'dark', 'light'),
      );
      expect(jsonDecode(File(file).readAsStringSync()), {
        'theme': saved ? 'light' : 'dark',
      });
    }, skip: skip);
  }

  group('CTUI-79 tester: shared ACP settings box', () {
    List<Map<String, Object?>> asks(AcpClient client) => [
      for (final m in client.lines.messages)
        if (m['method'] == 'session/request_permission') m,
    ];
    void choose(AcpClient client, Map<String, Object?> ask, String choice) =>
        client.send({
          'jsonrpc': '2.0',
          'id': ask['id'],
          'result': {
            'outcome': {'outcome': 'selected', 'optionId': choice},
          },
        });

    test(
      'a second session is refused until the first box settles, then accepted',
      () async {
        final (:client, :file) = await _client('{"theme":"dark"}');
        final a = await client.newSession(), b = await client.newSession();
        final first = await _prompt(client, a, 'settingstheme');
        final ask = await client.until(() => asks(client).firstOrNull);
        expect((ask['params'] as Map)['sessionId'], a);
        final blocked = await _prompt(client, b, 'settingsvim');
        await client.answer(blocked);
        final updates = [
          for (final m in client.lines.messages)
            if (m['method'] == 'session/update' &&
                (m['params'] as Map)['sessionId'] == b)
              (m['params'] as Map)['update'] as Map,
        ];
        final done = updates.lastWhere(
          (u) => u['sessionUpdate'] == 'tool_call_update',
        );
        expect(
          (((done['content'] as List).single as Map)['content'] as Map)['text'],
          settingsBoxHeld,
        );
        expect(asks(client), hasLength(1));
        expect(jsonDecode(File(file).readAsStringSync()), {'theme': 'dark'});
        choose(client, ask, 'yes');
        await client.answer(first);
        expect(jsonDecode(File(file).readAsStringSync()), {'theme': 'light'});
        final retry = await _prompt(client, b, 'settingsvim');
        final second = await client.until(
          () => asks(client).length == 2 ? asks(client).last : null,
        );
        expect((second['params'] as Map)['sessionId'], b);
        choose(client, second, 'yes');
        await client.answer(retry);
        expect(jsonDecode(File(file).readAsStringSync()), {
          'theme': 'light',
          'editorMode': 'vim',
        });
        expect(asks(client), hasLength(2));
      },
      skip: skip,
    );

    test(
      'cancelling a turn withdraws its box and a late yes writes nothing',
      () async {
        final (:client, :file) = await _client('{"theme":"dark"}');
        final session = await client.newSession();
        final turn = await _prompt(client, session, 'settingstheme');
        final ask = await client.until(() => asks(client).firstOrNull);
        client.send({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': session},
        });
        await client.answer(turn);
        choose(client, ask, 'yes');
        await client.answer(await _prompt(client, session, 'settingsread'));
        expect(jsonDecode(File(file).readAsStringSync()), {'theme': 'dark'});
      },
      skip: skip,
    );
  });
}

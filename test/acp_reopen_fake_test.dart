// chord acp's session/load and session/resume on the original's fake: a
// record the window wrote, reopened by chord acp and read back by the
// window; an unrecorded id the fake replays itself; a resume; a pending
// rename.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'acp_client.dart';
import 'fixtures/fake_harness.dart';

const _id = '0b6f7c2e-1d3a-4c5b-9e8f-7a6b5c4d3e2f';

Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};

/// A record as the window writes one: a turn, its words and a rename.
String _writeRecord(
  AcpClient client, {
  List<Map<String, Object?>> more = const [],
}) {
  final records = Directory(recordsDir(client.stateDir))
    ..createSync(recursive: true);
  final path = p.join(records.path, '$_id.jsonl');
  File(path).writeAsStringSync(
    [
      {
        'type': 'session',
        'version': 1,
        'sessionId': _id,
        'agent': 'fake',
        'cwd': client.cwd,
        'at': 1000,
      },
      {
        'type': 'prompt',
        'turnId': 't1',
        'prompt': 'Fix the parser',
        'images': 0,
        'at': 2000,
      },
      {
        'type': 'update',
        'turnId': 't1',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': _text('On it.'),
        },
      },
      {
        'type': 'result',
        'turnId': 't1',
        'result': {'status': 'completed', 'stopReason': 'end_turn'},
      },
      {'type': 'renamed', 'title': 'Parser fix', 'at': 3000},
      ...more,
    ].map(encodeRecord).join(),
  );
  return path;
}

/// What went to the client before the answer to [id]: each update's kind,
/// with its text or title where it has one.
List<String> _before(AcpClient client, int id) => [
  for (final message in client.lines.messages.takeWhile(
    (m) => m['id'] != id || m.containsKey('method'),
  ))
    if (message['method'] == 'session/update')
      switch ((message['params'] as Map)['update'] as Map) {
        {'sessionUpdate': final kind, 'content': {'text': final text}} =>
          '$kind $text',
        {'sessionUpdate': final kind, 'title': final title} => '$kind $title',
        {'sessionUpdate': final kind} => '$kind',
        _ => '?',
      }
    else if (message['method'] case final String method)
      method,
];

Map<String, Object?> _reopen(AcpClient client) => {
  'sessionId': _id,
  'cwd': client.cwd,
  'mcpServers': <Object?>[],
};

void main() {
  final skip = fakeAgentSkip;

  test('a record the window wrote is loaded by chord acp: its past ahead of '
      'the answer, not the fake\'s own; what chord acp adds the window reads '
      'back', () async {
    final client = AcpClient();
    final path = _writeRecord(client);
    await client.initialize();
    final id = client.ask('session/load', _reopen(client));
    final answered = await client.answer(id);
    expect(answered['result'], isNot(contains('sessionId')));
    expect(_before(client, id), [
      'user_message_chunk Fix the parser',
      'agent_message_chunk On it.',
      'session_info_update Parser fix',
    ]);
    expect(client.notified('_chord/session/state'), isEmpty);
    final prompt = await client.request('session/prompt', {
      'sessionId': _id,
      'prompt': [_text('text')],
    });
    expect((prompt['result'] as Map)['stopReason'], 'end_turn');
    await client.request('session/close', {'sessionId': _id});
    // The window's own reading of the record: both turns, in order.
    final history = await readRecordedHistory(path);
    expect(
      [
        for (final action in history.actions)
          if (action is PromptAction) action.text,
      ],
      ['Fix the parser', 'text'],
    );
  }, skip: skip);

  test('an id chord never recorded is loaded from the fake\'s own replay, '
      'ahead of the answer', () async {
    final client = AcpClient();
    await client.initialize();
    final id = client.ask('session/load', _reopen(client));
    await client.answer(id);
    expect(_before(client, id).first, 'user_message_chunk tools');
    expect(client.host.sessions.keys, [_id]);
  }, skip: skip);

  test('a resume replays nothing', () async {
    final client = AcpClient(flags: ['--resume-only']);
    _writeRecord(client);
    await client.initialize();
    final id = client.ask('session/resume', _reopen(client));
    final answered = await client.answer(id);
    expect(answered['result'], isNot(contains('sessionId')));
    expect(
      _before(client, id).where((s) => s.contains('message_chunk')),
      isEmpty,
    );
  }, skip: skip);

  test('a rename chord acp kept pending goes to an agent that takes titles '
      'when the session is loaded', () async {
    final client = AcpClient(flags: ['--set-title', 'echo']);
    final path = _writeRecord(
      client,
      more: [
        {'type': 'renamed', 'title': 'Later', 'at': 4000, 'pending': true},
      ],
    );
    await client.initialize();
    await client.request('session/load', _reopen(client));
    final kept = await client.until(() {
      final lines = File(path).readAsLinesSync();
      return lines.last.contains('"renamed"') && !lines.last.contains('pending')
          ? lines.last
          : null;
    });
    expect(kept, contains('"title":"Later"'));
  }, skip: skip);

  test(
    'a pending rename an agent never answers leaves the session usable',
    () async {
      final client = AcpClient(flags: ['--set-title', 'hang']);
      _writeRecord(
        client,
        more: [
          {'type': 'renamed', 'title': 'Later', 'at': 4000, 'pending': true},
        ],
      );
      await client.initialize();
      await client.request('session/load', _reopen(client));
      final prompt = await client.request('session/prompt', {
        'sessionId': _id,
        'prompt': [_text('text')],
      });
      expect((prompt['result'] as Map)['stopReason'], 'end_turn');
    },
    skip: skip,
  );

  test('what the record says was left open goes with the answer, a load\'s '
      'or a resume\'s', () async {
    for (final (method, flags) in [
      ('session/load', const <String>[]),
      ('session/resume', ['--resume-only']),
    ]) {
      final client = AcpClient(flags: flags);
      _writeRecord(
        client,
        more: [
          {
            'type': 'left_open',
            'agents': [
              {'name': 'tester'},
            ],
          },
        ],
      );
      await client.initialize();
      final answered = await client.request(method, _reopen(client));
      expect(((answered['result'] as Map)['_meta'] as Map)['chord/left_open'], [
        {'name': 'tester'},
      ], reason: method);
    }
  }, skip: skip);
}

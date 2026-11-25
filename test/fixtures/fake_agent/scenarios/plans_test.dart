import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../options.dart' as options;
import '../rpc.dart';
import '../turn.dart';
import 'plans.dart';

final class _PlanClient {
  _PlanClient(Object? reply) {
    connection = Connection.serve(
      input.stream,
      (bytes) {
        final message = jsonDecode(utf8.decode(bytes)) as Map;
        messages.add(message);
        if (message.containsKey('id')) {
          input.add(
            utf8.encode(
              '${jsonEncode({'jsonrpc': '2.0', 'id': message['id'], 'result': reply})}\n',
            ),
          );
        }
      },
      () async {},
      requests: {},
      notifications: {},
    );
  }

  final input = StreamController<List<int>>();
  final messages = <Map>[];
  late final Connection connection;

  List<String> get text => [
    for (final message in messages)
      if (message['method'] == 'session/update')
        if ((message['params'] as Map)['update'] case {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'text': final String text},
        })
          text,
  ];

  Future<void> close() async {
    await input.close();
    await connection.closed;
  }
}

void main() {
  group('tester: CTUI-147 plan reply shapes and remembered answers', () {
    setUp(() => options.args = ['--step-ms', '0']);
    for (final scenario in ['cursorplan', 'cursorplanearly', 'grokplan']) {
      for (final reply in <Object?>[
        null,
        true,
        [0, null, false],
      ]) {
        test('$scenario retains ${jsonEncode(reply)} whole', () async {
          final client = _PlanClient(reply);
          addTearDown(client.close);
          final sessionId = 'tester-$scenario-${jsonEncode(reply)}';
          final turn = Turn(
            client.connection.client,
            sessionId,
            Aborter().signal,
          );
          expect(await plans[scenario]!(turn), 'end_turn');
          final expected = 'Plan answer: ${stringify(reply)}';
          expect(client.text, [expected]);
          expect(
            await plans['planheard']!(
              Turn(client.connection.client, sessionId, Aborter().signal),
            ),
            'end_turn',
          );
          expect(client.text, [expected, expected]);
        });
      }
    }
  });
}

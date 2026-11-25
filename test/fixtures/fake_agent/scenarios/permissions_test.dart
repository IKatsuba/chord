import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../options.dart' as options;
import '../rpc.dart';
import '../turn.dart';
import 'permissions.dart';

final class _PermissionClient {
  _PermissionClient(this.outcome) {
    connection = Connection.serve(
      input.stream,
      (bytes) {
        final message = (jsonDecode(utf8.decode(bytes)) as Map)
            .cast<String, Object?>();
        messages.add(message);
        if (message['method'] == 'session/request_permission') {
          input.add(
            utf8.encode(
              '${jsonEncode({
                'jsonrpc': '2.0',
                'id': message['id'],
                'result': {'outcome': outcome},
              })}\n',
            ),
          );
        }
      },
      () async {},
      requests: {},
      notifications: {},
    );
  }

  final Map<String, Object?> outcome;
  final input = StreamController<List<int>>();
  final messages = <Map<String, Object?>>[];
  late final Connection connection;

  Future<void> close() async {
    await input.close();
    await connection.closed;
  }
}

void main() {
  group('tester: CTUI-147 permission refusal and cancellation', () {
    setUp(() => options.args = ['--step-ms', '0']);
    for (final scenario in [
      'permission',
      'twins',
      'multidiffask',
      'mcpask',
      'bigask',
    ]) {
      for (final cancelled in [false, true]) {
        test(
          '$scenario ${cancelled ? 'cancelled' : 'denied'} keeps the tool outcome',
          () async {
            final client = _PermissionClient(
              cancelled
                  ? {'outcome': 'cancelled'}
                  : {'outcome': 'selected', 'optionId': 'deny'},
            );
            addTearDown(client.close);
            final turn = Turn(
              client.connection.client,
              'tester-permission',
              Aborter().signal,
            );
            expect(
              await permissionPlays[scenario]!(turn),
              cancelled ? 'cancelled' : 'end_turn',
            );
            final updates = [
              for (final message in client.messages)
                if (message['method'] == 'session/update')
                  ((message['params'] as Map)['update'] as Map),
            ];
            expect(updates.first['sessionUpdate'], 'tool_call');
            expect(updates.first['status'], 'pending');
            if (cancelled) {
              expect(updates, hasLength(1));
            } else {
              final finished = updates.singleWhere(
                (update) => update['sessionUpdate'] == 'tool_call_update',
              );
              expect(finished['toolCallId'], updates.first['toolCallId']);
              expect(finished['status'], 'failed');
              expect(
                (updates.last['content'] as Map)['text'],
                'Permission: deny.',
              );
            }
            final request = client.messages.singleWhere(
              (message) => message['method'] == 'session/request_permission',
            );
            final params = request['params'] as Map;
            expect(params['sessionId'], 'tester-permission');
            expect(
              (params['options'] as List).where(
                (option) => (option as Map)['optionId'] == 'deny',
              ),
              hasLength(1),
            );
          },
        );
      }
    }
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../options.dart' as options;
import '../rpc.dart';
import '../sessions.dart';
import '../turn.dart';
import 'cycles.dart';

final class _CycleClient {
  _CycleClient() {
    connection = Connection.serve(
      input.stream,
      (bytes) {
        final message = jsonDecode(utf8.decode(bytes)) as Map;
        messages.add((message['params'] as Map));
      },
      () async {},
      requests: {},
      notifications: {},
    );
  }

  final input = StreamController<List<int>>();
  final messages = <Map>[];
  late final Connection connection;

  void close() {
    connection.close();
    unawaited(input.close());
  }
}

void main() {
  group('tester: CTUI-147 autonomous cycle boundaries', () {
    setUp(
      () => options.args = [
        '--step-ms',
        '0',
        '--cycle-cost',
        '0.25',
        '--cost-from',
        '2.5',
      ],
    );
    tearDown(() {
      for (final id in [
        'tester-cycle-a',
        'tester-cycle-b',
        'tester-gated-cycle',
      ]) {
        costs.remove(id);
      }
    });

    test('cycle costs accumulate only on their own session', () {
      costs['tester-cycle-b'] = 4;
      expect(cycleUsage('tester-cycle-a')['cost'], {
        'amount': 2.75,
        'currency': 'USD',
      });
      expect(cycleUsage('tester-cycle-b')['cost'], {
        'amount': 4.25,
        'currency': 'USD',
      });
      final next = cycleUsage('tester-cycle-a');
      expect(next['cost'], {'amount': 3.0, 'currency': 'USD'});
      expect(costs['tester-cycle-b'], 4.25);
      expect(next['_meta'], {
        '_claude/origin': {'kind': 'task-notification'},
      });
    });

    test(
      'quiet starts when the turn ends rather than when its play returns',
      () {
        fakeAsync((clock) {
          final client = _CycleClient();
          final turn = Turn(
            client.connection.client,
            'tester-gated-cycle',
            Aborter().signal,
          );
          var returned = false;
          cycles['claudecycle']!(turn).then((_) => returned = true);
          clock.elapse(Duration.zero);
          expect(returned, isTrue);
          expect(client.messages, hasLength(1));
          clock.elapse(const Duration(seconds: 3));
          expect(client.messages, hasLength(1));
          turn.end();
          clock.flushMicrotasks();
          clock.elapse(const Duration(milliseconds: 1499));
          expect(client.messages, hasLength(1));
          clock.elapse(const Duration(milliseconds: 401));
          expect(client.messages, hasLength(4));
          expect(
            client.messages.every(
              (message) => message['sessionId'] == 'tester-gated-cycle',
            ),
            isTrue,
          );
          expect(
            (client.messages.last['update'] as Map)['sessionUpdate'],
            'usage_update',
          );
          client.close();
          clock.flushMicrotasks();
          expect(clock.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'a client closed before quiet receives no cycle or remaining timer',
      () {
        fakeAsync((clock) {
          final client = _CycleClient();
          runCycle(client.connection.client, 'tester-closed-cycle');
          clock.elapse(const Duration(milliseconds: 100));
          client.close();
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 2));
          expect(client.messages, isEmpty);
          expect(clock.nonPeriodicTimerCount, 0);
        });
      },
    );
  });
}

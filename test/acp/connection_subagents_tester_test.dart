import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'connection_test.dart' show Harness;

void main() {
  group('tester connection child cancellation scope', () {
    test(
      'root cancel withdraws known child forms without cancelling another session',
      () {
        fakeAsync((clock) {
          final harness = Harness();
          final tokens = <String, CancellationToken>{};
          Agent? agent;
          connectAgent(
            harness.process,
            onTraffic: harness.traffic.add,
            onPermission: (_, _) => throw StateError('unexpected permission'),
            onElicitation: (raw, token) {
              tokens[raw['sessionId'] as String] = token;
              return Completer<Map<String, Object?>>().future;
            },
          ).then((value) => agent = value);
          clock.flushMicrotasks();
          harness.answer(harness.lastRequest('initialize')['id'], {
            'protocolVersion': 1,
          });
          clock.flushMicrotasks();
          for (final id in ['root', 'child', 'grandchild', 'other']) {
            harness.process.send({
              'jsonrpc': '2.0',
              'id': 'form-$id',
              'method': 'elicitation/create',
              'params': {
                'sessionId': id,
                'mode': 'form',
                'message': id,
                'requestedSchema': {
                  'type': 'object',
                  'properties': <String, Object?>{},
                },
              },
            });
          }
          clock.flushMicrotasks();
          expect(
            tokens.keys,
            containsAll(['root', 'child', 'grandchild', 'other']),
          );
          agent!.cancel('root', subagents: ['child', 'grandchild']);
          clock.flushMicrotasks();
          expect([
            for (final id in ['root', 'child', 'grandchild'])
              tokens[id]!.isCancelled,
          ], everyElement(true));
          expect(tokens['other']!.isCancelled, isFalse);
          final notifications = harness.written
              .where((m) => m['method'] == 'session/cancel')
              .toList();
          expect(notifications, hasLength(1));
          expect(notifications.single['params'], {'sessionId': 'root'});
          agent!.close();
          clock.elapse(const Duration(seconds: 3));
          expect(tokens['other']!.isCancelled, isTrue);
          expect(harness.process.exited, isTrue);
        });
      },
    );
  });
}

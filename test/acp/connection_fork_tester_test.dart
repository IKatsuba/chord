import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'connection_test.dart' show Harness;

void main() {
  group('CTUI-74 tester: fork request ownership', () {
    test('unsupported fork capabilities send no fork request', () {
      for (final offered in [null, false, 0, '']) {
        fakeAsync((async) {
          final harness = Harness();
          final agent = harness.open(
            async,
            init: {
              'protocolVersion': 1,
              'agentCapabilities': {
                'sessionCapabilities': {'fork': offered},
              },
            },
          );
          Object? error;
          agent
              .forkSession(
                ReopenSessionRequest(
                  sessionId: 'source',
                  cwd: '/w',
                  mcpServers: const [],
                ),
              )
              .then<void>(
                (_) => fail('fork accepted'),
                onError: (Object e) => error = e,
              );
          async.flushMicrotasks();
          expect(error, isA<AgentCapabilityError>());
          expect(
            harness.written.where((m) => m['method'] == 'session/fork'),
            isEmpty,
          );
          agent.close();
          async.flushMicrotasks();
        });
      }
    });

    test(
      'overlapping forks retain literal params and pair reversed answers',
      () {
        fakeAsync((async) {
          final harness = Harness();
          final agent = harness.open(
            async,
            init: {
              'protocolVersion': 1,
              'agentCapabilities': {
                'sessionCapabilities': {'fork': <String, Object?>{}},
              },
            },
          );
          final results = <String, String>{};
          for (final source in ['source A', 'source 界🙂']) {
            agent
                .forkSession(
                  ReopenSessionRequest(
                    sessionId: source,
                    cwd: '/w',
                    mcpServers: const [],
                  ),
                )
                .then((result) => results[source] = result.sessionId);
          }
          async.flushMicrotasks();
          final requests = harness.written
              .where((m) => m['method'] == 'session/fork')
              .toList();
          expect(requests, hasLength(2));
          expect((requests[0]['params'] as Map)['sessionId'], 'source A');
          expect((requests[1]['params'] as Map)['sessionId'], 'source 界🙂');
          expect(requests[0]['id'], isNot(requests[1]['id']));
          harness.answer(requests[1]['id'], {'sessionId': 'fork B'});
          harness.answer(requests[0]['id'], {'sessionId': 'fork A'});
          async.flushMicrotasks();
          expect(results, {'source A': 'fork A', 'source 界🙂': 'fork B'});
          agent.close();
          async.flushMicrotasks();
        });
      },
    );

    test(
      'a cancelled fork ignores its late answer and leaves the connection usable',
      () {
        fakeAsync((async) {
          final harness = Harness();
          final agent = harness.open(
            async,
            init: {
              'protocolVersion': 1,
              'agentCapabilities': {
                'sessionCapabilities': {'fork': true},
              },
            },
          );
          final token = CancellationToken();
          Object? failure;
          agent
              .forkSession(
                ReopenSessionRequest(
                  sessionId: 'old',
                  cwd: '/w',
                  mcpServers: const [],
                ),
                cancellationToken: token,
              )
              .then<void>(
                (_) => fail('cancelled fork answered'),
                onError: (Object e) => failure = e,
              );
          async.flushMicrotasks();
          final fork = harness.lastRequest('session/fork');
          token.cancel();
          async.flushMicrotasks();
          expect(failure, isA<CancelledException>());
          harness.answer(fork['id'], {'sessionId': 'late'});
          NewSessionResponse? fresh;
          agent
              .newSession(NewSessionRequest(cwd: '/w', mcpServers: const []))
              .then((value) => fresh = value);
          async.flushMicrotasks();
          harness.answer(harness.lastRequest('session/new')['id'], {
            'sessionId': 'fresh',
          });
          async.flushMicrotasks();
          expect(fresh?.sessionId, 'fresh');
          agent.close();
          async.flushMicrotasks();
        });
      },
    );
  });
}

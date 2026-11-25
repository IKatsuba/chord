import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'connection_test.dart' show Harness;

final _request = SteerRequest(
  sessionId: 'running',
  prompt: [ContentBlock.text('keep the held context')],
  meta: const {
    'steering': {'idleBehavior': 'promptRequired'},
  },
);

void main() {
  group('advertised steering transport', () {
    for (final meta in <Object?>[
      null,
      false,
      'steering',
      {},
      {'steering': null},
      {'steering': true},
      {
        'steering': {'supported': 'true'},
      },
      {
        'steering': {'supported': 1},
      },
      {
        'steering': {'supported': false},
      },
    ]) {
      test('does not infer support from $meta', () {
        fakeAsync((async) {
          final h = Harness();
          final agent = h.open(
            async,
            init: {'protocolVersion': 1, '_meta': meta},
          );
          Object? error;
          agent
              .steer(_request)
              .then<void>((_) {}, onError: (Object e) => error = e);
          async.flushMicrotasks();
          expect(agent.steering, isFalse);
          expect(error, isA<AgentCapabilityError>());
          expect(
            h.written.where((m) => m['method'] == '_session/steering'),
            isEmpty,
          );
          agent.close();
          async.flushMicrotasks();
        });
      });
    }
    test('sends exact extension payload and retains unknown numeric facts', () {
      fakeAsync((async) {
        final h = Harness();
        final agent = h.open(
          async,
          init: {
            'protocolVersion': 1,
            '_meta': {
              'steering': {'supported': true},
            },
          },
        );
        Map<String, Object?>? answer;
        agent.steer(_request).then<void>((value) => answer = value);
        async.flushMicrotasks();
        final wire = h.lastRequest('_session/steering');
        expect(wire['params'], _request.toJson());
        h.answer(wire['id'], {'outcome': 'injected', 'futureFact': 1.5});
        async.flushMicrotasks();
        expect(agent.steering, isTrue);
        expect(answer, {'outcome': 'injected', 'futureFact': 1.5});
        agent.close();
        async.flushMicrotasks();
      });
    });
    for (final before in [true, false]) {
      test(
        '${before ? 'pre' : 'on-wire'} cancellation rejects only the waiter',
        () {
          fakeAsync((async) {
            final h = Harness();
            final agent = h.open(
              async,
              init: {
                'protocolVersion': 1,
                '_meta': {
                  'steering': {'supported': true},
                },
              },
            );
            final token = CancellationToken();
            if (before) token.cancel();
            Object? error;
            var accepted = false;
            agent
                .steer(_request, cancellationToken: token)
                .then<void>(
                  (_) => accepted = true,
                  onError: (Object e) => error = e,
                );
            async.flushMicrotasks();
            final requests = h.written
                .where((m) => m['method'] == '_session/steering')
                .toList();
            expect(requests, hasLength(before ? 0 : 1));
            token.cancel();
            async.flushMicrotasks();
            if (!before) {
              h.answer(requests.single['id'], {'outcome': 'injected'});
            }
            async.flushMicrotasks();
            expect(error, isA<CancelledException>());
            expect(accepted, isFalse);
            agent.close();
            async.flushMicrotasks();
          });
        },
      );
    }
    test(
      'RPC refusal stays a refusal and an exit ends the outstanding wait',
      () {
        fakeAsync((async) {
          final h = Harness();
          final agent = h.open(
            async,
            init: {
              'protocolVersion': 1,
              '_meta': {
                'steering': {'supported': true},
              },
            },
          );
          Object? error;
          agent
              .steer(_request)
              .then<void>((_) {}, onError: (Object e) => error = e);
          async.flushMicrotasks();
          h.process.send({
            'jsonrpc': '2.0',
            'id': h.lastRequest('_session/steering')['id'],
            'error': {'code': -32601, 'message': 'not now'},
          });
          async.flushMicrotasks();
          expect(
            error,
            isA<RpcException>().having((e) => e.code, 'code', -32601),
          );
          error = null;
          agent
              .steer(_request)
              .then<void>((_) {}, onError: (Object e) => error = e);
          async.flushMicrotasks();
          h.process
            ..exit(const Exit(1))
            ..closeStdout()
            ..closeStderr();
          async.elapse(drainBound);
          expect(error, isA<AgentGone>());
          agent.close();
          async.flushMicrotasks();
        });
      },
    );
  });
}

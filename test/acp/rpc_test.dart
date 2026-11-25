import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/rpc.dart';
import 'package:chord/acp/schema.dart';
import 'package:test/test.dart';

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('chord\'s requests', () {
    late List<Map<String, Object?>> sent;
    late ChordRequests chord;

    setUp(() {
      sent = [];
      chord = ChordRequests(sent.add);
    });

    test('a request is written at once and settles with the result', () async {
      final answer = chord.request('session/new', {'cwd': '/w'});
      expect(sent, [
        {
          'jsonrpc': '2.0',
          'method': 'session/new',
          'id': 0,
          'params': {'cwd': '/w'},
        },
      ]);
      chord.response({
        'jsonrpc': '2.0',
        'id': 0,
        'result': {'sessionId': 's'},
      });
      expect(await answer, {'sessionId': 's'});
      chord.request('x', {});
      expect(sent.last['id'], 1);
    });

    test('an error answer fails it with the agent\'s code, message and '
        'data', () async {
      final answer = chord.request('initialize', {});
      chord.response({
        'jsonrpc': '2.0',
        'id': 0,
        'error': {
          'code': -32022,
          'message': 'Unsupported protocol version',
          'data': {
            'supported': [2],
          },
        },
      });
      await expectLater(
        answer,
        throwsA(
          isA<RpcException>()
              .having((e) => e.code, 'code', -32022)
              .having(
                (e) => e.message,
                'message',
                'Unsupported protocol version',
              )
              .having((e) => e.data, 'data', {
                'supported': [2],
              }),
        ),
      );
    });

    test('a notification carries no id', () {
      chord.notify('session/cancel', {'sessionId': 's'});
      expect(sent, [
        {
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': 's'},
        },
      ]);
    });

    test('a token already cancelled sends nothing', () async {
      final token = CancellationToken()..cancel();
      await expectLater(
        chord.request('session/prompt', {}, token: token),
        throwsA(isA<CancelledException>()),
      );
      expect(sent, isEmpty);
    });

    test('a token cancelled while waiting ends the wait, and the late answer '
        'is dropped', () async {
      final token = CancellationToken();
      final answer = chord.request('session/prompt', {}, token: token);
      token.cancel();
      await expectLater(answer, throwsA(isA<CancelledException>()));
      chord.response({
        'jsonrpc': '2.0',
        'id': 0,
        'error': {'code': -32603, 'message': 'late'},
      });
      await pump();
    });

    test('an answer before the token is cancelled wins', () async {
      final token = CancellationToken();
      final answer = chord.request('session/new', {}, token: token);
      chord.response({'jsonrpc': '2.0', 'id': 0, 'result': {}});
      expect(await answer, <String, Object?>{});
      token.cancel();
    });

    test('an answer to an id chord is not waiting on, or of another JSON '
        'type, is dropped', () async {
      final answer = chord.request('session/new', {});
      var settled = false;
      answer.then((_) => settled = true);
      chord.response({'jsonrpc': '2.0', 'id': '0', 'result': {}});
      chord.response({'jsonrpc': '2.0', 'id': 7, 'result': {}});
      chord.response({'jsonrpc': '2.0', 'id': 7});
      await pump();
      expect(settled, isFalse);
      chord.response({'jsonrpc': '2.0', 'id': 0, 'result': {}});
      await answer;
    });

    test('close fails every waiting request', () async {
      final first = chord.request('a', {});
      final second = chord.request('b', {});
      await chord.close();
      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
      await expectLater(chord.request('c', {}), throwsStateError);
      expect(sent, hasLength(2));
    });

    group('a malformed answer to a waiting request fails it -32600, as the '
        'SDK does', () {
      for (final (name, response) in [
        ('neither result nor error', {'jsonrpc': '2.0', 'id': 0}),
        (
          'both result and error',
          {
            'jsonrpc': '2.0',
            'id': 0,
            'result': {},
            'error': {'code': 1, 'message': 'x'},
          },
        ),
        ('jsonrpc missing', {'id': 0, 'result': {}}),
        (
          'an error without an int code',
          {
            'jsonrpc': '2.0',
            'id': 0,
            'error': {'code': '1', 'message': 'x'},
          },
        ),
        (
          'an error without a string message',
          {
            'jsonrpc': '2.0',
            'id': 0,
            'error': {'code': 1},
          },
        ),
        (
          'an error that is not an object',
          {'jsonrpc': '2.0', 'id': 0, 'error': 'x'},
        ),
      ]) {
        test(name, () async {
          final answer = chord.request('session/new', {});
          chord.response(response);
          await expectLater(
            answer,
            throwsA(
              isA<RpcException>()
                  .having((e) => e.code, 'code', -32600)
                  .having((e) => e.message, 'message', 'Invalid request')
                  .having((e) => e.data, 'data', response),
            ),
          );
        });
      }

      for (final code in [1.5, double.infinity]) {
        test('an error code of $code', () async {
          final response = {
            'jsonrpc': '2.0',
            'id': 0,
            'error': {'code': code, 'message': 'x'},
          };
          final answer = chord.request('session/new', {});
          chord.response(response);
          await expectLater(
            answer,
            throwsA(
              isA<RpcException>()
                  .having((e) => e.code, 'code', -32600)
                  .having((e) => e.data, 'data', response),
            ),
          );
        });
      }

      test('an integral error code written as 1.0 is the integer 1', () async {
        final answer = chord.request('session/new', {});
        chord.response({
          'jsonrpc': '2.0',
          'id': 0,
          'error': {'code': -32000.0, 'message': 'Authentication required'},
        });
        await expectLater(
          answer,
          throwsA(
            isA<RpcException>()
                .having((e) => e.code, 'code', -32000)
                .having((e) => e.message, 'message', 'Authentication required'),
          ),
        );
      });

      test('one to an id chord is not waiting on is dropped', () async {
        final answer = chord.request('session/new', {});
        var settled = false;
        answer.then((_) => settled = true, onError: (_) => settled = true);
        chord.response({'jsonrpc': '2.0', 'id': 5});
        await pump();
        expect(settled, isFalse);
      });
    });
  });

  group('route', () {
    late List<Map<String, Object?>> sent;
    late List<Map<String, Object?>> asked;
    late ChordRequests chord;
    late AgentRequests agent;

    setUp(() {
      sent = [];
      asked = [];
      chord = ChordRequests(sent.add);
      agent = AgentRequests(
        send: sent.add,
        closing: CancellationToken(),
        onPermission: (request, token) {
          asked.add(request.toJson());
          return Completer<RequestPermissionResponse>().future;
        },
      );
    });

    test('a response to chord\'s requests, a request to the dispatcher, '
        'other notifications nowhere', () async {
      final answer = chord.request('session/new', {});
      route(
        {
          'jsonrpc': '2.0',
          'method': 'session/update',
          'params': {'sessionId': 's'},
        },
        chord: chord,
        agent: agent,
      );
      route(
        {
          'jsonrpc': '2.0',
          'id': 0,
          'result': {'sessionId': 's'},
        },
        chord: chord,
        agent: agent,
      );
      expect(await answer, {'sessionId': 's'});
      route(_permission(9), chord: chord, agent: agent);
      expect(asked, hasLength(1));
      expect(agent.running, 1);
      route(
        {
          'jsonrpc': '2.0',
          'method': cancelRequestMethod,
          'params': {'requestId': 9},
        },
        chord: chord,
        agent: agent,
      );
      expect(agent.running, 0);
      expect(sent.last, {
        'jsonrpc': '2.0',
        'id': 9,
        'result': {
          'outcome': {'outcome': 'cancelled'},
        },
      });
    });
  });

  group('the agent\'s requests', () {
    late List<Map<String, Object?>> sent;
    late CancellationToken closing;
    late Completer<RequestPermissionResponse> handlerAnswer;
    late List<(RequestPermissionRequest, CancellationToken)> asked;
    late Map<String, List<CancellationToken>> held;
    late List<String> released;
    late AgentRequests agent;

    setUp(() {
      sent = [];
      closing = CancellationToken();
      handlerAnswer = Completer();
      asked = [];
      held = {};
      released = [];
      agent = AgentRequests(
        send: sent.add,
        closing: closing,
        onPermission: (request, token) {
          asked.add((request, token));
          return handlerAnswer.future;
        },
        hold: (sessionId, turn) {
          (held[sessionId] ??= []).add(turn);
          return () => released.add(sessionId);
        },
      );
    });

    Map<String, Object?> result(Object? id, Map<String, Object?> result) => {
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    };
    final cancelled = {
      'outcome': {'outcome': 'cancelled'},
    };

    test('elicitation is cancelled at once', () {
      agent.request({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'elicitation/create',
        'params': {'mode': 'form'},
      });
      expect(sent, [
        result(1, {'action': 'cancel'}),
      ]);
    });

    test('cursor\'s and grok\'s plans are cancelled at once, never -32601', () {
      for (final method in ['cursor/create_plan', 'x.ai/exit_plan_mode']) {
        agent.request({
          'jsonrpc': '2.0',
          'id': method,
          'method': method,
          'params': {'toolCallId': 't'},
        });
      }
      expect(sent, [
        result('cursor/create_plan', {'outcome': 'cancelled'}),
        result('x.ai/exit_plan_mode', {'outcome': 'cancelled'}),
      ]);
    });

    test('fs, terminal and anything else is -32601', () {
      for (final method in [
        'fs/read_text_file',
        'fs/write_text_file',
        'terminal/create',
        'terminal/output',
        '_vendor/thing',
      ]) {
        agent.request({
          'jsonrpc': '2.0',
          'id': 3,
          'method': method,
          'params': {},
        });
        expect(sent.last, {
          'jsonrpc': '2.0',
          'id': 3,
          'error': {
            'code': -32601,
            'message': '"Method not found": $method',
            'data': {'method': method},
          },
        });
      }
    });

    test('a message that is not a request is -32600 with id null', () {
      for (final message in <Map<String, Object?>>[
        {'id': 1, 'method': 'x'},
        {'jsonrpc': '1.0', 'id': 1, 'method': 'x'},
        {'jsonrpc': '2.0', 'id': 1, 'method': 5},
        {
          'jsonrpc': '2.0',
          'id': {'a': 1},
          'method': 'x',
        },
        {'jsonrpc': '2.0', 'id': true, 'method': 'x'},
      ]) {
        agent.request(message);
        expect(sent.last, {
          'jsonrpc': '2.0',
          'id': null,
          'error': {
            'code': -32600,
            'message': 'Invalid request',
            'data': message,
          },
        });
      }
      expect(asked, isEmpty);
    });

    test('a permission request missing what chord reads is -32602', () {
      final good = _permission(1)['params'] as Map<String, Object?>;
      for (final (params, why) in <(Object?, String)>[
        (null, 'params must be an object'),
        ({...good, 'sessionId': 1}, 'sessionId must be a string'),
        ({...good}..remove('toolCall'), 'toolCall.toolCallId must be a string'),
        (
          {
            ...good,
            'toolCall': {'title': 'x'},
          },
          'toolCall.toolCallId must be a string',
        ),
        ({...good, 'options': 'x'}, 'options must be an array'),
        (
          {
            ...good,
            'options': ['x'],
          },
          'options[0] must be an object',
        ),
        for (final field in ['optionId', 'name', 'kind'])
          (
            {
              ...good,
              'options': [
                {'optionId': 'a', 'name': 'A', 'kind': 'allow_once'}
                  ..remove(field),
              ],
            },
            'options[0].$field must be a string',
          ),
      ]) {
        agent.request({
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'session/request_permission',
          'params': params,
        });
        expect(sent.last, {
          'jsonrpc': '2.0',
          'id': 4,
          'error': {'code': -32602, 'message': 'Invalid params', 'data': why},
        });
      }
      expect(asked, isEmpty);
    });

    test('the handler\'s answer goes out once, and the request is held under '
        'its session until then', () async {
      agent.request(_permission(1));
      expect(asked.single.$1.toolCall.toolCallId, 'write-3');
      expect(held['s'], hasLength(1));
      expect(released, isEmpty);
      handlerAnswer.complete(RequestPermissionResponse.selected('allow'));
      await pump();
      expect(sent, [
        result(1, {
          'outcome': {'outcome': 'selected', 'optionId': 'allow'},
        }),
      ]);
      expect(released, ['s']);
      expect(agent.running, 0);
      held['s']!.single.cancel();
      expect(sent, hasLength(1));
    });

    test('a handler that fails is answered with the fallback', () async {
      agent.request(_permission(1));
      handlerAnswer.completeError(StateError('bridge bug'));
      await pump();
      expect(sent, [result(1, cancelled)]);
    });

    test('a handler that throws synchronously is answered with the '
        'fallback', () async {
      final agent = AgentRequests(
        send: sent.add,
        closing: closing,
        onPermission: (_, _) => throw StateError('sync'),
      );
      agent.request(_permission(1));
      await pump();
      expect(sent, [result(1, cancelled)]);
    });

    test('an option the request did not offer, or no outcome, is answered '
        'with the fallback', () async {
      for (final answer in [
        RequestPermissionResponse.selected('nope'),
        RequestPermissionResponse.fromJson({}),
        RequestPermissionResponse.fromJson({
          'outcome': {'outcome': 'maybe'},
        }),
        RequestPermissionResponse.fromJson({
          'outcome': {'outcome': 'selected'},
        }),
      ]) {
        sent.clear();
        handlerAnswer = Completer();
        agent.request(_permission(1));
        handlerAnswer.complete(answer);
        await pump();
        expect(sent, [result(1, cancelled)], reason: '${answer.toJson()}');
      }
    });

    test('the handler\'s own cancelled goes out as it is', () async {
      agent.request(_permission(1));
      handlerAnswer.complete(RequestPermissionResponse.cancelled());
      await pump();
      expect(sent, [result(1, cancelled)]);
    });

    test('\$/cancel_request withdraws a running request: the fallback goes '
        'out inside it, the handler\'s token is cancelled, and its late '
        'answer is dropped', () async {
      agent.request(_permission(1));
      final token = asked.single.$2;
      agent.cancelRequest({
        'jsonrpc': '2.0',
        'method': cancelRequestMethod,
        'params': {'requestId': 1},
      });
      expect(sent, [result(1, cancelled)]);
      expect(token.isCancelled, isTrue);
      expect(released, ['s']);
      handlerAnswer.complete(RequestPermissionResponse.selected('allow'));
      await pump();
      expect(sent, hasLength(1));
    });

    test(
      '\$/cancel_request for an unknown or answered id is ignored',
      () async {
        agent.request(_permission(1));
        for (final params in [
          {'requestId': 2},
          {'requestId': '1'},
          {'requestId': null},
          {'nothing': 1},
          null,
        ]) {
          agent.cancelRequest({
            'jsonrpc': '2.0',
            'method': cancelRequestMethod,
            'params': params,
          });
        }
        expect(sent, isEmpty);
        handlerAnswer.complete(RequestPermissionResponse.selected('allow'));
        await pump();
        agent.cancelRequest({
          'jsonrpc': '2.0',
          'method': cancelRequestMethod,
          'params': {'requestId': 1},
        });
        expect(sent, hasLength(1));
      },
    );

    test('a \$/cancel_request outside the envelope is -32600 and withdraws '
        'nothing', () async {
      agent.request(_permission(1));
      for (final message in <Map<String, Object?>>[
        {
          'jsonrpc': '1.0',
          'method': cancelRequestMethod,
          'params': {'requestId': 1},
        },
        {
          'method': cancelRequestMethod,
          'params': {'requestId': 1},
        },
      ]) {
        agent.cancelRequest(message);
        expect(sent.last, {
          'jsonrpc': '2.0',
          'id': null,
          'error': {
            'code': -32600,
            'message': 'Invalid request',
            'data': message,
          },
        });
      }
      expect(asked.single.$2.isCancelled, isFalse);
      expect(agent.running, 1);
      handlerAnswer.complete(RequestPermissionResponse.selected('allow'));
      await pump();
      expect(
        sent.last,
        result(1, {
          'outcome': {'outcome': 'selected', 'optionId': 'allow'},
        }),
      );
    });

    test('ids are matched by value and JSON type: 1 and "1" are two '
        'requests', () {
      agent.request(_permission(1));
      agent.request(_permission('1'));
      expect(agent.running, 2);
      agent.cancelRequest({
        'jsonrpc': '2.0',
        'method': cancelRequestMethod,
        'params': {'requestId': '1'},
      });
      expect(sent, [result('1', cancelled)]);
      expect(asked[0].$2.isCancelled, isFalse);
      expect(asked[1].$2.isCancelled, isTrue);
      expect(agent.running, 1);
    });

    test('the session\'s turn cancel answers its waiting request', () {
      agent.request(_permission(1));
      held['s']!.single.cancel();
      expect(sent, [result(1, cancelled)]);
      expect(asked.single.$2.isCancelled, isTrue);
    });

    test('two requests for one tool call stay distinct, each answered '
        'once', () async {
      final answers = [
        Completer<RequestPermissionResponse>(),
        Completer<RequestPermissionResponse>(),
      ];
      var next = 0;
      final agent = AgentRequests(
        send: sent.add,
        closing: closing,
        onPermission: (_, _) => answers[next++].future,
      );
      agent.request(_permission(1));
      agent.request(_permission(2));
      answers[1].complete(RequestPermissionResponse.selected('deny'));
      await pump();
      answers[0].complete(RequestPermissionResponse.selected('allow'));
      await pump();
      expect(sent, [
        result(2, {
          'outcome': {'outcome': 'selected', 'optionId': 'deny'},
        }),
        result(1, {
          'outcome': {'outcome': 'selected', 'optionId': 'allow'},
        }),
      ]);
    });

    test('closing answers every waiting request inside the cancel', () {
      agent.request(_permission(1));
      agent.request(_permission(2));
      closing.cancel();
      expect(sent, [result(1, cancelled), result(2, cancelled)]);
      expect(agent.running, 0);
    });

    test('a request after closing began gets its fallback at once, and the '
        'handler is not asked', () {
      closing.cancel();
      agent.request(_permission(1));
      agent.request({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'cursor/create_plan',
        'params': {},
      });
      agent.request({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'fs/read_text_file',
        'params': {},
      });
      expect(asked, isEmpty);
      expect(sent[0], result(1, cancelled));
      expect(sent[1], result(2, {'outcome': 'cancelled'}));
      expect((sent[2]['error'] as Map)['code'], -32601);
    });
  });

  group('tester: RPC lifecycle boundaries', () {
    test(
      'missing requestId does not withdraw a permission whose id is null',
      () async {
        final sent = <Map<String, Object?>>[];
        final closing = CancellationToken();
        late CancellationToken token;
        final answer = Completer<RequestPermissionResponse>();
        final agent = AgentRequests(
          send: sent.add,
          closing: closing,
          onPermission: (_, requestToken) {
            token = requestToken;
            return answer.future;
          },
        );
        agent.request(_permission(null));
        agent.cancelRequest({
          'jsonrpc': '2.0',
          'method': cancelRequestMethod,
          'params': <String, Object?>{},
        });
        expect(token.isCancelled, isFalse);
        expect(agent.running, 1);
        expect(sent, isEmpty);
        agent.cancelRequest({
          'jsonrpc': '2.0',
          'method': cancelRequestMethod,
          'params': {'requestId': null},
        });
        expect(token.isCancelled, isTrue);
        expect(agent.running, 0);
        expect(sent.single['id'], isNull);
        answer.completeError(StateError('late handler failure'));
        await pump();
        expect(sent, hasLength(1));
      },
    );

    test(
      'turn cancellation remains scoped to its session with concurrent permissions',
      () async {
        final sent = <Map<String, Object?>>[];
        final closing = CancellationToken();
        final turns = <String, CancellationToken>{};
        final released = <String>[];
        final tokens = <String, CancellationToken>{};
        final answers = <String, Completer<RequestPermissionResponse>>{};
        final agent = AgentRequests(
          send: sent.add,
          closing: closing,
          onPermission: (request, token) {
            tokens[request.sessionId] = token;
            return (answers[request.sessionId] = Completer()).future;
          },
          hold: (session, turn) {
            turns[session] = turn;
            return () {
              released.add(session);
            };
          },
        );
        for (final session in ['first', 'second']) {
          final message = _permission(session);
          (message['params'] as Map<String, Object?>)['sessionId'] = session;
          agent.request(message);
        }
        turns['first']!.cancel();
        expect(tokens['first']!.isCancelled, isTrue);
        expect(tokens['second']!.isCancelled, isFalse);
        expect(sent.single['id'], 'first');
        answers['first']!.completeError(StateError('late'));
        answers['second']!.complete(
          RequestPermissionResponse.selected('allow'),
        );
        await pump();
        closing.cancel();
        expect(sent.map((message) => message['id']), ['first', 'second']);
        expect(released, ['first', 'second']);
        expect(agent.running, 0);
      },
    );

    test('a turn cancelled by hold never publishes the permission handler', () {
      final sent = <Map<String, Object?>>[];
      var calls = 0;
      var releases = 0;
      final agent = AgentRequests(
        send: sent.add,
        closing: CancellationToken(),
        onPermission: (_, _) {
          calls++;
          return Completer<RequestPermissionResponse>().future;
        },
        hold: (_, turn) {
          turn.cancel();
          return () {
            releases++;
          };
        },
      );
      agent.request(_permission(1));
      expect(calls, 0);
      expect(releases, 1);
      expect(agent.running, 0);
      expect(sent.single['result'], {
        'outcome': {'outcome': 'cancelled'},
      });
    });

    test(
      'out-of-order replies retain each request and a null result settles',
      () async {
        final sent = <Map<String, Object?>>[];
        final chord = ChordRequests(sent.add);
        addTearDown(chord.close);
        final first = chord.request('first', {});
        final second = chord.request('second', {});
        var firstDone = false;
        first.then((_) {
          firstDone = true;
        });
        chord.response({'jsonrpc': '2.0', 'id': 1, 'result': null});
        expect(await second, isNull);
        expect(firstDone, isFalse);
        chord.response({
          'jsonrpc': '2.0',
          'id': 0,
          'result': {'ok': true},
        });
        expect(await first, {'ok': true});
        expect(sent.map((message) => message['id']), [0, 1]);
      },
    );

    test(
      'integral error-code normalization keeps the incoming map unchanged',
      () async {
        final chord = ChordRequests((_) {});
        addTearDown(chord.close);
        final answer = chord.request('x', {});
        final response = <String, Object?>{
          'jsonrpc': '2.0',
          'id': 0,
          'error': {
            'code': -32000.0,
            'message': 'no',
            'data': {
              'future': [1, null],
            },
          },
        };
        chord.response(response);
        await expectLater(
          answer,
          throwsA(
            isA<RpcException>().having((e) => e.code, 'code', -32000).having(
              (e) => e.data,
              'data',
              {
                'future': [1, null],
              },
            ),
          ),
        );
        expect((response['error'] as Map)['code'], isA<double>());
      },
    );
  });
}

Map<String, Object?> _permission(Object? id) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': 'session/request_permission',
  'params': {
    'sessionId': 's',
    'toolCall': {
      'toolCallId': 'write-3',
      'title': 'Write notes.txt',
      'kind': 'edit',
      'status': 'pending',
    },
    'options': [
      {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
      {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
    ],
  },
};

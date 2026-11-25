import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/rpc.dart';
import 'package:test/test.dart';

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('chord\'s requests withdrawn', () {
    test('with withdraws, a cancelled token sends \$/cancel_request for '
        'that request once', () async {
      final sent = <Map<String, Object?>>[];
      final chord = ChordRequests(sent.add, withdraws: true);
      final token = CancellationToken();
      final asked = chord.request(
        'session/request_permission',
        {},
        token: token,
      );
      token.cancel();
      await expectLater(asked, throwsA(isA<CancelledException>()));
      expect(sent.last, {
        'jsonrpc': '2.0',
        'method': r'$/cancel_request',
        'params': {'requestId': 0},
      });
      chord.response({'jsonrpc': '2.0', 'id': 0, 'result': {}});
      await pump();
      expect(sent, hasLength(2));
    });

    test('a withdrawn request waits until answered late, the answer '
        'ignored', () async {
      final sent = <Map<String, Object?>>[];
      final chord = ChordRequests(sent.add, withdraws: true);
      final token = CancellationToken();
      final asked = chord.request('x', {}, token: token);
      token.cancel();
      await expectLater(asked, throwsA(isA<CancelledException>()));
      expect(chord.waiting, 1);
      chord.response({'jsonrpc': '2.0', 'id': 0, 'result': 'late'});
      await pump();
      expect(chord.waiting, 0);
    });

    test('close releases every request still waiting, a withdrawn one '
        'too', () async {
      final chord = ChordRequests((_) {}, withdraws: true);
      final token = CancellationToken();
      chord.request('x', {}, token: token).ignore();
      final open = chord.request('y', {});
      token.cancel();
      expect(chord.waiting, 2);
      await chord.close();
      await expectLater(open, throwsA(anything));
      await pump();
      expect(chord.waiting, 0);
    });

    test('an answer already in sends no \$/cancel_request', () async {
      final sent = <Map<String, Object?>>[];
      final chord = ChordRequests(sent.add, withdraws: true);
      final token = CancellationToken();
      final asked = chord.request('x', {}, token: token);
      chord.response({'jsonrpc': '2.0', 'id': 0, 'result': 1});
      expect(await asked, 1);
      token.cancel();
      expect(sent, hasLength(1));
    });

    test('without withdraws, as the window asks an agent, nothing is '
        'sent', () async {
      final sent = <Map<String, Object?>>[];
      final chord = ChordRequests(sent.add);
      final token = CancellationToken();
      final asked = chord.request('x', {}, token: token);
      token.cancel();
      await expectLater(asked, throwsA(isA<CancelledException>()));
      expect(sent, hasLength(1));
    });
  });

  group('the client\'s requests', () {
    late List<Map<String, Object?>> sent;
    late CancellationToken closing;
    late ClientRequests client;
    late List<Served<Map<String, Object?>>> deferred;
    late List<Object?> heard;

    Map<String, Object?> anything(Object? params) =>
        params as Map<String, Object?>;

    Map<String, Object?> call(Object? id, String method, [Object? params]) => {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    };

    void initialize() {
      client.request(call(0, 'initialize', {'protocolVersion': 1}));
      sent.clear();
    }

    setUp(() {
      sent = [];
      deferred = [];
      heard = [];
      closing = CancellationToken();
      client = ClientRequests(send: sent.add, closing: closing)
        ..immediate('initialize', anything, (r) => {'protocolVersion': 1})
        ..immediate('echo', anything, (r) => r.params)
        ..immediate('later', anything, (r) async => {'later': true})
        ..immediate('throws', anything, (r) => throw StateError('chord failed'))
        ..immediate(
          'refuses',
          anything,
          (r) => throw RpcException(
            -32002,
            'Resource not found',
            data: {'sessionId': 's'},
          ),
        )
        ..immediate('checked', (params) {
          throw RpcException(
            -32602,
            'Invalid params',
            data: {
              '_errors': <String>[],
              'sessionId': {
                '_errors': [
                  'Invalid input: expected string, received undefined',
                ],
              },
            },
          );
        }, (r) => {})
        ..deferred('session/prompt', anything, deferred.add)
        ..notification('session/cancel', anything, heard.add);
    });

    test('before initialize every other request is -32600, notifications '
        'pass', () {
      client.request(call(1, 'session/new', {'cwd': '/w'}));
      client.request(call(2, 'nothing/here'));
      client.notify({
        'jsonrpc': '2.0',
        'method': 'session/cancel',
        'params': {'sessionId': 's'},
      });
      expect(sent, [
        {
          'jsonrpc': '2.0',
          'id': 1,
          'error': {
            'code': -32600,
            'message':
                "Invalid request: ACP connection must be initialized before "
                "'session/new'",
          },
        },
        {
          'jsonrpc': '2.0',
          'id': 2,
          'error': {
            'code': -32600,
            'message':
                "Invalid request: ACP connection must be initialized before "
                "'nothing/here'",
          },
        },
      ]);
      expect(heard, [
        {'sessionId': 's'},
      ]);
    });

    test('initialize opens the rest once it is answered, and may come '
        'again', () {
      client.request(call(0, 'initialize'));
      expect(sent.single['result'], {'protocolVersion': 1});
      client.request(call(1, 'echo', {'a': 1}));
      client.request(call(2, 'initialize'));
      expect(sent.skip(1), [
        {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {'a': 1},
        },
        {
          'jsonrpc': '2.0',
          'id': 2,
          'result': {'protocolVersion': 1},
        },
      ]);
    });

    test('a failed initialize leaves the gate shut', () {
      client.immediate('initialize', anything, (_) => throw StateError('no'));
      client.request(call(0, 'initialize'));
      client.request(call(1, 'echo'));
      expect(sent.last['error'], containsPair('code', -32600));
    });

    test('an unknown method is -32601 with its name as data', () {
      initialize();
      client.request(call(3, '_chord/nothing'));
      expect(sent, [
        {
          'jsonrpc': '2.0',
          'id': 3,
          'error': {
            'code': -32601,
            'message': '"Method not found": _chord/nothing',
            'data': {'method': '_chord/nothing'},
          },
        },
      ]);
    });

    test('a malformed request is -32600 with itself as data, and id null', () {
      initialize();
      final bad = {'id': 1, 'method': 'echo'};
      client.request(bad);
      final badId = {'jsonrpc': '2.0', 'id': true, 'method': 'echo'};
      client.request(badId);
      expect(sent, [
        {
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32600, 'message': 'Invalid request', 'data': bad},
        },
        {
          'jsonrpc': '2.0',
          'id': null,
          'error': {
            'code': -32600,
            'message': 'Invalid request',
            'data': badId,
          },
        },
      ]);
    });

    test('a check that refuses is that -32602, and the handler never '
        'runs', () {
      initialize();
      client.request(call(4, 'checked', {}));
      expect(sent.single['error'], {
        'code': -32602,
        'message': 'Invalid params',
        'data': {
          '_errors': <String>[],
          'sessionId': {
            '_errors': ['Invalid input: expected string, received undefined'],
          },
        },
      });
      expect(client.running, 0);
    });

    test('absent params are read as an empty object', () {
      initialize();
      client.request(call(5, 'echo'));
      expect(sent.single['result'], <String, Object?>{});
    });

    test('an immediate answer is written in the same call, a later one when '
        'it comes', () async {
      initialize();
      client.request(call(6, 'echo', {'x': 1}));
      expect(sent, hasLength(1));
      client.request(call(7, 'later'));
      expect(sent, hasLength(1));
      await pump();
      expect(sent.last, {
        'jsonrpc': '2.0',
        'id': 7,
        'result': {'later': true},
      });
    });

    test('an RpcException is answered as it is; anything else -32603 with '
        'its words as details', () {
      initialize();
      client.request(call(8, 'refuses'));
      client.request(call(9, 'throws'));
      expect(sent.map((m) => m['error']), [
        {
          'code': -32002,
          'message': 'Resource not found',
          'data': {'sessionId': 's'},
        },
        {
          'code': -32603,
          'message': 'Internal error',
          'data': {'details': 'chord failed'},
        },
      ]);
    });

    test('a deferred answer is written when respond is called, ahead of '
        'what is sent after it in the same stack', () {
      initialize();
      client.request(call(10, 'session/prompt', {'sessionId': 's'}));
      expect(sent, isEmpty);
      final [served] = deferred;
      expect(served.id, 10);
      client.respond(10, {'stopReason': 'end_turn'});
      sent.add({'jsonrpc': '2.0', 'method': 'session/update'});
      expect(sent.map((m) => m['id'] ?? m['method']), [10, 'session/update']);
    });

    test('a request is answered once, whatever answers it again', () {
      initialize();
      client.request(call(11, 'session/prompt', <String, Object?>{}));
      client.respond(11, {'stopReason': 'end_turn'});
      client.respond(11, {'stopReason': 'cancelled'});
      client.fail(11, StateError('late'));
      expect(sent, hasLength(1));
      expect(client.running, 0);
    });

    test('\$/cancel_request cancels the request it names by value and type, '
        'and a cancel then answers -32800', () {
      initialize();
      client.request(call(1, 'session/prompt', <String, Object?>{}));
      client.request(call('1', 'session/prompt', <String, Object?>{}));
      final [number, text] = deferred;
      client.cancelRequest({
        'jsonrpc': '2.0',
        'method': r'$/cancel_request',
        'params': {'requestId': '1'},
      });
      expect(number.token.isCancelled, isFalse);
      expect(text.token.isCancelled, isTrue);
      client.fail('1', text.token.exception!);
      expect(sent.single, {
        'jsonrpc': '2.0',
        'id': '1',
        'error': {
          'code': -32800,
          'message': 'Request cancelled',
          'data': {'requestId': '1'},
        },
      });
    });

    test('a null id is an id: its own \$/cancel_request answers -32800 '
        'naming null', () {
      initialize();
      client.request(call(null, 'session/prompt', <String, Object?>{}));
      final [served] = deferred;
      client.cancelRequest({
        'jsonrpc': '2.0',
        'method': r'$/cancel_request',
        'params': {'requestId': null},
      });
      expect(served.token.isCancelled, isTrue);
      client.fail(null, served.token.exception!);
      expect(sent.single, {
        'jsonrpc': '2.0',
        'id': null,
        'error': {
          'code': -32800,
          'message': 'Request cancelled',
          'data': {'requestId': null},
        },
      });
    });

    test('a cancel of an answered or unknown request changes nothing', () {
      initialize();
      client.request(call(1, 'session/prompt', <String, Object?>{}));
      final [served] = deferred;
      client.respond(1, {});
      client.cancelRequest({
        'jsonrpc': '2.0',
        'method': r'$/cancel_request',
        'params': {'requestId': 1},
      });
      client.cancelRequest({
        'jsonrpc': '2.0',
        'method': r'$/cancel_request',
        'params': {'requestId': 99},
      });
      expect(served.token.isCancelled, isFalse);
      expect(sent, hasLength(1));
    });

    test('the connection\'s close cancels every running token', () {
      initialize();
      client.request(call(1, 'session/prompt', <String, Object?>{}));
      closing.cancel();
      expect(deferred.single.token.isCancelled, isTrue);
    });

    test('notifications are never answered; an unknown one is ignored', () {
      initialize();
      client.notify({
        'jsonrpc': '2.0',
        'method': 'session/cancel',
        'params': {'sessionId': 's'},
      });
      client.notify({'jsonrpc': '2.0', 'method': 'nothing/here'});
      expect(sent, isEmpty);
      expect(heard, [
        {'sessionId': 's'},
      ]);
    });
  });

  group('a notification that fails', () {
    test('a checker or handler that throws is unanswered, heard once, and a '
        'later request is still served', () {
      final sent = <Map<String, Object?>>[];
      final failed = <(String, int, String)>[];
      final client =
          ClientRequests(
              send: sent.add,
              closing: CancellationToken(),
              onNotificationFailed: (method, error) =>
                  failed.add((method, error.code, error.message)),
            )
            ..immediate('initialize', (p) => p, (r) => <String, Object?>{})
            ..notification(
              'session/cancel',
              (p) => throw RpcException(-32602, 'Invalid params'),
              (_) {},
            )
            ..notification(
              'broken/check',
              (p) => throw StateError('bad check'),
              (_) {},
            )
            ..notification(
              'broken/handler',
              (p) => p,
              (_) => throw StateError('chord failed'),
            );
      for (final method in [
        'session/cancel',
        'broken/check',
        'broken/handler',
      ]) {
        client.notify({'jsonrpc': '2.0', 'method': method});
      }
      expect(sent, isEmpty);
      expect(failed, [
        ('session/cancel', -32602, 'Invalid params'),
        ('broken/check', -32603, 'Internal error'),
        ('broken/handler', -32603, 'Internal error'),
      ]);
      client.request({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'});
      expect(sent.single['result'], <String, Object?>{});
    });
  });

  group('serve', () {
    late List<Map<String, Object?>> sent;
    late ChordRequests chord;
    late ClientRequests client;
    late List<Object?> heard;

    setUp(() {
      sent = [];
      heard = [];
      chord = ChordRequests(sent.add, withdraws: true);
      client = ClientRequests(send: sent.add, closing: CancellationToken())
        ..immediate('initialize', (p) => p, (r) => <String, Object?>{})
        ..deferred('session/prompt', (p) => p, (r) => heard.add(r.token))
        ..notification('session/cancel', (p) => p, heard.add);
    });

    void served(Map<String, Object?> message) =>
        serve(message, chord: chord, client: client, send: sent.add);

    test('a request to the client\'s dispatcher, a response to chord\'s '
        'requests, notifications and cancels to the dispatcher', () async {
      served({'jsonrpc': '2.0', 'id': 0, 'method': 'initialize'});
      expect(sent.single['result'], <String, Object?>{});
      final asked = chord.request('session/request_permission', {});
      served({
        'jsonrpc': '2.0',
        'id': 0,
        'result': {'outcome': 'x'},
      });
      expect(await asked, {'outcome': 'x'});
      served({'jsonrpc': '2.0', 'id': 5, 'method': 'session/prompt'});
      served({
        'jsonrpc': '2.0',
        'method': r'$/cancel_request',
        'params': {'requestId': 5},
      });
      expect((heard.single as CancellationToken).isCancelled, isTrue);
      served({
        'jsonrpc': '2.0',
        'method': 'session/cancel',
        'params': {'sessionId': 's'},
      });
      expect(heard.last, {'sessionId': 's'});
    });

    test('what is neither is -32600 with itself as data', () {
      for (final bad in <Map<String, Object?>>[
        {'jsonrpc': '2.0'},
        {'jsonrpc': '1.0', 'method': 'session/cancel'},
        {
          'method': r'$/cancel_request',
          'params': {'requestId': 1},
        },
      ]) {
        sent.clear();
        served(bad);
        expect(sent, [
          {
            'jsonrpc': '2.0',
            'id': null,
            'error': {
              'code': -32600,
              'message': 'Invalid request',
              'data': bad,
            },
          },
        ]);
      }
    });
  });

  group('tester U2 dispatcher boundaries', () {
    Map<String, Object?> call(Object? id, String method) => {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
    };

    test('concurrent initialization opens on the first success only', () {
      final sent = <Map<String, Object?>>[];
      final client =
          ClientRequests(send: sent.add, closing: CancellationToken())
            ..deferred('initialize', (p) => p, (_) {})
            ..immediate('echo', (p) => p, (_) => 'ready');
      client.request(call(1, 'initialize'));
      client.request(call(2, 'initialize'));
      client.fail(1, StateError('first refused'));
      client.request(call(3, 'echo'));
      expect((sent.last['error'] as Map)['code'], -32600);
      expect(client.running, 1);
      client.respond(2, {});
      client.request(call(4, 'echo'));
      expect(sent.last, resultMessage(4, 'ready'));
      expect(client.running, 0);
    });

    test('malformed cancellation cannot withdraw an explicit null id', () {
      final sent = <Map<String, Object?>>[];
      late Served<Object?> held;
      final client =
          ClientRequests(send: sent.add, closing: CancellationToken())
            ..immediate('initialize', (p) => p, (_) => {})
            ..deferred('held', (p) => p, (r) => held = r);
      client.request(call('init', 'initialize'));
      sent.clear();
      client.request(call(null, 'held'));
      for (final params in <Object?>[
        null,
        {},
        {'requestId': true},
        {'requestId': []},
      ]) {
        client.cancelRequest({
          'jsonrpc': '2.0',
          'method': cancelRequestMethod,
          'params': params,
        });
      }
      expect(held.token.isCancelled, isFalse);
      client.cancelRequest({
        'method': cancelRequestMethod,
        'params': {'requestId': null},
      });
      expect(held.token.isCancelled, isFalse);
      expect((sent.single['error'] as Map)['code'], -32600);
      client.cancelRequest({
        'jsonrpc': '2.0',
        'method': cancelRequestMethod,
        'params': {'requestId': null},
      });
      expect(held.token.isCancelled, isTrue);
      client.fail(null, held.token.exception!);
      expect((sent.last['error'] as Map)['code'], -32800);
      expect(client.running, 0);
    });

    test(
      'a late async failure cannot answer a request already settled',
      () async {
        final sent = <Map<String, Object?>>[];
        final late = Completer<Object?>();
        final client =
            ClientRequests(send: sent.add, closing: CancellationToken())
              ..immediate('initialize', (p) => p, (_) => {})
              ..immediate('held', (p) => p, (_) => late.future);
        client.request(call('init', 'initialize'));
        sent.clear();
        client.request(call(1, 'held'));
        client.respond(1, 'done');
        late.completeError(StateError('late'));
        await pump();
        expect(sent, [resultMessage(1, 'done')]);
        expect(client.running, 0);
      },
    );

    test(
      'withdrawing one outbound ask leaves the other answer intact',
      () async {
        final sent = <Map<String, Object?>>[];
        final chord = ChordRequests(sent.add, withdraws: true);
        addTearDown(chord.close);
        final one = CancellationToken();
        final two = CancellationToken();
        final first = chord.request('ask', {'sessionId': 'first'}, token: one);
        final second = chord.request('ask', {
          'sessionId': 'second',
        }, token: two);
        final cancelled = expectLater(
          first,
          throwsA(isA<CancelledException>()),
        );
        one.cancel();
        one.cancel();
        await cancelled;
        expect(sent.where((m) => m['method'] == cancelRequestMethod), [
          {
            'jsonrpc': '2.0',
            'method': cancelRequestMethod,
            'params': {'requestId': 0},
          },
        ]);
        chord.response(resultMessage(0, 'late first'));
        chord.response(resultMessage(1, 'second answer'));
        expect(await second, 'second answer');
        two.cancel();
        await pump();
        expect(
          sent.where((m) => m['method'] == cancelRequestMethod),
          hasLength(1),
        );
      },
    );
  });
}

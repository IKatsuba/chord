// The fake's own dispatcher answers as the original's SDK does: its error
// words and data, `initialize` first, lines of JSON, and its requests to
// the client through json_rpc_2's Client.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import 'rpc.dart';
import 'schema.dart';
import 'signals.dart';

/// A connection served in memory: what goes in, and each line that came out.
final class _Served {
  _Served({
    Map<String, RequestSpec> requests = const {},
    Map<String, NotificationSpec> notifications = const {},
  }) {
    connection = Connection.serve(
      _input.stream,
      (bytes) => _out.add(utf8.decode(bytes)),
      () async {},
      requests: {
        'initialize': RequestSpec((_) => {'protocolVersion': 1}),
        ...requests,
      },
      notifications: notifications,
    );
  }

  final _input = StreamController<List<int>>();
  final _out = StreamController<String>.broadcast();
  late final Connection connection;
  final lines = <Map<String, Object?>>[];

  void send(String line) => _input.add(utf8.encode('$line\n'));

  /// The next line out, decoded.
  Future<Map<String, Object?>> next() async {
    final line = await _out.stream.first;
    expect(line, endsWith('\n'));
    return (jsonDecode(line) as Map).cast<String, Object?>();
  }

  /// Sends [message] and returns the next line out.
  Future<Map<String, Object?>> ask(Map<String, Object?> message) {
    final answer = next();
    send(jsonEncode({'jsonrpc': '2.0', ...message}));
    return answer;
  }

  Future<void> initialize() => ask({
    'id': 0,
    'method': 'initialize',
    'params': {'protocolVersion': 1},
  });

  Future<void> close() => _input.close();
}

void main() {
  group('tester: CTUI-147 arbitrary plan replies and delayed rejection', () {
    for (final value in <Object?>[
      null,
      false,
      true,
      0,
      2.5,
      '界e\u0301👩‍💻',
      <Object?>[],
      [
        1,
        null,
        false,
        {'nested': 'value'},
      ],
    ]) {
      test('requestAny preserves ${jsonEncode(value)}', () async {
        final served = _Served();
        addTearDown(served.close);
        await served.initialize();
        final sent = served.next();
        final answer = served.connection.client.requestAny(
          'cursor/create_plan',
          {},
        );
        final id = (await sent)['id'];
        served.send(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': value}));
        expect(await answer, value);
      });
    }

    test(
      'an early rejection remains awaitable and an abandoned one is handled',
      () async {
        final unhandled = <Object>[];
        final finished = Completer<void>();
        runZonedGuarded(() async {
          final served = _Served();
          try {
            await served.initialize();
            final sent = served.next();
            final delayed = served.connection.client.requestAny(
              'cursor/create_plan',
              {},
            );
            final id = (await sent)['id'];
            served.send(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': id,
                'error': {
                  'code': -32601,
                  'message': 'Method not found',
                  'data': {'early': true},
                },
              }),
            );
            final abandonedSent = served.next();
            served.connection.client.requestAny('cursor/create_plan', {});
            final abandonedId = (await abandonedSent)['id'];
            served.send(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': abandonedId,
                'error': {'code': -32601, 'message': 'Method not found'},
              }),
            );
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await expectLater(
              delayed,
              throwsA(
                isA<RequestError>()
                    .having((error) => error.code, 'code', -32601)
                    .having(
                      (error) => error.message,
                      'message',
                      'Method not found',
                    )
                    .having((error) => error.data, 'data', {'early': true}),
              ),
            );
          } finally {
            await served.close();
            finished.complete();
          }
        }, (error, _) => unhandled.add(error));
        await finished.future;
        expect(unhandled, isEmpty);
      },
    );
  });

  group('tester: CTUI-147 request cancellation isolation', () {
    test(
      'cancelling an older request keeps its id after another starts',
      () async {
        final served = _Served();
        addTearDown(served.close);
        await served.initialize();
        final firstCancel = Aborter();
        final firstSent = served.next();
        final first = served.connection.client.request(
          'x/first',
          {},
          cancellation: firstCancel.signal,
        );
        final firstId = (await firstSent)['id'];
        final secondSent = served.next();
        final second = served.connection.client.request('x/second', {});
        final secondId = (await secondSent)['id'];
        expect(secondId, isNot(firstId));
        var firstSettled = false;
        first.then((_) => firstSettled = true);
        final withdrawn = served.next();
        firstCancel.abort();
        expect(await withdrawn, {
          'jsonrpc': '2.0',
          'method': r'$/cancel_request',
          'params': {'requestId': firstId},
        });
        expect(firstSettled, isFalse);
        served.send(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': secondId,
            'result': {'second': true},
          }),
        );
        expect(await second, {'second': true});
        expect(firstSettled, isFalse);
        served.send(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': firstId,
            'result': {'first': true},
          }),
        );
        expect(await first, {'first': true});
      },
    );

    test(
      'a pre-aborted request is sent then withdrawn and awaits its result',
      () async {
        final served = _Served();
        addTearDown(served.close);
        await served.initialize();
        final cancellation = Aborter()..abort();
        final emitted = served._out.stream.take(2).toList();
        final answer = served.connection.client.request(
          'x/pre-aborted',
          {},
          cancellation: cancellation.signal,
        );
        final messages = [
          for (final line in await emitted) jsonDecode(line) as Map,
        ];
        final id = messages.first['id'];
        expect(messages.first['method'], 'x/pre-aborted');
        expect(messages.last, {
          'jsonrpc': '2.0',
          'method': r'$/cancel_request',
          'params': {'requestId': id},
        });
        served.send(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {'late': true},
          }),
        );
        expect(await answer, {'late': true});
      },
    );

    test('cancellation after an answer emits no stale withdrawal', () async {
      final served = _Served();
      addTearDown(served.close);
      await served.initialize();
      final cancellation = Aborter();
      final sent = served.next();
      final answer = served.connection.client.request(
        'x/done',
        {},
        cancellation: cancellation.signal,
      );
      final id = (await sent)['id'];
      served.send(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': {'done': true},
        }),
      );
      expect(await answer, {'done': true});
      final messages = <Object?>[];
      final barrier = Completer<void>();
      final listener = served._out.stream.listen((line) {
        final message = jsonDecode(line) as Map;
        messages.add(message);
        if (message['method'] == 'x/barrier') barrier.complete();
      });
      addTearDown(listener.cancel);
      cancellation.abort();
      await served.connection.client.notify('x/barrier', {});
      await barrier.future;
      expect(messages, [
        {'jsonrpc': '2.0', 'method': 'x/barrier', 'params': {}},
      ]);
    });
  });

  group('tester: CTUI-147 dispatcher transport and lifetime', () {
    test('byte fragments preserve Unicode, escapes and CRLF framing', () async {
      final served = _Served(
        requests: {'x/echo': RequestSpec((context) => context.params)},
      );
      addTearDown(served.close);
      await served.initialize();
      const text = '界👩🏽‍💻e\u0301\u001b[31m\n"\\';
      final answer = served.next();
      final bytes = utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'id': 'unicode',
          'method': 'x/echo',
          'params': {'text': text},
        })}\r\n',
      );
      for (final byte in bytes) {
        served._input.add([byte]);
      }
      expect(await answer, {
        'jsonrpc': '2.0',
        'id': 'unicode',
        'result': {'text': text},
      });
    });

    test('a thousand notifications in one chunk retain their order', () async {
      final heard = <int>[];
      final complete = Completer<void>();
      final served = _Served(
        notifications: {
          'x/update': NotificationSpec((params, _) {
            heard.add(params['n'] as int);
            if (heard.length == 1000) complete.complete();
          }),
        },
      );
      addTearDown(served.close);
      await served.initialize();
      served._input.add(
        utf8.encode(
          [
            for (var n = 0; n < 1000; n++)
              jsonEncode({
                'jsonrpc': '2.0',
                'method': 'x/update',
                'params': {'n': n},
              }),
            '',
          ].join('\n'),
        ),
      );
      await complete.future;
      expect(heard, List.generate(1000, (n) => n));
    });

    test('a slow request does not block another request or mix ids', () async {
      final slow = Completer<Object?>();
      final entered = Completer<void>();
      final served = _Served(
        requests: {
          'x/slow': RequestSpec((_) {
            entered.complete();
            return slow.future;
          }),
          'x/fast': RequestSpec((_) => {'fast': true}),
        },
      );
      addTearDown(served.close);
      await served.initialize();
      served.send(
        jsonEncode({'jsonrpc': '2.0', 'id': 'slow', 'method': 'x/slow'}),
      );
      await entered.future;
      final fast = await served.ask({'id': 7, 'method': 'x/fast'});
      expect(fast, {
        'jsonrpc': '2.0',
        'id': 7,
        'result': {'fast': true},
      });
      final late = served.next();
      slow.complete({'slow': true});
      expect(await late, {
        'jsonrpc': '2.0',
        'id': 'slow',
        'result': {'slow': true},
      });
    });

    test('closing input settles an unanswered request to the client', () async {
      final served = _Served();
      await served.initialize();
      final sent = served.next();
      final pending = served.connection.client.request('x/wait', {});
      final failed = expectLater(pending, throwsA(anything));
      expect((await sent)['method'], 'x/wait');
      await served.close();
      await served.connection.closed;
      await failed;
      expect(served.connection.isClosed, isTrue);
    });
  });

  test('a request before initialize is refused -32600, naming it', () async {
    final served = _Served();
    addTearDown(served.close);
    expect(await served.ask({'id': 1, 'method': 'session/new'}), {
      'jsonrpc': '2.0',
      'id': 1,
      'error': {
        'code': -32600,
        'message':
            "Invalid request: ACP connection must be initialized before "
            "'session/new'",
      },
    });
  });

  test('a method it does not serve is "Method not found", with data '
      '{method}', () async {
    final served = _Served();
    addTearDown(served.close);
    await served.initialize();
    expect(await served.ask({'id': 1, 'method': 'session/nope'}), {
      'jsonrpc': '2.0',
      'id': 1,
      'error': {
        'code': -32601,
        'message': '"Method not found": session/nope',
        'data': {'method': 'session/nope'},
      },
    });
  });

  test("params that do not fit are Invalid params, zod's format() tree as "
      'data', () async {
    final served = _Served(
      requests: {'session/prompt': RequestSpec(parse: parsePrompt, (_) => {})},
    );
    addTearDown(served.close);
    await served.initialize();
    expect(
      await served.ask({
        'id': 1,
        'method': 'session/prompt',
        'params': {'prompt': 'no'},
      }),
      {
        'jsonrpc': '2.0',
        'id': 1,
        'error': {
          'code': -32602,
          'message': 'Invalid params',
          'data': {
            '_errors': <Object?>[],
            'sessionId': {
              '_errors': ['Invalid input: expected string, received undefined'],
            },
            'prompt': {
              '_errors': ['Invalid input: expected array, received string'],
            },
          },
        },
      },
    );
  });

  test('a handler refusing with words of its own sends no data', () async {
    final served = _Served(
      requests: {
        'x/refuse': RequestSpec(
          (_) => throw RequestError.invalidParams(null, 'x cannot be y'),
        ),
        'x/fail': RequestSpec((_) => throw StateError('broke')),
      },
    );
    addTearDown(served.close);
    await served.initialize();
    expect((await served.ask({'id': 1, 'method': 'x/refuse'}))['error'], {
      'code': -32602,
      'message': 'Invalid params: x cannot be y',
    });
    expect((await served.ask({'id': 2, 'method': 'x/fail'}))['error'], {
      'code': -32603,
      'message': 'Internal error',
      'data': {'details': 'broke'},
    });
  });

  test('nothing answers as an empty object where the SDK fills one in, '
      'else null', () async {
    final served = _Served(
      requests: {
        'x/empty': RequestSpec(empty: true, (_) => null),
        'x/null': RequestSpec((_) => null),
      },
    );
    addTearDown(served.close);
    await served.initialize();
    expect((await served.ask({'id': 1, 'method': 'x/empty'}))['result'], {});
    final none = await served.ask({'id': 2, 'method': 'x/null'});
    expect(none.containsKey('result'), isTrue);
    expect(none['result'], isNull);
  });

  test(
    'bad JSON, a batch and a non-object are answered with id null',
    () async {
      final served = _Served();
      addTearDown(served.close);
      var answer = served.next();
      served.send('{not json');
      expect(await answer, {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error'},
      });
      answer = served.next();
      served.send('[1]');
      expect((await answer)['error'], {
        'code': -32600,
        'message': 'Invalid request: JSON-RPC batches are not supported',
      });
      answer = served.next();
      served.send('7');
      expect((await answer)['error'], {
        'code': -32600,
        'message': 'Invalid request',
        'data': 7,
      });
    },
  );

  test('a whole double goes out as an integer, as JavaScript writes it', () {
    expect(
      stringify({
        'a': 2.0,
        'b': 0.0125,
        'c': [1.0],
      }),
      '{"a":2,"b":0.0125,"c":[1]}',
    );
  });

  test(
    "its requests to the client get the client's result, or its error",
    () async {
      final served = _Served();
      addTearDown(served.close);
      await served.initialize();
      final asked = served.next();
      final result = served.connection.client.request('x/ask', {'n': 1});
      final request = await asked;
      expect(request, {
        'jsonrpc': '2.0',
        'method': 'x/ask',
        'id': 0,
        'params': {'n': 1},
      });
      served.send(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 0,
          'result': {'ok': 1},
        }),
      );
      expect(await result, {'ok': 1});

      final refused = served.connection.client.request('x/ask', {});
      await served.next();
      served.send(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'error': {'code': -32000, 'message': 'no', 'data': 3},
        }),
      );
      await expectLater(
        refused,
        throwsA(
          isA<RequestError>()
              .having((e) => e.code, 'code', -32000)
              .having((e) => e.message, 'message', 'no')
              .having((e) => e.data, 'data', 3),
        ),
      );
    },
  );

  test(r'a request whose cancellation aborts tells the client $/cancel_request '
      'with its id, and still awaits its answer', () async {
    final served = _Served();
    addTearDown(served.close);
    await served.initialize();
    final cancel = Aborter();
    final asked = served.next();
    final answer = served.connection.client.request(
      'session/request_permission',
      {'sessionId': 's'},
      cancellation: cancel.signal,
    );
    expect((await asked)['id'], 0);
    final withdrawn = served.next();
    cancel.abort();
    expect(await withdrawn, {
      'jsonrpc': '2.0',
      'method': r'$/cancel_request',
      'params': {'requestId': 0},
    });
    served.send(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 0,
        'result': {
          'outcome': {'outcome': 'cancelled'},
        },
      }),
    );
    expect(await answer, {
      'outcome': {'outcome': 'cancelled'},
    });
  });

  test('a request refused before it is awaited fails only where it is '
      'awaited, as the SDK marks it handled', () async {
    final unhandled = <Object>[];
    await runZonedGuarded(() async {
      final served = _Served();
      addTearDown(served.close);
      await served.initialize();
      for (final (id, ask) in <(int, Future<Object?> Function())>[
        (0, () => served.connection.client.request('x/ask', {})),
        (1, () => served.connection.client.requestAny('x/ask', {})),
      ]) {
        final asked = served.next();
        final answer = ask();
        await asked;
        served.send(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32601, 'message': 'Method not found'},
          }),
        );
        // The refusal comes and goes with nobody awaiting it yet.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await expectLater(
          answer,
          throwsA(isA<RequestError>().having((e) => e.code, 'code', -32601)),
        );
      }
    }, (error, _) => unhandled.add(error));
    expect(unhandled, isEmpty);
  });

  test(
    'a notification reaches its handler, and the end of input closes',
    () async {
      final heard = Completer<Map<String, Object?>>();
      final served = _Served(
        notifications: {
          'session/cancel': NotificationSpec(
            parse: parseSessionId,
            (params, _) => heard.complete(params),
          ),
        },
      );
      served.send(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'session/cancel',
          'params': {'sessionId': 's', 'extra': 1},
        }),
      );
      expect(await heard.future, {'sessionId': 's'});
      await served.close();
      await served.connection.closed;
      expect(served.connection.isClosed, isTrue);
    },
  );
}

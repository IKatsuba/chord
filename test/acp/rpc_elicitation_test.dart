import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/rpc.dart';
import 'package:chord/acp/schema.dart';
import 'package:test/test.dart';

Future<void> pump() => Future<void>.delayed(Duration.zero);

Map<String, Object?> form(Object? id, {String? sessionId = 's1'}) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': 'elicitation/create',
  'params': {
    'sessionId': ?sessionId,
    'mode': 'form',
    'message': 'Your name?',
    'requestedSchema': {'type': 'object'},
  },
};

void main() {
  late List<Map<String, Object?>> sent;
  late CancellationToken closing;
  late List<String> held;

  AgentRequests requests([ElicitationHandler? onElicitation]) => AgentRequests(
    send: sent.add,
    onPermission: (request, token) async =>
        RequestPermissionResponse.cancelled(),
    closing: closing,
    hold: (sessionId, turn) {
      held.add(sessionId);
      return () => held.add('released $sessionId');
    },
    onElicitation: onElicitation,
  );

  setUp(() {
    sent = [];
    closing = CancellationToken();
    held = [];
  });

  test('without a handler a form is cancelled at once, as the window '
      'declares none', () {
    requests().request(form(1));
    expect(sent.single, {
      'jsonrpc': '2.0',
      'id': 1,
      'result': {'action': 'cancel'},
    });
  });

  test('a handler\'s answer goes as it came, held under its session while it '
      'waits', () async {
    final answer = Completer<Map<String, Object?>>();
    Map<String, Object?>? asked;
    requests((params, token) {
      asked = params;
      return answer.future;
    }).request(form(2));
    expect(asked?['message'], 'Your name?');
    expect(held, ['s1']);
    answer.complete({
      'action': 'accept',
      'content': {'name': 'Ada'},
    });
    await pump();
    expect(sent.single['result'], {
      'action': 'accept',
      'content': {'name': 'Ada'},
    });
    expect(held, ['s1', 'released s1']);
  });

  test(
    'an action ACP does not have, or a handler that fails, is cancel',
    () async {
      final dispatcher = requests((params, token) async {
        if (params['message'] == 'Your name?') return {'action': 'maybe'};
        throw StateError('no');
      });
      dispatcher.request(form(3));
      dispatcher.request({
        ...form(4),
        'params': {'sessionId': 's1', 'mode': 'url', 'message': 'Open it'},
      });
      await pump();
      expect(
        [for (final m in sent) m['result']],
        [
          {'action': 'cancel'},
          {'action': 'cancel'},
        ],
      );
    },
  );

  test('a mode ACP lacks is cancelled before the handler hears it', () {
    var asked = false;
    requests((params, token) async {
      asked = true;
      return {'action': 'accept'};
    }).request({
      ...form(14),
      'params': {'sessionId': 's1', 'mode': 'future', 'message': '?'},
    });
    expect(asked, isFalse);
    expect(sent.single['result'], {'action': 'cancel'});
  });

  test('a request-scoped form is answered without a session hold', () async {
    requests(
      (params, token) async => {'action': 'decline'},
    ).request(form(5, sessionId: null));
    await pump();
    expect(held, isEmpty);
    expect(sent.single['result'], {'action': 'decline'});
  });

  test('the agent withdrawing it, or the connection closing, answers cancel '
      'once, and the handler\'s token is cancelled', () async {
    final tokens = <CancellationToken>[];
    final dispatcher = requests((params, token) {
      tokens.add(token);
      return Completer<Map<String, Object?>>().future;
    });
    dispatcher.request(form(6));
    dispatcher.request(form(7));
    dispatcher.cancelRequest({
      'jsonrpc': '2.0',
      'method': r'$/cancel_request',
      'params': {'requestId': 6},
    });
    expect(tokens.first.isCancelled, isTrue);
    expect(sent.single, {
      'jsonrpc': '2.0',
      'id': 6,
      'result': {'action': 'cancel'},
    });
    closing.cancel();
    expect(tokens.last.isCancelled, isTrue);
    expect(sent.last['id'], 7);
    expect(sent, hasLength(2));
  });

  group('tester U8 elicitation cancellation boundaries', () {
    for (final closes in [false, true]) {
      test(
        '${closes ? 'close' : 'withdrawal'} answers once before late handler settlement',
        () async {
          final answer = Completer<Map<String, Object?>>();
          CancellationToken? token;
          final dispatcher = requests((params, incoming) {
            token = incoming;
            return answer.future;
          });
          dispatcher.request(form('held'));
          expect(dispatcher.running, 1);
          if (closes) {
            closing.cancel();
          } else {
            dispatcher.cancelRequest({
              'jsonrpc': '2.0',
              'method': cancelRequestMethod,
              'params': {'requestId': 'held'},
            });
          }
          expect(token!.isCancelled, isTrue);
          expect(sent, [
            resultMessage('held', {'action': 'cancel'}),
          ]);
          expect(held, ['s1', 'released s1']);
          expect(dispatcher.running, 0);
          answer.completeError(StateError('late handler failure'));
          await pump();
          expect(sent, hasLength(1));
          expect(held, ['s1', 'released s1']);
        },
      );
    }

    test(
      'equal string and number ids hold independent session requests',
      () async {
        final answers = <Completer<Map<String, Object?>>>[];
        final tokens = <CancellationToken>[];
        final dispatcher = requests((params, token) {
          final answer = Completer<Map<String, Object?>>();
          answers.add(answer);
          tokens.add(token);
          return answer.future;
        });
        dispatcher.request(form(1));
        dispatcher.request({
          ...form('1'),
          'params': {'sessionId': 's2', 'mode': 'url', 'message': 'Open'},
        });
        dispatcher.cancelRequest({
          'jsonrpc': '2.0',
          'method': cancelRequestMethod,
          'params': {'requestId': 1},
        });
        expect(tokens.map((t) => t.isCancelled), [true, false]);
        answers[0].complete({'action': 'accept'});
        answers[1].complete({
          'action': 'decline',
          '_meta': {'kept': true},
        });
        await pump();
        expect(sent, [
          resultMessage(1, {'action': 'cancel'}),
          resultMessage('1', {
            'action': 'decline',
            '_meta': {'kept': true},
          }),
        ]);
        expect(held, ['s1', 's2', 'released s1', 'released s2']);
        expect(dispatcher.running, 0);
      },
    );
  });
}

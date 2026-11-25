import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:test/test.dart';

void main() {
  group('tester: successful exit bookkeeping boundaries', () {
    test('opening and late updates preserve immutable metadata and status', () {
      for (final kind in ['tool_call', 'tool_call_update']) {
        for (final status in [
          'pending',
          'in_progress',
          'completed',
          'failed',
        ]) {
          for (final content in [null, const <Object?>[]]) {
            final relay = enricherRelay([rawOutputContent]);
            final sent = <String, Object?>{
              'sessionUpdate': kind,
              'toolCallId': 'read',
              'status': status,
              'rawOutput': const {'exit_code': -0.0},
              'content': ?content,
              '_meta': const {
                'kept': {'nested': true},
                filledKey: ['prior'],
              },
            };
            final result = _send(relay.fromAgent, 'session', sent);
            expect(identical(result, sent), isTrue);
            expect(result, sent);
            expect(filledIn(result), ['prior']);
          }
        }
      }
    });

    test(
      'suppression never takes ownership across sessions or repeated updates',
      () {
        final relay = enricherRelay(m1Enrichers);
        Message send(String session, Message fields) => _send(
          relay.fromAgent,
          session,
          {'toolCallId': 'shared', ...fields},
        );
        send('owned', {
          'sessionUpdate': 'tool_call',
          'content': _text('agent file'),
        });
        for (var i = 0; i < 1000; i++) {
          final result = send('unowned', {
            'sessionUpdate': 'tool_call_update',
            'rawOutput': const {'exit_code': 0},
          });
          expect(result.containsKey('content'), isFalse);
        }
        expect(
          send('unowned', {
            'sessionUpdate': 'tool_call_update',
            'rawOutput': 'later file',
          })['content'],
          _text('later file'),
        );
        expect(
          send('owned', {
            'sessionUpdate': 'tool_call_update',
            'rawOutput': 'must not replace',
          }).containsKey('content'),
          isFalse,
        );
      },
    );

    test('agent terminal and diff content survive bookkeeping unchanged', () {
      for (final content in <List<Message>>[
        [
          {'type': 'terminal', 'terminalId': 'file'},
        ],
        [
          {'type': 'diff', 'path': 'file.dart', 'oldText': '', 'newText': 'x'},
        ],
      ]) {
        final relay = enricherRelay(m1Enrichers);
        final result = _send(relay.fromAgent, 'session', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'read',
          'rawOutput': const {'exit_code': 0},
          'content': content,
        });
        expect(identical(result['content'], content), isTrue);
        expect(
          _send(relay.fromAgent, 'session', {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'read',
            'rawOutput': const {'exit_code': 0},
            'status': 'completed',
          }).containsKey('content'),
          isFalse,
        );
      }
    });
  });
}

Message _send(
  List<Message> Function(Message) fromAgent,
  String session,
  Message fields,
) => notificationOf(
  fromAgent({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {'sessionId': session, 'update': fields},
  }).single,
)!.$2;

List<Message> _text(String value) => [
  {
    'type': 'content',
    'content': {'type': 'text', 'text': value},
  },
];

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/acp/traffic.dart';
import 'package:chord/session/inbox.dart';
import 'package:test/test.dart';

Traffic _update(String id, Map<String, Object?> update) => Traffic.agent({
  'jsonrpc': '2.0',
  'method': 'session/update',
  'params': {'sessionId': id, 'update': update},
});
Traffic _say(String id, String text) => _update(id, {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
});
Traffic _announce(String on, String child) =>
    _update(on, {'sessionUpdate': 'subagent_update', 'sessionId': child});
String _text(acp.SessionUpdate update) => switch (update.toJson()) {
  {'content': {'text': final String text}} => text,
  final json => json['sessionUpdate'] as String,
};

SessionInbox _reopening() => SessionInbox()
  ..beginReopen('session/resume', 'root')
  ..hear(
    Traffic.chord({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'session/resume',
      'params': {'sessionId': 'root'},
    }),
  );
void _reply(SessionInbox inbox) => inbox.hear(
  Traffic.agent({'jsonrpc': '2.0', 'id': 1, 'result': <String, Object?>{}}),
);
void _complete(SessionInbox inbox) => inbox.completeReopen(
  acp.SessionResponse.fromJson({
    'modes': {'currentModeId': 'root-mode', 'availableModes': <Object?>[]},
  }),
  rawHasPast: true,
);

void main() {
  group('tester subscribeAll reopen delivery', () {
    test(
      'subscribeAll alone drains retained early and post-reply updates then later live traffic',
      () {
        final inbox = _reopening();
        inbox.hear(_announce('root', 'child'));
        inbox.hear(_say('child', 'early child'));
        _reply(inbox);
        inbox.hear(_say('root', 'post reply'));
        _complete(inbox);
        inbox.hear(_say('child', 'before subscription'));
        final heard = <(String?, String)>[];
        inbox.subscribeAll((update, id) => heard.add((id, _text(update))));
        expect(heard, [
          (null, 'subagent_update'),
          ('child', 'early child'),
          (null, 'post reply'),
          ('child', 'before subscription'),
        ]);
        inbox.hear(_say('root', 'live root'));
        inbox.hear(_say('child', 'live child'));
        expect(heard.skip(4), [(null, 'live root'), ('child', 'live child')]);
        expect(inbox.subagents, {'child'});
        inbox.close();
      },
    );

    test('child state stays separate during retained drain', () {
      final inbox = _reopening();
      inbox.hear(_announce('root', 'child'));
      inbox.hear(
        _update('child', {
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'child-mode',
        }),
      );
      _reply(inbox);
      _complete(inbox);
      inbox.subscribeAll((_, _) {});
      expect(inbox.state.modes?['currentModeId'], 'root-mode');
      inbox.close();
    });

    test(
      'mixed listener delivery preserves global subscription order and root-only filter',
      () {
        final inbox = SessionInbox()
          ..open(
            'root',
            acp.NewSessionResponse.fromJson({'sessionId': 'root'}),
          );
        final heard = <String>[];
        inbox.subscribeAll(
          (u, id) => heard.add('first:${id ?? 'root'}:${_text(u)}'),
        );
        inbox.subscribe((u) => heard.add('second:root:${_text(u)}'));
        final remove = inbox.subscribeAll(
          (u, id) => heard.add('third:${id ?? 'root'}:${_text(u)}'),
        );
        inbox.hear(_announce('root', 'child'));
        heard.clear();
        inbox.hear(_say('root', 'one'));
        inbox.hear(_say('child', 'two'));
        expect(heard, [
          'first:root:one',
          'second:root:one',
          'third:root:one',
          'first:child:two',
          'third:child:two',
        ]);
        remove();
        heard.clear();
        inbox.hear(_say('child', 'three'));
        expect(heard, ['first:child:three']);
        inbox.close();
      },
    );

    test(
      'reentrant live update during retained drain is delivered once in order',
      () {
        final inbox = _reopening();
        inbox.hear(_say('root', 'first'));
        _reply(inbox);
        inbox.hear(_say('root', 'second'));
        _complete(inbox);
        final heard = <String>[];
        inbox.subscribeAll((u, _) {
          heard.add(_text(u));
          if (_text(u) == 'first') inbox.hear(_say('root', 'reentrant'));
        });
        expect(heard, ['first', 'second', 'reentrant']);
        inbox.hear(_say('root', 'later'));
        expect(heard, ['first', 'second', 'reentrant', 'later']);
        inbox.close();
      },
    );

    test(
      'close during retained delivery drops the tail and future live updates',
      () {
        final inbox = _reopening();
        inbox.hear(_say('root', 'first'));
        _reply(inbox);
        inbox.hear(_say('root', 'tail'));
        _complete(inbox);
        final heard = <String>[];
        inbox.subscribeAll((u, _) {
          heard.add(_text(u));
          inbox.close();
        });
        inbox.hear(_say('root', 'late'));
        inbox.subscribeAll((u, _) => heard.add(_text(u)));
        expect(heard, ['first']);
      },
    );
  });
}

// The inbox's subagents, as the original's openSession routes them through
// its session tree: a subagent's updates reach subscribeAll with its id and
// never the session's own listeners or state.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/acp/traffic.dart';
import 'package:chord/session/inbox.dart';
import 'package:test/test.dart';

Traffic _update(String sessionId, Map<String, Object?> update) =>
    Traffic.agent({
      'jsonrpc': '2.0',
      'method': 'session/update',
      'params': {'sessionId': sessionId, 'update': update},
    });

Traffic _say(String sessionId, String text) => _update(sessionId, {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
});

Traffic _announce(String on, String child) =>
    _update(on, {'sessionUpdate': 'subagent_update', 'sessionId': child});

Traffic _mode(String sessionId, String mode) => _update(sessionId, {
  'sessionUpdate': 'current_mode_update',
  'currentModeId': mode,
});

String _said(acp.SessionUpdate update) => switch (update.toJson()) {
  {'content': {'text': final String text}} => text,
  final json => json['sessionUpdate'] as String,
};

void main() {
  test("a subagent's updates are tagged, held for the first listener, and "
      "never the session's own", () {
    final inbox = SessionInbox()
      ..open(
        's1',
        acp.NewSessionResponse.fromJson({
          'sessionId': 's1',
          'modes': {
            'currentModeId': 'default',
            'availableModes': [
              {'id': 'default', 'name': 'Default'},
              {'id': 'plan', 'name': 'Plan'},
            ],
          },
        }),
      );
    for (final traffic in [
      _say('child', 'before it was announced'),
      _announce('s1', 'child'),
      _say('child', 'from the child'),
      _announce('child', 'grandchild'),
      _say('grandchild', 'from the grandchild'),
      _mode('child', 'plan'),
      _say('s1', 'from the session'),
      _say('stranger', 'never opened'),
    ]) {
      inbox.hear(traffic);
    }
    expect(inbox.subagents, {'child', 'grandchild'});
    // A subagent's mode is not the session's.
    expect(inbox.state.modes?['currentModeId'], 'default');

    final all = <String>[];
    inbox.subscribeAll(
      (update, subagentId) =>
          all.add('${subagentId ?? 's1'}: ${_said(update)}'),
    );
    expect(all, [
      's1: subagent_update',
      'child: from the child',
      'child: subagent_update',
      'grandchild: from the grandchild',
      'child: current_mode_update',
      's1: from the session',
    ]);

    final own = <String>[];
    inbox.subscribe((update) => own.add(_said(update)));
    inbox.hear(_say('grandchild', 'later'));
    inbox.hear(_say('s1', 'own later'));
    expect(own, ['own later']);
    expect(all.skip(6), ['grandchild: later', 's1: own later']);
  });

  test('a plain first listener takes only what was held of the session', () {
    final inbox = SessionInbox()
      ..open('s1', acp.NewSessionResponse.fromJson({'sessionId': 's1'}));
    inbox.hear(_announce('s1', 'child'));
    inbox.hear(_say('child', 'from the child'));
    inbox.hear(_say('s1', 'own'));
    final own = <String>[];
    inbox.subscribe((update) => own.add(_said(update)));
    expect(own, ['subagent_update', 'own']);
  });
}

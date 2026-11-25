// The routing and holding of the original's `openSession`, as a pure inbox,
// and agent_state.ts's fold; subagents' updates are inbox_subagents_test's.
// Left for later: the account's pushes, and a resumed session's past.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/acp/traffic.dart';
import 'package:chord/session/agent_state.dart';
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

String _text(acp.SessionUpdate update) =>
    (update.toJson()['content'] as Map)['text'] as String;

Map<String, Object?> _modeOption(String current) => {
  'id': 'mode',
  'name': 'Mode',
  'category': 'mode',
  'type': 'select',
  'currentValue': current,
  'options': [
    {'value': 'default', 'name': 'Default'},
    {'value': 'plan', 'name': 'Plan'},
  ],
};

acp.NewSessionResponse _answer([Map<String, Object?> more = const {}]) =>
    acp.NewSessionResponse.fromJson({'sessionId': 's1', ...more});

void main() {
  test('updates before the session opens are held, whatever their session, '
      'and routed in arrival order once it does', () {
    final inbox = SessionInbox();
    final heard = <String>[];

    inbox.subscribe((u) => heard.add(_text(u)));
    inbox.hear(_say('s1', 'one'));
    inbox.hear(_say('other', 'stray'));
    inbox.hear(_say('s1', 'two'));

    expect(heard, isEmpty);

    inbox.open('s1', _answer());

    expect(heard, ['one', 'two']);

    inbox.hear(_say('s1', 'three'));
    expect(heard, ['one', 'two', 'three']);
  });

  test('an update for another session is dropped', () {
    final inbox = SessionInbox()..open('s1', _answer());
    final heard = <String>[];

    inbox.subscribe((u) => heard.add(_text(u)));
    inbox.hear(_say('s2', 'not ours'));
    inbox.hear(_say('s1', 'ours'));

    expect(heard, ['ours']);
  });

  test('before the first subscriber routed updates are held, handed to it '
      'synchronously and in order; later subscribers hear only live ones', () {
    final inbox = SessionInbox()..open('s1', _answer());
    final first = <String>[];
    final second = <String>[];

    inbox.hear(_say('s1', 'a'));
    inbox.hear(_say('s1', 'b'));
    inbox.subscribe((u) => first.add(_text(u)));

    expect(first, ['a', 'b']);

    inbox.subscribe((u) => second.add(_text(u)));
    inbox.hear(_say('s1', 'c'));

    expect(first, ['a', 'b', 'c']);
    expect(second, ['c']);
  });

  test('an unsubscribed listener hears nothing more, and with none left '
      'updates are held again', () {
    final inbox = SessionInbox()..open('s1', _answer());
    final first = <String>[];
    final stop = inbox.subscribe((u) => first.add(_text(u)));

    stop();
    inbox.hear(_say('s1', 'held'));

    final next = <String>[];

    inbox.subscribe((u) => next.add(_text(u)));

    expect(first, isEmpty);
    expect(next, ['held']);
  });

  test("only the agent's session/update notifications are heard; an "
      'unknown kind passes', () {
    final inbox = SessionInbox()..open('s1', _answer());
    final heard = <String>[];

    inbox.subscribe((u) => heard.add(u.kind));

    for (final traffic in [
      Traffic.chord({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 's1',
          'update': {'sessionUpdate': 'plan', 'entries': <Object?>[]},
        },
      }),
      Traffic.stderr('noise'),
      Traffic.agent({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'session/update',
        'params': {
          'sessionId': 's1',
          'update': {'sessionUpdate': 'plan'},
        },
      }),
      Traffic.agent({'jsonrpc': '2.0', 'method': 'other/thing'}),
      Traffic.agent({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': 'x',
      }),
      Traffic.agent({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 1,
          'update': {'sessionUpdate': 'plan'},
        },
      }),
      Traffic.agent({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 's1',
          'update': {'sessionUpdate': 3},
        },
      }),
      _update('s1', {'sessionUpdate': 'something_new', 'x': 1}),
    ]) {
      inbox.hear(traffic);
    }

    expect(heard, ['something_new']);
  });

  test("the answer seeds the agent's state first, so an early mode or "
      'option update overrides it', () {
    final inbox = SessionInbox();

    inbox.hear(
      _update('s1', {
        'sessionUpdate': 'current_mode_update',
        'currentModeId': 'plan',
      }),
    );
    inbox.open(
      's1',
      _answer({
        'configOptions': [_modeOption('default')],
        'modes': {'currentModeId': 'default', 'availableModes': <Object?>[]},
        'models': {'currentModelId': 'm'},
      }),
    );

    expect(inbox.state.configOptions.single['currentValue'], 'plan');
    expect(inbox.state.modes!['currentModeId'], 'plan');
    expect(inbox.state.models, {'currentModelId': 'm'});

    inbox.hear(
      _update('s1', {
        'sessionUpdate': 'config_option_update',
        'configOptions': [_modeOption('default')],
      }),
    );

    expect(inbox.state.configOptions.single['currentValue'], 'default');
  });

  test('closing drops what is held, early or for a listener, and every '
      'listener', () {
    final early = SessionInbox();

    early.hear(_say('s1', 'early'));
    early.close();
    early.open('s1', _answer());

    final heard = <String>[];

    early.subscribe((u) => heard.add(_text(u)));
    early.hear(_say('s1', 'late'));

    expect(heard, isEmpty);

    final held = SessionInbox()..open('s1', _answer());

    held.hear(_say('s1', 'held'));
    held.close();
    held.subscribe((u) => heard.add(_text(u)));

    expect(heard, isEmpty);
  });

  group('a listener that closes the inbox while it hears', () {
    test('ends the held drain: nothing after it is heard', () {
      final inbox = SessionInbox()..open('s1', _answer());
      final heard = <String>[];

      inbox.hear(_say('s1', 'a'));
      inbox.hear(_say('s1', 'b'));
      inbox.subscribe((u) {
        heard.add(_text(u));
        inbox.close();
      });
      inbox.hear(_say('s1', 'c'));

      expect(heard, ['a']);
    });

    test("ends open's early drain: nothing after it is routed, folded or "
        'held', () {
      final inbox = SessionInbox();
      final heard = <String>[];

      inbox.subscribe((u) {
        heard.add(u.kind);
        inbox.close();
      });
      inbox.hear(_say('s1', 'a'));
      inbox.hear(
        _update('s1', {
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'plan',
        }),
      );
      inbox.open(
        's1',
        _answer({
          'configOptions': [_modeOption('default')],
        }),
      );

      expect(heard, ['agent_message_chunk']);
      expect(inbox.state.configOptions.single['currentValue'], 'default');

      final later = <String>[];

      inbox.subscribe((u) => later.add(u.kind));

      expect(later, isEmpty);
    });

    test('stops the live delivery to the listeners after it', () {
      final inbox = SessionInbox()..open('s1', _answer());
      final second = <String>[];

      inbox.subscribe((_) => inbox.close());
      inbox.subscribe((u) => second.add(_text(u)));
      inbox.hear(_say('s1', 'a'));

      expect(second, isEmpty);
    });
  });

  group("the agent's state", () {
    test('a session with nothing said has no options, modes, models or '
        'commands', () {
      final state = stateOf(_answer());

      expect(state.configOptions, isEmpty);
      expect(state.modes, isNull);
      expect(state.models, isNull);
      expect(state.commands, isEmpty);
    });

    test('a mode update moves the mode option and the modes, and leaves '
        'other options', () {
      final state = foldUpdate(
        stateOf(
          _answer({
            'configOptions': [
              _modeOption('default'),
              {'id': 'model', 'type': 'select', 'currentValue': 'a'},
            ],
          }),
        ),
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'plan',
        }),
      );

      expect(state.configOptions.map((o) => o['currentValue']), ['plan', 'a']);
      expect(state.modes, isNull);
    });

    test('options that are no list, and kinds that move nothing, leave the '
        'identical state', () {
      final state = stateOf(
        _answer({
          'configOptions': [_modeOption('default')],
        }),
      );

      for (final update in <Map<String, Object?>>[
        {'sessionUpdate': 'config_option_update', 'configOptions': 'x'},
        {'sessionUpdate': 'current_mode_update', 'currentModeId': 3},
        {'sessionUpdate': 'available_commands_update', 'availableCommands': 1},
        {'sessionUpdate': 'agent_message_chunk'},
      ]) {
        expect(
          identical(
            foldUpdate(state, acp.SessionUpdate.fromJson(update)),
            state,
          ),
          isTrue,
          reason: '$update',
        );
      }
      expect(identical(withOptions(state, null), state), isTrue);
    });

    test('the commands the agent offers are kept as it sent them', () {
      final state = foldUpdate(
        AgentState.empty,
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {'name': 'init', 'description': 'Set up'},
          ],
        }),
      );

      expect(state.commands.single.name, 'init');
    });
  });

  group('tester: inbox routing boundaries', () {
    test('a thousand early updates route exactly and drain only once', () {
      final inbox = SessionInbox();
      for (var i = 0; i < 1000; i++) {
        inbox.hear(_say('other', 'stray $i'));
        inbox.hear(_say('s1', '界 e\u0301 👩‍💻\x1b[31m $i'));
      }
      inbox.open('s1', _answer());
      final heard = <String>[];
      final stop = inbox.subscribe((u) => heard.add(_text(u)));
      expect(heard, [
        for (var i = 0; i < 1000; i++) '界 e\u0301 👩‍💻\x1b[31m $i',
      ]);
      stop();
      stop();
      final later = <String>[];
      inbox.subscribe((u) => later.add(_text(u)));
      expect(later, isEmpty);
      inbox.hear(_say('s1', 'live'));
      expect(later, ['live']);
      expect(heard, hasLength(1000));
      inbox.close();
    });

    test(
      'state is folded before live listeners and an unrelated mode is ignored',
      () {
        final inbox = SessionInbox()
          ..open(
            's1',
            _answer({
              'configOptions': [_modeOption('default')],
            }),
          );
        final before = inbox.state;
        final seen = <Object?>[];
        inbox.subscribe(
          (_) => seen.add(inbox.state.configOptions.single['currentValue']),
        );
        inbox.hear(
          _update('other', {
            'sessionUpdate': 'current_mode_update',
            'currentModeId': 'foreign',
          }),
        );
        expect(identical(inbox.state, before), isTrue);
        inbox.hear(
          _update('s1', {
            'sessionUpdate': 'current_mode_update',
            'currentModeId': 'plan',
          }),
        );
        expect(seen, ['plan']);
        expect(before.configOptions.single['currentValue'], 'default');
        inbox.close();
      },
    );
  });
}

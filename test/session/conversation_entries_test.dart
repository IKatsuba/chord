import 'dart:async';

import 'package:chord/acp/rpc.dart' show RpcException;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/starting.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

Map<String, Object?> _select(String id, String category, String current) => {
  'id': id,
  'name': id,
  'category': category,
  'type': 'select',
  'currentValue': current,
  'options': [
    {'value': 'low', 'name': 'Low'},
    {'value': 'medium', 'name': 'Medium'},
    {'value': 'high', 'name': 'High'},
  ],
};

/// A scripted session listing an effort and a model, whose sets move them
/// unless [moves] is false.
ScriptedSession _session({bool moves = true}) {
  final session = ScriptedSession()
    ..state = AgentState(
      configOptions: [
        _select('effort', 'thought_level', 'medium'),
        _select('model', 'model', 'low'),
      ],
    );
  session.change = (kind, id, value) async {
    if (!moves) return;
    session.state = AgentState(
      configOptions: [
        for (final option in session.state.configOptions)
          option['id'] == id ? {...option, 'currentValue': value} : option,
      ],
    );
  };
  return session;
}

/// The conversation started on [session] with [starting]; its events.
List<ConversationEvent> _started(
  FakeAsync async,
  ScriptedSession session,
  Starting starting,
) {
  final events = <ConversationEvent>[];
  Conversation(
      ({required onTraffic, required cancellationToken}) =>
          Future.value(session),
      starting: starting,
    )
    ..listen(events.add)
    ..start();
  async.flushMicrotasks();
  return events;
}

void main() {
  test('an entry not current is set as the client sent it once the session '
      'is up', () {
    fakeAsync((async) {
      final session = _session();
      final events = _started(
        async,
        session,
        const Starting(
          entries: [
            {
              'configId': 'effort',
              'value': 'high',
              '_meta': {'x': 1},
            },
          ],
        ),
      );
      expect(session.entries, [
        {
          'configId': 'effort',
          'value': 'high',
          '_meta': {'x': 1},
        },
      ]);
      expect(events.whereType<Connected>(), hasLength(1));
      expect(events.whereType<ConnectFailed>(), isEmpty);
    });
  });

  test('one already current costs nothing, and one not listed is dropped', () {
    fakeAsync((async) {
      final session = _session();
      final events = _started(
        async,
        session,
        const Starting(
          entries: [
            {'configId': 'effort', 'value': 'medium'},
            {'configId': 'nothing', 'value': 'x'},
          ],
        ),
      );
      expect(session.entries, isEmpty);
      expect(events.whereType<Connected>(), hasLength(1));
    });
  });

  test('a refusal fails the start in its words', () {
    fakeAsync((async) {
      final session = _session()
        ..change = (kind, id, value) async =>
            throw RpcException(-32602, 'the agent says no');
      final events = _started(
        async,
        session,
        const Starting(
          entries: [
            {'configId': 'effort', 'value': 'high'},
          ],
        ),
      );
      expect(events.whereType<Connected>(), isEmpty);
      expect(
        events.whereType<ConnectFailed>().single.message,
        'Could not start with effort high, set by the client: the agent says '
        'no',
      );
    });
  });

  test('an agent that answers and stays on another value fails the start', () {
    fakeAsync((async) {
      final session = _session(moves: false);
      final events = _started(
        async,
        session,
        const Starting(
          entries: [
            {'configId': 'effort', 'value': 'high'},
          ],
        ),
      );
      expect(
        events.whereType<ConnectFailed>().single.message,
        'Could not start with effort high, set by the client: the agent is in '
        'medium',
      );
    });
  });

  test('a client\'s entry beats chord\'s starting value for the same '
      'option', () {
    fakeAsync((async) {
      final session = _session();
      _started(
        async,
        session,
        const Starting(
          model: StartingValue('high'),
          entries: [
            {'configId': 'model', 'value': 'medium'},
          ],
        ),
      );
      expect(session.changes, [('entry', 'model', 'medium')]);
    });
  });

  test('a refusal'
      's words are the agent'
      's details where it gives them', () {
    fakeAsync((async) {
      final session = _session()
        ..change = (kind, id, value) async => throw RpcException(
          -32602,
          'Invalid params',
          data: {'details': ' effort cannot be high '},
        );
      final events = _started(
        async,
        session,
        const Starting(
          entries: [
            {'configId': 'effort', 'value': 'high'},
          ],
        ),
      );
      expect(
        events.whereType<ConnectFailed>().single.message,
        'Could not start with effort high, set by the client: effort cannot '
        'be high',
      );
    });
  });

  test('a session let go while a starting ask is out is sent no entry', () {
    fakeAsync((async) {
      final held = Completer<void>();
      final session = _session();
      final moves = session.change!;
      session.change = (kind, id, value) async {
        if (kind == 'model') await held.future;
        await moves(kind, id, value);
      };
      final conversation = Conversation(
        ({required onTraffic, required cancellationToken}) =>
            Future.value(session),
        starting: const Starting(
          model: StartingValue('high'),
          entries: [
            {'configId': 'effort', 'value': 'high'},
          ],
        ),
      )..start();
      async.flushMicrotasks();
      expect(session.changes, [('model', 'high', null)]);
      conversation.close();
      held.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 7));
      expect(session.entries, isEmpty);
    });
  });

  group('tester U8 retired setup boundaries', () {
    test('retirement during a client entry sends no remaining entries', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        final session = _session();
        final apply = session.change!;
        session.change = (kind, id, value) async {
          await gate.future;
          await apply(kind, id, value);
        };
        final events = <ConversationEvent>[];
        final conversation =
            Conversation(
                ({required onTraffic, required cancellationToken}) =>
                    Future.value(session),
                starting: const Starting(
                  entries: [
                    {'configId': 'effort', 'value': 'high'},
                    {'configId': 'model', 'value': 'medium'},
                  ],
                ),
              )
              ..listen(events.add)
              ..start();
        async.flushMicrotasks();
        expect(session.entries.map((e) => e['configId']), ['effort']);
        conversation.close();
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        expect(session.entries.map((e) => e['configId']), ['effort']);
        expect(events.whereType<Connected>(), isEmpty);
        expect(events.whereType<ConnectFailed>(), isEmpty);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });
  });
}

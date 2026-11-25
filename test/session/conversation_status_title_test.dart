import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:chord/session/subagents.dart' show Heard;
import 'package:test/test.dart';

import 'conversation_fake.dart';

Map<String, Object?> info(Object? title) => {
  'sessionUpdate': 'session_info_update',
  'title': title,
};

/// [updates], each the session's own as it heard them.
List<Heard> own(List<acp.SessionUpdate> updates) => [
  for (final update in updates) (update: update, subagentId: null),
];

void main() {
  test('the title is the last the agent gave or a rename, and null takes it '
      'back', () {
    fakeAsync((async) {
      final session = ScriptedSession()..titles = true;
      final conversation = Conversation(
        ({required onTraffic, required cancellationToken}) =>
            Future.value(session),
      )..start();
      async.flushMicrotasks();
      expect(conversation.title, isNull);
      session.say(info('Fix the tokenizer'));
      async.flushMicrotasks();
      expect(conversation.title, 'Fix the tokenizer');
      // Left out or blank keeps it.
      session.say({'sessionUpdate': 'session_info_update'});
      session.say(info('  '));
      async.flushMicrotasks();
      expect(conversation.title, 'Fix the tokenizer');
      conversation.rename('Renamed');
      async.flushMicrotasks();
      expect(conversation.title, 'Renamed');
      session.say(info(null));
      async.flushMicrotasks();
      expect(conversation.title, isNull);
      conversation.close();
      async.flushMicrotasks();
    });
  });

  test(
    'the first prompt is the first sent, kept, and a clear forgets both',
    () {
      fakeAsync((async) {
        var opens = 0;
        final sessions = [ScriptedSession(), ScriptedSession()];
        final conversation = Conversation(
          ({required onTraffic, required cancellationToken}) =>
              Future.value(sessions[opens++]),
        )..start();
        async.flushMicrotasks();
        expect(conversation.firstPrompt, isNull);
        conversation.send('first');
        async.flushMicrotasks();
        sessions[0].turns.single.answer();
        async.flushMicrotasks();
        conversation.send('second');
        async.flushMicrotasks();
        expect(conversation.firstPrompt, 'first');
        sessions[0].say(info('Old'));
        async.flushMicrotasks();
        conversation.clear();
        async.flushMicrotasks();
        expect((conversation.firstPrompt, conversation.title), (null, null));
        conversation.close();
        async.flushMicrotasks();
      });
    },
  );

  test("a session opened again takes its past's first prompt and title", () {
    fakeAsync((async) {
      final session = ScriptedSession()
        ..prepared = PreparedHistory(
          rawHasPast: true,
          omitted: false,
          actions: const [
            PromptAction('history-1', 'Earlier ask', 0),
            PromptAction('history-2', 'Later ask', 1),
          ],
          title: 'Kept title',
        );
      final conversation = Conversation(
        ({required onTraffic, required cancellationToken}) =>
            Future.value(session),
      )..start();
      async.flushMicrotasks();
      expect(conversation.firstPrompt, 'Earlier ask');
      expect(conversation.title, 'Kept title');
      conversation.close();
      async.flushMicrotasks();
    });
  });

  group("the past's title", () {
    String? recorded(List<Map<String, Object?>> lines) {
      final projection = PreparedHistory.fromJson(
        recordActions([
          {'type': 'session', 'version': 1, 'sessionId': 's', 'agent': 'a'},
          ...lines,
        ]).toJson(),
      );
      return projection.title;
    }

    test('in a record: the last rename or agent title, in order', () {
      expect(recorded([]), isNull);
      expect(
        recorded([
          {'type': 'update', 'turnId': 't', 'update': info('Agent')},
          {'type': 'renamed', 'title': 'Renamed', 'at': 1},
        ]),
        'Renamed',
      );
      expect(
        recorded([
          {'type': 'renamed', 'title': 'Renamed', 'at': 1},
          {'type': 'update', 'turnId': 't', 'update': info('Agent')},
        ]),
        'Agent',
      );
      expect(
        recorded([
          {'type': 'update', 'turnId': 't', 'update': info('Agent')},
          {'type': 'update', 'turnId': 't', 'update': info(null)},
        ]),
        isNull,
      );
      // A subagent's title is not the session's.
      expect(
        recorded([
          {
            'type': 'update',
            'turnId': 't',
            'subagentId': 'x',
            'update': info('Task'),
          },
        ]),
        isNull,
      );
    });

    test("in an agent's replay: its last title", () {
      final history = pastActions(
        own([
          for (final title in ['One', 'Two', ' '])
            acp.SessionUpdate.fromJson(info(title)),
        ]),
        0,
      );
      expect(history.title, 'Two');
    });
  });
}

// A team agent's first prompt carries its team part ahead of the message;
// once cleared, its next prompt, whoever sends it, opens with the part
// again, once.
import 'dart:io';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';
import 'transcript/fold.dart';

const TeamPart _part = (
  team: 'bugfix',
  member: 'tester',
  text: 'You are tester, a member of team bugfix.',
);

void main() {
  group('tester: CTUI-95 persisted cleared-team prompt', () {
    test(
      'saved first-part text replays without separate team instructions',
      () async {
        final dir = await Directory.systemTemp.createTemp('team-part-record-');
        final recorder = FileRecording(
          dir.path,
          failed: fail,
          uuid: () => 'team-part',
        );
        final sessions = <ScriptedSession>[];
        final events = <ConversationEvent>[];
        final conversation = Conversation(({
          required onTraffic,
          required cancellationToken,
        }) async {
          final session = ScriptedSession()..id = 's${sessions.length}';
          sessions.add(session);
          return session;
        }, recording: recorder)..listen(events.add);
        addTearDown(() async {
          await conversation.close();
          await dir.delete(recursive: true);
        });
        conversation.start();
        await Future<void>.delayed(Duration.zero);
        await conversation.clear(_part);
        await Future<void>.delayed(Duration.zero);
        const text = 'From the person: 界🙂e\u0301\n\x1b[31mred\x1b[0m';
        expect(conversation.send(text), isTrue);
        await Future<void>.delayed(Duration.zero);
        final first = sessions.last.turns.single;
        expect(first.text, '${teamBlock(_part)}\n$text');
        first.answer();
        await Future<void>.delayed(Duration.zero);
        expect(conversation.send('Again.'), isTrue);
        await Future<void>.delayed(Duration.zero);
        sessions.last.turns.last.answer();
        await Future<void>.delayed(Duration.zero);
        await conversation.close();
        final file = dir.listSync(recursive: true).whereType<File>().single;
        final raw = await readPast(file.path);
        final replayed = recordActions(
          raw,
        ).actions.whereType<PromptAction>().toList();
        expect(replayed.map((prompt) => prompt.text), [first.text, 'Again.']);
        expect(replayed.every((prompt) => prompt.team == null), isTrue);
        expect(fold(replayed).entries.whereType<TeamPartEntry>(), isEmpty);
        expect(
          events
              .whereType<Transcribed>()
              .map((event) => event.action)
              .whereType<PromptAction>()
              .map((prompt) => prompt.text),
          [text, 'Again.'],
        );
      },
    );
  });

  test('the team part goes ahead of the first message, in <team>', () {
    expect(
      teamBlock(_part),
      '<team name="bugfix" role="member" member="tester">\n'
      'You are tester, a member of team bugfix.\n</team>',
    );
    expect(
      teamBlock((team: 'bugfix', member: null, text: 'Lead.')),
      '<team name="bugfix" role="lead">\nLead.\n</team>',
    );
    fakeAsync((async) {
      final s = Scripted();
      s.conversation.start();
      async.flushMicrotasks();
      const lead = MessageFrom('bugfix', reachable: true);
      s.conversation.deliver(lead, 'Write the test.', _part);
      async.flushMicrotasks();
      expect(
        s.session.turns.single.text,
        wrapTeamMessage(_part, lead, 'Write the test.'),
      );
      expect(
        s.session.turns.single.text,
        '${teamBlock(_part)}\n<message from="bugfix">\nWrite the test.\n'
        '</message>',
      );
      s.conversation.close();
      async.flushMicrotasks();
    });
  });

  test("a cleared team agent's next prompt opens with its part, once", () {
    fakeAsync((async) {
      final sessions = <ScriptedSession>[];
      final conversation = Conversation(({
        required onTraffic,
        required cancellationToken,
      }) {
        final session = ScriptedSession();
        sessions.add(session);
        return Future.value(session);
      });
      conversation.start();
      async.flushMicrotasks();
      conversation.clear(_part).ignore();
      async.elapse(const Duration(seconds: 5));
      expect(sessions, hasLength(2));
      conversation.send('From the person.');
      async.flushMicrotasks();
      expect(
        sessions.last.turns.single.text,
        '${teamBlock(_part)}\nFrom the person.',
      );
      sessions.last.turns.single.answer();
      async.flushMicrotasks();
      conversation.send('Again.');
      async.flushMicrotasks();
      expect(sessions.last.turns.last.text, 'Again.');
      conversation.close();
      async.flushMicrotasks();
    });
  });

  // CTUI-95: as the original's #play, the part goes to the agent only; the
  // person's prompt is drawn without an instructions line, and its record
  // replays the <team> block as the prompt's text.
  test("a cleared team agent's first prompt draws no instructions line, live "
      'or replayed', () {
    fakeAsync((async) {
      final s = Scripted();
      s.conversation.start();
      async.flushMicrotasks();
      s.conversation.clear(_part).ignore();
      async.elapse(const Duration(seconds: 5));
      final from = s.events.length;
      s.conversation.send('From the person.');
      async.flushMicrotasks();
      final sent = s.session.turns.last.text;
      expect(sent, '${teamBlock(_part)}\nFrom the person.');
      final prompts = [
        for (final event in s.events.skip(from))
          if (event case Transcribed(action: final PromptAction prompt)) prompt,
      ];
      expect(prompts.single.text, 'From the person.');
      expect(prompts.single.team, isNull);
      expect(fold(prompts).entries.whereType<TeamPartEntry>(), isEmpty);
      s.conversation.close();
      async.flushMicrotasks();

      final replayed = recordActions([
        {'type': 'prompt', 'turnId': 't', 'prompt': sent, 'images': 0, 'at': 1},
      ]).actions.whereType<PromptAction>().single;
      expect(replayed.text, sent);
      expect(replayed.team, isNull);
    });
  });
}

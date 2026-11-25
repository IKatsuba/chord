// The original's tests/session/conversation_between_test.ts, its forms and
// links on the fake agent: asked with no turn running they wait between
// turns and hold what is queued until the last is answered or withdrawn,
// and `clear` withdraws them.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart' show windowCapabilities;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/elicitations.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

void main() {
  final skip = fakeAgentSkip;
  late List<ConversationEvent> events;
  late Conversation conversation;
  Session? owner;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('chord-between-');
    events = [];
    owner = null;
    conversation = Conversation(
      ({required onTraffic, required CancellationToken cancellationToken}) =>
          openSession(
            agent: 'fake',
            command: fakeAgentCommand(),
            cwd: dir.path,
            open: fakeOpenerWith(capabilities: windowCapabilities()),
            onTraffic: onTraffic,
            cancellationToken: cancellationToken,
          ).then((session) => owner = session),
    )..listen(events.add);
    addTearDown(() async {
      await conversation.close();
      dir.deleteSync(recursive: true);
    });
    conversation.start();
  });

  Future<void> until(bool Function() holds) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!holds()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  List<TranscriptAction> actions() => [
    for (final event in events)
      if (event case Transcribed(:final action)) action,
  ];

  List<ElicitationRequestedAction> asked() =>
      actions().whereType<ElicitationRequestedAction>().toList();

  Future<Session> connected() async {
    await until(() => events.any((e) => e is Connected));
    return owner!;
  }

  Map<String, Object?> form(Session session, String message) => {
    'sessionId': session.id,
    'mode': 'form',
    'message': message,
    'requestedSchema': {'type': 'object', 'properties': <String, Object?>{}},
  };

  Map<String, Object?> link(Session session, String message) => {
    'sessionId': session.id,
    'mode': 'url',
    'message': message,
    'url': 'https://example.com/approve',
    'elicitationId': 'link',
  };

  test('before the first prompt, forms and links wait between turns until '
      'answered', () async {
    final session = await connected();
    final formAnswer = session.elicitations.handler(
      form(session, 'Choose a target'),
      CancellationToken(),
    );
    final linkAnswer = session.elicitations.handler(
      link(session, 'Approve the target'),
      CancellationToken(),
    );
    final [first, second] = asked();
    expect([first.turnId, second.turnId], ['session', 'session']);
    expect(first.elicitation.between && second.elicitation.between, isTrue);
    expect(first.elicitation, isA<FormWait>());
    expect(second.elicitation, isA<LinkWait>());
    // Asked by the session's own agent: no asker named.
    expect(first.elicitation.asker, isNull);
    expect(actions().whereType<PromptAction>(), isEmpty);

    conversation.answer(second.elicitation.id, const DeclineReply());
    expect(await linkAnswer, {'action': 'decline'});
    conversation.answer(
      first.elicitation.id,
      const AcceptReply(<String, Object?>{}),
    );
    expect(await formAnswer, {'action': 'accept', 'content': {}});
    expect(actions().whereType<ElicitationSettledAction>(), hasLength(2));
  }, skip: skip);

  test('a form and a link hold a prompt until the last wait settles', () async {
    final session = await connected();
    final formAnswer = session.elicitations.handler(
      form(session, 'Form'),
      CancellationToken(),
    );
    final withdrawn = CancellationToken();
    final linkAnswer = session.elicitations.handler(
      link(session, 'Link'),
      withdrawn,
    );
    conversation.send('text');
    await until(() => events.whereType<Queued>().isNotEmpty);
    expect(events.whereType<Queued>().every((q) => q.afterAnswer), isTrue);

    conversation.answer(asked().first.elicitation.id, const DeclineReply());
    await formAnswer;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(actions().whereType<PromptAction>(), isEmpty);

    withdrawn.cancel();
    expect(await linkAnswer, {'action': 'cancel'});
    expect(
      actions().whereType<ElicitationSettledAction>().last.answer,
      isA<ElicitationWithdrawn>(),
    );
    await until(() => actions().whereType<PromptAction>().isNotEmpty);
    expect(actions().whereType<PromptAction>().single.text, 'text');
  }, skip: skip);

  test(
    "a prompt sent while a turn's form waits goes once it is answered",
    () async {
      await connected();
      conversation.send('form');
      await until(() => asked().isNotEmpty);
      final id = asked().single.elicitation.id;
      conversation.send('text');
      await until(() => events.whereType<Queued>().isNotEmpty);
      // The turn stays on the form; cancelling it would withdraw it.
      expect(conversation.elicitationRequest(id), isNotNull);
      conversation.answer(id, const DeclineReply());
      await until(() => actions().whereType<ResultAction>().length == 2);
      expect(
        [for (final p in actions().whereType<PromptAction>()) p.text],
        ['form', 'text'],
      );
    },
    skip: skip,
  );

  test('clear withdraws the forms and links the session asked', () async {
    final session = await connected();
    final formAnswer = session.elicitations.handler(
      form(session, 'Form'),
      CancellationToken(),
    );
    final linkAnswer = session.elicitations.handler(
      link(session, 'Link'),
      CancellationToken(),
    );
    final ids = [for (final a in asked()) a.elicitation.id];
    await conversation.clear();
    expect(await formAnswer, {'action': 'cancel'});
    expect(await linkAnswer, {'action': 'cancel'});
    for (final id in ids) {
      expect(conversation.elicitationRequest(id), isNull);
    }
  }, skip: skip);
}

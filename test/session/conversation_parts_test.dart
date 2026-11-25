import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';
import 'recording_conversation_test.dart' show Spy;

const _parts = PromptParts(
  images: [(mimeType: 'image/png', data: 'AAAA')],
  resources: [
    {
      'type': 'resource',
      'resource': {
        'uri': 'file:///n.md',
        'mimeType': 'text/markdown',
        'text': 'x',
      },
    },
  ],
  links: [
    {'type': 'resource_link', 'name': 'a.ts', 'uri': 'file:///a.ts'},
  ],
);

void main() {
  test('a prompt\'s parts reach the agent with it, at once or after the '
      'queue', () {
    fakeAsync((async) {
      final session = ScriptedSession();
      final conversation = Conversation(
        ({required onTraffic, required cancellationToken}) =>
            Future.value(session),
      )..start();
      async.flushMicrotasks();
      conversation.sendTurn('a', 'first', parts: _parts);
      conversation.sendTurn('b', 'second', parts: _parts);
      expect(identical(session.turns.single.parts, _parts), isTrue);
      session.turns.single.answer();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      expect(session.turns, hasLength(2));
      expect(identical(session.turns.last.parts, _parts), isTrue);
      conversation.close();
      async.flushMicrotasks();
    });
  });

  test('a steer carries its parts into the running turn, and its record '
      'keeps them as a prompt'
      's', () {
    fakeAsync((async) {
      final session = ScriptedSession()..steering = true;
      final spy = Spy([]);
      final conversation = Conversation(
        ({required onTraffic, required cancellationToken}) =>
            Future.value(session),
        recording: spy,
      )..start();
      async.flushMicrotasks();
      conversation.send('running');
      conversation.sendTurn('s', 'steer', parts: _parts);
      expect(conversation.steerQueued('s'), 'sent');
      async.flushMicrotasks();
      expect(identical(session.steered.single.parts, _parts), isTrue);
      session.steered.single.answer();
      async.flushMicrotasks();
      final recorded = spy.prompts.last;
      expect(recorded['prompt'], 'steer');
      expect(recorded['images'], 1);
      expect(recorded['resources'], [
        {'uri': 'file:///n.md', 'mimeType': 'text/markdown'},
      ]);
      expect(recorded['links'], _parts.links);
      conversation.close();
      async.flushMicrotasks();
    });
  });

  test('the window\'s prompts carry none', () {
    fakeAsync((async) {
      final session = ScriptedSession();
      final conversation = Conversation(
        ({required onTraffic, required cancellationToken}) =>
            Future.value(session),
      )..start();
      async.flushMicrotasks();
      conversation.send('typed');
      expect(identical(session.turns.single.parts, PromptParts.none), isTrue);
      conversation.close();
      async.flushMicrotasks();
    });
  });

  test('what is submitted keeps a resource\'s uri and type, not its '
      'content', () {
    final submitted = SubmittedContent.fromWire('t', [
      {'type': 'text', 'text': 'look'},
      {'type': 'image', 'mimeType': 'image/png', 'data': 'AAAA'},
      ..._parts.resources,
      ..._parts.links,
    ]);
    expect(submitted.prompt, 'look');
    expect(submitted.images, 1);
    expect(submitted.resources, [
      {'uri': 'file:///n.md', 'mimeType': 'text/markdown'},
    ]);
    expect(submitted.links, _parts.links);
  });
  group('tester U5 queue payload boundaries', () {
    for (final held in [false, true]) {
      test(
        'parts survive ${held ? 'permission hold and release' : 'refused steering and putback'}',
        () {
          fakeAsync((async) {
            final session = ScriptedSession()..steering = true;
            final events = <ConversationEvent>[];
            final spy = Spy([]);
            final conversation =
                Conversation(
                    ({required onTraffic, required cancellationToken}) =>
                        Future.value(session),
                    recording: spy,
                  )
                  ..listen(events.add)
                  ..start();
            async.flushMicrotasks();
            conversation.sendTurn('running', 'running');
            if (held) {
              session.ask().ignore();
              async.flushMicrotasks();
            }
            conversation.sendTurn('payload', 'payload', parts: _parts);
            expect(conversation.steerQueued('payload'), 'sent');
            async.flushMicrotasks();
            if (held) {
              expect(session.steered, isEmpty);
              final wait = events
                  .whereType<Transcribed>()
                  .map((e) => e.action)
                  .whereType<PermissionRequestedAction>()
                  .single
                  .wait;
              conversation.choose(wait.id, 'allow');
              async.flushMicrotasks();
            }
            expect(identical(session.steered.single.parts, _parts), isTrue);
            session.steered.single.answer(
              held ? SteerOutcome.injected : SteerOutcome.refused,
            );
            async.flushMicrotasks();
            if (!held) {
              session.turns.first.answer();
              async.flushMicrotasks();
              async.elapse(const Duration(seconds: 5));
              expect(session.turns, hasLength(2));
              expect(identical(session.turns.last.parts, _parts), isTrue);
            }
            final recorded = spy.prompts.last;
            expect(recorded['images'], 1);
            expect(recorded['resources'], [
              {'uri': 'file:///n.md', 'mimeType': 'text/markdown'},
            ]);
            expect(recorded['links'], _parts.links);
            conversation.close();
            async.flushMicrotasks();
            expect(async.nonPeriodicTimerCount, 0);
          });
        },
      );
    }
  });
}

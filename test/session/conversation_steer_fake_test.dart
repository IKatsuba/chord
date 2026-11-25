@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

Future<void> _until(
  Conversation conversation,
  List<ConversationEvent> events,
  bool Function(ConversationEvent) matches,
) async {
  if (events.any(matches)) return;
  final done = Completer<void>();
  final stop = conversation.listen((event) {
    if (matches(event) && !done.isCompleted) done.complete();
  });
  try {
    await done.future.timeout(const Duration(seconds: 10));
  } finally {
    stop();
  }
}

List<PromptAction> _prompts(List<ConversationEvent> events) => [
  for (final event in events)
    if (event case Transcribed(action: final PromptAction action)) action,
];

void main() {
  for (final adapter in ['claude', 'codex']) {
    test(
      'fake $adapter injects oldest personal text and link once into held turn',
      () async {
        await withSession((session, traffic) async {
          await File('${session.cwd}/notes.txt').writeAsString('held context');
          final conversation = Conversation(
            ({required onTraffic, required cancellationToken}) async => session,
          );
          final events = <ConversationEvent>[];
          conversation.listen(events.add);
          try {
            conversation.start();
            await _until(conversation, events, (event) => event is Connected);
            conversation.send('texttillsteeredheld');
            await _until(
              conversation,
              events,
              (event) => event is Transcribed && event.action is UpdateAction,
            );
            conversation.send(
              'typed @notes.txt',
              'held shell output\n\ntyped @notes.txt',
              ['notes.txt'],
            );
            expect(conversation.steerQueued(), 'sent');
            await _until(
              conversation,
              events,
              (event) =>
                  event is Transcribed &&
                  event.action is PromptAction &&
                  (event.action as PromptAction).into != null,
            );
            expect(_prompts(events).map((p) => (p.text, p.into)), [
              ('texttillsteeredheld', null),
              ('typed @notes.txt', 'turn-1'),
            ]);
            final requests = [
              for (final event in traffic.heard)
                if (event case ChordTraffic(
                  :final message,
                ) when message['method'] == '_session/steering')
                  message,
            ];
            expect(requests, hasLength(1));
            final blocks =
                ((requests.single['params'] as Map)['prompt'] as List)
                    .cast<Map>();
            expect(
              blocks.first['text'],
              'held shell output\n\ntyped @notes.txt',
            );
            expect(blocks.last['name'], 'notes.txt');
            conversation.interrupt();
            await _until(
              conversation,
              events,
              (event) => event is Transcribed && event.action is ResultAction,
            );
            expect(_prompts(events), hasLength(2));
          } finally {
            await conversation.close();
          }
        }, flags: ['--steering', adapter]);
      },
      skip: fakeAgentSkip,
    );
  }
  for (final adapter in ['claude', 'codex24', 'codex']) {
    test(
      'fake late $adapter sends queued personal row once as next client turn',
      () async {
        await withSession((session, traffic) async {
          final conversation = Conversation(
            ({required onTraffic, required cancellationToken}) async => session,
          );
          final events = <ConversationEvent>[];
          conversation.listen(events.add);
          try {
            conversation.start();
            await _until(conversation, events, (event) => event is Connected);
            conversation.send('text');
            conversation.send('slow');
            expect(conversation.steerQueued(), 'sent');
            await _until(
              conversation,
              events,
              (_) => _prompts(events).where((p) => p.text == 'slow').isNotEmpty,
            );
            expect(_prompts(events).map((p) => (p.text, p.into)), [
              ('text', null),
              ('slow', null),
            ]);
            final self = events.whereType<Transcribed>().where(
              (e) => e.action is SelfStartedAction,
            );
            expect(self, hasLength(adapter == 'codex' ? 1 : 0));
            // PromptAction precedes admission; wait for this client's second wire request.
            await traffic.next(
              (event) =>
                  event is ChordTraffic &&
                  event.message['method'] == 'session/prompt' &&
                  ((event.message['params'] as Map)['prompt'] as List).any(
                    (block) => block is Map && block['text'] == 'slow',
                  ),
            );
            final submitted = [
              for (final event in traffic.heard)
                if (event case ChordTraffic(
                  :final message,
                ) when message['method'] == 'session/prompt')
                  message,
            ];
            expect(submitted, hasLength(2));
            expect(
              traffic.said,
              isNot(contains('Started alongside a turn still playing.')),
            );
            if (adapter == 'codex') {
              final cancels = [
                for (final event in traffic.heard)
                  if (event case ChordTraffic(
                    :final message,
                  ) when message['method'] == 'session/cancel')
                    message,
              ];
              expect(cancels, hasLength(1));
            }
            conversation.interrupt();
          } finally {
            await conversation.close();
          }
        }, flags: ['--steering', adapter, '--steer-late']);
      },
      skip: fakeAgentSkip,
    );
  }
}

@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

class _Live {
  _Live(Session session) {
    conversation = Conversation(
      ({required onTraffic, required cancellationToken}) async => session,
    );
    conversation.listen((event) {
      events.add(event);
      changes.add(null);
    });
    conversation.start();
  }
  late final Conversation conversation;
  final events = <ConversationEvent>[];
  final changes = StreamController<void>.broadcast();

  List<TranscriptAction> get actions => [
    for (final event in events)
      if (event case Transcribed(:final action)) action,
  ];
  Future<void> until(bool Function() condition) async {
    if (condition()) return;
    await changes.stream
        .firstWhere((_) => condition())
        .timeout(const Duration(seconds: 20));
  }

  Future<void> close() async {
    await conversation.close();
    await changes.close();
  }
}

void main() {
  group(
    'tester: original fake cycle lifetime boundaries',
    skip: fakeAgentSkip,
    () {
      test(
        'an end with a held permission stays held and its answer opens no cycle',
        () async {
          await withSession((session, _) async {
            final live = _Live(session);
            Future<acp.RequestPermissionResponse>? response;
            void Function() stop = () {};
            void observe(acp.SessionUpdate update) {
              if (response != null || update.kind != 'agent_message_chunk') {
                return;
              }
              final content = update.toJson()['content'];
              if (content is! Map ||
                  !(content['text'] as String).contains(
                    'The background build ended;',
                  )) {
                return;
              }
              response = session.permissions.handler(
                acp.RequestPermissionRequest.fromJson({
                  'sessionId': session.id,
                  'toolCall': {
                    'toolCallId': 'cycle-permission',
                    'title': 'Keep the log',
                  },
                  'options': [
                    {
                      'optionId': 'allow',
                      'name': 'Allow',
                      'kind': 'allow_once',
                    },
                  ],
                }),
                CancellationToken(),
              );
            }

            try {
              await live.until(
                () => live.events.any((event) => event is Connected),
              );
              stop = session.subscribe(observe);
              live.conversation.send('claudecycle');
              await live.until(
                () =>
                    live.actions.whereType<CycleStartedAction>().isNotEmpty &&
                    live.actions.whereType<ResultAction>().length == 2,
              );
              final asked = live.actions
                  .whereType<PermissionRequestedAction>()
                  .single;
              expect(asked.between, isTrue);
              expect(
                asked.turnId,
                live.actions.whereType<CycleStartedAction>().single.turnId,
              );
              final held =
                  live.events.fold(AppState.starting, reduceApp).transcript.turn
                      as AwaitingPermission;
              expect((held.between, held.cycle), (true, false));
              expect(
                live.actions.whereType<PermissionSettledAction>(),
                isEmpty,
              );
              live.conversation.choose(asked.wait.id, 'allow');
              expect((await response!).toJson()['outcome'], {
                'outcome': 'selected',
                'optionId': 'allow',
              });
              await live.until(
                () => live.actions
                    .whereType<PermissionSettledAction>()
                    .isNotEmpty,
              );
              expect(
                live.actions.whereType<CycleStartedAction>(),
                hasLength(1),
              );
              expect(live.actions.whereType<ResultAction>(), hasLength(2));
              expect(
                live.events.fold(AppState.starting, reduceApp).transcript.turn,
                isA<Idle>(),
              );
            } finally {
              stop();
              await live.close();
            }
          }, flags: ['--adapter', 'claude']);
        },
      );

      test('duplicate Esc sends one cancel to the original fake', () async {
        await withSession((session, _) async {
          final live = _Live(session);
          String said() => [
            for (final action in live.actions.whereType<UpdateAction>())
              if (action.update.kind == 'agent_message_chunk')
                (action.update.toJson()['content'] as Map)['text'],
          ].join();
          try {
            await live.until(
              () => live.events.any((event) => event is Connected),
            );
            live.conversation.send('claudecyclebare');
            await live.until(() => said().contains('The build passed.'));
            final cycle = live.actions
                .whereType<CycleStartedAction>()
                .single
                .turnId;
            live.conversation.interrupt();
            live.conversation.interrupt();
            await live.until(
              () => said().contains('Cancel heard with no turn.'),
            );
            live.conversation.send('cancels');
            await live.until(() => said().contains('Cancels with no turn:'));
            expect(said(), contains('Cancels with no turn: 1.'));
            expect(
              live.actions.whereType<CancelAction>().where(
                (a) => a.turnId == cycle,
              ),
              hasLength(1),
            );
            expect(
              live.actions.whereType<ResultAction>().where(
                (a) => a.turnId == cycle,
              ),
              hasLength(1),
            );
          } finally {
            await live.close();
          }
        }, flags: ['--adapter', 'claude', '--say-cancels']);
      });
    },
  );
}

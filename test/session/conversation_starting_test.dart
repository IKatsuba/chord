import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/starting.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';
import 'settings_test.dart' show select, value;

const _file = 'set in .chord/settings.json';

/// An agent listing models, efforts and modes, each changed as asked.
AgentState _offering({
  String model = 'small',
  String effort = 'low',
  String mode = 'default',
}) => AgentState(
  configOptions: [
    select('model', 'model', [value('small'), value('large')], current: model),
    select('effort', 'thought_level', [
      value('low'),
      value('high'),
    ], current: effort),
    select('mode', 'mode', [value('default'), value('plan')], current: mode),
  ],
);

List<String> _failures(Scripted s) => [
  for (final event in s.events)
    if (event case Transcribed(action: FailedAction(:final message))) message,
];

void main() {
  group('tester: CTUI-29 startup retirement ownership', () {
    for (final lateFailure in [false, true]) {
      test(
        'clear retires a held startup before its late ${lateFailure ? 'failure' : 'answer'}',
        () {
          fakeAsync((async) {
            final old = ScriptedSession()..state = _offering();
            final next = ScriptedSession()
              ..state = _offering(model: 'large', effort: 'high', mode: 'plan');
            old.prepared = PreparedHistory(
              rawHasPast: true,
              omitted: false,
              actions: [const PromptAction('old-past', 'retired history', 0)],
            );
            final held = Completer<void>();
            old.change = (kind, id, v) => held.future;
            var opens = 0;
            final events = <ConversationEvent>[];
            final conversation = Conversation(
              ({required onTraffic, required cancellationToken}) async =>
                  opens++ == 0 ? old : next,
              starting: const Starting(
                model: StartingValue('large'),
                effort: StartingValue('high'),
                mode: StartingValue('plan'),
              ),
            )..listen(events.add);
            conversation.start();
            async.flushMicrotasks();
            expect(old.changes, [('model', 'large', null)]);
            var cleared = false;
            conversation.clear().then((_) => cleared = true);
            async.flushMicrotasks();
            expect(cleared, isTrue);
            expect(old.closes, 1);
            expect(events.whereType<Connected>(), hasLength(1));
            expect(next.changes, isEmpty);
            final settled = events.length;
            if (lateFailure) {
              held.completeError(RpcException(-32603, 'retired refusal'));
            } else {
              held.complete();
            }
            async.flushMicrotasks();
            expect(events, hasLength(settled));
            expect(events.whereType<HistoryReplayed>(), isEmpty);
            expect(old.changes, [('model', 'large', null)]);
            conversation.close();
            async.flushMicrotasks();
            expect(old.closes, 1);
            expect(next.closes, 1);
          });
        },
      );
    }

    test(
      'closing cancels a startup permission without publishing connected or history',
      () {
        fakeAsync((async) {
          final s = Scripted(
            starting: const Starting(mode: StartingValue('plan')),
          );
          s.session.state = _offering();
          s.session.prepared = PreparedHistory(
            rawHasPast: true,
            omitted: false,
            actions: [const PromptAction('past', 'earlier', 0)],
          );
          String? outcome;
          s.session.change = (kind, id, v) async {
            outcome = (await s.session.ask()).outcome;
          };
          s.conversation.start();
          async.flushMicrotasks();
          expect(s.session.permissions.pending(), hasLength(1));
          s.conversation.close();
          async.flushMicrotasks();
          expect(outcome, 'cancelled');
          expect(s.session.permissions.pending(), isEmpty);
          expect(s.events.last, isA<Closing>());
          expect(s.events.whereType<Connected>(), isEmpty);
          expect(s.events.whereType<HistoryReplayed>(), isEmpty);
        });
      },
    );

    test(
      'model completion changes the efforts read by the next startup ask',
      () {
        fakeAsync((async) {
          final s = Scripted(
            starting: const Starting(
              model: StartingValue('large'),
              effort: StartingValue('high'),
              mode: StartingValue('plan'),
            ),
          );
          s.session.state = AgentState(
            configOptions: [
              select('model', 'model', [
                value('small'),
                value('large'),
              ], current: 'small'),
              select('old-effort', 'thought_level', [
                value('low'),
              ], current: 'low'),
            ],
          );
          s.session.change = (kind, id, v) async {
            if (kind == 'model') s.session.state = _offering(model: 'large');
          };
          s.conversation.start();
          async.flushMicrotasks();
          expect(s.session.changes, [
            ('model', 'large', null),
            ('option', 'effort', 'high'),
            ('mode', 'plan', null),
          ]);
          expect(_failures(s), isEmpty);
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );

    test(
      'two sessions keep startup permissions and prompt admission independent',
      () {
        fakeAsync((async) {
          final held = Scripted(
            starting: const Starting(mode: StartingValue('plan')),
          );
          final ready = Scripted(
            starting: const Starting(model: StartingValue('large')),
          );
          held.session.state = _offering();
          ready.session.state = _offering();
          held.session.change = (kind, id, v) async {
            await held.session.ask();
          };
          held.conversation.start();
          ready.conversation.start();
          async.flushMicrotasks();
          expect(held.conversation.send('held prompt'), isFalse);
          ready.conversation.send('ready prompt');
          async.flushMicrotasks();
          expect(held.session.turns, isEmpty);
          expect(ready.session.turns.single.text, 'ready prompt');
          expect(held.events.whereType<Connected>(), isEmpty);
          expect(ready.events.whereType<Connected>(), hasLength(1));
          held.conversation.reject(
            held.session.permissions.pending().single.id,
          );
          async.flushMicrotasks();
          expect(held.events.whereType<Connected>(), hasLength(1));
          expect(held.session.turns, isEmpty);
          held.conversation.send('accepted prompt');
          async.flushMicrotasks();
          expect(held.session.turns.single.text, 'accepted prompt');
          held.conversation.close();
          ready.conversation.close();
          async.flushMicrotasks();
        });
      },
    );
  });
  test('the starting model, effort and mode are asked in order before the '
      'session is shown', () {
    fakeAsync((async) {
      final s = Scripted(
        starting: const Starting(
          model: StartingValue('large', from: _file),
          effort: StartingValue('high', from: 'set by --effort'),
          mode: StartingValue('plan', from: _file),
        ),
      );
      s.session.state = _offering();
      s.session.change = (kind, id, v) async {
        final now = s.session.state.configOptions;
        s.session.state = _offering(
          model: kind == 'model' ? id : now[0]['currentValue'] as String,
          effort: kind == 'option' ? v! : now[1]['currentValue'] as String,
          mode: kind == 'mode' ? id : now[2]['currentValue'] as String,
        );
      };
      s.conversation.start();
      async.flushMicrotasks();
      expect(s.session.changes, [
        ('model', 'large', null),
        ('option', 'effort', 'high'),
        ('mode', 'plan', null),
      ]);
      expect(_failures(s), isEmpty);
      expect(s.events.whereType<Connected>(), hasLength(1));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });

  test('a refused value is said with where it was set, before connected, and '
      'the session goes on', () {
    fakeAsync((async) {
      final s = Scripted(
        starting: const Starting(
          model: StartingValue('huge', from: 'set by --model'),
          effort: StartingValue('max', from: _file),
          mode: StartingValue('plan', from: 'set by --permission-mode'),
        ),
      );
      s.session.state = _offering();
      s.session.change = (kind, id, v) => Future.error(
        RpcException(-32603, 'Internal error', data: {'details': 'Not now.'}),
      );
      s.conversation.start();
      async.flushMicrotasks();
      expect(s.session.changes, [('mode', 'plan', null)]);
      expect(_failures(s), [
        'Could not start on huge, set by --model: the agent offers small, '
            'large',
        'Could not start on max effort, $_file: the agent offers low, high',
        'Could not start in plan mode, set by --permission-mode: Not now.',
      ]);
      final failed = s.events.indexWhere(
        (event) => event is Transcribed && event.action is FailedAction,
      );
      expect(failed, lessThan(s.events.indexWhere((e) => e is Connected)));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });

  test('an agent listing no modes or efforts is not asked; a value already '
      'current costs nothing', () {
    fakeAsync((async) {
      final s = Scripted(
        starting: const Starting(
          model: StartingValue('small'),
          effort: StartingValue('high', from: _file),
          mode: StartingValue('plan', from: _file),
        ),
      );
      s.session.state = AgentState(
        configOptions: [
          select('model', 'model', [value('small')], current: 'small'),
        ],
      );
      s.conversation.start();
      async.flushMicrotasks();
      expect(s.session.changes, isEmpty);
      expect(_failures(s), [
        'Could not start on high effort, $_file: the agent offers no efforts',
        'Could not start in plan mode, $_file: the agent offers no modes',
      ]);
      s.conversation.close();
      async.flushMicrotasks();
    });
  });

  test('a change asked while the start applies waits behind it', () {
    fakeAsync((async) {
      final s = Scripted(starting: const Starting(mode: StartingValue('plan')));
      s.session.state = _offering();
      final held = Completer<void>();
      s.session.change = (kind, id, v) =>
          kind == 'mode' && id == 'plan' ? held.future : Future.value();
      s.conversation.start();
      async.flushMicrotasks();
      s.conversation.setModel('large').ignore();
      async.flushMicrotasks();
      expect(s.session.changes, [('mode', 'plan', null)]);
      expect(s.events.whereType<Connected>(), isEmpty);
      held.complete();
      async.flushMicrotasks();
      expect(s.session.changes, [
        ('mode', 'plan', null),
        ('model', 'large', null),
      ]);
      expect(s.events.whereType<Connected>(), hasLength(1));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
  test('with a past, the refusals go first in its batch, as the original '
      'says them before the past', () {
    fakeAsync((async) {
      final s = Scripted(
        starting: const Starting(mode: StartingValue('yolo', from: _file)),
      );
      s.session.state = _offering();
      s.session.resumed = const Resume(sessionId: 's1', cwd: '/w');
      s.session.prepared = PreparedHistory(
        rawHasPast: true,
        omitted: false,
        actions: [const PromptAction('past-1', 'earlier', 0)],
      );
      s.conversation.start();
      async.flushMicrotasks();
      final batch = s.events.whereType<HistoryReplayed>().single.actions;
      expect(batch.first, isA<FailedAction>());
      expect(
        (batch.first as FailedAction).message,
        'Could not start in yolo mode, $_file: the agent offers default, plan',
      );
      expect(batch[1], isA<PromptAction>());
      // Said live as well, then again first in the batch that replaces it.
      expect(_failures(s), hasLength(1));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });

  test('a close while a starting request is out reaches the session at '
      'once', () {
    fakeAsync((async) {
      final s = Scripted(starting: const Starting(mode: StartingValue('plan')));
      s.session.state = _offering();
      final held = Completer<void>();
      s.session.change = (kind, id, v) => held.future;
      s.conversation.start();
      async.flushMicrotasks();
      expect(s.session.changes, [('mode', 'plan', null)]);
      var closed = false;
      s.conversation.close().then((_) => closed = true);
      async.flushMicrotasks();
      expect(s.session.closes, 1);
      expect(closed, isTrue);
      held.complete();
      async.flushMicrotasks();
      expect(s.session.closes, 1);
      expect(s.events.whereType<Connected>(), isEmpty);
    });
  });

  test('a permission a starting setter asks is shown and answered before '
      'connected', () {
    fakeAsync((async) {
      final s = Scripted(starting: const Starting(mode: StartingValue('plan')));
      s.session.state = _offering();
      String? answered;
      s.session.change = (kind, id, v) async {
        answered = (await s.session.ask()).optionId;
      };
      s.conversation.start();
      async.flushMicrotasks();
      expect(
        s.events.any(
          (e) => e is Transcribed && e.action is PermissionRequestedAction,
        ),
        isTrue,
      );
      expect(s.events.whereType<Connected>(), isEmpty);
      s.conversation.choose(s.session.permissions.pending().single.id, 'allow');
      async.flushMicrotasks();
      expect(answered, 'allow');
      expect(s.events.whereType<Connected>(), hasLength(1));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
  AppState fold(Scripted s) => s.events.fold(AppState.starting, reduceApp);

  Scripted resumedWithPast(Future<void> Function(Scripted s) setter) {
    final s = Scripted(
      starting: const Starting(
        model: StartingValue('huge', from: _file),
        mode: StartingValue('plan'),
      ),
    );
    s.session.state = _offering();
    s.session.resumed = const Resume(sessionId: 's1', cwd: '/w');
    s.session.prepared = PreparedHistory(
      rawHasPast: true,
      omitted: false,
      actions: [
        const PromptAction('past-1', 'earlier', 0),
        const ResultAction('past-1', TurnAnswered('end_turn')),
      ],
    );
    s.session.change = (kind, id, v) => setter(s);
    return s;
  }

  test('a startup permission still pending survives the replay and is '
      'answered after it', () {
    fakeAsync((async) {
      String? answered;
      final s = resumedWithPast((s) async {
        s.session.ask().then((r) => answered = r.optionId);
      });
      s.conversation.start();
      async.flushMicrotasks();
      final batch = s.events.whereType<HistoryReplayed>().single.actions;
      expect(batch.map((a) => a.runtimeType), [
        FailedAction,
        PermissionRequestedAction,
        PromptAction,
        ResultAction,
      ]);
      expect(s.events.whereType<Connected>(), hasLength(1));
      final turn = fold(s).transcript.turn;
      expect(turn, isA<AwaitingPermission>());
      s.conversation.choose(s.session.permissions.pending().single.id, 'allow');
      async.flushMicrotasks();
      expect(answered, 'allow');
      expect(fold(s).transcript.turn, isNot(isA<AwaitingPermission>()));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });

  test('a startup permission settled before the replay keeps its rows, in '
      'the order they were said, before the past', () {
    fakeAsync((async) {
      late Scripted held;
      final s = resumedWithPast((s) async {
        final answer = s.session.ask();
        held.conversation.choose(
          s.session.permissions.pending().single.id,
          'allow',
        );
        await answer;
      });
      held = s;
      s.conversation.start();
      async.flushMicrotasks();
      final batch = s.events.whereType<HistoryReplayed>().single.actions;
      expect(batch.map((a) => a.runtimeType), [
        FailedAction,
        PermissionRequestedAction,
        PermissionSettledAction,
        PromptAction,
        ResultAction,
      ]);
      expect(
        (batch.first as FailedAction).message,
        'Could not start on huge, $_file: the agent offers small, large',
      );
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
}

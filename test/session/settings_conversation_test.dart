import 'dart:async';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/choice.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'conversation_fake.dart';
import 'settings_test.dart' show select, value;

void main() {
  test(
    'setting requests serialize during a turn and recover after refusal',
    () {
      fakeAsync((async) {
        final s = Scripted();
        s.conversation.start();
        async.flushMicrotasks();
        s.conversation.send('running');
        final first = Completer<void>();
        s.session.change = (kind, id, v) =>
            id == 'plan' ? first.future : Future.value();
        final mode = s.conversation.setMode('plan');
        final model = s.conversation.setModel('small');
        final config = s.conversation.setOption('effort', 'low');
        mode.ignore();
        model.ignore();
        config.ignore();
        async.flushMicrotasks();
        expect(s.session.changes, [('mode', 'plan', null)]);
        first.completeError(StateError('refused'));
        async.flushMicrotasks();
        expect(s.session.changes, [
          ('mode', 'plan', null),
          ('model', 'small', null),
          ('option', 'effort', 'low'),
        ]);
        expect(
          s.events
              .whereType<Transcribed>()
              .map((e) => e.action)
              .whereType<FailedAction>()
              .single
              .message,
          contains('Could not switch to plan mode'),
        );
        expect(s.events.whereType<ModePending>().map((e) => e.pending), [
          true,
          false,
        ]);
        expect(s.session.turns, hasLength(1));
        s.conversation.close();
        async.flushMicrotasks();
      });
    },
  );
  test(
    'model then effort uses post-answer option id and replaces one pending note',
    () {
      fakeAsync((async) {
        final s = Scripted();
        s.session.state = AgentState(
          configOptions: [
            select('old', 'thought_level', [value('high')]),
          ],
        );
        s.conversation.start();
        async.flushMicrotasks();
        s.session.change = (kind, id, v) async {
          s.session.state = AgentState(
            configOptions: [
              select('fresh', 'thought_level', [
                value('high', 'High'),
              ], current: kind == 'model' ? 'low' : 'high'),
            ],
          );
        };
        s.conversation
            .makeChoice(
              const ModelChoice(
                model: (id: 'small', name: 'Small'),
                effort: (option: 'old', value: 'high', name: 'High'),
              ),
              'model',
            )
            .ignore();
        expect(
          s.events.whereType<SettingNoted>().single.text,
          'Switching to Small…',
        );
        async.flushMicrotasks();
        expect(s.session.changes, [
          ('model', 'small', null),
          ('option', 'fresh', 'high'),
        ]);
        final notes = s.events.whereType<SettingNoted>().toList();
        expect(notes.map((n) => n.id).toSet(), hasLength(1));
        expect(notes.last.text, 'Switched to Small · High effort');
        s.conversation.close();
        async.flushMicrotasks();
      });
    },
  );
  test('unsupported post-model effort stays unsent and retains model', () {
    fakeAsync((async) {
      final s = Scripted();
      s.conversation.start();
      async.flushMicrotasks();
      s.conversation
          .makeChoice(
            const ModelChoice(
              model: (id: 'small', name: 'Small'),
              effort: (option: 'old', value: 'high', name: 'High'),
            ),
            'model',
          )
          .ignore();
      async.flushMicrotasks();
      expect(s.session.changes, [('model', 'small', null)]);
      expect(
        s.events.whereType<SettingNoted>().last.text,
        'Switched to Small; it offers no High effort.',
      );
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
  test(
    'close retires queued operations and drops late results and effort calls',
    () {
      fakeAsync((async) {
        final s = Scripted();
        s.conversation.start();
        async.flushMicrotasks();
        final ack = Completer<void>();
        s.session.change = (_, _, _) => ack.future;
        s.conversation
            .makeChoice(
              const ModelChoice(
                model: (id: 'small', name: 'Small'),
                effort: (option: 'old', value: 'high', name: 'High'),
              ),
              'model',
            )
            .ignore();
        s.conversation.setMode('plan').ignore();
        async.flushMicrotasks();
        s.conversation.close();
        async.flushMicrotasks();
        final count = s.events.length;
        ack.complete();
        async.flushMicrotasks();
        expect(s.session.changes, [('model', 'small', null)]);
        expect(s.events.length, count);
        expect(s.events.last, isA<Closing>());
      });
    },
  );
  test('exact effort and fast look up options when their link runs', () {
    fakeAsync((async) {
      final s = Scripted();
      s.conversation.start();
      async.flushMicrotasks();
      final ack = Completer<void>();
      s.session.change = (kind, id, v) async {
        if (kind == 'model') {
          await ack.future;
          s.session.state = AgentState(
            configOptions: [
              select('reason', 'thought_level', [value('high', 'High')]),
              {
                ...select('speed', 'model_config', [
                  value('off'),
                  value('on'),
                ], current: 'off'),
                '_meta': {'chord/parameter': 'fast'},
              },
            ],
          );
        }
      };
      s.conversation.setModel('small').ignore();
      s.conversation.setEffortById('fake', 'high', 'effort high').ignore();
      s.conversation.toggleFast('fake').ignore();
      async.flushMicrotasks();
      ack.complete();
      async.flushMicrotasks();
      expect(s.session.changes, [
        ('model', 'small', null),
        ('option', 'reason', 'high'),
        ('option', 'speed', 'on'),
      ]);
      expect(
        s.events
            .whereType<SettingNoted>()
            .where((n) => n.command == 'effort high')
            .map((n) => n.id)
            .toSet(),
        hasLength(1),
      );
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
  test(
    'pending note listener can close before a request reaches the agent',
    () {
      fakeAsync((async) {
        final s = Scripted();
        s.conversation.start();
        async.flushMicrotasks();
        s.conversation.listen((e) {
          if (e is SettingNoted) s.conversation.close();
        });
        s.conversation
            .makeChoice(const ModelChoice(model: (id: 'm', name: 'M')), 'model')
            .ignore();
        async.flushMicrotasks();
        expect(s.session.changes, isEmpty);
      });
    },
  );
}

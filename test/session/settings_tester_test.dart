import 'dart:async';

import 'package:chord/session/choice.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

void main() {
  group('tester session setting lifecycle', () {
    test('a hanging setting holds only its own session queue', () {
      fakeAsync((async) {
        final first = Scripted();
        final second = Scripted();
        first.conversation.start();
        second.conversation.start();
        async.flushMicrotasks();
        final ack = Completer<void>();
        first.session.change = (_, _, _) => ack.future;
        first.conversation.setModel('held').ignore();
        first.conversation.setOption('effort', 'high').ignore();
        second.conversation.setMode('plan').ignore();
        second.conversation.setModel('independent').ignore();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(first.session.changes, [('model', 'held', null)]);
        expect(second.session.changes, [
          ('mode', 'plan', null),
          ('model', 'independent', null),
        ]);
        expect(first.events.whereType<ModePending>(), isEmpty);
        expect(second.events.whereType<ModePending>().map((e) => e.pending), [
          true,
          false,
        ]);
        first.conversation.close();
        second.conversation.close();
        async.flushMicrotasks();
        final count = first.events.length;
        ack.completeError(StateError('late refusal'));
        async.flushMicrotasks();
        expect(first.session.changes, [('model', 'held', null)]);
        expect(first.events, hasLength(count));
        expect(first.events.last, isA<Closing>());
        expect(first.session.closes, 1);
        expect(second.session.closes, 1);
      });
    });

    test('turn cancellation leaves setting serialization independent', () {
      fakeAsync((async) {
        final s = Scripted();
        s.conversation.start();
        async.flushMicrotasks();
        s.conversation.send('running');
        final ack = Completer<void>();
        s.session.change = (kind, _, _) =>
            kind == 'model' ? ack.future : Future.value();
        s.conversation.setModel('small').ignore();
        s.conversation.setMode('plan').ignore();
        async.flushMicrotasks();
        s.conversation.interrupt();
        async.flushMicrotasks();
        expect(s.session.cancels, 1);
        s.session.turns.single.answer(const TurnAnswered('cancelled'));
        async.flushMicrotasks();
        expect(s.session.changes, [('model', 'small', null)]);
        ack.complete();
        async.flushMicrotasks();
        expect(s.session.changes, [
          ('model', 'small', null),
          ('mode', 'plan', null),
        ]);
        expect(s.session.turns, hasLength(1));
        expect(s.events.whereType<ModePending>().map((e) => e.pending), [
          true,
          false,
        ]);
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    test('a refused model skips effort and releases the next setting', () {
      fakeAsync((async) {
        final s = Scripted();
        s.conversation.start();
        async.flushMicrotasks();
        s.session.change = (kind, _, _) => kind == 'model'
            ? Future.error(StateError('model refused'))
            : Future.value();
        s.conversation
            .makeChoice(
              const ModelChoice(
                model: (id: 'small', name: 'Small'),
                effort: (option: 'effort', value: 'high', name: 'High'),
              ),
              'model',
            )
            .ignore();
        s.conversation.setOption('independent', 'next').ignore();
        async.flushMicrotasks();
        expect(s.session.changes, [
          ('model', 'small', null),
          ('option', 'independent', 'next'),
        ]);
        final notes = s.events.whereType<SettingNoted>().toList();
        expect(notes, hasLength(2));
        expect(notes.first.id, notes.last.id);
        expect(notes.last.failed, isTrue);
        expect(notes.last.text, contains('Could not switch to Small'));
        expect(notes.last.text, contains('model refused'));
        s.conversation.close();
        async.flushMicrotasks();
      });
    });
  });
}

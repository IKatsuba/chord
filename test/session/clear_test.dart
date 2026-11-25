import 'dart:async';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/prompt.dart' show endOf;
import 'package:chord/ui/start_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'conversation_fake.dart';

void main() {
  test('clear reducer keeps window draft, cursor and verbose preference', () {
    final before = AppState(
      draft: 'kept draft',
      cursor: endOf('kept draft'),
      expanded: true,
      transcript: const Transcript(entries: [UserEntry('old', 'old')]),
    );
    final after = reduceApp(before, const Cleared());
    expect(after.draft, before.draft);
    expect(after.cursor, before.cursor);
    expect(after.expanded, isTrue);
    expect(after.transcript.entries, isEmpty);
    expect(after.start.phase, StartPhase.starting);
  });

  test(
    'clear retires queued settings and turns without holding a fresh session',
    () {
      fakeAsync((async) {
        final old = ScriptedSession(), fresh = ScriptedSession();
        var opens = 0;
        final c = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              opens++ == 0 ? old : fresh,
        );
        final events = <ConversationEvent>[];
        var app = AppState.starting;
        c.listen((e) {
          events.add(e);
          app = reduceApp(app, e);
        });
        c.start();
        async.flushMicrotasks();
        c.send('running');
        c.send('queued');
        final ack = Completer<void>();
        old.change = (_, _, _) => ack.future;
        c.setModel('old-hung').ignore();
        c.setMode('old-queued').ignore();
        async.flushMicrotasks();
        c.clear();
        async.flushMicrotasks();
        expect(opens, 2);
        // Closed once its cancelled turn has had its say, as the original.
        async.elapse(const Duration(milliseconds: settleLimitMs + quietMs));
        expect(old.closes, 1);
        expect(
          events.whereType<QueueWithdrawn>().single.prompts.single.text,
          'queued',
        );
        expect(events.whereType<Cleared>(), hasLength(1));
        expect(app.start.phase, StartPhase.connected);
        expect(app.transcript.entries, isEmpty);
        c.setMode('fresh-mode').ignore();
        async.flushMicrotasks();
        expect(fresh.changes, [('mode', 'fresh-mode', null)]);
        c.send('fresh');
        async.flushMicrotasks();
        final count = events.length;
        ack.completeError(StateError('late refusal'));
        old.turns.single.answer();
        old.chunk('late text');
        async.flushMicrotasks();
        expect(events.length, count);
        expect(old.changes, [('model', 'old-hung', null)]);
        expect(fresh.turns.single.text, 'fresh');
        c.close();
        async.flushMicrotasks();
        expect(fresh.closes, 1);
      });
    },
  );
  test(
    'clear while opening isolates the late session and close awaits retirements',
    () {
      fakeAsync((async) {
        final opening = Completer<Session>();
        final old = ScriptedSession(), fresh = ScriptedSession();
        var opens = 0;
        final c = Conversation(
          ({required onTraffic, required cancellationToken}) =>
              opens++ == 0 ? opening.future : Future.value(fresh),
        );
        final events = <ConversationEvent>[];
        c.listen(events.add);
        c.start();
        c.clear();
        async.flushMicrotasks();
        expect(events.whereType<Connected>(), hasLength(1));
        var closed = false;
        c.close().then((_) => closed = true);
        async.flushMicrotasks();
        expect(closed, isFalse);
        opening.complete(old);
        async.flushMicrotasks();
        expect(old.closes, 1);
        expect(fresh.closes, 1);
        expect(closed, isTrue);
        expect(events.whereType<Connected>(), hasLength(1));
        expect(events.last, isA<Closing>());
      });
    },
  );
  test(
    'retired permission withdrawal cannot settle a replacement request with same id',
    () {
      fakeAsync((async) {
        final old = ScriptedSession(), fresh = ScriptedSession();
        var opens = 0;
        final c = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              opens++ == 0 ? old : fresh,
        );
        var app = AppState.starting;
        c.listen((e) => app = reduceApp(app, e));
        c.start();
        async.flushMicrotasks();
        old.ask();
        async.flushMicrotasks();
        c.clear();
        async.flushMicrotasks();
        final answer = fresh.ask();
        async.flushMicrotasks();
        final wait =
            (app.transcript.turn as AwaitingPermission).permissions.single;
        c.choose(wait.id, 'allow');
        async.flushMicrotasks();
        var answered = false;
        answer.then((_) => answered = true);
        async.flushMicrotasks();
        expect(answered, isTrue);
        c.close();
        async.flushMicrotasks();
      });
    },
  );
  test('a clear listener can close before the replacement starts', () {
    fakeAsync((async) {
      var opens = 0;
      final session = ScriptedSession();
      final c = Conversation(({
        required onTraffic,
        required cancellationToken,
      }) async {
        opens++;
        return session;
      });
      c.listen((e) {
        if (e is Cleared) c.close();
      });
      c.start();
      async.flushMicrotasks();
      c.clear();
      async.flushMicrotasks();
      expect(opens, 1);
      expect(session.closes, 1);
      expect(c.send('late'), isFalse);
    });
  });
}

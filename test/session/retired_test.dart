// A session /clear or a resume let go: it closes once its turn has said what
// it cost, its figures go to its own record only, and the session that
// follows never sees them; as the original's conversation.ts retirement.

import 'dart:async';

import 'package:chord/session/agent_state.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

/// A conversation over [sessions] in turn, its events, its app state and
/// the lines a recording appended, by path.
class _Rig {
  _Rig(this.sessions) {
    conversation = Conversation(
      ({required onTraffic, required cancellationToken}) async =>
          sessions[opens++],
      recording: recording,
    );
    conversation.listen((event) {
      events.add(event);
      app = reduceApp(app, event);
    });
  }

  final List<ScriptedSession> sessions;
  var opens = 0;
  late final Conversation conversation;
  final events = <ConversationEvent>[];
  var app = AppState.starting;
  final lines = <String, List<Map<String, Object?>>>{};
  var _records = 0;
  late final recording = FileRecording(
    'state',
    failed: fail,
    uuid: () => 'record-${++_records}',
    append: (path, text) async => (lines[path] ??= []).addAll(
      parseRecord(text).cast<Map<String, Object?>>(),
    ),
  );

  List<Map<String, Object?>> usageIn(String path) => [
    for (final line in lines[path] ?? const <Map<String, Object?>>[])
      if (line['type'] == 'usage') line,
  ];

  String get firstPath => lines.keys.first;
}

Map<String, Object?> _cost(num amount) => {
  'sessionUpdate': 'usage_update',
  'used': 10,
  'size': 100,
  'cost': {'amount': amount, 'currency': 'USD'},
};

const _retire = Duration(milliseconds: settleLimitMs + quietMs);

void main() {
  group('tester: CTUI-29 retired record ownership', () {
    test('overlapping resume swaps retain each old turn in its own record', () {
      fakeAsync((async) {
        final first = ScriptedSession(),
            second = ScriptedSession(),
            third = ScriptedSession();
        final lines = <String, List<Map<String, Object?>>>{};
        var records = 0, reopens = 0;
        final recording = FileRecording(
          'state',
          failed: fail,
          uuid: () => 'swap-${++records}',
          append: (path, text) async => (lines[path] ??= []).addAll(
            parseRecord(text).cast<Map<String, Object?>>(),
          ),
        );
        final events = <ConversationEvent>[];
        var app = AppState.starting;
        final conversation =
            Conversation(
              ({required onTraffic, required cancellationToken}) async => first,
              reopen:
                  (
                    resume, {
                    required onTraffic,
                    required cancellationToken,
                  }) async => reopens++ == 0 ? second : third,
              recording: recording,
            )..listen((event) {
              events.add(event);
              app = reduceApp(app, event);
            });
        conversation.start();
        async.flushMicrotasks();
        conversation.send('first');
        async.flushMicrotasks();
        first.say(_cost(0.1));
        conversation.resume(const Resume(sessionId: 'second', cwd: '/w'));
        async.flushMicrotasks();
        conversation.send('second');
        async.flushMicrotasks();
        second.say(_cost(0.2));
        conversation.resume(const Resume(sessionId: 'third', cwd: '/w'));
        async.flushMicrotasks();
        second.turns.single.answer(
          const TurnAnswered('cancelled', usage: {'inputTokens': 2}),
        );
        first.turns.single.answer(
          const TurnAnswered('cancelled', usage: {'inputTokens': 1}),
        );
        first.say(_cost(0.15));
        async.flushMicrotasks();
        async.elapse(_retire);
        expect((first.closes, second.closes, third.closes), (1, 1, 0));
        final usage = {
          for (final entry in lines.entries)
            entry.key: entry.value
                .where((line) => line['type'] == 'usage')
                .toList(),
        };
        expect(usage, hasLength(2));
        final paths = usage.keys.toList();
        expect(
          usage[paths[0]]!.every((line) => line['turnId'] == 'turn-1'),
          isTrue,
        );
        expect(usage[paths[0]]!.last['usage'], {'inputTokens': 1});
        expect((usage[paths[0]]!.last['cost'] as Map)['amount'], 0.15);
        expect(usage[paths[1]]!.single['turnId'], 'turn-2');
        expect(usage[paths[1]]!.single['usage'], {'inputTokens': 2});
        expect(app.spent, isNull);
        expect(app.transcript.entries, isEmpty);
        conversation.close();
        async.flushMicrotasks();
        expect(third.closes, 1);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('quit joins a delayed retired usage append after the turn closes', () {
      fakeAsync((async) {
        final old = ScriptedSession(), fresh = ScriptedSession();
        final gate = Completer<void>();
        final lines = <Map<String, Object?>>[];
        var blocked = false, opens = 0, records = 0;
        final recording = FileRecording(
          'state',
          failed: fail,
          uuid: () => 'delayed-${++records}',
          append: (path, text) async {
            final parsed = parseRecord(text).cast<Map<String, Object?>>();
            if (parsed.any((line) => line['type'] == 'usage')) {
              blocked = true;
              await gate.future;
            }
            lines.addAll(parsed);
          },
        );
        final events = <ConversationEvent>[];
        final conversation = Conversation(
          ({required onTraffic, required cancellationToken}) async =>
              opens++ == 0 ? old : fresh,
          recording: recording,
        )..listen(events.add);
        conversation.start();
        async.flushMicrotasks();
        conversation.send('old');
        async.flushMicrotasks();
        old.say(_cost(0.25));
        conversation.clear();
        async.flushMicrotasks();
        old.onClose = () => old.turns.single.answer(
          const TurnAnswered('cancelled', usage: {'outputTokens': 7}),
        );
        var closed = false;
        conversation.close().then((_) => closed = true);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: quietMs));
        expect(old.closes, 1);
        expect(fresh.closes, 1);
        expect(blocked, isTrue);
        expect(closed, isFalse);
        gate.complete();
        async.flushMicrotasks();
        expect(closed, isTrue);
        expect(lines.where((line) => line['type'] == 'usage').single['usage'], {
          'outputTokens': 7,
        });
        final closing = events.indexWhere((event) => event is Closing);
        expect(events.skip(closing + 1), [isA<RetiredUsage>()]);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test(
      'late updates cannot extend a no-answer retirement past its bound',
      () {
        fakeAsync((async) {
          final old = ScriptedSession(), fresh = ScriptedSession();
          final rig = _Rig([old, fresh]);
          rig.conversation.start();
          async.flushMicrotasks();
          rig.conversation.send('never answers');
          async.flushMicrotasks();
          rig.conversation.clear();
          async.flushMicrotasks();
          for (var tick = 1; tick <= 5; tick++) {
            async.elapse(const Duration(milliseconds: 900));
            old.say(_cost(tick / 100));
            async.flushMicrotasks();
          }
          expect(old.closes, 0);
          async.elapse(const Duration(milliseconds: 500));
          expect(old.closes, 1);
          async.elapse(const Duration(milliseconds: quietMs));
          final delivered = rig.events.length;
          old.turns.single.answer(
            const TurnAnswered('cancelled', usage: {'inputTokens': 99}),
          );
          async.flushMicrotasks();
          expect(rig.events, hasLength(delivered));
          expect(rig.usageIn(rig.firstPath), isEmpty);
          expect(rig.app.spent, isNull);
          rig.conversation.close();
          async.flushMicrotasks();
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );
  });
  test("a cleared turn's cancelled answer and late cost go to the old record "
      'only, and the new session never sees them', () {
    fakeAsync((async) {
      final old = ScriptedSession(), fresh = ScriptedSession();
      final rig = _Rig([old, fresh]);
      rig.conversation.start();
      async.flushMicrotasks();
      rig.conversation.send('running');
      async.flushMicrotasks();
      old.say(_cost(0.01));
      rig.conversation.clear();
      async.flushMicrotasks();
      // Not closed until its turn has had its say.
      expect(old.closes, 0);
      old.turns.single.answer(
        const TurnAnswered('cancelled', usage: {'inputTokens': 9}),
      );
      async.flushMicrotasks();
      old.say(_cost(0.04));
      async.flushMicrotasks();
      async.elapse(_retire);
      expect(old.closes, 1);
      expect(rig.events.whereType<RetiredUsage>(), hasLength(2));
      expect(rig.events.whereType<RetiredUpdate>(), hasLength(1));

      // The new session's own turn, in its own record.
      rig.conversation.send('fresh');
      async.flushMicrotasks();
      fresh.turns.single.answer(
        const TurnAnswered('end_turn', usage: {'outputTokens': 3}),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      rig.recording.flushed();
      async.flushMicrotasks();

      final paths = rig.lines.keys.toList();
      expect(paths, hasLength(2));
      final oldUsage = rig.usageIn(paths.first);
      expect(oldUsage.map((l) => l['turnId']).toSet(), {'turn-1'});
      expect(oldUsage.first['usage'], {'inputTokens': 9});
      expect((oldUsage.last['cost'] as Map)['amount'], closeTo(0.04, 1e-12));
      expect(
        rig.lines[paths.first]!
            .where((l) => l['type'] == 'update')
            .last['update'],
        _cost(0.04),
      );
      final freshUsage = rig.usageIn(paths.last);
      expect(freshUsage.single['usage'], {'outputTokens': 3});
      // The window: only the new session's spend, no old figure.
      expect(rig.app.spent!.turns.keys, [freshUsage.single['turnId']]);
      expect(rig.app.spent!.costs, isNull);
      expect(rig.app.transcript.usage, isNull);
      rig.conversation.close();
      async.flushMicrotasks();
    });
  });

  test('quitting while a session is retiring closes it at once', () {
    fakeAsync((async) {
      final old = ScriptedSession(), fresh = ScriptedSession();
      final rig = _Rig([old, fresh]);
      rig.conversation.start();
      async.flushMicrotasks();
      rig.conversation.send('never answered');
      async.flushMicrotasks();
      rig.conversation.clear();
      async.flushMicrotasks();
      expect(old.closes, 0);
      var closed = false;
      rig.conversation.close().then((_) => closed = true);
      async.flushMicrotasks();
      expect(old.closes, 1);
      expect(fresh.closes, 1);
      // Its close may still answer its turn: a quiet's wait at most.
      async.elapse(const Duration(milliseconds: quietMs));
      expect(closed, isTrue);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('a second clear while one session retires leaves no session open', () {
    fakeAsync((async) {
      final first = ScriptedSession(), second = ScriptedSession();
      final third = ScriptedSession();
      final rig = _Rig([first, second, third]);
      rig.conversation.start();
      async.flushMicrotasks();
      rig.conversation.send('first turn');
      async.flushMicrotasks();
      rig.conversation.clear();
      async.flushMicrotasks();
      rig.conversation.send('second turn');
      async.flushMicrotasks();
      rig.conversation.clear();
      async.flushMicrotasks();
      expect((first.closes, second.closes), (0, 0));
      async.elapse(_retire);
      expect((first.closes, second.closes, third.closes), (1, 1, 0));
      expect(async.nonPeriodicTimerCount, 0);
      rig.conversation.close();
      async.flushMicrotasks();
      expect(third.closes, 1);
    });
  });

  test('a session let go with no turn running closes once quiet', () {
    fakeAsync((async) {
      final old = ScriptedSession(), fresh = ScriptedSession();
      old.state = AgentState.empty;
      final rig = _Rig([old, fresh]);
      rig.conversation.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      rig.conversation.clear();
      async.flushMicrotasks();
      expect(old.closes, 1);
      rig.conversation.close();
      async.flushMicrotasks();
    });
  });
  test("a quit that closes the retiring session keeps its turn's last "
      'figures in its own record, and listeners hear them as retired usage '
      'only', () {
    fakeAsync((async) {
      final old = ScriptedSession(), fresh = ScriptedSession();
      final rig = _Rig([old, fresh]);
      rig.conversation.start();
      async.flushMicrotasks();
      rig.conversation.send('running');
      async.flushMicrotasks();
      old.say(_cost(0.02));
      rig.conversation.clear();
      async.flushMicrotasks();
      // Its close answers the turn it was still asked, with its usage.
      old.onClose = () => old.turns.single.answer(
        const TurnAnswered('cancelled', usage: {'inputTokens': 12}),
      );
      final before = rig.events.length;
      final app = rig.app;
      var closed = false;
      rig.conversation.close().then((_) => closed = true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      expect(closed, isTrue);
      expect(old.closes, 1);
      // After Closing, listeners hear the old turn's figures as retired
      // usage alone, as the original's emit tells every event; the session
      // in front counts none of them.
      expect(
        rig.events.skip(before).where((e) => e is! Closing),
        everyElement(isA<RetiredUsage>()),
      );
      expect(rig.events.skip(before).whereType<RetiredUsage>(), hasLength(1));
      expect(rig.app.spent, app.spent);
      final usage = rig.usageIn(rig.firstPath);
      expect(usage.single['usage'], {'inputTokens': 12});
      expect((usage.single['cost'] as Map)['amount'], closeTo(0.02, 1e-12));
      expect(rig.lines.keys, hasLength(1));
    });
  });
}

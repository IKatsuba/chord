import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/rpc.dart' show RpcException;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

/// A conversation over [session], up, its events kept.
({Conversation conversation, List<ConversationEvent> events}) up(
  FakeAsync async,
  ScriptedSession session,
) {
  final conversation = Conversation(
    ({required onTraffic, required cancellationToken}) => Future.value(session),
  );
  final events = <ConversationEvent>[];
  conversation.listen(events.add);
  conversation.start();
  async.flushMicrotasks();
  return (conversation: conversation, events: events);
}

List<String> renames(List<ConversationEvent> events) => [
  for (final event in events)
    if (event is Renamed) event.title,
];

void main() {
  group('tester U6 rename lifecycle boundaries', () {
    for (final rejects in [false, true]) {
      test(
        'clear detaches a late ${rejects ? 'refusal' : 'answer'} and queued renames',
        () {
          fakeAsync((async) {
            final gate = Completer<String>();
            final old = ScriptedSession()
              ..titles = true
              ..onTitle = (_) => gate.future;
            final fresh = ScriptedSession()..titles = true;
            var opens = 0;
            final events = <ConversationEvent>[];
            final conversation =
                Conversation(
                    ({required onTraffic, required cancellationToken}) =>
                        Future.value(opens++ == 0 ? old : fresh),
                  )
                  ..listen(events.add)
                  ..start();
            async.flushMicrotasks();
            final settled = <RenameTaken?>[];
            conversation.rename('old').then(settled.add);
            conversation.rename('old queued').then(settled.add);
            async.flushMicrotasks();
            expect(old.titled, ['old']);
            conversation.clear();
            async.flushMicrotasks();
            conversation.rename('new').then(settled.add);
            async.flushMicrotasks();
            expect(fresh.titled, ['new']);
            expect(renames(events), ['new']);
            if (rejects) {
              gate.completeError(StateError('late refusal'));
            } else {
              gate.complete('late answer');
            }
            async.flushMicrotasks();
            expect(old.titled, ['old']);
            expect(settled, [(title: 'new', agent: true), null, null]);
            expect(renames(events), ['new']);
            conversation.close();
            async.flushMicrotasks();
            expect(async.nonPeriodicTimerCount, 0);
          });
        },
      );
    }
    test(
      'close does not await a hung title and suppresses its late answer',
      () {
        fakeAsync((async) {
          final gate = Completer<String>();
          final session = ScriptedSession()
            ..titles = true
            ..onTitle = (_) => gate.future;
          final (:conversation, :events) = up(async, session);
          var completed = false;
          RenameTaken? renamed;
          conversation.rename('late').then((value) {
            renamed = value;
            completed = true;
          });
          async.flushMicrotasks();
          var closed = false;
          conversation.close().then((_) => closed = true);
          async.flushMicrotasks();
          expect(closed, isTrue);
          expect(completed, isFalse);
          gate.complete('late');
          async.flushMicrotasks();
          expect(completed, isTrue);
          expect(renamed, isNull);
          expect(renames(events), isEmpty);
          expect(async.nonPeriodicTimerCount, 0);
        });
      },
    );
    test('one session cannot serialize another sessions renames', () {
      fakeAsync((async) {
        final gate = Completer<String>();
        final heldSession = ScriptedSession()
          ..titles = true
          ..onTitle = (_) => gate.future;
        final held = up(async, heldSession);
        final free = up(async, ScriptedSession()..titles = true);
        held.conversation.rename('held');
        free.conversation.rename('free');
        async.flushMicrotasks();
        expect(renames(held.events), isEmpty);
        expect(renames(free.events), ['free']);
        gate.complete('held');
        async.flushMicrotasks();
        expect(renames(held.events), ['held']);
        held.conversation.close();
        free.conversation.close();
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 0);
      });
    });
    test(
      'the worker reads the newest pending title until a completed rename',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'chord-title-sequence-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/record.jsonl');
        file.writeAsStringSync(
          encodeRecord({
            'type': 'prompt',
            'turnId': 'saved',
            'prompt': 'hi',
            'images': 0,
            'at': 1,
          }),
        );
        await recordPendingRename(file.path, 'first', 2);
        await recordPendingRename(file.path, '界👩‍💻e\u0301', 3);
        expect(
          (await readRecordedHistory(file.path)).pendingRename,
          '界👩‍💻e\u0301',
        );
        file.writeAsStringSync(
          encodeRecord({'type': 'renamed', 'title': 'agent kept', 'at': 4}),
          mode: FileMode.append,
        );
        expect((await readRecordedHistory(file.path)).pendingRename, isNull);
        await recordPendingRename(file.path, 'next', 5);
        expect((await readRecordedHistory(file.path)).pendingRename, 'next');
        expect(
          const LineSplitter().convert(file.readAsStringSync()),
          hasLength(5),
        );
      },
    );
  });
  group('a rename', () {
    test('for an agent that takes no title: the typed title folded to one '
        'line, in chord alone', () {
      fakeAsync((async) {
        final session = ScriptedSession();
        final (:conversation, :events) = up(async, session);
        RenameTaken? taken;
        conversation.rename('  Fix\n  the   parser ').then((t) => taken = t);
        async.flushMicrotasks();
        expect(taken, (title: 'Fix the parser', agent: false));
        expect(session.titled, isEmpty);
        expect(renames(events), ['Fix the parser']);
        conversation.close();
        async.flushMicrotasks();
      });
    });

    test('for an agent that takes one: by session/set_title, its answer '
        'kept', () {
      fakeAsync((async) {
        final session = ScriptedSession()
          ..titles = true
          ..onTitle = (title) async => 'Agent: $title';
        final (:conversation, :events) = up(async, session);
        RenameTaken? taken;
        conversation.rename('Fix  it').then((t) => taken = t);
        async.flushMicrotasks();
        expect(session.titled, ['Fix it']);
        expect(taken, (title: 'Agent: Fix it', agent: true));
        expect(renames(events), ['Agent: Fix it']);
        conversation.close();
        async.flushMicrotasks();
      });
    });

    test('a refusal is the agent\'s error, and nothing is renamed', () {
      fakeAsync((async) {
        final session = ScriptedSession()
          ..titles = true
          ..onTitle = (_) async =>
              throw RpcException(-32600, 'Invalid request');
        final (:conversation, :events) = up(async, session);
        Object? failed;
        conversation.rename('x').catchError((Object e) {
          failed = e;
          return null;
        });
        async.flushMicrotasks();
        expect(
          failed,
          isA<RpcException>().having((e) => e.code, 'code', -32600),
        );
        expect(renames(events), isEmpty);
        // The next rename is not held by the refused one.
        session.onTitle = null;
        conversation.rename('y');
        async.flushMicrotasks();
        expect(renames(events), ['y']);
        conversation.close();
        async.flushMicrotasks();
      });
    });

    test('a hung rename holds the renames after it, and nothing else', () {
      fakeAsync((async) {
        final hung = Completer<String>();
        final session = ScriptedSession()
          ..titles = true
          ..onTitle = (_) => hung.future;
        final (:conversation, :events) = up(async, session);
        conversation.rename('first');
        conversation.rename('second');
        async.flushMicrotasks();
        expect(session.titled, ['first']);
        conversation.send('still usable');
        conversation.setMode('ask').ignore();
        async.flushMicrotasks();
        expect(session.turns.single.text, 'still usable');
        expect(session.changes, [('mode', 'ask', null)]);
        session.onTitle = null;
        hung.complete('first');
        async.flushMicrotasks();
        expect(session.titled, ['first', 'second']);
        expect(renames(events), ['first', 'second']);
        conversation.close();
        async.flushMicrotasks();
      });
    });

    test('once closing, a rename is refused', () {
      fakeAsync((async) {
        final (:conversation, events: _) = up(async, ScriptedSession());
        conversation.close();
        async.flushMicrotasks();
        expect(conversation.rename('x'), throwsStateError);
        async.flushMicrotasks();
      });
    });
  });

  group('a rename chord acp recorded while the session was not loaded', () {
    PreparedHistory pending(String title) => PreparedHistory(
      rawHasPast: true,
      omitted: false,
      actions: const [],
      pendingRename: title,
    );

    test('goes to an agent that takes titles when the session opens', () {
      fakeAsync((async) {
        final session = ScriptedSession()
          ..titles = true
          ..prepared = pending('Pending title');
        final (conversation: _, :events) = up(async, session);
        expect(session.titled, ['Pending title']);
        expect(renames(events), ['Pending title']);
      });
    });

    test('stays in the record for one that takes none', () {
      fakeAsync((async) {
        final session = ScriptedSession()..prepared = pending('Pending title');
        final (conversation: _, :events) = up(async, session);
        expect(session.titled, isEmpty);
        expect(renames(events), isEmpty);
      });
    });
  });

  group('the record', () {
    List<Map<String, Object?>> linesOf(String text) => [
      for (final line in const LineSplitter().convert(text))
        jsonDecode(line) as Map<String, Object?>,
    ];

    ({FileRecording recording, StringBuffer written}) recordingIn() {
      final written = StringBuffer();
      return (
        recording: FileRecording(
          '/state',
          failed: (_) {},
          uuid: () => 'fixture',
          now: () => 5,
          append: (path, text) async => written.write(text),
        ),
        written: written,
      );
    }

    test('a rename of a session reopened keeps what was held for it, then '
        'its line', () async {
      final (:recording, :written) = recordingIn();
      recording.opened(
        const RecordingSession(
          sessionId: 's',
          agent: 'a',
          cwd: '/w',
          record: '/state/old.jsonl',
        ),
      );
      recording.heard(const Renamed('Fix the parser', 7));
      await recording.flushed();
      expect(linesOf('$written').map((line) => line['type']), [
        'opened',
        'state',
        'renamed',
      ]);
      expect(linesOf('$written').last, {
        'type': 'renamed',
        'title': 'Fix the parser',
        'at': 7,
      });
    });

    test(
      'a new session\'s rename alone keeps nothing until a prompt',
      () async {
        final (:recording, :written) = recordingIn();
        recording.opened(
          const RecordingSession(sessionId: 's', agent: 'a', cwd: '/w'),
        );
        recording.heard(const Renamed('Early', 7));
        await recording.flushed();
        expect('$written', isEmpty);
        recording.sent('t', 'hi', 0, const [], 8);
        await recording.flushed();
        expect(linesOf('$written').map((line) => line['type']), [
          'session',
          'opened',
          'state',
          'renamed',
          'prompt',
        ]);
      },
    );

    test('a pending rename is one line marked pending, which a reopen reads '
        'until a later rename takes over', () async {
      final written = <(String, String)>[];
      await recordPendingRename(
        '/state/s.jsonl',
        'Later',
        9,
        append: (path, text) async => written.add((path, text)),
      );
      expect(written, [
        (
          '/state/s.jsonl',
          '{"type":"renamed","title":"Later","at":9,"pending":true}\n',
        ),
      ]);
      final pending = jsonDecode(written.single.$2);
      expect(recordActions([pending]).pendingRename, 'Later');
      expect(
        recordActions([
          pending,
          {'type': 'renamed', 'title': 'Taken', 'at': 10},
        ]).pendingRename,
        isNull,
      );
      final crossed = PreparedHistory.fromJson(
        jsonDecode(jsonEncode(recordActions([pending]).toJson()))
            as Map<String, Object?>,
      );
      expect(crossed.pendingRename, 'Later');
    });

    test('a record on disk read through its worker keeps the pending '
        'title', () async {
      final dir = Directory.systemTemp.createTempSync('chord-pending-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/record.jsonl';
      File(path).writeAsStringSync(
        encodeRecord({
          'type': 'prompt',
          'turnId': 't',
          'prompt': 'hi',
          'images': 0,
          'at': 1,
        }),
      );
      await recordPendingRename(path, 'Away', 2);
      expect((await readRecordedHistory(path)).pendingRename, 'Away');
      File(path).writeAsStringSync(
        encodeRecord({'type': 'renamed', 'title': 'Taken', 'at': 3}),
        mode: FileMode.append,
      );
      expect((await readRecordedHistory(path)).pendingRename, isNull);
    });
  });
}

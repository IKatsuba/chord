import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'recording_conversation_test.dart' show Controlled;
import 'recording_test.dart' show lines;

const _start = {
  'sessionUpdate': 'session_info_update',
  '_meta': {'codebuddy.ai/unsolicitedTurn': true},
};

Map<String, Object?> _usage(num amount, {bool end = false}) => {
  'sessionUpdate': 'usage_update',
  'used': 10,
  'size': 100,
  'cost': {'amount': amount, 'currency': 'USD'},
  if (end)
    '_meta': {
      '_claude/origin': {'kind': 'task-notification'},
    },
};

List<TranscriptAction> _actions(List<ConversationEvent> events) => [
  for (final event in events)
    if (event case Transcribed(:final action)) action,
];

final class _Run {
  _Run(List<Controlled> sessions) {
    var opening = 0, recordId = 0;
    recording = FileRecording(
      'fixture-state',
      failed: fail,
      uuid: () => 'record-${++recordId}',
      now: () => 1,
      append: (path, text) async => (writes[path] ??= []).add(text),
    );
    conversation = Conversation(
      ({required onTraffic, required cancellationToken}) async =>
          sessions[opening++],
      recording: recording,
    )..listen(events.add);
  }
  final writes = <String, List<String>>{};
  final events = <ConversationEvent>[];
  late final FileRecording recording;
  late final Conversation conversation;

  void flush(FakeAsync async) {
    var flushed = false;
    recording.flushed().then((_) => flushed = true);
    async.flushMicrotasks();
    expect(flushed, isTrue);
  }

  List<Map<String, Object?>> get written => lines(writes.values.single.join());
}

void main() {
  group('tester: conversation cycle recording integration', () {
    test(
      'a cycle before any prompt unlocks the record and replays its cancellation',
      () {
        fakeAsync((async) {
          final session = Controlled('first');
          final run = _Run([session]);
          run.conversation.start();
          async.flushMicrotasks();
          run.flush(async);
          expect(run.writes, isEmpty);
          session.emit(_start);
          session.inner.chunk('autonomous output');
          session.emit(_usage(0.03));
          run.conversation.interrupt();
          run.flush(async);
          final cycle = _actions(
            run.events,
          ).whereType<CycleStartedAction>().single.turnId;
          final written = run.written;
          expect(written.first['type'], 'session');
          expect(
            written.where(
              (row) =>
                  row['type'] == 'prompt' || row['type'] == 'cycle_started',
            ),
            isEmpty,
          );
          expect(
            written.where((row) => row['type'] == 'cancel').single['turnId'],
            cycle,
          );
          expect(
            written.where((row) => row['type'] == 'result').single['turnId'],
            cycle,
          );
          final replay = recordActions(written).actions;
          expect(
            replay.whereType<CancelAction>().single.turnId,
            'history-$cycle',
          );
          expect(
            replay.whereType<ResultAction>().single.turnId,
            'history-$cycle',
          );
          expect(
            replay.whereType<UsageAction>().single.figures.cost.cost!.amount,
            closeTo(0.03, 1e-12),
          );
          run.conversation.close();
          async.flushMicrotasks();
          expect(session.closes, 1);
        });
      },
    );

    test('late cycle cost correction replaces one row live and on replay', () {
      fakeAsync((async) {
        final session = Controlled('first');
        final run = _Run([session]);
        run.conversation.start();
        async.flushMicrotasks();
        run.conversation.send('first');
        async.flushMicrotasks();
        session.emit(_usage(0.01));
        session.inner.turns.single.answer();
        async.flushMicrotasks();
        session.emit(_start);
        session.inner.chunk('autonomous output');
        session.emit(_usage(0.03, end: true));
        session.emit(_usage(0.04, end: true));
        run.flush(async);
        final cycle = _actions(
          run.events,
        ).whereType<CycleStartedAction>().single.turnId;
        final live = run.events.fold(AppState.starting, reduceApp).spent!;
        expect(live.costs, hasLength(2));
        expect(live.costs!['turn-1']!.cost.cost!.amount, closeTo(0.01, 1e-12));
        expect(live.costs![cycle]!.cost.cost!.amount, closeTo(0.03, 1e-12));
        final replayed = recordActions(run.written).actions
            .whereType<UsageAction>()
            .where((a) => a.turnId == 'history-$cycle')
            .toList();
        expect(replayed, hasLength(2));
        expect(replayed.last.figures.cost.cost!.amount, closeTo(0.03, 1e-12));
        expect(
          _actions(
            run.events,
          ).whereType<ResultAction>().where((a) => a.turnId == cycle),
          hasLength(1),
        );
        run.conversation.close();
        async.flushMicrotasks();
      });
    });

    test(
      'prompt takeover records the late cycle end under the prompt without finishing it',
      () {
        fakeAsync((async) {
          final session = Controlled('first');
          final run = _Run([session]);
          run.conversation.start();
          async.flushMicrotasks();
          run.conversation.send('first');
          async.flushMicrotasks();
          session.emit(_usage(0.01));
          session.inner.turns.single.answer();
          async.flushMicrotasks();
          session.emit(_start);
          session.inner.chunk('autonomous output');
          final cycle = _actions(
            run.events,
          ).whereType<CycleStartedAction>().single.turnId;
          run.conversation.send('take over');
          async.flushMicrotasks();
          session.emit(_usage(0.03, end: true));
          expect(
            _actions(
              run.events,
            ).whereType<ResultAction>().where((a) => a.turnId == 'turn-2'),
            isEmpty,
          );
          session.inner.turns.last.answer();
          run.flush(async);
          final written = run.written;
          expect(
            written.where(
              (row) => row['turnId'] == cycle && row['type'] == 'result',
            ),
            isEmpty,
          );
          expect(
            written.where(
              (row) => row['turnId'] == 'turn-2' && row['type'] == 'result',
            ),
            hasLength(1),
          );
          final figures = recordActions(
            written,
          ).actions.whereType<UsageAction>().last.figures;
          expect(figures.turnId, 'history-turn-2');
          expect(figures.cost.cost!.amount, closeTo(0.02, 1e-12));
          run.conversation.close();
          async.flushMicrotasks();
        });
      },
    );

    test('clear sends late cycle figures only to the retired record', () {
      fakeAsync((async) {
        final old = Controlled('old'), current = Controlled('current');
        final run = _Run([old, current]);
        run.conversation.start();
        async.flushMicrotasks();
        old.emit(_start);
        old.inner.chunk('old output');
        old.emit(_usage(0.02));
        final cycle = _actions(
          run.events,
        ).whereType<CycleStartedAction>().single.turnId;
        run.conversation.clear();
        async.flushMicrotasks();
        current.emit(_start);
        current.inner.chunk('current output');
        current.emit(_usage(0.01, end: true));
        old.emit(_usage(0.03, end: true));
        run.flush(async);
        expect(run.writes, hasLength(2));
        final records = run.writes.values
            .map((chunks) => lines(chunks.join()))
            .toList();
        final retired = records.singleWhere(
          (rows) => rows.first['sessionId'] == 'old',
        );
        final fresh = records.singleWhere(
          (rows) => rows.first['sessionId'] == 'current',
        );
        expect(fresh.where((row) => row['turnId'] == cycle), isEmpty);
        final figures = recordActions(
          retired,
        ).actions.whereType<UsageAction>().last.figures;
        expect(figures.turnId, 'history-$cycle');
        expect(figures.cost.cost!.amount, closeTo(0.03, 1e-12));
        expect(
          recordActions(
            fresh,
          ).actions.whereType<UsageAction>().single.figures.cost.cost!.amount,
          closeTo(0.01, 1e-12),
        );
        async.elapse(const Duration(milliseconds: quietMs));
        run.conversation.close();
        async.flushMicrotasks();
        expect(old.closes, 1);
        expect(current.closes, 1);
      });
    });
  });
}

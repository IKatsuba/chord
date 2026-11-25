import 'dart:convert';
import 'dart:io';

// A plan in the session's record, from the original's record.ts
// (plan_asked, plan_answered) and its replay, where an ask the record never
// saw answered comes back withdrawn.
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'transcript/fold.dart';

const cursor = PlanWait(
  'plan-7',
  PlanAgent.cursor,
  toolCallId: 'c1',
  plan: '# Route',
  name: 'Route',
  overview: 'Split it.',
  todos: [(id: 'read', content: 'Read 日本語', status: 'completed')],
  phases: [
    (name: 'Move', todos: [(id: 'move', content: 'Move', status: 'cancelled')]),
  ],
);
const grok = PlanWait('plan-8', PlanAgent.grok, toolCallId: 'c2');

Future<List<Map<String, Object?>>> recorded(
  List<TranscriptAction> actions,
) async {
  final writes = <String>[];
  final recording = FileRecording(
    'isolated-state',
    failed: fail,
    uuid: () => 'fixture',
    append: (_, text) async => writes.add(text),
  );
  recording.opened(
    const RecordingSession(
      sessionId: 's',
      agent: 'fake',
      cwd: 'project',
      state: AgentState.empty,
    ),
  );
  recording.sent('t1', 'plan it', 0, [], 1);
  for (final action in actions) {
    recording.heard(Transcribed(action));
  }
  await recording.flushed();
  recording.heard(const Closing());
  await recording.flushed();
  return parseRecord(writes.join()).cast<Map<String, Object?>>();
}

void main() {
  test('a plan and its answer read back as they were written', () {
    for (final wait in [cursor, grok]) {
      final again = PlanWait.fromJson(wait.toJson())!;
      expect(again.toJson(), wait.toJson());
    }
    for (final answer in const [
      PlanAccepted(),
      PlanKept(),
      PlanKept('Smaller.'),
      PlanLeft(),
      PlanCancelled(),
      PlanWithdrawn(),
    ]) {
      expect(PlanAnswer.fromJson(answer.toJson())?.toJson(), answer.toJson());
    }
    expect(PlanWait.fromJson({'id': 'x', 'agent': 'cursor'}), isNull);
    expect(PlanWait.fromJson({'agent': 'grok', 'toolCallId': 'c'}), isNull);
    expect(PlanAnswer.fromJson({'type': 'kept', 'note': 3}), isNull);
    expect(PlanAnswer.fromJson({'type': 'yes'}), isNull);
  });

  test('the record keeps a plan asked and how it was answered, and reads '
      'them back onto the call', () async {
    final raw = await recorded([
      const PlanRequestedAction('t1', cursor),
      const PlanSettledAction('t1', 'plan-7', PlanKept('Smaller.')),
    ]);
    expect(raw.where((e) => e['type'] == 'plan_asked').single, {
      'type': 'plan_asked',
      'turnId': 't1',
      'wait': cursor.toJson(),
    });
    expect(raw.where((e) => e['type'] == 'plan_answered').single, {
      'type': 'plan_answered',
      'turnId': 't1',
      'id': 'plan-7',
      'answer': {'type': 'kept', 'note': 'Smaller.'},
    });
    final history = recordActions(raw);
    expect(history.omitted, isFalse);
    final ask = fold(history.actions).planAsks.single;
    expect(ask.wait.toJson(), cursor.toJson());
    expect(ask.answer?.toJson(), {'type': 'kept', 'note': 'Smaller.'});
  });

  test('one the record never saw answered comes back withdrawn', () async {
    final raw = await recorded([const PlanRequestedAction('t1', grok)]);
    final ask = fold(recordActions(raw).actions).planAsks.single;
    expect(ask.answer, isA<PlanWithdrawn>());
  });

  test("the record worker's codec carries both through", () async {
    final raw = await recorded([
      const PlanRequestedAction('t1', cursor),
      const PlanSettledAction('t1', 'plan-7', PlanAccepted()),
      const PlanRequestedAction('t1', grok),
    ]);
    final history = recordActions(raw);
    final again = PreparedHistory.fromJson(history.toJson());
    final asks = fold(again.actions).planAsks;
    expect(asks.map((ask) => ask.wait.id), ['plan-7', 'plan-8']);
    expect(asks.first.answer, isA<PlanAccepted>());
    expect(asks.last.answer, isA<PlanWithdrawn>());
    expect(asks.first.wait.toJson(), cursor.toJson());
  });

  group("an ask never answered goes withdrawn where it stood", () {
    // A crash left plan A open; a later turn reused call c1 for plan B,
    // which was accepted.
    final lines = <Map<String, Object?>>[
      {
        'type': 'session',
        'version': 1,
        'sessionId': 's',
        'agent': 'a',
        'cwd': '/w',
        'at': 0,
      },
      {'type': 'prompt', 'turnId': 't1', 'prompt': 'one', 'at': 1, 'images': 0},
      {
        'type': 'update',
        'turnId': 't1',
        'update': {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c1',
          'title': 'Plan',
        },
      },
      {
        'type': 'plan_asked',
        'turnId': 't1',
        'wait': const PlanWait('A', PlanAgent.grok, toolCallId: 'c1').toJson(),
      },
      {'type': 'prompt', 'turnId': 't2', 'prompt': 'two', 'at': 2, 'images': 0},
      {
        'type': 'update',
        'turnId': 't2',
        'update': {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c1',
          'title': 'Plan',
        },
      },
      {
        'type': 'plan_asked',
        'turnId': 't2',
        'wait': const PlanWait('B', PlanAgent.grok, toolCallId: 'c1').toJson(),
      },
      {
        'type': 'plan_answered',
        'turnId': 't2',
        'id': 'B',
        'answer': {'type': 'accepted'},
      },
      {'type': 'renamed', 'title': 'Kept', 'at': 3},
    ];

    void check(PreparedHistory history) {
      final state = fold(history.actions);
      final calls = state.entries.whereType<ToolEntry>().toList();
      expect(calls.last.call.plan?.wait.id, 'B');
      expect(calls.last.call.plan?.answer, isA<PlanAccepted>());
      final asks = {for (final ask in state.planAsks) ask.wait.id: ask.answer};
      expect(asks['A'], isA<PlanWithdrawn>());
      expect(asks['B'], isA<PlanAccepted>());
    }

    test("in the record's projection and its codec", () {
      final history = recordActions(lines);
      check(history);
      check(PreparedHistory.fromJson(history.toJson()));
    });

    test("in the record worker, which keeps the title too", () async {
      final dir = Directory.systemTemp.createTempSync('chord-plan-records-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/r.jsonl')
        ..writeAsStringSync(lines.map(jsonEncode).join('\n'));
      final history = await readRecordedHistory(file.path);
      check(history);
      expect(history.title, 'Kept');
    });
  });
}

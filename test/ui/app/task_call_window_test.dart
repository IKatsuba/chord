// A task stands where its `spawn_task` call stood, as the original's
// session/transcript/chord.ts `link` puts it: the call draws no block of its
// own, its later updates draw nothing, and two tasks spawned back to back
// group as one `Running 2 agents…` block. Checked live in the window and on
// a record read back, against the original's `taskcost` and `tasktwo`
// captures (docs/design/evidence/CTUI-35/children/orig-*).
import 'dart:io';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/replay.dart' show recordActions;
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/transcript/reducer.dart' show reduceTranscript;
import 'package:chord/session/transcript/entries.dart' show replayTranscript;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show window;

/// One `spawn_task` as the fake makes it: its call, the task's block
/// starting, chord's answer served, and the call's own completion.
List<TranscriptAction> _spawn(String turn, String id, String name, String job) {
  final input = {'agent': 'fake', 'prompt': job, 'name': name};
  final call = 'call-$id';
  return [
    UpdateAction(
      turn,
      acp.SessionUpdate.fromJson({
        'sessionUpdate': 'tool_call',
        'toolCallId': call,
        'status': 'pending',
        'title': 'mcp__chord__spawn_task',
        'kind': 'other',
        'rawInput': input,
      }),
    ),
    UpdateAction(
      turn,
      taskUpdate(
        id,
        SubagentState.running,
        task: TaskStart(id: id, name: name, runtime: 'fake', prompt: job),
      ),
    ),
    ServedAction(
      turn,
      ChordCall(
        tool: ChordTool.spawnTask,
        input: input,
        answer: {'id': id, 'name': name, 'agent': 'fake'},
        task: id,
      ),
    ),
    UpdateAction(
      turn,
      acp.SessionUpdate.fromJson({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': call,
        'status': 'completed',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': '{"id": "$id"}'},
          },
        ],
      }),
    ),
  ];
}

UpdateAction _said(String turn, String text) => UpdateAction(
  turn,
  acp.SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
);

/// The fake's `tasktwo`: two `taskwait` tasks, then its reply.
List<TranscriptAction> _tasktwo() => [
  const PromptAction('t1', 'tasktwo', 0),
  ..._spawn('t1', 'build', 'Watch the build', 'taskwait'),
  ..._spawn('t1', 'deploy', 'Watch the deploy', 'taskwait'),
  _said('t1', 'The build and the deploy are being watched.'),
  const ResultAction('t1', TurnAnswered('end_turn')),
];

/// The fake's `taskcost`: one `costwait` task, then its reply.
List<TranscriptAction> _taskcost() => [
  const PromptAction('t1', 'taskcost', 0),
  ..._spawn('t1', 'cost', 'Count the cost', 'costwait'),
  _said('t1', 'The cost is being counted.'),
  const ResultAction('t1', TurnAnswered('end_turn')),
];

/// The record main's session writes for [actions]: the same lines, as a
/// resume reads them back.
List<Object?> _record(List<TranscriptAction> actions) => [
  {
    'type': 'session',
    'version': 1,
    'sessionId': 'main-1',
    'agent': 'fake',
    'cwd': 'fixture-project',
    'at': 0,
  },
  for (final action in actions)
    switch (action) {
      PromptAction(:final turnId, :final text) => {
        'type': 'prompt',
        'turnId': turnId,
        'at': 1,
        'prompt': text,
        'images': 0,
      },
      UpdateAction(:final turnId, :final update) => {
        'type': 'update',
        'turnId': turnId,
        'update': update.toJson(),
      },
      ServedAction(:final turnId, :final call) => {
        'type': 'served',
        'turnId': turnId,
        'call': call.toJson(),
      },
      ResultAction(:final turnId) => {
        'type': 'result',
        'turnId': turnId,
        'result': {'status': 'completed', 'stopReason': 'end_turn'},
      },
      _ => throw StateError('not written here: $action'),
    },
];

/// A window with main up and [actions] heard live, or, given [replayed],
/// read back from main's record.
Future<void> _main(
  WidgetTester t,
  Size size,
  List<TranscriptAction> actions, {
  bool replayed = false,
}) async {
  final w = await window(t, size, EditorTerminal());
  final fold = w.connection.fold;
  fold.app.value = reduceApp(
    fold.app.value,
    const Connected('m', AgentState.empty),
  );
  if (replayed) {
    final history = recordActions(_record(actions));
    expect(history.omitted, isFalse);
    fold.heard(
      mainKey,
      HistoryReplayed(history.actions, state: AgentState.empty),
    );
  } else {
    for (final action in actions) {
      fold.heard(mainKey, Transcribed(action));
    }
  }
  await settle(t);
}

/// The transcript's rows from the prompt's line [prompt] to the reply
/// [reply], both kept.
List<String> _between(List<String> lines, String prompt, String reply) {
  final from = lines.indexWhere((row) => row.trimRight() == ' › $prompt');
  final to = lines.indexWhere((row) => row.contains(reply));
  expect((from, to), isNot(anyOf((-1, anything), (anything, -1))));
  return [for (final row in lines.sublist(from, to + 1)) row.trimRight()];
}

/// The original's capture [name] at [size], the same rows.
List<String> _original(Size size, String name, String prompt, String reply) {
  final file = File(
    'docs/design/evidence/CTUI-35/children/'
    'orig-${size.width}x${size.height}-$name.txt',
  );
  return _between(file.readAsLinesSync(), prompt, reply);
}

void main() {
  _testerTaskReplacement();
  for (final replayed in const [false, true]) {
    final how = replayed ? 'read back from its record' : 'live';
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      group('at $size, $how', () {
        testWidgets("one task: its block alone where its call stood, no "
            "block for the call", (t) async {
          await _main(t, size, _taskcost(), replayed: replayed);
          const reply = 'The cost is being counted.';
          final rows = _between(t.screen.lines, 'taskcost', reply);
          expect(rows, [
            ' › taskcost',
            '',
            ' ⏺ Agent(Count the cost) · fake',
            '   ⎿  Initializing…',
            '',
            ' ⏺ $reply',
          ]);
          expect(rows, _original(size, 'taskcost', 'taskcost', reply));
          expect(t.screen.text, isNot(contains('costwait')));
          expect(t.screen.text, isNot(contains('spawn_task')));
        });

        testWidgets('two tasks back to back: one `Running 2 agents…` '
            'group, row for row as the original draws it', (t) async {
          await _main(t, size, _tasktwo(), replayed: replayed);
          const reply = 'The build and the deploy are being watched.';
          final rows = _between(t.screen.lines, 'tasktwo', reply);
          expect(rows, [
            ' › tasktwo',
            '',
            ' ⏺ Running 2 agents… (ctrl+o to expand)',
            '   ├─ Agent(Watch the build) · fake · 0 tool uses',
            '   │  ⎿  Initializing…',
            '   └─ Agent(Watch the deploy) · fake · 0 tool uses',
            '      ⎿  Initializing…',
            '',
            ' ⏺ $reply',
          ]);
          expect(rows, _original(size, 'tasktwo', 'tasktwo', reply));
          expect(t.screen.text, isNot(contains('taskwait')));
        });
      });
    }
  }
}

void _testerTaskReplacement() {
  group('CTUI-35 tester: task replacement lifetime', () {
    test(
      'move preserves occurrence identity and late call updates never restore the tool row',
      () {
        final actions = _spawn('t1', 'build', 'Watch the build', 'taskwait');
        var state = reduceTranscript(
          const Transcript(),
          const PromptAction('t1', 'tasktwo', 0),
        );
        for (final action in actions.take(2)) {
          state = reduceTranscript(state, action);
        }
        final before = state.entries.whereType<SubagentEntry>().single;
        state = reduceTranscript(state, actions[2]);
        expect(
          identical(
            state.entries.whereType<SubagentEntry>().single.identity,
            before.identity,
          ),
          isTrue,
        );
        expect(
          state.entries.whereType<SubagentEntry>().single.subagent.callId,
          'call-build',
        );
        for (var i = 0; i < 1000; i++) {
          state = reduceTranscript(state, actions.last);
        }
        state = reduceTranscript(
          state,
          UpdateAction('t1', taskUpdate('build', SubagentState.completed)),
        );
        final after = state.entries.whereType<SubagentEntry>().single;
        expect(identical(after.identity, before.identity), isTrue);
        expect(after.subagent.callId, 'call-build');
        expect(state.entries.whereType<ToolEntry>(), isEmpty);
        expect(before.subagent.callId, isNull);
        expect(before.subagent.state, SubagentState.running);
      },
    );

    test(
      'record replay suppresses a thousand late call updates while keeping adjacent task calls',
      () {
        final first = _spawn('t1', 'build', 'Watch the build', 'taskwait');
        final actions = <TranscriptAction>[
          const PromptAction('t1', 'tasktwo', 0),
          ...first,
          ..._spawn('t1', 'deploy', 'Watch the deploy', 'taskwait'),
          for (var i = 0; i < 1000; i++) first.last,
        ];
        final replay = replayTranscript(
          recordActions(_record(actions)).actions,
        );
        final blocks = replay.entries.whereType<SubagentEntry>().toList();
        expect(blocks.map((entry) => entry.subagent.callId), [
          'call-build',
          'call-deploy',
        ]);
        expect(replay.entries.whereType<ToolEntry>(), isEmpty);
        expect(
          replay.entries.indexOf(blocks[1]),
          replay.entries.indexOf(blocks[0]) + 1,
        );
        expect(blocks[0].identity, isNot(same(blocks[1].identity)));
      },
    );

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'three adjacent tasks remain one group at $size after late call updates',
        (t) async {
          final first = _spawn('t1', 'build', 'Build', 'taskwait');
          await _main(t, size, [
            const PromptAction('t1', 'taskthree', 0),
            ...first,
            ..._spawn('t1', 'deploy', 'Deploy', 'taskwait'),
            ..._spawn('t1', 'check', 'Check', 'taskwait'),
            ...List.filled(1000, first.last),
            _said('t1', 'All three are watched.'),
            const ResultAction('t1', TurnAnswered('end_turn')),
          ]);
          final rows = _between(
            t.screen.lines,
            'taskthree',
            'All three are watched.',
          );
          expect(
            rows.where((row) => row.contains('Running 3 agents')),
            hasLength(1),
          );
          for (final title in ['Build', 'Deploy', 'Check']) {
            expect(
              rows.where((row) => row.contains('Agent($title)')),
              hasLength(1),
            );
          }
          expect(rows.join('\n'), isNot(contains('mcp__chord__spawn_task')));
        },
      );
    }
  });
}

// A task agent of main's in the window, as the original's
// tests/ui/app/Tasks_test.tsx and tests/ui/agents/AgentsTasks_test.tsx see
// it, less the background summary the owner left for CTUI-36: after its
// parent's turn the status line counts it and no row under the agents list
// names it; its permission and its form name it as their asker between
// turns.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show window;

const _fix = TaskStart(
  id: 'task-1',
  name: 'Fix the tokenizer',
  runtime: 'fake',
  prompt: 'taskchild',
  model: 'fake-small',
);

const _watch = TaskStart(
  id: 'task-1',
  name: 'Watch the build',
  runtime: 'fake',
  prompt: 'taskwait',
);

UpdateAction _started(TaskStart start) => UpdateAction(
  't1',
  taskUpdate('task-1', SubagentState.running, task: start),
);

const _ended = ResultAction('t1', TurnAnswered('end_turn'));

/// The task's edit, waiting on the person since after the turn ended.
List<TranscriptAction> _asks() => [
  UpdateAction(
    't1',
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'edit-1',
      'title': 'Edit src/parse/tokenize.ts',
      'kind': 'edit',
      'status': 'pending',
    }),
    subagentId: 'task-1',
  ),
  PermissionRequestedAction(
    't1',
    PermissionWait(
      'perm-1',
      toolCallId: 'edit-1',
      title: 'Edit src/parse/tokenize.ts',
      kind: 'edit',
      subagentId: 'task-1',
      options: [
        acp.PermissionOption.fromJson({
          'optionId': 'allow',
          'name': 'Allow',
          'kind': 'allow_once',
        }),
        acp.PermissionOption.fromJson({
          'optionId': 'deny',
          'name': 'Deny',
          'kind': 'reject_once',
        }),
      ],
    ),
    at: 2000,
    between: true,
  ),
];

/// A window of main and its child parser, main up and its [actions] heard.
Future<void> _main(
  WidgetTester t,
  Size size,
  List<TranscriptAction> actions,
) async {
  final w = await window(t, size, EditorTerminal());
  final fold = w.connection.fold;
  fold.app.value = reduceApp(
    fold.app.value,
    const Connected('m', AgentState.empty),
  );
  for (final action in actions) {
    fold.heard(mainKey, Transcribed(action));
  }
  await settle(t);
}

/// The window's rows from the status line's down: the line, then the list.
List<String> _below(WidgetTester t) {
  final lines = t.screen.lines;
  final box = lines.lastIndexWhere((row) => row.startsWith('╰'));
  return lines.sublist(box + 1).where((row) => row.trim().isNotEmpty).toList();
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('after its turn, a task still at work: its block, the '
          'status line counting it, and no row under the list', (t) async {
        await _main(t, size, [
          PromptAction('t1', 'tasklong', 0),
          _started(_watch),
          _ended,
        ]);
        expect(t.screen, shows(' ⏺ Agent(Watch the build) · fake'));
        expect(t.screen, shows('   ⎿  Initializing…'));
        final below = _below(t);
        expect(below.first.trim(), '1 agent still running');
        // The list, main and parser, and nothing after it: nothing names
        // the background until CTUI-36.
        expect(below.skip(1).map((row) => row.trim().split(' ').first), [
          'main',
          'parser',
        ]);
        expect(t.screen.text, isNot(contains('background')));
        expect(t.screen.text, isNot(contains('task running')));
      });

      testWidgets("the task's permission between turns names it, with the "
          'key that answers it', (t) async {
        await _main(t, size, [
          PromptAction('t1', 'task', 0),
          _started(_fix),
          _ended,
          ..._asks(),
        ]);
        expect(
          t.screen,
          shows('│ Agent(Fix the tokenizer) · fake asks · between turns'),
        );
        expect(t.screen, shows('ctrl+x a to answer'));
        expect(t.screen.text, isNot(contains('main asks')));
        final y = t.screen.lines.indexWhere(
          (row) => row.contains('Agent(Fix the tokenizer) · fake asks'),
        );
        final row = t.screen.lines[y];
        final at = row.indexOf('Agent(');
        final accent = t.screen.styleAt(at, y).fg;
        expect(accent, isNotNull);
        expect(t.screen.styleAt(at, y).isBold, isTrue);
        final rest = row.indexOf('(Fix');
        expect(t.screen.styleAt(rest, y).isBold, isFalse);
        expect(t.screen.styleAt(rest, y).fg, accent);
        final between = row.indexOf(' · between');
        expect(t.screen.styleAt(between + 1, y).isDim, isTrue);
      });

      testWidgets("the task's form between turns names it in its "
          'heading', (t) async {
        await _main(t, size, [
          PromptAction('t1', 'leftform', 0),
          _started(
            const TaskStart(
              id: 'task-1',
              name: 'Carry the form',
              runtime: 'fake',
              prompt: 'leftform',
            ),
          ),
          _ended,
          const ElicitationRequestedAction(
            't1',
            FormWait(
              'form-1',
              'Name the project.',
              schema: {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string', 'title': 'Project name'},
                },
                'required': ['name'],
              },
              at: 2000,
              between: true,
              subagentId: 'task-1',
            ),
          ),
        ]);
        expect(
          t.screen,
          shows('Agent(Carry the form) · fake asks for input · between turns'),
        );
        expect(t.screen, shows('ctrl+x a to answer'));
        expect(t.screen.text, isNot(contains('main asks')));
      });

      testWidgets("/cost names main's task under it, ended, and one still "
          'at work as counted when it ends', (t) async {
        await _main(t, size, [
          PromptAction('t1', 'task', 0),
          _started(_fix),
          UpdateAction(
            't1',
            taskUpdate(
              'task-1',
              SubagentState.completed,
              spent: const TaskSpent(
                tokens: {'totalTokens': 2000},
                cost: (amount: 0.0125, currency: 'USD'),
              ),
            ),
          ),
          UpdateAction(
            't1',
            taskUpdate('task-2', SubagentState.running, task: _watch),
          ),
          _ended,
        ]);
        await t.type('/cost');
        await t.press('enter');
        await settle(t);
        final row = t.screen.lines.firstWhere(
          (row) => row.contains('task agent, ended'),
        );
        // Under main, two in.
        expect(row.trimLeft(), startsWith('Fix the tokenizer'));
        expect(
          row.indexOf('Fix the tokenizer'),
          t.screen.lines
                  .firstWhere((row) => row.contains('This session'))
                  .indexOf('This session') +
              2,
        );
        expect(row, contains(r'$0.0125   2,000  task agent, ended'));
        expect(t.screen, shows('  Watch the build'));
        expect(t.screen, shows('task agent, running: counted'));
        expect(t.screen, shows('1 running'));
      });
    });
  }
}

// Subagents in the real window with no agent: a launch whose prompt has
// code in its first rows and folds, a group of two whose first did work
// with a tool, its permission answered, a notice, a compaction and a reply
// with code, and a message back. ctrl+o opens and folds them; ctrl+x b
// picks code; a drag selects.
//
//   dart run tool/agents.dart
//
// Ctrl+Q quits.
import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

/// The launch prompt: code in its first rows, then steps past the fold.
final launchPrompt = [
  'Run this first.',
  '```sh\nbun test\n```',
  for (var i = 1; i <= 8; i++) 'Step $i of checking the build.',
].join('\n\n');

/// The fixture's transcript, everything at rest.
List<model.Entry> agentsEntries() => appended([], [
  const model.UserEntry('t', 'check the build and the layer'),
  model.AgentMessageEntry(
    't',
    'launch',
    toSubagent: true,
    agentId: 'a',
    title: 'Check the build',
    text: launchPrompt,
    launch: true,
  ),
  model.SubagentEntry(
    't',
    model.Subagent(
      'a',
      state: model.SubagentState.completed,
      title: 'Check the build',
      prompt: launchPrompt,
      startedAt: 0,
      endedAt: 4000,
      entries: [
        const model.ToolEntry(
          't',
          model.ToolCall(
            'c1',
            title: 'Write notes/build.md',
            kind: 'edit',
            status: 'completed',
          ),
        ),
        const model.PermissionEntry('t', title: 'Write notes/build.md'),
        const model.NoticeEntry(
          't',
          model.NoticeSeverity.warning,
          'Rate limited',
          description: 'Retrying in a moment.',
        ),
        const model.CompactionEntry(
          't',
          model.Compaction('k1', 'completed', summary: 'Kept the build notes.'),
        ),
        model.AssistantEntry(
          't',
          TextRun.empty.plus(
            'The build holds. Run it again with:\n\n```sh\nbun test --watch\n```',
          ),
        ),
      ],
    ),
  ),
  const model.SubagentEntry(
    't',
    model.Subagent(
      'b',
      state: model.SubagentState.completed,
      title: 'Find the layer',
      prompt: 'Find where the layer is drawn.',
      startedAt: 0,
      endedAt: 2000,
    ),
  ),
  const model.AgentMessageEntry(
    't',
    'back',
    toSubagent: false,
    agentId: 'b',
    title: 'Find the layer',
    text: 'The **layer** is in `render.dart`.\n\n> Quoted from the notes.',
  ),
]);

/// The fixture's window over [connection].
Widget agentsPreview(StartConnection connection) {
  connection.app.value = AppState(
    start: const StartState(phase: StartPhase.connected),
    transcript: model.Transcript(entries: agentsEntries()),
  );
  return Builder(
    builder: (context) => Actions(
      bindings: [Binding('ctrl+q', 'Quit fixture', () => exitApp(context))],
      child: TranscriptWindow(
        launch: const Launch(
          name: 'fixture',
          agent: null,
          agentCommand: 'unused',
          version: '0.0.1',
          directory: 'project',
        ),
        connection: connection,
      ),
    ),
  );
}

Future<void> main(List<String> args) async {
  final connection = StartConnection(command: 'unused', cwd: '.');
  await runApp(agentsPreview(connection), beforeExit: connection.close);
}

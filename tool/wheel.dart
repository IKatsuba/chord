import 'dart:async';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/shortcuts/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

/// Agent-free stress proposal; the fitting diff matches fake `permission`.
model.PermissionWait wheelPermission({
  bool fitting = false,
}) => model.PermissionWait(
  'wheel-fixture',
  title: fitting ? 'Write notes.txt' : 'Write seeded stress proposal',
  kind: 'edit',
  content: [
    acp.ToolCallContent.fromJson({
      'type': 'diff',
      'path': 'notes.txt',
      'newText': fitting
          ? 'notes\n'
          : '${[for (var i = 1; i <= 60; i++) 'proposed line $i'].join('\n')}\n',
    }),
  ],
  options: [
    for (final (id, name, kind) in [
      ('allow', 'Allow once', 'allow_once'),
      ('always', 'Always allow', 'allow_always'),
      ('deny', 'Deny', 'reject_once'),
    ])
      acp.PermissionOption.fromJson({
        'optionId': id,
        'name': name,
        'kind': kind,
      }),
  ],
);

/// The fixture's exact real prompt text, with seven rows for narrow help.
String wheelDraft(List<String> args) => [
  'unsubmitted draft',
  if (args.contains('--tall-draft'))
    for (var i = 2; i <= 7; i++) 'draft line $i',
].join('\n');

/// Seeds the real prompt before exposing the requested window fixtures.
Widget wheelPreview(StartConnection connection, List<String> args) {
  final permission =
      args.contains('--permission') || args.contains('--fitting');
  final entries = [
    for (var i = 0; i < 100; i++)
      model.UserEntry('row$i', 'Named transcript row $i'),
  ];
  connection.app.value = AppState(
    start: const StartState(phase: StartPhase.connected),
    transcript: model.Transcript(entries: entries),
  );
  var seeded = false;
  return Builder(
    builder: (context) {
      if (!seeded) {
        seeded = true;
        context.owner.afterLayout(
          () => scheduleMicrotask(() {
            context.owner.focusManager.dispatchPaste(wheelDraft(args));
            final current = connection.app.value;
            connection.app.value = AppState(
              start: current.start,
              closing: args.contains('--closing'),
              shortcuts: ShortcutsState(help: args.contains('--help')),
              draft: current.draft,
              cursor: current.cursor,
              scroll: current.scroll,
              transcript: model.Transcript(
                entries: entries,
                turn: permission
                    ? model.AwaitingPermission('turn', 0, [
                        wheelPermission(fitting: args.contains('--fitting')),
                      ])
                    : const model.Idle(),
              ),
            );
          }),
        );
      }
      return Actions(
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
      );
    },
  );
}

Future<void> main(List<String> args) async {
  final connection = StartConnection(command: 'unused', cwd: '.');
  await runApp(wheelPreview(connection, args), beforeExit: connection.close);
}

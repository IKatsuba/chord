// A form or link asked of the person, in the real window with no agent.
//
//   dart run tool/form.dart --long-link
//     a link asked between turns, held, its message and URL long enough to
//     fold at 80x24; ctrl+x a takes the keys into it.
//   dart run tool/form.dart --permission-over
//     a form asked in the turn: type into it, then F2 brings a permission
//     over it and F3 answers that permission; the form comes back as it was
//     left. With no agent, the window's own answer to the permission reaches
//     nothing, so F3 stands in for it.
//
// Ctrl+Q quits.
import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

import '../test/fixtures/forms.dart';
import 'wheel.dart' show wheelPermission;

/// A link asked between turns at [at], too long to stand whole in a short
/// window.
model.ElicitationWait longLink(num at) => model.LinkWait(
  'long-link',
  [
    for (var i = 1; i <= 6; i++)
      'Line $i of why the agent needs you to sign in before it goes on.',
  ].join('\n'),
  'https://example.com/oauth/authorize?client=chord&scope=${'read:project,' * 12}write',
).asked(at: at, between: true);

/// The `form` scenario's form, asked in the turn.
const formOver = model.FormWait(
  'form-over',
  'Set up the deploy target',
  schema: formSchema,
);

AppState _state(
  StartState start, {
  required model.TurnState turn,
  required List<model.ElicitationWait> asking,
}) => AppState(
  start: start,
  transcript: model.Transcript(
    entries: const [model.UserEntry('t', 'deploy it')],
    turn: turn,
    asking: asking,
  ),
);

/// The fixture's window over [connection], as [args] ask.
Widget formPreview(StartConnection connection, List<String> args) {
  const start = StartState(phase: StartPhase.connected);
  final long = args.contains('--long-link');
  // Asked now, so the waiting line counts as a real run's does.
  num now() => DateTime.now().millisecondsSinceEpoch;
  final asked = now();
  connection.app.value = long
      ? _state(start, turn: const model.Idle(), asking: [longLink(asked)])
      : _state(
          start,
          turn: model.Working('t', asked),
          asking: [formOver.asked(at: asked)],
        );
  void set(model.TurnState turn) {
    final current = connection.app.value;
    connection.app.value = AppState(
      start: current.start,
      draft: current.draft,
      cursor: current.cursor,
      scroll: current.scroll,
      transcript: model.Transcript(
        entries: current.transcript.entries,
        turn: turn,
        asking: current.transcript.asking,
      ),
    );
  }

  return Builder(
    builder: (context) => Actions(
      bindings: [
        Binding('ctrl+q', 'Quit fixture', () => exitApp(context)),
        if (!long) ...[
          Binding(
            'f2',
            'Bring a permission over the form',
            () => set(
              model.AwaitingPermission('t', asked, [
                wheelPermission().askedAt(now()),
              ]),
            ),
          ),
          Binding(
            'f3',
            'Answer the permission',
            () => set(model.Working('t', asked)),
          ),
        ],
      ],
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
  await runApp(formPreview(connection, args), beforeExit: connection.close);
}

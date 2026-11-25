// A form a permission covers for a while comes back as the person left it,
// as the original keeps its `filling` by the request's id (dialogs/state.ts
// form_filled); one settled is let go.
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/wheel.dart' show wheelPermission;
import '../../fixtures/forms.dart';
import 'selection_window_test.dart';

const _form = model.FormWait(
  'f',
  'Set up the deploy target',
  schema: formSchema,
);

void _set(
  StartConnection connection,
  model.TurnState turn, {
  bool asked = true,
}) {
  final old = connection.app.value;
  connection.app.value = AppState(
    start: old.start,
    transcript: model.Transcript(
      entries: old.transcript.entries,
      turn: turn,
      asking: asked ? const [_form] : const [],
    ),
  );
}

/// The Project name field's row.
String _name(WidgetTester t) =>
    t.screen.lines.firstWhere((line) => line.contains('Project name'));

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('a form covered by a permission comes back as it was left '
        '$size', (t) async {
      final connection = selectionConnection();
      addTearDown(connection.close);
      _set(connection, const model.Working('t', 0));
      await t.pumpWidget(
        TranscriptWindow(launch: selectionLaunch, connection: connection),
        size: size,
      );
      expect(t.screen.text, contains('Project name'));
      await t.type('deploy');
      expect(_name(t), contains('deploy'));

      _set(connection, model.AwaitingPermission('t', 0, [wheelPermission()]));
      await t.pump();
      expect(t.screen.text, isNot(contains('Project name')));

      _set(connection, const model.Working('t', 0));
      await t.pump();
      expect(t.screen.text, contains('Project name'));
      expect(_name(t), contains('deploy'));
      // Its keys come back too: what is typed goes on where it was left.
      await t.type('-api');
      expect(_name(t), contains('deploy-api'));

      // Settled, it is let go: asked again under the same id, it starts
      // as new.
      _set(connection, const model.Working('t', 0), asked: false);
      await t.pump();
      _set(connection, const model.Working('t', 0));
      await t.pump();
      expect(_name(t), isNot(contains('deploy')));
    });
  }
}

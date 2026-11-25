// The keybindings file's problems in the window, from the original's
// Status.tsx: counted with the first named, until the draft is touched.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const launch = Launch(
  name: 'fake',
  agent: null,
  agentCommand: 'fake',
  version: '0.0.1',
  directory: '.',
);

const notice = 'keybindings.json: 2 problems · unknown context "Nope", ignored';

void main() {
  test('the notice starts the window, and touching the draft takes it', () {
    final state = AppState.starting.withKeysFailed(notice);
    expect(state.keysFailed, notice);
    expect(AppState.starting.withKeysFailed(null).keysFailed, isNull);
    final typed = reduceWindow(state, const DraftEditedAction('x', 1));
    expect(typed.keysFailed, isNull);
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the status line says the problems until a key types, at '
        '$size', (t) async {
      final hanging = Completer<Agent>();
      final c = StartConnection(
        command: 'fake',
        cwd: '.',
        agent: 'fake',
        owner: Owned(),
        keysFailed: notice,
        open:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) => hanging.future,
      )..start();
      addTearDown(c.close);
      addTearDown(() {
        hanging.future.ignore();
        hanging.completeError(StateError('over'));
      });
      await t.pumpWidget(
        TranscriptWindow(launch: launch, connection: c),
        size: size,
      );
      String status() => t.screen.lines.lastWhere((l) => l.trim().isNotEmpty);
      // It outranks the start's own line, as a failure does.
      expect(status(), contains('keybindings.json: 2 problems'));
      await t.type('x');
      expect(status(), isNot(contains('keybindings.json')));
      expect(status(), contains('Starting fake…'));
    });
  }
}

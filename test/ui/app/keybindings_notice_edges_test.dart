import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'keybindings_window_test.dart' show launch, notice;

void main() {
  group('tester: keybindings notice lifetime', () {
    test('connection results and exit preserve a notice until editing', () {
      for (final event in const [
        Connected('session', AgentState.empty),
        ConnectFailed('failed startup'),
        Gone('agent exited'),
      ]) {
        final state = reduceApp(
          AppState.starting.withKeysFailed(notice),
          event,
        );
        expect(state.keysFailed, notice);
        expect(
          reduceWindow(state, const DraftClearedAction()).keysFailed,
          isNull,
        );
      }
    });

    test('unchanged draft and unrelated actions retain the notice', () {
      final initial = AppState.starting.withKeysFailed(notice);
      expect(
        reduceWindow(initial, const DraftEditedAction('', 0)),
        same(initial),
      );
      var state = reduceWindow(initial, const ToggleExpandedAction());
      state = reduceWindow(state, const QuitArmedAction());
      state = reduceWindow(state, const QuitDisarmedAction());
      expect(state.keysFailed, notice);
      state = reduceWindow(state, const PasteFailedAction('paste failed'));
      state = reduceWindow(state, const DraftEditedAction('界👩‍💻é', 3));
      expect(state.keysFailed, isNull);
      expect(state.pasteFailed, isNull);
    });

    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'quit and paste outrank warning; paste editing clears both $size',
        (t) async {
          final c = StartConnection(command: 'unused', cwd: '.')
            ..app.value = AppState.starting.withKeysFailed(notice);
          addTearDown(c.close);
          await t.pumpWidget(
            TranscriptWindow(launch: launch, connection: c),
            size: size,
          );
          String status() =>
              t.screen.lines.lastWhere((line) => line.trim().isNotEmpty);
          expect(status(), contains('keybindings.json: 2 problems'));
          c.app.value = reduceWindow(c.app.value, const QuitArmedAction());
          await t.pump();
          expect(status(), contains('Press ctrl+c again to quit'));
          c.app.value = reduceWindow(c.app.value, const QuitDisarmedAction());
          await t.pump();
          expect(status(), contains('keybindings.json: 2 problems'));
          c.app.value = reduceWindow(
            c.app.value,
            const PasteFailedAction('paste failure'),
          );
          await t.pump();
          expect(status(), contains('paste failure'));
          expect(status(), isNot(contains('keybindings.json')));
          expect(c.app.value.keysFailed, notice);
          await t.resize(const Size(20, 8));
          await t.resize(size);
          await t.paste('界👩‍💻é');
          expect(c.app.value.keysFailed, isNull);
          expect(c.app.value.pasteFailed, isNull);
          expect(status(), contains('Starting fake…'));
        },
      );
    }
  });
}

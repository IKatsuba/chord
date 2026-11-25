import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart' show select;
import 'permission_window_test.dart' show launch;

void main() {
  group('tester: held permission status hint precedence', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      for (final cycle in [false, true]) {
        testWidgets(
          'draft and selection outrank shortcut hint, cycle=$cycle at $size',
          (t) async {
            final connection = StartConnection(command: 'unused', cwd: '.');
            addTearDown(connection.close);
            connection.app.value = AppState(
              start: const StartState(phase: StartPhase.connected),
              transcript: model.Transcript(
                entries: const [model.UserEntry('turn', 'select me')],
                turn: model.AwaitingPermission(
                  'turn',
                  0,
                  const [model.PermissionWait('held', title: 'Held request')],
                  between: true,
                  cycle: cycle,
                  cycleSince: cycle ? 0 : null,
                ),
              ),
            );
            await t.pumpWidget(
              TranscriptWindow(
                launch: launch,
                connection: connection,
                copyOnSelect: false,
              ),
              size: size,
            );
            expect(t.screen.lines.last, contains('? for shortcuts'));
            expect(
              t.screen.lines.last,
              contains('permission asked between turns'),
            );
            await t.type('draft');
            expect(t.screen.lines.last, isNot(contains('? for shortcuts')));
            await t.press('ctrl+u');
            expect(connection.app.value.draft, isEmpty);
            expect(t.screen.lines.last, contains('? for shortcuts'));
            await t.resize(Size.zero);
            await t.resize(const Size(1, 1));
            await t.resize(size);
            expect(t.screen.lines.last, contains('? for shortcuts'));
            await select(t, 'select me');
            expect(t.screen.lines.last, contains('ctrl + c to copy'));
            expect(t.screen.lines.last, isNot(contains('? for shortcuts')));
          },
        );
      }
    }
  });
}

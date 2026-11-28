import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'window_layout_test.dart' show launch;

// chord_tui's ListView takes the wheel only with scrollsOnWheel; chord's
// transcript handles the wheel itself, so one report must move it once.
void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a wheel report scrolls the transcript once, not twice, at '
        '$size', (t) async {
      final c = StartConnection(command: 'unused', cwd: '.')
        ..app.value = AppState(
          start: const StartState(phase: StartPhase.connected),
          transcript: model.Transcript(
            entries: [
              for (var i = 0; i < 100; i++)
                model.UserEntry('row$i', 'Named transcript row $i'),
            ],
          ),
        );
      addTearDown(c.close);
      await t.pumpWidget(
        TranscriptWindow(launch: launch, connection: c),
        size: size,
      );
      final before = c.app.value.scroll.offset;
      await t.mouse(
        MouseEvent(
          MouseEventKind.wheel,
          position: const Offset(2, 2),
          scrollDelta: const Offset(0, -1),
        ),
      );
      expect(c.app.value.scroll.offset, before - 1);
      await t.mouse(
        MouseEvent(
          MouseEventKind.wheel,
          position: const Offset(2, 2),
          scrollDelta: const Offset(0, -3),
        ),
      );
      expect(c.app.value.scroll.offset, before - 1 - 3);
    });
  }
}

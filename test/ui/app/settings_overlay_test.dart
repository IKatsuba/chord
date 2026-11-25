import 'package:chord/session/agent_state.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../session/settings_test.dart' show select, value;
import 'window_fake_test.dart' show launch;

void main() {
  for (final size in [
    const Size(120, 40),
    const Size(80, 24),
    const Size(80, 14),
  ]) {
    testWidgets('numbered picker floats opaquely and bubbles wheel at $size', (
      t,
    ) async {
      final c = StartConnection(command: 'unused', cwd: '.')
        ..app.value = AppState(
          start: const StartState(phase: StartPhase.connected),
          agent: AgentState(
            configOptions: [
              select('model', 'model', [
                for (var i = 0; i < 30; i++) value('model$i'),
              ], current: 'model0'),
            ],
          ),
          transcript: model.Transcript(
            entries: [
              for (var i = 0; i < 100; i++)
                model.UserEntry('$i', 'background row $i'),
            ],
          ),
        );
      addTearDown(c.close);
      await t.pumpWidget(
        TranscriptWindow(launch: launch, connection: c),
        size: size,
      );
      final focus = t.focusManager.primaryFocus;
      final prompt = t.screen.lines.indexWhere((row) => row.startsWith('╭'));
      await t.type('/model');
      await t.press('enter');
      await t.pump();
      expect(
        t.screen.lines.lastIndexWhere((row) => row.startsWith('╭')),
        prompt,
      );
      final title = t.screen.lines.indexWhere(
        (row) => row.contains('Select model'),
      );
      final bottom = t.screen.lines.indexWhere((row) => row.startsWith('╰'));
      expect(title, greaterThanOrEqualTo(1));
      for (final row in t.screen.lines.sublist(title, bottom + 1)) {
        expect(row, isNot(contains('background row')));
      }
      final offset = c.app.value.scroll.offset;
      final choices = t.screen.lines.sublist(title, bottom + 1);
      await t.mouse(
        MouseEvent(
          MouseEventKind.wheel,
          position: Offset(10, title + 3),
          scrollDelta: const Offset(0, -1),
        ),
      );
      expect(c.app.value.scroll.offset, offset - 1);
      expect(t.screen.lines.sublist(title, bottom + 1), choices);
      await t.press('esc');
      expect(t.focusManager.primaryFocus, same(focus));
      await t.type('kept draft');
      expect(c.app.value.draft, 'kept draft');
    });
  }
}

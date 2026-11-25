import 'package:chord/session/agent_state.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
import 'package:chord/ui/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/widgets/theme.dart' show TerminalEnvironment;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'app/start_page_test.dart' show agents;
import 'pickers/settings_picker_test.dart' show options;
import 'start_look_test.dart' show select;

void main() {
  group('tester: startup bound-key handoff boundaries', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      for (final first in ['down', 'enter', '1']) {
        testWidgets('$first yields to a cancel chord without choosing $size', (
          t,
        ) async {
          var canceled = 0;
          final picked = <String>[];
          await t.pumpWidget(
            StartLook(
              keymap: select({'escape': null, '$first q': 'select:cancel'}),
              child: StartPage(
                version: 'test',
                directory: 'project',
                agents: agents(3),
                onPicked: picked.add,
                onCanceled: () => canceled++,
              ),
            ),
            size: size,
          );
          await t.press(first);
          expect(picked, isEmpty);
          expect(canceled, 0);
          await t.press('q');
          expect(canceled, 1);
          expect(picked, isEmpty);
          expect(t.exitRequested, isTrue);
        });
      }

      for (final kind in ['settings', 'theme']) {
        testWidgets('$kind picker yields Enter prefix to cancellation $size', (
          t,
        ) async {
          var canceled = 0, picked = 0;
          await t.pumpWidget(
            StartLook(
              keymap: select({'escape': null, 'enter q': 'select:cancel'}),
              child: kind == 'theme'
                  ? ThemePicker(
                      current: 'dark',
                      background: const TerminalBackground(
                        Brightness.dark,
                        BrightnessSource.fallback,
                      ),
                      room: size.height,
                      onMove: (_) {},
                      onPick: (_) => picked++,
                      onCanceled: () => canceled++,
                    )
                  : Align(
                      alignment: Alignment.bottomLeft,
                      child: SettingsPicker(
                        state: const SettingsPickerState('model'),
                        agent: AgentState(configOptions: options),
                        agentName: 'fake',
                        windowRows: size.height,
                        onAction: (_) {},
                        onSelected: (_) => picked++,
                        onCanceled: () => canceled++,
                      ),
                    ),
            ),
            size: size,
          );
          await t.press('enter');
          expect(picked, 0);
          await t.press('q');
          expect(canceled, 1);
          expect(picked, 0);
        });
      }

      testWidgets(
        'named startup theme respects NO_COLOR through resize $size',
        (t) async {
          await t.pumpWidget(
            TerminalEnvironment(
              background: const TerminalBackground(
                Brightness.dark,
                BrightnessSource.fallback,
              ),
              noColor: true,
              child: StartLook(
                theme: 'light-ansi',
                child: StartPage(
                  version: 'test',
                  directory: 'project',
                  agents: agents(3),
                  onPicked: (_) {},
                ),
              ),
            ),
            size: size,
          );
          for (final room in [const Size(1, 1), const Size(0, 0), size]) {
            await t.resize(room);
          }
          expect(t.screen.text, contains('Select agent'));
          for (var y = 0; y < size.height; y++) {
            for (var x = 0; x < size.width; x++) {
              expect(t.screen.styleAt(x, y).fg, isNull);
              expect(t.screen.styleAt(x, y).bg, isNull);
            }
          }
        },
      );
    }
  });
}

// A settings call's rows select as they are drawn, in their tones, as the
// original's SettingsBody rows are selectable.
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/theme/theme.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('a change\'s rows are drawn in their tones and select as '
        'text, at $size', (t) async {
      final theme = ThemeData.dark();
      const entry = model.ToolEntry(
        't',
        model.ToolCall(
          'c1',
          title: 'mcp__chord__settings',
          status: 'completed',
          chord: model.ChordCall(
            tool: model.ChordTool.settings,
            input: {
              'action': 'set',
              'path': ['agent'],
              'value': 'codex',
            },
            answer: {
              'path': ['agent'],
              'before': 'claude',
              'after': 'codex',
              'file': '~/s.json',
              'saved': true,
              'takesEffect': 'next start',
              'shadowedBy': '.chord/settings.json',
            },
          ),
        ),
      );
      final source = entrySelectionSource(
        entry,
        id: 'e',
        revision: 0,
        width: size.width,
        settingsStyles: (warning: theme.warning, success: theme.success),
      );
      final selection = SelectionController();
      addTearDown(selection.dispose);
      await t.pumpWidget(
        Theme(
          data: theme,
          child: ChordThemeScope(
            child: SelectionArea(
              controller: selection,
              selectionStyle: const Style(inverse: true),
              child: Tool(entry.call, expanded: false, selectionSource: source),
            ),
          ),
        ),
        size: size,
      );
      final lines = [for (final line in t.screen.lines) line.trimRight()];
      expect(lines.sublist(1, 6), [
        '⏺ Settings(agent) · change',
        '  ⎿  Now    "claude"',
        '     After  "codex"',
        '     .chord/settings.json sets this too, and wins here',
        '     Saved to ~/s.json · takes effect at the next start',
      ]);
      expect(t.screen.styleAt(5, 4), theme.warning);
      expect(t.screen.styleAt(5, 5), theme.success);
      t.host.handleMouse(
        const MouseEvent(
          MouseEventKind.press,
          position: Offset(5, 2),
          button: MouseButton.primary,
        ),
      );
      t.host.handleMouse(
        const MouseEvent(
          MouseEventKind.move,
          position: Offset(20, 3),
          button: MouseButton.primary,
        ),
      );
      t.host.handleMouse(
        const MouseEvent(
          MouseEventKind.release,
          position: Offset(20, 3),
          button: MouseButton.primary,
        ),
      );
      expect(
        selection.snapshot()!.text.trimRight(),
        'Now    "claude"\nAfter  "codex"',
      );
    });
  }
}

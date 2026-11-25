// The no-agent subagents fixture draws at both sizes, folded and opened,
// without a selection geometry error.
import 'package:chord/session/start_connection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../../tool/agents.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('the fixture folds and opens at $size', (t) async {
      final connection = StartConnection(command: 'unused', cwd: '.');
      addTearDown(connection.close);
      await t.pumpWidget(agentsPreview(connection), size: size);
      expect(t.screen.text, contains('→ to Agent(Check the build)'));
      expect(t.screen.text, contains('lines (ctrl+o to expand)'));
      await t.press('ctrl+o');
      await t.press('end');
      expect(t.screen.text, contains('Quoted from the notes.'));
      await t.press('ctrl+o');
      expect(t.screen.text, contains('lines (ctrl+o to expand)'));
    });
  }
}

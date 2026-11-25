// A link asked between turns is held above the prompt and, like a form,
// folds into the room the window leaves it, as the original's Link.tsx
// wraps its body in Fold: the status line keeps the last row.
import 'package:chord/session/start_connection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/form.dart';

void main() {
  testWidgets('a long held link folds at 80x24 with the status line '
      'on the last row', (t) async {
    final connection = StartConnection(command: 'unused', cwd: '.');
    addTearDown(connection.close);
    await t.pumpWidget(
      formPreview(connection, const ['--long-link']),
      size: const Size(80, 24),
    );
    final lines = t.screen.lines;
    final more = lines.indexWhere((line) => line.contains('more lines'));
    expect(more, isNot(-1), reason: t.screen.text);
    expect(lines[more], startsWith('│   … '));
    expect(lines[more + 2], startsWith('│ ctrl+x a to answer'));
    expect(lines[23], startsWith('  ● '));
    expect(t.screen.text, isNot(contains('Open in the browser')));
  });

  testWidgets('a long link at 120x40 stands whole', (t) async {
    final connection = StartConnection(command: 'unused', cwd: '.');
    addTearDown(connection.close);
    await t.pumpWidget(
      formPreview(connection, const ['--long-link']),
      size: const Size(120, 40),
    );
    expect(t.screen.text, isNot(contains('more lines')));
    expect(t.screen.text, contains('1. Open in the browser'));
  });
}

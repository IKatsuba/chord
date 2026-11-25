// The start pages take the keybindings file and the theme setting, as the
// original's main passes keymap and colours to its Start.
import 'dart:convert';

import 'package:chord/ui/app/start.dart';
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:chord/ui/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../tool/resume.dart' show resumeFixtureState;
import 'app/start_page_test.dart' show agents;

Keybindings select(Map<String, Object?> bindings) => readKeybindings(
  jsonEncode({
    'bindings': [
      {'context': 'Select', 'bindings': bindings},
    ],
  }),
).keymap;

/// The colours the screen draws its text in.
Set<Color?> colours(WidgetTester t) => {
  for (var y = 0; y < t.screen.lines.length; y++)
    for (var x = 0; x < t.screen.lines[y].length; x++)
      if (t.screen.lines[y][x].trim().isNotEmpty) t.screen.styleAt(x, y).fg,
};

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the agent page cancels on the file\'s key and says it, at '
        '$size', (t) async {
      var canceled = 0;
      await t.pumpWidget(
        StartLook(
          keymap: select({'escape': null, 'q': 'select:cancel'}),
          child: StartPage(
            version: '0.0.1',
            directory: 'project',
            agents: agents(3),
            onPicked: (_) {},
            onCanceled: () => canceled++,
          ),
        ),
        size: size,
      );
      final text = t.screen.text.replaceAll(RegExp(r'\s+'), ' ');
      expect(text, contains('Q to cancel'));
      expect(text, isNot(contains('Esc to cancel')));
      await t.press('esc');
      expect(canceled, 0);
      await t.press('q');
      expect(canceled, 1);
    });

    testWidgets('the resume page changes scope and cancels on the file\'s '
        'keys, and says them, at $size', (t) async {
      var canceled = 0;
      await t.pumpWidget(
        StartLook(
          keymap: select({
            'escape': null,
            'q': 'select:cancel',
            'ctrl+a': null,
            'ctrl+t': 'select:toggleScope',
          }),
          child: ResumeStartPage(
            version: 'test',
            directory: 'project',
            agent: 'fake',
            cwd: 'project',
            home: 'home',
            sessions: resumeFixtureState(const []).sessions,
            openedAt: 946771200000,
            onPicked: (_) {},
            onCanceled: () => canceled++,
          ),
        ),
        size: size,
      );
      final text = t.screen.text.replaceAll(RegExp(r'\s+'), ' ');
      expect(text, contains('Ctrl+t for all directories'));
      expect(text, contains('Q to quit'));
      await t.press('ctrl+t');
      expect(
        t.screen.text.replaceAll(RegExp(r'\s+'), ' '),
        contains('Ctrl+t for this directory'),
      );
      await t.press('esc');
      expect(canceled, 0);
      await t.press('q');
      expect(canceled, 1);
    });

    testWidgets('a picker key the file gives cancel cancels, choosing '
        'nothing, at $size', (t) async {
      var canceled = 0;
      final picked = <String>[];
      await t.pumpWidget(
        StartLook(
          keymap: select({'enter': 'select:cancel', 'escape': null}),
          child: StartPage(
            version: '0.0.1',
            directory: 'project',
            agents: agents(3),
            onPicked: picked.add,
            onCanceled: () => canceled++,
          ),
        ),
        size: size,
      );
      expect(
        t.screen.text.replaceAll(RegExp(r'\s+'), ' '),
        contains('Enter to cancel'),
      );
      await t.press('enter');
      expect(canceled, 1);
      expect(picked, isEmpty);
    });

    testWidgets('a picker key the file gives the scope changes it, moving '
        'nothing, at $size', (t) async {
      final picked = <Object>[];
      await t.pumpWidget(
        StartLook(
          keymap: select({'j': 'select:toggleScope', 'ctrl+a': null}),
          child: ResumeStartPage(
            version: 'test',
            directory: 'project',
            agent: 'fake',
            cwd: 'project',
            home: 'home',
            sessions: resumeFixtureState(const []).sessions,
            openedAt: 946771200000,
            onPicked: picked.add,
          ),
        ),
        size: size,
      );
      final before = t.screen.text;
      await t.press('j');
      final after = t.screen.text.replaceAll(RegExp(r'\s+'), ' ');
      expect(after, contains('J for this directory'));
      expect(t.screen.text, isNot(before));
      expect(picked, isEmpty);
    });

    testWidgets('the start page is drawn in the theme the file names, at '
        '$size', (t) async {
      Widget look(String? theme) => StartLook(
        theme: theme,
        child: StartPage(
          version: '0.0.1',
          directory: 'project',
          agents: agents(3),
          onPicked: (_) {},
        ),
      );
      await t.pumpWidget(look(null), size: size);
      final auto = colours(t);
      await t.pumpWidget(look('light-ansi'), size: size);
      final ansi = colours(t);
      expect(ansi, isNot(auto));
      expect(ansi.whereType<RgbColor>(), isEmpty);
    });
  }
}

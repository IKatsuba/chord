// /theme in the window, from the original's guide: moving through the list
// shows the whole window in the theme highlighted, Enter keeps it and saves
// it to the settings file, and Esc goes back.
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'selection_window_test.dart' show selectionConnection;

Future<StartConnection> window(
  WidgetTester t,
  Size size, {
  String? theme,
  String? settingsFile,
}) async {
  // Connected, so chord's own commands run, with nothing in the transcript.
  final c = selectionConnection(const []);
  c.app.value = c.app.value.withTheme(theme);
  addTearDown(c.close);
  await t.pumpWidget(
    TranscriptWindow(
      launch: Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
        theme: theme,
        settingsFile: settingsFile,
        shownSettingsFile: settingsFile,
      ),
      connection: c,
    ),
    size: size,
  );
  return c;
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

/// The colour the picker's title is drawn in: the theme's focus.
Color? titleColour(WidgetTester t) {
  final y = t.screen.lines.indexWhere((l) => l.contains('Theme'));
  final x = t.screen.lines[y].indexOf('Theme');
  return t.screen.styleAt(x, y).fg;
}

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('/theme lists the themes, the one in use marked, and the '
        'window previews the one highlighted, at $size', (t) async {
      final c = await window(t, size);
      await t.type('/theme');
      await t.press('enter');
      await settle(t);
      expect(
        t.screen.text,
        contains('Auto (dark: the terminal did not say) ✔'),
      );
      expect(t.screen.text, contains('Light, colour-blind friendly'));
      expect(t.screen.text, contains('Enter to keep'));
      expect(t.screen.text, contains('Esc to go back to Auto'));
      expect(c.app.value.themePreview, 'auto');
      expect(titleColour(t), RgbColor.hex('#b1b9f9'));
      await t.press('down');
      await t.press('down');
      await settle(t);
      expect(c.app.value.themePreview, 'light');
      expect(titleColour(t), RgbColor.hex('#4a5ae0'));
      // Esc goes back, to the theme in use and its colours.
      await t.press('esc');
      await settle(t);
      expect(c.app.value.themePreview, isNull);
      expect(c.app.value.theme, 'auto');
      expect(t.screen.text, isNot(contains('Enter to keep')));
    });

    testWidgets("Enter keeps the theme and saves it to the user's file, at "
        '$size', (t) async {
      final dir = await Directory.systemTemp.createTemp('chord-theme-');
      addTearDown(() => dir.delete(recursive: true));
      final file = p.join(dir.path, 'chord', 'settings.json');
      final c = await window(t, size, settingsFile: file);
      await t.type('/theme');
      await t.press('enter');
      await settle(t);
      await t.press('down');
      await t.press('down');
      await t.press('enter');
      await settle(t);
      expect(c.app.value.theme, 'light');
      expect(c.app.value.themePreview, isNull);
      for (var i = 0; i < 20 && !File(file).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await t.pump();
      }
      expect(await File(file).readAsString(), contains('"theme": "light"'));
      await settle(t);
      expect(t.screen.text, contains('Theme set to Light'));
    });

    testWidgets("the window starts in the user's theme, at $size", (t) async {
      await window(t, size, theme: 'light-ansi');
      await t.type('/theme');
      await t.press('enter');
      await settle(t);
      expect(t.screen.text, contains("Light, the terminal's 16 colours ✔"));
      expect(titleColour(t), Colors.blue);
    });

    testWidgets('a plan put to the person takes the picker\'s place and its '
        'preview, which come back after, at $size', (t) async {
      final c = await window(t, size);
      await t.type('/theme');
      await t.press('enter');
      await settle(t);
      await t.press('down');
      await t.press('down');
      await settle(t);
      expect(c.app.value.shownTheme, 'light');
      c.app.value = reduceApp(
        c.app.value,
        const Transcribed(
          PlanRequestedAction(
            't1',
            PlanWait('p1', PlanAgent.grok, toolCallId: 'c1', plan: '# Plan'),
          ),
        ),
      );
      await settle(t);
      // The plan has the keys and the window its colours in use.
      expect(t.screen.text, isNot(contains('Enter to keep')));
      expect(c.app.value.shownTheme, 'auto');
      expect(c.app.value.themePreview, 'light');
      c.app.value = reduceApp(
        c.app.value,
        const Transcribed(PlanSettledAction('t1', 'p1', PlanLeft())),
      );
      await settle(t);
      expect(t.screen.text, contains('Enter to keep'));
      expect(c.app.value.shownTheme, 'light');
    });
  }

  test('/clear keeps the theme, as the original, and vim mode reset, a '
      'fix of its slip', () {
    final chosen = reduceWindow(
      reduceWindow(
        reduceWindow(
          const AppState().withVim(true),
          const VimChangedAction(
            VimState(mode: VimMode.normal, pending: ['d']),
          ),
        ),
        const ThemePickerOpenedAction(),
      ),
      const ThemeChosenAction('light'),
    );
    final cleared = reduceApp(chosen, const Cleared());
    expect(cleared.theme, 'light');
    expect(cleared.shownTheme, 'light');
    expect(cleared.themePreview, isNull);
    expect(cleared.vim, const VimState());
  });
}

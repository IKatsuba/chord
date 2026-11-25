import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/widgets/theme.dart' show TerminalEnvironment;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart' show selectionConnection;
import 'theme_window_test.dart' show window, settle;

void main() {
  group('tester: theme choice lifecycle boundaries', () {
    test(
      'clear retains committed theme and vim register but clears transient state',
      () {
        final state = AppState(
          theme: 'light-ansi',
          themePreview: 'dark',
          vim: const VimState(
            mode: VimMode.normal,
            pending: ['f'],
            goalColumn: 9,
            lastFind: 'fx',
            register: VimRegister('kept'),
          ),
        );
        final cleared = reduceApp(state, const Cleared());
        expect(cleared.theme, 'light-ansi');
        expect(cleared.themePreview, isNull);
        expect(cleared.vim, const VimState(register: VimRegister('kept')));
      },
    );

    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'keeping current theme and cancelling preview never rewrite $size',
        (t) async {
          final root = await Directory.systemTemp.createTemp('theme-no-write-');
          addTearDown(() => root.delete(recursive: true));
          final file = File('${root.path}/settings.json');
          const raw = '{ "theme": "light", "keep": true }\n';
          await file.writeAsString(raw);
          final before = await file.stat();
          final c = await window(
            t,
            size,
            theme: 'light',
            settingsFile: file.path,
          );
          await t.type('/theme');
          await t.press('enter');
          await settle(t);
          await t.press('enter');
          await settle(t);
          expect(c.app.value.themePreview, isNull);
          expect(c.app.value.theme, 'light');
          expect(await file.readAsString(), raw);
          expect((await file.stat()).modified, before.modified);
          expect(t.screen.text, isNot(contains('Theme set to')));
          await t.type('/theme');
          await t.press('enter');
          await settle(t);
          await t.press('down');
          await t.press('esc');
          await settle(t);
          expect(c.app.value.theme, 'light');
          expect(await file.readAsString(), raw);
          expect((await file.stat()).modified, before.modified);
        },
      );

      testWidgets(
        'failed save keeps chosen theme live and preserves broken file $size',
        (t) async {
          final root = await Directory.systemTemp.createTemp('theme-failure-');
          addTearDown(() => root.delete(recursive: true));
          final file = File('${root.path}/settings.json');
          await file.writeAsString('{');
          final c = await window(t, size, settingsFile: file.path);
          await t.type('/theme');
          await t.press('enter');
          await settle(t);
          await t.press('down down enter');
          await settle(t);
          expect(c.app.value.theme, 'light');
          expect(c.app.value.themePreview, isNull);
          expect(await file.readAsString(), '{');
          expect(t.screen.text, contains('Could not save the theme'));
          expect(root.listSync(), hasLength(1));
        },
      );

      testWidgets(
        'permission hides theme preview and settlement restores it $size',
        (t) async {
          final c = await window(t, size, theme: 'dark');
          await t.type('/theme');
          await t.press('enter');
          await settle(t);
          await t.press('down');
          expect(c.app.value.shownTheme, 'light');
          c.app.value = reduceApp(
            c.app.value,
            const Transcribed(model.PromptAction('turn', 'request', 0)),
          );
          c.app.value = reduceApp(
            c.app.value,
            const Transcribed(
              model.PermissionRequestedAction(
                'turn',
                model.PermissionWait('ask', title: 'Permission'),
              ),
            ),
          );
          await settle(t);
          expect(c.app.value.themePickerShown, isFalse);
          expect(c.app.value.shownTheme, 'dark');
          expect(t.screen.text, isNot(contains('Enter to keep')));
          c.app.value = reduceApp(
            c.app.value,
            const Transcribed(
              model.PermissionSettledAction('turn', 'ask', model.Rejected()),
            ),
          );
          await settle(t);
          expect(c.app.value.shownTheme, 'light');
          expect(t.screen.text, contains('Enter to keep'));
          await t.press('esc');
          expect(c.app.value.shownTheme, 'dark');
        },
      );

      testWidgets(
        'NO_COLOR remains unpainted during named-theme preview $size',
        (t) async {
          final c = selectionConnection(const []);
          c.app.value = c.app.value.withTheme('light');
          addTearDown(c.close);
          await t.pumpWidget(
            TerminalEnvironment(
              background: const TerminalBackground(
                Brightness.dark,
                BrightnessSource.fallback,
              ),
              noColor: true,
              child: Theme(
                data: ThemeData.plain(),
                child: TranscriptWindow(
                  launch: const Launch(
                    name: 'fake',
                    agent: null,
                    agentCommand: 'unused',
                    version: 'test',
                    directory: '.',
                    theme: 'light',
                  ),
                  connection: c,
                ),
              ),
            ),
            size: size,
          );
          await t.type('/theme');
          await t.press('enter');
          await settle(t);
          expect(t.screen.text, contains('NO_COLOR is set'));
          await t.press('down');
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

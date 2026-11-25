import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: named theme bridge boundaries', () {
    test('every setting marks itself independently of auto resolution', () {
      for (final setting in themeSettingIds) {
        for (final brightness in Brightness.values) {
          final found = TerminalBackground(
            brightness,
            BrightnessSource.terminal,
          );
          final choices = themeChoices(setting, found);
          expect(choices.where((c) => c.current).single.value, setting);
          expect(choices.where((c) => c.label.endsWith(' ✔')), hasLength(1));
          expect(
            resolveTheme(setting, found),
            setting == 'auto' ? brightness.name : setting,
          );
        }
      }
    });

    test('layout is bounded and monotonic through all threshold rooms', () {
      var previous = 0;
      for (var room = -10; room <= 45; room++) {
        final layout = themePickerLayout(room);
        expect(layout.choices, inInclusiveRange(0, 7));
        expect(layout.choices, greaterThanOrEqualTo(previous));
        expect(layout.sample, room >= 18);
        previous = layout.choices;
      }
    });

    test('every palette colour is understood by the framework bridge', () {
      for (final p in palettes.values) {
        for (final colour in [
          p.accent,
          p.permission,
          p.inlineCode,
          p.link,
          p.bash,
          p.plan,
          p.edits,
          p.auto,
          p.error,
          p.warning,
          p.success,
          p.selection,
          ...?p.agents,
          ...?p.code?.values,
          ...?p.codeOnTint?.values,
          p.diffAdded,
          p.diffRemoved,
          if (p.tint case final tint?) ...[tint.added, tint.removed, tint.text],
        ]) {
          if (colour != null) expect(colorOf(colour), isA<Color>());
        }
      }
      expect(colorOf('ansi256(0)'), const IndexedColor(0));
      expect(colorOf('ansi256(255)'), const IndexedColor(255));
      expect(colorOf('gray'), Colors.gray);
    });

    for (final size in const [Size(80, 24), Size(120, 40)]) {
      for (final name in palettes.keys) {
        testWidgets('$name retains its extension and paints mode roles $size', (
          t,
        ) async {
          final theme = themeData(name);
          final extension = theme.extension<ChordTheme>()!;
          ChordTheme? seen;
          await t.pumpWidget(
            Theme(
              data: theme,
              child: ChordThemeScope(
                child: Builder(
                  builder: (context) {
                    seen = chordThemeOf(context);
                    return Text('界👩‍💻é', style: seen!.bash);
                  },
                ),
              ),
            ),
            size: size,
          );
          expect(seen, same(extension));
          expect(t.screen.styleAt(0, 0).fg, extension.bash.fg);
          expect(extension.selection, theme.selection);
          for (final room in [const Size(1, 1), const Size(0, 0), size]) {
            await t.resize(room);
            expect(seen, same(extension));
          }
          expect(t.screen.text, startsWith('界👩‍💻é'));
        });
      }

      testWidgets(
        'NO_COLOR bridge retains inverse selection and plain roles $size',
        (t) async {
          for (final name in palettes.keys) {
            final theme = themeData(name, colour: false);
            ChordTheme? seen;
            await t.pumpWidget(
              Theme(
                data: theme,
                child: ChordThemeScope(
                  child: Builder(
                    builder: (context) {
                      seen = chordThemeOf(context);
                      return Text('plain', style: seen!.bash);
                    },
                  ),
                ),
              ),
              size: size,
            );
            expect(seen, same(chordPlain));
            expect(seen!.selection.isInverse, isTrue);
            expect(t.screen.styleAt(0, 0).fg, isNull);
            expect(theme.diff.tint, isNull);
            expect(
              theme.brightness,
              name.startsWith('light') ? Brightness.light : Brightness.dark,
            );
          }
        },
      );
    }
  });
}

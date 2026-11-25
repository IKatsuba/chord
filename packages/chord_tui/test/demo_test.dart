import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/widgets/theme.dart' show TerminalEnvironment;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/demo.dart';

void main() {
  group('the demo shows the theme', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      final at = '${size.width}x${size.height}';
      final w = size.width, h = size.height;

      testWidgets('header, borders and KeyHelp at $at', (t) async {
        await t.pumpWidget(const Demo(), size: size);
        final dark = ThemeData.dark();
        expect(t.screen.lines[0], startsWith(' chorded-tui demo '));
        expect(t.screen.lines[0], endsWith('dark: the terminal did not say'));
        expect(t.screen.styleAt(1, 0), dark.accent.merge(Style.bold));
        // The log box's border is the theme's, the prompt's is focus.
        expect(t.screen.styleAt(0, 1), dark.border);
        expect(t.screen.styleAt(0, h - 4), dark.focus);
        expect(t.screen.lines[h - 1], contains('ctrl+t Theme'));
      });

      testWidgets('ctrl+o shows the swatches at $at', (t) async {
        await t.pumpWidget(const Demo(), size: size);
        await t.type('hello');
        await t.press('enter');
        await t.press('ctrl+o');
        final dark = ThemeData.dark();
        expect(
          t.screen.lines[2],
          startsWith(
            '│ accent link code success warning error  + added  - removed',
          ),
        );
        expect(t.screen.styleAt(2, 2), dark.accent);
        expect(t.screen.styleAt(9, 2), dark.link);
        final plus = t.screen.lines[2].indexOf('+');
        expect(
          t.screen.styleAt(plus, 2),
          dark.diff.tint!.added.merge(dark.diff.added),
        );
        expect(t.screen.lines[3], contains('5 cells'));
        expect(
          t.screen.styleAt(t.screen.lines[3].indexOf('5 cells'), 3),
          dark.warning,
        );
      });

      testWidgets('ctrl+t cycles auto, dark, light, plain at $at', (t) async {
        await t.pumpWidget(const Demo(), size: size);
        await t.press('ctrl+t');
        expect(t.screen.lines[0], endsWith('dark (ctrl+t)'));
        expect(t.screen.styleAt(0, h - 4), ThemeData.dark().focus);
        await t.press('ctrl+t');
        expect(t.screen.lines[0], endsWith('light (ctrl+t)'));
        expect(t.screen.styleAt(0, h - 4), ThemeData.light().focus);
        expect(
          t.screen.styleAt(1, 0),
          ThemeData.light().accent.merge(Style.bold),
        );
        await t.press('ctrl+t');
        expect(t.screen.lines[0], endsWith('plain (ctrl+t)'));
        expect(t.screen.styleAt(0, 1), Style.dim);
        expect(t.screen.styleAt(0, h - 4), Style.bold);
        expect(t.screen.styleAt(w - 1, 0).fg, isNull);
        await t.press('ctrl+t');
        expect(t.screen.lines[0], endsWith('dark: the terminal did not say'));
      });
      testWidgets('under NO_COLOR every choice is plain and says so, at $at', (
        t,
      ) async {
        await t.pumpWidget(
          TerminalEnvironment(
            background: const TerminalBackground(
              Brightness.light,
              BrightnessSource.terminal,
            ),
            noColor: true,
            child: Theme(
              data: ThemeData.plain(brightness: Brightness.light),
              child: const Demo(),
            ),
          ),
          size: size,
        );
        expect(
          t.screen.lines[0],
          endsWith('light, from the terminal, no colour'),
        );
        for (final name in ['dark', 'light', 'plain']) {
          await t.press('ctrl+t');
          expect(t.screen.lines[0], endsWith('$name (ctrl+t), no colour'));
          expect(t.screen.styleAt(1, 0), Style.bold);
          expect(t.screen.styleAt(0, 1), Style.dim);
        }
        await t.press('ctrl+t');
        expect(t.screen.lines[0], endsWith('no colour'));
      });
    }
    testWidgets('a label that does not fit is dropped whole', (t) async {
      // ' chorded-tui demo ' takes 18 cells, the label 30.
      await t.pumpWidget(const Demo(), size: const Size(48, 24));
      expect(
        t.screen.lines[0],
        ' chorded-tui demo dark: the terminal did not say',
      );
      await t.resize(const Size(47, 24));
      expect(t.screen.lines[0], ' chorded-tui demo');
      // A shorter label shows again at the same width.
      await t.press('ctrl+t');
      expect(t.screen.lines[0], endsWith('dark (ctrl+t)'));
    });
  });

  group('the demo scrolls its log', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      final at = '${size.width}x${size.height}';

      testWidgets('fill, page and line keys, and ctrl+o keep the top at $at', (
        t,
      ) async {
        await t.pumpWidget(const Demo(), size: size);
        await t.press('ctrl+x f');
        expect(t.screen, shows('200 line 200'));
        await t.press('pageup');
        await t.press('shift+up');
        // The first item whose first row is in sight, by its number.
        String? first() => [
          for (final l in t.screen.lines.skip(2))
            RegExp(r'^│ (\d+) ').firstMatch(l)?.group(1),
        ].nonNulls.first;
        final top = t.screen.lines[2];
        final item = first();
        expect(top, isNot(contains('200 line 200')));
        await t.press('ctrl+o');
        expect(t.screen.lines[2], contains('accent link code'));
        expect(first(), item);
        await t.press('ctrl+o');
        expect(t.screen.lines[2], top);
        await t.type('back\n');
        expect(t.screen, shows('201 back'));
      });
    }
  });

  group('tester: demo interactions across theme changes', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'draft, log and busy state survive a full theme cycle at $size',
        (t) async {
          await t.pumpWidget(const Demo(), size: size);
          await t.paste('日本語 🙂 e\u0301');
          await t.press('ctrl+x b');
          await t.press('ctrl+o');
          for (var choice = 0; choice < 4; choice++) {
            await t.press('ctrl+t');
            expect(t.screen, shows('> 日本語 🙂 e\u0301'));
            expect(t.screen, shows('accent link code success warning error'));
          }
          await t.press('left');
          await t.press('backspace');
          await t.paste('!');
          await t.press('enter');
          expect(t.screen, shows('1 日本語 🙂!e\u0301'));
          expect(t.screen, shows('11 cells'));
          await t.paste('keep draft');
          await t.press('ctrl+x c');
          expect(t.screen, shows('Type something and press enter.'));
          expect(t.screen, shows('> keep draft'));
          await t.press('ctrl+x b');
          await t.press('ctrl+o');
          await t.press('ctrl+q');
          expect(t.exitRequested, isTrue);
        },
      );

      testWidgets(
        'NO_COLOR covers every painted cell after interactions at $size',
        (t) async {
          await t.pumpWidget(
            TerminalEnvironment(
              background: const TerminalBackground(
                Brightness.light,
                BrightnessSource.terminal,
              ),
              noColor: true,
              child: Theme(
                data: ThemeData.plain(brightness: Brightness.light),
                child: const Demo(),
              ),
            ),
            size: size,
          );
          await t.paste('日本語🙂');
          await t.press('enter');
          await t.press('ctrl+o');
          await t.press('ctrl+x b');
          for (var choice = 0; choice < 5; choice++) {
            expect(t.screen.lines.first, endsWith('no colour'));
            for (var y = 0; y < size.height; y++) {
              for (var x = 0; x < size.width; x++) {
                final style = t.screen.styleAt(x, y);
                expect(style.fg, isNull, reason: 'fg at $x,$y choice $choice');
                expect(style.bg, isNull, reason: 'bg at $x,$y choice $choice');
              }
            }
            await t.press('ctrl+t');
          }
          await t.pumpWidget(Text('removed'));
          await t.pump(const Duration(milliseconds: 120));
          expect(t.screen, shows('removed'));
        },
      );
    }

    testWidgets('a draft survives zero, one-cell and narrow resizes', (
      t,
    ) async {
      await t.pumpWidget(const Demo());
      await t.paste('🙂e\u0301日本語');
      for (final size in const [
        Size(1, 1),
        Size(0, 0),
        Size(34, 24),
        Size(120, 40),
        Size(80, 24),
      ]) {
        await t.resize(size);
      }
      expect(t.screen, shows('> 🙂e\u0301日本語'));
      await t.press('enter');
      expect(t.screen, shows('1 🙂e\u0301日本語'));
    });
  });

  group('tester: scrolled demo refill', () {
    for (final size in [const Size(80, 24), const Size(120, 40)]) {
      testWidgets('clear, submit and refill resume the bottom at $size', (
        tester,
      ) async {
        await tester.pumpWidget(const Demo(), size: size);
        await tester.press('ctrl+x f');
        await tester.press('pageup');
        await tester.press('ctrl+x c');
        expect(tester.screen, shows('Type something and press enter.'));
        await tester.paste('界🙂é');
        await tester.press('enter');
        expect(tester.screen, shows('1 界🙂é'));
        await tester.press('ctrl+x f');
        expect(tester.screen, shows('201 line 201'));
        await tester.press('ctrl+q');
        expect(tester.exitRequested, isTrue);
      });
    }
  });
  group('tester: LayoutBuilder demo header recovery', () {
    testWidgets('NO_COLOR long label drops whole and returns after resize', (
      t,
    ) async {
      await t.pumpWidget(
        TerminalEnvironment(
          background: const TerminalBackground(
            Brightness.light,
            BrightnessSource.terminal,
          ),
          noColor: true,
          child: Theme(data: ThemeData.plain(), child: const Demo()),
        ),
        size: const Size(120, 40),
      );
      const label = 'light, from the terminal, no colour';
      final width = 18 + label.length;
      await t.paste('界🙂e\u0301');
      await t.resize(Size(width, 24));
      expect(t.screen.lines.first, ' chorded-tui demo $label');
      await t.resize(Size(width - 1, 24));
      expect(t.screen.lines.first, ' chorded-tui demo');
      for (final size in const [
        Size(0, 0),
        Size(1, 1),
        Size(80, 24),
        Size(120, 40),
      ]) {
        await t.resize(size);
      }
      expect(t.screen.lines.first, endsWith(label));
      expect(t.screen, shows('> 界🙂e\u0301'));
      await t.press('ctrl+q');
      expect(t.exitRequested, isTrue);
    });
  });
}

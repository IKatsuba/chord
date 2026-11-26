import 'package:chord_site/page.dart';
import 'package:chord_site/palette.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../web/gallery.dart';
import 'fake_host.dart';

MouseEvent _at(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

Future<void> tap(WidgetTester t, int x, int y) async {
  await t.mouse(_at(MouseEventKind.press, x, y));
  await t.mouse(_at(MouseEventKind.release, x, y));
}

/// A line without the scrollbar's column.
String bare(String line) => line.replaceAll('┃', '').trimRight();

void main() {
  for (final size in const [Size(192, 56), Size(120, 40)]) {
    group('desktop at $size', () {
      testWidgets('the top line: a blank row, the mark and the numbered '
          'sections, a blank row, the rule', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        final dark = ThemeData.dark();
        expect(t.screen.lines[0], '');
        expect(t.screen.lines[2], '');
        expect(t.screen.lines[3], '─' * size.width);
        expect(t.screen.styleAt(0, 3), dark.border);
        final nav = t.screen.lines[1];
        expect(nav, startsWith('  CHORD / CHORD_TUI'));
        expect(t.screen.styleAt(8, 1), dark.accent.merge(Style.bold));
        expect(
          nav,
          contains('01 APP    02 FRAMEWORK    03 GALLERY    04 INSTALL'),
        );
        expect(nav, endsWith('GITHUB ↗ g    DEV'));
        // The current section is inverted: ink on cream.
        expect(t.screen.styleAt(nav.indexOf('04'), 1).isInverse, isTrue);
        expect(t.screen.styleAt(nav.indexOf('INSTALL'), 1).isInverse, isTrue);
        expect(
          t.screen.styleAt(nav.indexOf('GALLERY'), 1),
          dark.text.merge(Style.bold),
        );
        expect(
          t.screen.styleAt(nav.indexOf('03'), 1),
          dark.accent.merge(Style.bold),
        );
      });

      testWidgets('the help row sits on the bar colour', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        expect(
          t.screen.styleAt(size.width - 1, size.height - 1).bg,
          SiteColors.bar,
        );
      });

      testWidgets('a digit opens its section from another page, and a tap on '
          'a section opens it', (t) async {
        final host = FakeHost('/install');
        await t.pumpWidget(Site(host: host), size: size);
        await t.press('1');
        expect(host.pushed, ['/chord']);
        final nav = t.screen.lines[1];
        await tap(t, nav.indexOf('GALLERY'), 1);
        expect(host.pushed.last, '/chord_tui/gallery');
        await tap(t, nav.indexOf('CHORD'), 1);
        expect(host.pushed.last, '/', reason: 'the mark goes home');
      });

      testWidgets('m opens no menu where the sections fit', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        await t.press('m');
        expect(t.screen, isNot(shows('❯ 01 APP')));
      });

      testWidgets('the panel lists the section digits; the help row does '
          'not', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        expect(t.screen.lines.last, isNot(contains('1–4')));
        await t.press('f1');
        expect(t.screen, shows(RegExp(r'1–4\s+section')));
      });
    });
  }

  // The nav folds its sections into MENU m on a phone, and wherever they
  // do not fit: 80 columns too.
  for (final size in const [Size(80, 24), Size(54, 56), Size(43, 37)]) {
    group('folded at $size', () {
      testWidgets('m opens the menu over the page; esc closes it', (t) async {
        final host = FakeHost('/install');
        await t.pumpWidget(Site(host: host), size: size);
        expect(
          t.screen.lines[1],
          matches(RegExp(r'^  CHORD / CHORD_TUI +MENU m$')),
        );
        await t.press('m');
        final lines = t.screen.lines;
        expect(lines.sublist(4, 11), [
          '',
          ' ❯ 01 APP',
          '   02 FRAMEWORK',
          '   03 GALLERY',
          '   04 INSTALL',
          '      GITHUB ↗ g',
          '',
        ]);
        expect(lines.last, ' esc close');
        // Nothing reaches the page meanwhile.
        await t.paste('typed');
        await t.press('esc');
        expect(t.screen, isNot(shows('❯ 01 APP')));
        expect(host.pushed, isEmpty);
        expect(t.screen.lines.last, contains('escape up'));
        expect(t.screen.lines.last, isNot(contains('esc close')));
      });

      testWidgets('inside an entered example the help row ends with f1 '
          'keys, ? being text there', (t) async {
        await t.pumpWidget(
          Site(host: FakeHost('/chord_tui/text_area'), gallery: siteGallery),
          size: size,
        );
        await t.press('tab');
        expect(t.screen.lines.last, endsWith('f1 keys'));
        expect(t.screen.lines.last, isNot(contains('? keys')));
      });

      for (final quit in ['ctrl+q', 'ctrl+c']) {
        testWidgets('$quit closes the open menu and goes home, home too', (
          t,
        ) async {
          final host = FakeHost('/install');
          await t.pumpWidget(Site(host: host), size: size);
          await t.press('m');
          await t.press(quit);
          expect(host.pushed, ['/']);
          expect(t.screen, isNot(shows('❯ 01 APP')));
          await t.press('m');
          await t.press(quit);
          expect(host.pushed, ['/'], reason: 'already home');
          expect(t.screen, isNot(shows('❯ 01 APP')));
          expect(t.exitRequested, isFalse);
        });
      }

      testWidgets('F1 over the open menu lists its keys, and Esc closes the '
          'panel first', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        await t.press('m');
        await t.press('f1');
        expect(t.screen, shows(' Keys'));
        expect(t.screen, shows(RegExp(r'up/down\s+move')));
        expect(t.screen, shows(RegExp(r'enter\s+open')));
        expect(t.screen, shows(RegExp(r'1–4\s+section')));
        expect(t.screen, shows(RegExp(r'escape/m\s+close')));
        await t.press('esc');
        expect(t.screen, isNot(shows(' Keys')));
        expect(t.screen, shows('❯ 01 APP'));
      });

      testWidgets('the page'
          's keys are out of reach while the menu is open, '
          'and back after', (t) async {
        await t.pumpWidget(
          Site(host: FakeHost('/chord_tui/gallery'), gallery: siteGallery),
          size: size,
        );
        String selected() =>
            t.screen.lines.firstWhere((l) => l.contains('⏎ RUN'));
        // Demo starts selected, below the fold at 80x24: the down step
        // below shows where the selection was.
        await t.press('m');
        await t.press('right');
        await t.press('esc');
        await t.press('down');
        await t.pump();
        // Down from Demo: Picker two to a row, Markdown one to a row; a
        // right the menu let through would have started from Markdown.
        expect(selected(), contains(size.width < 60 ? 'MARKDOWN' : 'PICKER'));
      });

      testWidgets('m closes it again', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        await t.press('m');
        await t.press('m');
        expect(t.screen, isNot(shows('❯ 01 APP')));
      });

      testWidgets('↓ and Enter open the marked row', (t) async {
        final host = FakeHost('/install');
        await t.pumpWidget(Site(host: host), size: size);
        await t.press('m');
        await t.press('down');
        expect(t.screen, shows(' ❯ 02 FRAMEWORK'));
        await t.press('enter');
        expect(host.pushed, ['/chord_tui']);
        expect(t.screen, isNot(shows('❯ 01 APP')));
      });

      testWidgets('a digit opens its row, and g opens GitHub', (t) async {
        final host = FakeHost('/install');
        await t.pumpWidget(Site(host: host), size: size);
        await t.press('m');
        await t.press('3');
        expect(host.pushed, ['/chord_tui/gallery']);
        await t.press('m');
        await t.press('g');
        expect(host.opened, ['https://github.com/IKatsuba/chord']);
        expect(host.pushed, hasLength(1));
      });

      testWidgets('a tap on the menu opens it, and a tap on a row opens the '
          'row', (t) async {
        final host = FakeHost('/install');
        await t.pumpWidget(Site(host: host), size: size);
        await tap(t, t.screen.lines[1].indexOf('MENU'), 1);
        expect(t.screen, shows('❯ 01 APP'));
        await tap(t, 5, t.screen.lines.indexOf('   04 INSTALL'));
        expect(host.pushed, isEmpty, reason: 'the page it is on');
        await tap(t, t.screen.lines[1].indexOf('MENU'), 1);
        await tap(t, 5, t.screen.lines.indexOf('      GITHUB ↗ g'));
        expect(host.opened, ['https://github.com/IKatsuba/chord']);
      });

      testWidgets('a menu open as the window grows past a phone closes', (
        t,
      ) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        await t.press('m');
        await t.resize(const Size(120, 40));
        expect(t.screen, isNot(shows('❯ 01 APP')));
        await t.resize(size);
        expect(t.screen, isNot(shows('❯ 01 APP')));
      });
    });
  }

  group('SitePage', () {
    Widget page(int count, {int measure = narrowMeasure}) => SitePage(
      measure: measure,
      sections: [for (var i = 0; i < count; i++) Text('section $i')],
    );

    for (final (size, left) in const [
      (Size(171, 50), 23), // (170 - 124) ~/ 2
      (Size(120, 40), 4),
      (Size(54, 56), 2),
    ]) {
      testWidgets('centres the measure with its gutter, and a scrollbar, at '
          '$size', (t) async {
        await t.pumpWidget(page(200), size: size);
        expect(bare(t.screen.lines.first), '${' ' * left}section 0');
        expect(t.screen.charAt(size.width - 1, 0), '┃');
      });
    }

    testWidgets('the scrollbar thumb is muted under the site theme', (t) async {
      await t.pumpWidget(
        Theme(data: siteTheme(), child: page(200)),
        size: const Size(120, 40),
      );
      expect(t.screen.charAt(119, 0), '┃');
      expect(t.screen.styleAt(119, 0), Style(fg: SiteColors.muted));
    });

    testWidgets('the wider measure for chord and the gallery', (t) async {
      await t.pumpWidget(
        page(3, measure: wideMeasure),
        size: const Size(171, 50),
      );
      expect(bare(t.screen.lines.first), '${' ' * 17}section 0');
    });

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('the wheel scrolls it, a row a step, at $size', (t) async {
        await t.pumpWidget(page(200), size: size);
        Future<void> wheel(int rows) => t.mouse(
          MouseEvent(
            MouseEventKind.wheel,
            position: const Offset(10, 3),
            scrollDelta: Offset(0, rows),
          ),
        );
        await wheel(3);
        await t.pump();
        expect(bare(t.screen.lines.first).trim(), 'section 3');
        await wheel(-1);
        await t.pump();
        expect(bare(t.screen.lines.first).trim(), 'section 2');
      });
    }

    testWidgets('↓, PgDn, End and Home scroll it', (t) async {
      await t.pumpWidget(page(200), size: const Size(80, 24));
      await t.press('down');
      expect(bare(t.screen.lines.first).trim(), 'section 1');
      await t.press('pagedown');
      expect(bare(t.screen.lines.first).trim(), 'section 23');
      await t.press('end');
      expect(bare(t.screen.lines.last).trim(), 'section 199');
      await t.press('home');
      expect(bare(t.screen.lines.first).trim(), 'section 0');
    });
  });
}

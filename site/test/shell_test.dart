import 'package:chord_site/page.dart';
import 'package:chord_site/palette.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

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
  for (final size in const [Size(171, 50), Size(120, 40), Size(80, 24)]) {
    group('desktop at $size', () {
      testWidgets('the nav is three rows on the surface colour, then the '
          'line-coloured rule', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        for (final y in [0, 1, 2]) {
          expect(t.screen.styleAt(size.width - 1, y).bg, SiteColors.surface);
        }
        expect(t.screen.styleAt(0, 3), ThemeData.dark().border);
        final nav = t.screen.lines[1];
        expect(nav, contains('4 Install'));
        final current = t.screen.styleAt(nav.indexOf('Install'), 1);
        expect(current.isUnderline && current.isBold, isTrue);
        expect(
          t.screen.styleAt(nav.indexOf('Gallery'), 1).isUnderline,
          isFalse,
        );
        expect(nav.contains('GitHub ↗ g'), size.width >= 100);
      });

      testWidgets('the help row sits on the surface colour', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        expect(
          t.screen.styleAt(size.width - 1, size.height - 1).bg,
          SiteColors.surface,
        );
      });

      testWidgets('a digit opens its section from another page, and a tap on '
          'a section opens it', (t) async {
        final host = FakeHost('/install');
        await t.pumpWidget(Site(host: host), size: size);
        await t.press('1');
        expect(host.pushed, ['/chord']);
        final nav = t.screen.lines[1];
        await tap(t, nav.indexOf('Gallery'), 1);
        expect(host.pushed.last, '/chord_tui/gallery');
        await tap(t, nav.indexOf('chord'), 1);
        expect(host.pushed.last, '/', reason: 'the mark goes home');
      });

      testWidgets('m opens no menu on a desktop', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        await t.press('m');
        expect(t.screen, isNot(shows('❯ 1 chord')));
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

  for (final size in const [Size(54, 56), Size(43, 37)]) {
    group('phone at $size', () {
      testWidgets('m opens the menu over the page; esc closes it', (t) async {
        final host = FakeHost('/install');
        await t.pumpWidget(Site(host: host), size: size);
        expect(t.screen.styleAt(0, 0).bg, SiteColors.surface);
        await t.press('m');
        final lines = t.screen.lines;
        expect(lines.sublist(2, 9), [
          '',
          ' ❯ 1 chord',
          '   2 chord_tui',
          '   3 Gallery',
          '   4 Install',
          '     GitHub ↗ g',
          '',
        ]);
        expect(t.screen.styleAt(5, 6).bg, SiteColors.surface);
        expect(lines.last, ' esc close');
        // Nothing reaches the page meanwhile.
        await t.paste('typed');
        await t.press('esc');
        expect(t.screen, isNot(shows('❯ 1 chord')));
        expect(host.pushed, isEmpty);
        expect(t.screen.lines.last, ' escape up  ? keys');
      });

      testWidgets('m closes it again', (t) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        await t.press('m');
        await t.press('m');
        expect(t.screen, isNot(shows('❯ 1 chord')));
      });

      testWidgets('↓ and Enter open the marked row', (t) async {
        final host = FakeHost('/install');
        await t.pumpWidget(Site(host: host), size: size);
        await t.press('m');
        await t.press('down');
        expect(t.screen, shows(' ❯ 2 chord_tui'));
        await t.press('enter');
        expect(host.pushed, ['/chord_tui']);
        expect(t.screen, isNot(shows('❯ 1 chord')));
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
        await tap(t, t.screen.lines[0].indexOf('menu'), 0);
        expect(t.screen, shows('❯ 1 chord'));
        await tap(t, 5, t.screen.lines.indexOf('   4 Install'));
        expect(host.pushed, isEmpty, reason: 'the page it is on');
        await tap(t, t.screen.lines[0].indexOf('menu'), 0);
        await tap(t, 5, t.screen.lines.indexOf('     GitHub ↗ g'));
        expect(host.opened, ['https://github.com/IKatsuba/chord']);
      });

      testWidgets('a menu open as the window grows past a phone closes', (
        t,
      ) async {
        await t.pumpWidget(Site(host: FakeHost('/install')), size: size);
        await t.press('m');
        await t.resize(const Size(120, 40));
        expect(t.screen, isNot(shows('❯ 1 chord')));
        await t.resize(size);
        expect(t.screen, isNot(shows('❯ 1 chord')));
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

    testWidgets('the wider measure for chord and the gallery', (t) async {
      await t.pumpWidget(
        page(3, measure: wideMeasure),
        size: const Size(171, 50),
      );
      expect(bare(t.screen.lines.first), '${' ' * 17}section 0');
    });

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

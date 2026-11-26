import 'package:chord_site/page.dart';
import 'package:chord_site/palette.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

void main() {
  group('CHD-638 tester: page measure and viewport', () {
    for (final (size, content) in [
      (const Size(171, 50), 124),
      (const Size(120, 40), 111),
      (const Size(80, 24), 71),
      (const Size(54, 56), 49),
    ]) {
      testWidgets('long sections respect both gutters at $size', (t) async {
        final c = ScrollController();
        await t.pumpWidget(
          SitePage(controller: c, sections: [Text('x' * 300)]),
          size: size,
        );
        final first = t.screen.lines.first.replaceAll('┃', '').trimRight();
        final left = (size.width - 1 - content) ~/ 2;
        expect(first, '${' ' * left}${'x' * content}');
        expect(c.contentRows, (300 / content).ceil());
      });
    }

    testWidgets('zero and tiny views recover to a scrolling page', (t) async {
      final c = ScrollController();
      await t.pumpWidget(
        SitePage(
          controller: c,
          sections: [for (var i = 0; i < 100; i++) Text('界👩‍💻e\u0301 $i')],
        ),
        size: Size.zero,
      );
      for (final size in [
        const Size(1, 1),
        const Size(2, 2),
        const Size(54, 56),
      ]) {
        await t.resize(size);
      }
      expect(t.screen, shows('界👩‍💻e\u0301 0'));
      await t.press('end');
      expect(c.offset, c.contentRows - c.viewRows);
      await t.press('home');
      expect(c.offset, 0);
    });

    testWidgets('page-specific arrow bindings win over scaffold scrolling', (
      t,
    ) async {
      final c = ScrollController();
      var calls = 0;
      await t.pumpWidget(
        SitePage(
          controller: c,
          bindings: [Binding('down', 'Select', () => calls++)],
          sections: [for (var i = 0; i < 100; i++) Text('row $i')],
        ),
      );
      await t.press('down');
      expect(calls, 1);
      expect(c.offset, 0);
      await t.press('pagedown');
      expect(c.offset, c.viewRows - 2);
    });
  });

  group('CHD-638 tester: shell menu lifetime', () {
    for (final size in [
      const Size(80, 24),
      const Size(52, 52),
      const Size(54, 56),
      const Size(43, 37),
    ]) {
      testWidgets('keys panel blocks menu selection and resumes it at $size', (
        t,
      ) async {
        final host = FakeHost('/install');
        addTearDown(host.popped.close);
        await t.pumpWidget(Site(host: host), size: size);
        await t.press('m');
        await t.press('down');
        await t.press('f1');
        await t.press('1');
        await t.press('enter');
        await t.paste('typed');
        expect(host.pushed, isEmpty);
        expect(host.opened, isEmpty);
        await t.press('f1');
        expect(t.screen, shows('❯ 02 FRAMEWORK'));
        await t.press('enter');
        expect(host.pushed, ['/chord_tui']);
      });

      testWidgets(
        'removal while menu and panel are open cancels history at $size',
        (t) async {
          final host = FakeHost('/install');
          addTearDown(host.popped.close);
          await t.pumpWidget(Site(host: host), size: size);
          await t.press('m');
          await t.press('f1');
          await t.pumpWidget(Text('removed'));
          expect(host.popped.hasListener, isFalse);
          host.popped.add('/chord');
          await t.press('enter');
          await t.press('ctrl+q');
          expect(t.screen.text, 'removed');
          expect(host.pushed, isEmpty);
          expect(host.opened, isEmpty);
        },
      );
    }
  });

  group('CHD-638 tester: C shell scroll style', () {
    testWidgets('the page thumb stays muted at both ends', (t) async {
      final c = ScrollController();
      await t.pumpWidget(
        Theme(
          data: siteTheme(),
          child: SitePage(
            controller: c,
            sections: [for (var i = 0; i < 200; i++) Text('row$i')],
          ),
        ),
      );
      expect(t.screen.charAt(79, 0), '┃');
      expect(t.screen.styleAt(79, 0).fg, SiteColors.muted);
      c.toBottom();
      await t.pump();
      expect(t.screen.charAt(79, 23), '┃');
      expect(t.screen.styleAt(79, 23).fg, SiteColors.muted);
    });
  });
}

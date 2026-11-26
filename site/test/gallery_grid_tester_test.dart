import 'package:chord_site/gallery.dart';
import 'package:chord_site/pages/gallery_grid.dart';
import 'package:chord_site/router.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../web/gallery.dart';
import 'fake_host.dart';

void main() {
  group('CHD-638 tester: gallery grid boundary input', () {
    testWidgets('an empty gallery ignores every arrow and Enter', (t) async {
      final opened = <SiteRoute>[];
      await t.pumpWidget(GalleryPage(Gallery.none, opened.add));
      for (final key in ['up', 'down', 'left', 'right', 'enter']) {
        await t.press(key);
      }
      expect(opened, isEmpty);
      expect(t.screen, shows('GALLERY'));
    });

    for (final size in [
      const Size(171, 50),
      const Size(120, 40),
      const Size(80, 24),
      const Size(54, 56),
    ]) {
      testWidgets('1000 navigation updates settle on the last card at $size', (
        t,
      ) async {
        final host = FakeHost('/chord_tui/gallery');
        addTearDown(host.popped.close);
        await t.pumpWidget(
          Site(host: host, gallery: siteGallery),
          size: size,
        );
        for (var i = 0; i < 500; i++) {
          t.host.handleKey(const KeyEvent('right'));
          t.host.handleKey(const KeyEvent('down'));
        }
        await t.pump();
        expect(
          t.screen.lines.firstWhere((line) => line.contains('⏎ run')),
          contains('9  Mouse'),
        );
        await t.press('enter');
        expect(host.pushed, ['/chord_tui/mouse']);
      });
    }

    testWidgets(
      'clamped navigation reveals a selected card after manual scrolling',
      (t) async {
        final host = FakeHost('/chord_tui/gallery');
        addTearDown(host.popped.close);
        await t.pumpWidget(
          Site(host: host, gallery: siteGallery),
          size: const Size(80, 24),
        );
        await t.press('end');
        expect(t.screen, isNot(shows('⏎ run')));
        await t.press('left');
        expect(
          t.screen.lines.firstWhere((line) => line.contains('⏎ run')),
          contains('1  Demo'),
        );
        await t.press('enter');
        expect(host.pushed, ['/chord_tui/demo']);
      },
    );
  });
}

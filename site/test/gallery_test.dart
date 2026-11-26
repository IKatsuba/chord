import 'dart:io';

import 'package:chord_site/router.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../web/gallery.dart';
import 'fake_host.dart';

const _sizes = [Size(120, 40), Size(80, 24)];

void main() {
  test('every entry is an example file, and none is named gallery', () {
    for (final entry in siteGallery.entries) {
      expect(
        File('../packages/chord_tui/example/${entry.name}.dart').existsSync(),
        isTrue,
        reason: entry.name,
      );
      expect(entry.name, isNot(SiteRouter.galleryName));
    }
  });

  testWidgets('the gallery lists every example and opens by number', (t) async {
    final host = FakeHost('/chord_tui/gallery');
    await t.pumpWidget(
      Site(host: host, gallery: siteGallery),
      size: const Size(120, 40),
    );
    for (final entry in siteGallery.entries) {
      expect(t.screen, shows(entry.name));
    }
    await t.press('2');
    expect(host.pushed, ['/chord_tui/markdown']);
    expect(host.titles.last, 'markdown · chord_tui');
  });

  for (final entry in siteGallery.entries) {
    for (final size in _sizes) {
      testWidgets('${entry.name} builds and draws in its frame at $size', (
        t,
      ) async {
        final host = FakeHost('/chord_tui/${entry.name}');
        await t.pumpWidget(
          Site(host: host, gallery: siteGallery),
          size: size,
        );
        expect(t.screen, shows('example/${entry.name}.dart'));
        expect(t.screen, shows(entry.description));
        // Something of the example is drawn inside the frame.
        final inside = t.screen.lines
            .skipWhile((l) => !l.contains('example/${entry.name}.dart'))
            .skip(1)
            .where((l) => l.replaceAll(RegExp(r'[│ ]'), '').isNotEmpty);
        expect(inside, isNotEmpty);
      });
    }

    testWidgets('${entry.name}: quit keys go home, never out', (t) async {
      for (final key in ['ctrl+q', 'ctrl+c']) {
        final host = FakeHost('/chord_tui/${entry.name}');
        await t.pumpWidget(
          Site(host: host, gallery: siteGallery),
          size: const Size(120, 40),
        );
        await t.press(key);
        expect(host.pushed, ['/'], reason: key);
        expect(t.exitRequested, isFalse, reason: key);
      }
    });

    testWidgets(
      '${entry.name}: esc ${entry.ownsEscape ? 'is the example\'s' : 'goes back to the gallery'}',
      (t) async {
        final host = FakeHost('/chord_tui/${entry.name}');
        await t.pumpWidget(
          Site(host: host, gallery: siteGallery),
          size: const Size(120, 40),
        );
        expect(
          t.screen,
          shows(
            entry.ownsEscape
                ? "esc is the example's here; ctrl+q home"
                : 'esc back to the gallery',
          ),
        );
        await t.press('esc');
        expect(
          host.pushed,
          entry.ownsEscape ? isEmpty : ['/chord_tui/gallery'],
        );
      },
    );
  }

  for (final size in _sizes) {
    testWidgets('chord_tui runs README\'s example, at $size', (t) async {
      final host = FakeHost('/chord_tui');
      await t.pumpWidget(
        Site(host: host, gallery: siteGallery),
        size: size,
      );
      expect(t.screen, shows('The Flutter way, for the terminal'));
      expect(t.screen, shows('example/main.dart'));
      expect(t.screen, shows('▸ Run checks'));
      await t.press('ctrl+o');
      expect(t.screen, shows('▾ Run checks'));
      await t.press('enter');
      expect(host.pushed, ['/chord_tui/gallery']);
    });
  }
}

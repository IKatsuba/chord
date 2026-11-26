import 'dart:io';

import 'package:chord_site/router.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../web/gallery.dart';
import 'fake_host.dart';

const _sizes = [Size(120, 40), Size(80, 24)];

/// Text each example draws itself, so a frame with nothing of it fails.
const _markers = {
  'demo': 'chorded-tui demo',
  'markdown': 'Terminal cells',
  'picker': 'Pick one',
  'form': 'New deployment',
  'text_area': 'Text area',
  'diff': 'src/greeting.ts',
  'dialog': 'The transcript is here.',
  'layers': 'of the transcript',
  'mouse': 'Pointer events · reports',
};

/// The rows inside the frame, between its borders.
List<String> _framed(WidgetTester t) => [
  for (final l in t.screen.lines)
    if (l.startsWith(' │')) l,
];

void main() {
  test('every entry is an example file, and none is named gallery', () {
    expect(_markers.keys, [for (final e in siteGallery.entries) e.name]);
    for (final entry in siteGallery.entries) {
      expect(
        File('../packages/chord_tui/example/${entry.name}.dart').existsSync(),
        isTrue,
        reason: entry.name,
      );
      expect(entry.name, isNot(SiteRouter.galleryName));
    }
  });

  test('a run of digits is written as a range, anything else joined', () {
    expect(keysLabel(['1', '2', '3', '4']), '1–4');
    expect(keysLabel(['1', '2', '3', '4', '5', '6', '7', '8', '9']), '1–9');
    expect(keysLabel(['1', '2']), '1/2');
    expect(keysLabel(['1', '3', '4']), '1/3/4');
    expect(keysLabel(['up', 'down']), 'up/down');
  });

  test('no example binds F1, which the site takes for its keys', () {
    for (final entry in [...siteGallery.entries.map((e) => e.name), 'main']) {
      final source = File(
        '../packages/chord_tui/example/$entry.dart',
      ).readAsStringSync();
      expect(source, isNot(contains(RegExp("['\"]f1"))), reason: entry);
    }
  });

  testWidgets('F1 opens the keys panel over an example, ? is text there', (
    t,
  ) async {
    final host = FakeHost('/chord_tui/text_area');
    await t.pumpWidget(
      Site(host: host, gallery: siteGallery),
      size: const Size(120, 40),
    );
    await t.type('why?');
    expect(t.screen, isNot(shows(' Keys')));
    expect(t.screen, shows('why?'));
    await t.press('f1');
    expect(t.screen, shows(' Keys'));
    expect(t.screen.lines.last, ' escape close  f1 close  ctrl+q home');
    // More keys than rows: the panel counts the rest instead.
    expect(t.screen, shows(RegExp(r'… \+\d+ more')));
    // The open panel takes every key: nothing is typed under it.
    await t.type('abc');
    await t.press('enter');
    await t.press('f1');
    expect(t.screen, isNot(shows(' Keys')));
    expect(t.screen, shows('why?'));
    expect(t.screen, isNot(shows('why?abc')));
    expect(host.pushed, isEmpty);
  });

  testWidgets('the panel names F1 alone for its keys on an example page', (
    t,
  ) async {
    await t.pumpWidget(
      Site(host: FakeHost('/chord_tui/diff'), gallery: siteGallery),
      size: const Size(120, 40),
    );
    await t.press('f1');
    expect(t.screen.lines, contains(matches(RegExp(r'^ +f1 +keys$'))));
    expect(t.screen.lines, isNot(contains(matches(RegExp(r'\?/f1')))));
  });

  testWidgets('the open panel swallows clicks and the wheel', (t) async {
    final host = FakeHost('/chord_tui/picker');
    await t.pumpWidget(
      Site(host: host, gallery: siteGallery),
      size: const Size(120, 40),
    );
    await t.press('f1');
    final row = t.screen.lines.indexWhere((l) => l.contains('3.  Choice 3'));
    await t.mouse(
      MouseEvent(
        MouseEventKind.press,
        position: Offset(10, row),
        button: MouseButton.primary,
      ),
    );
    await t.mouse(
      MouseEvent(
        MouseEventKind.wheel,
        position: Offset(10, row),
        scrollDelta: const Offset(0, 3),
      ),
    );
    await t.press('esc');
    expect(t.screen, isNot(shows(' Keys')));
    expect(t.screen, shows('Chosen: nothing yet'));
    expect(t.screen, shows('❯   1.  Choice 1'));
  });

  testWidgets('quit keys close the open panel and go home', (t) async {
    for (final key in ['ctrl+q', 'ctrl+c']) {
      final host = FakeHost('/chord_tui/form');
      await t.pumpWidget(
        Site(host: host, gallery: siteGallery),
        size: const Size(80, 24),
      );
      await t.press('f1');
      await t.press(key);
      expect(host.pushed, ['/'], reason: key);
      expect(t.screen, isNot(shows(' Keys')), reason: key);
      expect(t.exitRequested, isFalse, reason: key);
    }
  });

  testWidgets('the gallery writes its nine digits as one range', (t) async {
    await t.pumpWidget(
      Site(host: FakeHost('/chord_tui/gallery'), gallery: siteGallery),
      size: const Size(80, 24),
    );
    expect(
      t.screen.lines.last,
      ' up/down move  enter open  1–9 jump  escape up  ? keys',
    );
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
        // The example itself is drawn inside the frame.
        expect(
          _framed(t).where((l) => l.contains(_markers[entry.name]!)),
          isNotEmpty,
        );
      });
    }

    for (final size in _sizes) {
      testWidgets('${entry.name}: the rows keep their own keys, $size', (
        t,
      ) async {
        await t.pumpWidget(
          Site(
            host: FakeHost('/chord_tui/${entry.name}'),
            gallery: siteGallery,
          ),
          size: size,
        );
        // The dialog example opens its dialog once the first frame is laid.
        await t.pump();
        final lines = t.screen.lines;
        // The site's row: its own keys only, the same on every example.
        expect(
          lines.last,
          entry.ownsEscape
              ? ' ctrl+q home  f1 keys'
              : ' escape up  ctrl+q home  f1 keys',
        );
        // The frame's rows: the example's own, never the site's keys or Quit.
        final framed = _framed(t).join('\n');
        expect(framed, contains(_markers[entry.name]!));
        for (final site in ['f1', 'keys', 'open GitHub', 'ctrl+q', 'Quit']) {
          expect(framed, isNot(contains(site)), reason: site);
        }
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
      // README's example lists its own key alone in its frame.
      expect(
        t.screen.lines,
        contains(matches(RegExp(r'^ │ctrl\+o Toggle tool details +│$'))),
      );
      expect(
        t.screen.lines.last,
        ' enter gallery  escape up  ctrl+q home  f1 keys',
      );
      await t.press('ctrl+o');
      expect(t.screen, shows('▾ Run checks'));
      await t.press('enter');
      expect(host.pushed, ['/chord_tui/gallery']);
    });
  }
}

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

Future<FakeHost> _example(WidgetTester t, String name, Size size) async {
  final host = FakeHost('/chord_tui/$name');
  await t.pumpWidget(
    Site(host: host, gallery: siteGallery),
    size: size,
  );
  // The dialog example opens its dialog once the first frame is laid.
  await t.pump();
  return host;
}

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

  testWidgets('F1 opens the keys panel over an entered example, where ? '
      'is text', (t) async {
    final host = await _example(t, 'text_area', const Size(80, 24));
    await t.press('tab');
    await t.type('why?');
    expect(t.screen, isNot(shows(' Keys')));
    expect(t.screen, shows('why?'));
    await t.press('f1');
    expect(t.screen, shows(' Keys'));
    // The open panel takes every key: nothing is typed under it.
    await t.type('abc');
    await t.press('enter');
    await t.press('f1');
    expect(t.screen, isNot(shows(' Keys')));
    expect(t.screen, shows('why?'));
    expect(t.screen, isNot(shows('why?abc')));
    expect(host.pushed, isEmpty);
  });

  testWidgets('a paste while the panel is open edits nothing', (t) async {
    await _example(t, 'text_area', const Size(120, 40));
    await t.press('tab');
    await t.press('f1');
    await t.paste('pasted under');
    await t.press('esc');
    expect(t.screen, isNot(shows('pasted under')));
    await t.paste('pasted over');
    expect(t.screen, shows('pasted over'));
  });

  testWidgets('the panel names F1 alone for its keys inside an entered '
      'example, and ? too on the page', (t) async {
    await _example(t, 'diff', const Size(120, 40));
    await t.press('f1');
    expect(t.screen.lines, contains(matches(RegExp(r'^ +\?/f1 +keys$'))));
    await t.press('f1');
    await t.press('tab');
    await t.press('f1');
    expect(t.screen.lines, contains(matches(RegExp(r'^ +f1 +keys$'))));
    expect(t.screen.lines, isNot(contains(matches(RegExp(r'\?/f1')))));
  });

  testWidgets('the open panel swallows clicks and the wheel', (t) async {
    await _example(t, 'picker', const Size(120, 40));
    await t.press('tab');
    final before = t.screen.text;
    await t.press('f1');
    final row = t.screen.lines.indexWhere((l) => l.contains('Choice 3'));
    final at = Offset(40, row < 0 ? 20 : row);
    await t.mouse(
      MouseEvent(
        MouseEventKind.press,
        position: at,
        button: MouseButton.primary,
      ),
    );
    await t.mouse(
      MouseEvent(
        MouseEventKind.wheel,
        position: at,
        scrollDelta: const Offset(0, 3),
      ),
    );
    await t.press('esc');
    expect(t.screen, isNot(shows(' Keys')));
    expect(t.screen.text, before);
  });

  testWidgets('quit keys close the open panel and go home', (t) async {
    for (final key in ['ctrl+q', 'ctrl+c']) {
      final host = await _example(t, 'form', const Size(80, 24));
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
      ' left/right/up/down move  enter run  1–9 open  escape up  ? keys  '
      'm menu',
    );
  });

  testWidgets('the gallery lists every example and opens by number', (t) async {
    final host = FakeHost('/chord_tui/gallery');
    await t.pumpWidget(
      Site(host: host, gallery: siteGallery),
      size: const Size(120, 40),
    );
    // Every cell, by its caps name, as the page scrolls a page at a time.
    final seen = <String>{};
    for (var n = 0; n < 8; n++) {
      for (final entry in siteGallery.entries) {
        if (t.screen.text.contains(entry.title.toUpperCase())) {
          seen.add(entry.name);
        }
      }
      await t.press('pagedown');
    }
    expect(seen, {for (final e in siteGallery.entries) e.name});
    await t.press('home');
    await t.press('2');
    expect(host.pushed, ['/chord_tui/markdown']);
    expect(host.titles.last, 'markdown · chord_tui');
  });

  for (final entry in siteGallery.entries) {
    for (final size in _sizes) {
      testWidgets('${entry.name} builds and draws in its plate at $size', (
        t,
      ) async {
        await _example(t, entry.name, size);
        for (
          var i = 0;
          i < 60 && !t.screen.text.contains(_markers[entry.name]!);
          i++
        ) {
          await t.press('down');
        }
        expect(t.screen, shows(_markers[entry.name]!));
        expect(t.screen, shows('EXAMPLE/${entry.name.toUpperCase()}.DART'));
      });
    }

    testWidgets('${entry.name}: quit keys go home from the page and from '
        'inside, never out', (t) async {
      for (final enter in [false, true]) {
        for (final key in ['ctrl+q', 'ctrl+c']) {
          final host = await _example(t, entry.name, const Size(120, 40));
          if (enter) await t.press('tab');
          await t.press(key);
          expect(
            host.pushed,
            enter && entry.ownsEscape ? isEmpty : ['/'],
            reason: '$key, entered $enter',
          );
          expect(t.exitRequested, isFalse, reason: key);
        }
      }
    });

    testWidgets(
      '${entry.name}: esc on the page goes up to the gallery; inside, '
      '${entry.ownsEscape ? "it is the example's and ctrl+q leaves" : "it leaves"}',
      (t) async {
        final host = await _example(t, entry.name, const Size(120, 40));
        await t.press('tab');
        expect(
          t.screen,
          shows(entry.ownsEscape ? 'CTRL+Q LEAVES' : 'ESC LEAVES'),
        );
        await t.press(entry.ownsEscape ? 'ctrl+q' : 'esc');
        expect(t.screen, shows('TAB TO ENTER'));
        expect(host.pushed, isEmpty);
        await t.press('esc');
        expect(host.pushed, ['/chord_tui/gallery']);
      },
    );
  }
}

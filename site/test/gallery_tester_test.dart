import 'package:chord_site/gallery.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../web/gallery.dart';
import 'fake_host.dart';

const _phoneMarkers = {
  'demo': 'chorded-tui demo',
  'markdown': 'Terminal cells',
  'picker': 'Pick one',
  'form': 'New deployment',
  'text_area': 'Text area',
  'diff': 'src/greeting.ts',
  'dialog': 'The transcript is here.',
  'layers': 'of the transcript',
  'mouse': 'Pointer events',
};

void main() {
  group('tester: gallery phone routes', () {
    for (final entry in siteGallery.entries) {
      testWidgets(
        '${entry.name} draws its own content and returns home on a phone',
        (t) async {
          final host = FakeHost('/chord_tui/${entry.name}');
          addTearDown(host.popped.close);
          await t.pumpWidget(
            Site(host: host, gallery: siteGallery),
            size: const Size(43, 37),
          );
          expect(t.screen, shows(_phoneMarkers[entry.name]!));
          await t.press('f1');
          expect(t.screen, shows(' Keys'));
          await t.press('ctrl+q');
          expect(host.pushed, ['/']);
          expect(t.exitRequested, isFalse);
        },
      );
    }
  });

  group('tester: modal key panel isolation', () {
    for (final size in const [Size(120, 40), Size(80, 24), Size(43, 37)]) {
      testWidgets(
        'all input is swallowed and the page survives the panel at $size',
        (t) async {
          final events = <String>[];
          final gallery = Gallery([
            GalleryEntry(
              'probe',
              'input probe',
              (_) => Focus(
                autofocus: true,
                onKey: (event) {
                  events.add('key ${event.combo}');
                  return true;
                },
                onPaste: (text) {
                  events.add('paste $text');
                  return true;
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => events.add('click'),
                  onPointerSignal: (_) => events.add('wheel'),
                  child: Text('probe input'),
                ),
              ),
            ),
          ], () => const SizedBox());
          final host = FakeHost('/chord_tui/probe');
          addTearDown(host.popped.close);
          await t.pumpWidget(
            Site(host: host, gallery: gallery),
            size: size,
          );
          await t.press('x');
          expect(events, isEmpty, reason: 'the plate has not been entered');
          await t.press('tab');
          await t.press('x');
          expect(events, ['key x']);
          final row = t.screen.lines.indexWhere(
            (line) => line.contains('probe input'),
          );
          await t.press('f1');
          for (final key in [
            'a',
            '?',
            'enter',
            'tab',
            'shift+tab',
            'left',
            'right',
            'up',
            'down',
            'pageup',
            'pagedown',
            'home',
            'end',
            'ctrl+o',
            'ctrl+s',
          ]) {
            await t.press(key);
          }
          await t.paste('界🙂e\u0301\x1b[31m');
          await t.paste('');
          await t.mouse(
            MouseEvent(
              MouseEventKind.press,
              position: Offset(5, row),
              button: MouseButton.primary,
            ),
          );
          await t.mouse(
            MouseEvent(
              MouseEventKind.wheel,
              position: Offset(5, row),
              scrollDelta: const Offset(0, 1),
            ),
          );
          expect(events, ['key x']);
          expect(host.pushed, isEmpty);
          await t.press('f1');
          expect(t.screen, isNot(shows(' Keys')));
          await t.press('y');
          await t.paste('after');
          expect(events, ['key x', 'key y', 'paste after']);
        },
      );
    }
  });

  group('tester: embedded editing and resize', () {
    for (final name in ['demo', 'picker', 'form', 'text_area']) {
      testWidgets('? opens help on the page and is typed inside $name', (
        t,
      ) async {
        final host = FakeHost('/chord_tui/$name');
        addTearDown(host.popped.close);
        await t.pumpWidget(
          Site(host: host, gallery: siteGallery),
          size: const Size(80, 24),
        );
        await t.press('?');
        expect(t.screen, shows(' Keys'));
        await t.press('f1');
        await t.press('tab');
        if (name == 'picker') await t.press('/');
        await t.type('why?');
        expect(t.screen, isNot(shows(' Keys')));
        expect(t.screen, shows('why?'));
      });
    }

    testWidgets('draft and focus survive panel resize across every layout', (
      t,
    ) async {
      final host = FakeHost('/chord_tui/text_area');
      addTearDown(host.popped.close);
      await t.pumpWidget(
        Site(host: host, gallery: siteGallery),
        size: const Size(120, 40),
      );
      await t.press('tab');
      await t.type('界🙂e\u0301');
      await t.press('f1');
      await t.press('end');
      await t.resize(const Size(43, 37));
      expect(t.screen, shows(' Keys'));
      await t.paste('unreached');
      await t.resize(const Size(80, 24));
      await t.press('esc');
      expect(t.screen, shows('界🙂e\u0301'));
      expect(t.screen, isNot(shows('unreached')));
      await t.type('Z');
      expect(t.screen, shows('界🙂e\u0301Z'));
      expect(host.pushed, isEmpty);
    });
  });
}

import 'package:chord_site/gallery.dart';
import 'package:chord_site/key_row.dart';
import 'package:chord_site/router.dart';
import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

final _gallery = Gallery([
  GalleryEntry('markdown', 'md', (_) => Text('md')),
], () => Text('readme'));

void main() {
  group('tester: shell route and lifecycle boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24), Size(43, 37)]) {
      testWidgets(
        'deep example uses explicit parents and quit goes home, $size',
        (t) async {
          final host = FakeHost(
            pathUnderBase('/docs/chord/chord_tui/markdown', '/docs/chord/'),
          );
          addTearDown(host.popped.close);
          await t.pumpWidget(
            Site(
              host: host,
              gallery: _gallery,
              recordings: const ['permission'],
            ),
            size: size,
          );
          expect(host.titles, ['markdown · chord_tui']);
          expect(host.pushed, isEmpty);
          await t.press('esc');
          expect(host.pushed.last, '/chord_tui/gallery');
          await t.press('esc');
          expect(host.pushed.last, '/chord_tui');
          await t.press('f1');
          await t.press('ctrl+q');
          expect(host.pushed.last, '/');
          expect(t.screen, isNot(shows(' Keys')));
          final pushes = host.pushed.length;
          await t.press('ctrl+c');
          await t.press('ctrl+q');
          await t.press('esc');
          expect(host.pushed, hasLength(pushes));
          expect(t.exitRequested, isFalse);
        },
      );
    }

    testWidgets('pop closes help without pushing and unmount cancels pops', (
      t,
    ) async {
      final host = FakeHost();
      addTearDown(host.popped.close);
      await t.pumpWidget(
        Site(host: host, gallery: _gallery, recordings: const ['permission']),
      );
      expect(host.popped.hasListener, isTrue);
      await t.press('?');
      host.popped.add('/chord/permission');
      await t.pump();
      expect(host.titles.last, 'permission · chord');
      expect(host.pushed, isEmpty);
      expect(t.screen, isNot(shows(' Keys')));
      await t.press('esc');
      expect(host.pushed, ['/chord']);
      await t.pumpWidget(Text('removed'));
      expect(host.popped.hasListener, isFalse);
      final titles = host.titles.length;
      host.popped.add('/install');
      await t.pump();
      expect(host.titles, hasLength(titles));
      expect(t.screen.text, 'removed');
    });

    testWidgets('resize preserves home routes and the mobile row', (t) async {
      final host = FakeHost();
      addTearDown(host.popped.close);
      await t.pumpWidget(Site(host: host), size: const Size(120, 40));
      await t.press('down');
      await t.resize(const Size(43, 37));
      expect(t.screen.lines.last, contains('? keys'));
      expect(t.screen.lines[35], contains('esc'));
      await t.resize(const Size(80, 24));
      expect(t.screen.lines.last, contains('i install'));
      expect(t.screen.lines[1], isNot(contains('GITHUB')));
      await t.resize(const Size(120, 40));
      expect(t.screen.lines[1], contains('GITHUB ↗ g'));
      expect(t.screen.lines.last, contains('w watch'));
      await t.press('2');
      expect(host.pushed, ['/chord_tui']);
    });

    testWidgets(
      'a burst of history events leaves the last path without pushes',
      (t) async {
        final host = FakeHost();
        addTearDown(host.popped.close);
        await t.pumpWidget(Site(host: host));
        for (var i = 0; i < 1000; i++) {
          host.popped.add(i == 999 ? '/unknown/界🙂e\u0301' : '/install');
        }
        await t.pump();
        expect(t.screen, shows('PAGE NOT FOUND.'));
        expect(t.screen, shows('/unknown/界🙂e\u0301'));
        expect(host.titles.last, 'not found · chord');
        expect(host.pushed, isEmpty);
        await t.press('esc');
        expect(host.pushed, ['/']);
      },
    );

    testWidgets('every mobile key is dispatched once to the current focus', (
      t,
    ) async {
      final received = <String>[];
      await t.pumpWidget(
        Column(
          children: [
            Expanded(
              child: Focus(
                autofocus: true,
                onKey: (event) {
                  received.add(event.combo.toString());
                  return true;
                },
                child: Text('page'),
              ),
            ),
            const KeyRow(),
          ],
        ),
        size: const Size(43, 37),
      );
      final line = t.screen.lines.last;
      for (final (_, label) in KeyRow.keys) {
        await t.mouse(
          MouseEvent(
            MouseEventKind.press,
            position: Offset(line.indexOf(label), 36),
            button: MouseButton.primary,
          ),
        );
      }
      expect(received, [
        'escape',
        'tab',
        'left',
        'up',
        'down',
        'right',
        'enter',
        'f1',
      ]);
    });
  });
}

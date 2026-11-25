import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'overlay_focus_test.dart' show overlayOf;
import 'overlay_follower_test.dart' show Page;

void main() {
  group('tester latest overlay surface lifecycle', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'removal before deferred effects cannot revive visibility at $size',
        (t) async {
          final page = OverlayEntry(builder: (_) => Text('Page'));
          final entry = OverlayEntry(builder: (_) => Text('界🙂e\u0301'));
          await t.pumpWidget(Overlay(initialEntries: [page]), size: size);
          final overlay = overlayOf(t);
          overlay.insert(entry);
          expect(entry.visible, isFalse);
          t.host.owner.afterLayout(() {
            entry.remove();
            expect(entry.visible, isFalse);
          });
          await t.pump();
          expect(entry.visible, isFalse);
          await t.pump();
          expect(entry.visible, isFalse);
          overlay.insert(entry);
          expect(entry.visible, isFalse);
          await t.pump();
          expect(entry.visible, isTrue);
          entry.remove();
          entry.dispose();
          await t.pump();
          expect(entry.visible, isFalse);
        },
      );

      testWidgets(
        'coalesced surface updates and getter reads have no callbacks at $size',
        (t) async {
          final link = LayerLink();
          var width = 4;
          var builds = 0;
          final page = OverlayEntry(
            requestFocus: false,
            builder: (_) => Page(link, below: 5),
          );
          final entry = OverlayEntry(
            requestFocus: false,
            builder: (_) {
              builds++;
              return CompositedTransformFollower(
                link: link,
                followerAnchor: Alignment.bottomLeft,
                child: SizedBox(
                  width: width,
                  height: 1,
                  child: Text.ansi('界🙂e\u0301\x1b[31mR\x1b[0m'),
                ),
              );
            },
          );
          await t.pumpWidget(
            Overlay(initialEntries: [page, entry]),
            size: size,
          );
          final before = builds;
          for (var i = 0; i < 1000; i++) {
            expect(entry.visible, isTrue);
          }
          expect(builds, before);
          for (var i = 0; i < 1000; i++) {
            width = i.isEven ? 1 : 0;
            entry.markNeedsBuild();
          }
          await t.pump();
          expect(entry.visible, isFalse);
          width = 1;
          entry.markNeedsBuild();
          await t.pump();
          expect(entry.visible, isTrue);
          await t.resize(const Size(1, 1));
          expect(entry.visible, isFalse);
          await t.resize(const Size(0, 0));
          expect(entry.visible, isFalse);
          await t.resize(size);
          expect(entry.visible, isTrue);
          await t.pumpWidget(const SizedBox());
          expect(entry.visible, isFalse);
          expect(page.visible, isFalse);
        },
      );
    }
  });
}

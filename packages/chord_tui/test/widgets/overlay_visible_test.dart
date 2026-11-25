import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'overlay_focus_test.dart' show overlayOf;
import 'overlay_follower_test.dart' show Page;

void main() {
  testWidgets('raw base visibility is false on either zero surface axis', (
    t,
  ) async {
    final page = OverlayEntry(builder: (_) => Text('page'));
    expect(page.visible, isFalse);
    await t.pumpWidget(
      Overlay(initialEntries: [page]),
      size: const Size(80, 24),
    );
    expect(page.visible, isTrue);
    for (final size in [
      const Size(0, 24),
      const Size(80, 0),
      const Size(0, 0),
    ]) {
      await t.resize(size);
      expect(page.visible, isFalse);
    }
    await t.resize(const Size(120, 40));
    expect(page.visible, isTrue);
    await t.pumpWidget(Text('unmounted'));
    expect(page.visible, isFalse);
  });
  testWidgets(
    'unmount clears live entries and covering does not imply hidden geometry',
    (t) async {
      final page = OverlayEntry(builder: (_) => Text('page'));
      final layer = OverlayEntry(
        requestFocus: false,
        builder: (_) => Text('cover'),
      );
      await t.pumpWidget(
        Overlay(initialEntries: [page, layer]),
        size: const Size(80, 24),
      );
      expect(page.visible, isTrue);
      expect(layer.visible, isTrue);
      await t.pumpWidget(const SizedBox());
      expect(page.visible, isFalse);
      expect(layer.visible, isFalse);
    },
  );
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'passive follower reports zero room, unlink and lifecycle immediately at $size',
      (t) async {
        final link = LayerLink();
        var target = true;
        var fallback = false;
        var empty = false;
        final page = OverlayEntry(
          requestFocus: false,
          builder: (_) => Page(link, below: 5, target: target),
        );
        final entry = OverlayEntry(
          requestFocus: false,
          builder: (_) => CompositedTransformFollower(
            link: link,
            followerAnchor: Alignment.bottomLeft,
            showWhenUnlinked: fallback,
            child: empty ? const SizedBox() : Text('completion'),
          ),
        );
        expect(entry.visible, isFalse);
        await t.pumpWidget(Overlay(initialEntries: [page, entry]), size: size);
        expect(entry.visible, isTrue);
        await t.resize(const Size(80, 5));
        expect(entry.visible, isFalse);
        await t.resize(const Size(0, 24));
        expect(entry.visible, isFalse);
        await t.resize(size);
        expect(entry.visible, isTrue);
        target = false;
        page.markNeedsBuild();
        await t.pump();
        expect(entry.visible, isFalse);
        fallback = true;
        entry.markNeedsBuild();
        await t.pump();
        expect(entry.visible, isTrue);
        target = true;
        page.markNeedsBuild();
        await t.pump();
        expect(entry.visible, isTrue);
        empty = true;
        entry.markNeedsBuild();
        await t.pump();
        expect(entry.visible, isFalse);
        empty = false;
        entry.markNeedsBuild();
        await t.pump();
        final overlay = overlayOf(t);
        entry.remove();
        expect(entry.visible, isFalse);
        overlay.insert(entry);
        expect(entry.visible, isFalse);
        await t.pump();
        expect(entry.visible, isTrue);
        entry.remove();
        entry.dispose();
        expect(entry.visible, isFalse);
        await t.pump();
        expect(entry.visible, isFalse);
        expect(() => overlay.insert(entry), throwsStateError);
        await t.pumpWidget(const SizedBox());
        expect(page.visible, isFalse);
      },
    );
  }
}

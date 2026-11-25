import 'package:chord_tui/chord_tui.dart' show ScrollController;
import 'package:chord_tui/src/foundation/scroll_state.dart';
import 'package:chord_tui/src/rendering/list_viewport.dart';
import 'package:test/test.dart';

/// Extents of [heights] at width 80, each under version 'v'.
ItemExtents extents(List<int> heights) {
  final e = ItemExtents()
    ..width = 80
    ..length = heights.length;
  for (var i = 0; i < heights.length; i++) {
    e.record(i, heights[i], 'v');
  }
  return e;
}

void main() {
  test('the sum follows record, replace and truncate', () {
    final e = extents([2, 10, 3]);
    expect(e.total, 15);
    expect([for (var i = 0; i < 3; i++) e.itemTop(i)], [0, 2, 12]);
    e.record(1, 4, 'v');
    expect(e.total, 9);
    expect(e.itemTop(2), 6);
    e.length = 2;
    expect(e.total, 6);
    e.length = 4;
    expect(e.isKnown(2), isFalse);
    expect(e.total, 6);
    e.record(3, 5, 'v');
    expect(e.total, 11);
  });

  test('a version change drops one height', () {
    final e = extents([2, 10, 3]);
    final v = Object();
    e.record(0, 2, v);
    e.checkVersions((i) => i == 0 ? v : (i == 1 ? 'w' : 'v'));
    expect([e.isKnown(0), e.isKnown(1), e.isKnown(2)], [true, false, true]);
    expect(e.total, 5);
    // Equal versions that are not identical keep their height.
    e.record(1, 10, (1, 'entry'));
    e.checkVersions((i) => i == 1 ? (1, 'entry') : (i == 0 ? v : 'v'));
    expect(e.isKnown(1), isTrue);
  });

  test('a width change drops every height', () {
    final e = extents([2, 10, 3]);
    e.width = 80;
    expect(e.total, 15);
    e.width = 40;
    expect([e.isKnown(0), e.isKnown(1), e.isKnown(2)], [false, false, false]);
    expect(e.total, 0);
    expect(e.length, 3);
  });

  test("an anchor is the item a row falls in, with the original's data", () {
    final e = extents([2, 10, 3]);
    expect(e.anchorAt(0), const ListAnchor(0, 0));
    expect(e.anchorAt(5), const ListAnchor(1, 3));
    expect(e.anchorAt(14), const ListAnchor(2, 2));
    expect(extents([]).anchorAt(3), isNull);

    // The item has moved down and folded to one row.
    final relaid = extents([4, 1, 3]);
    expect(relaid.topOf(const ListAnchor(1, 3)), 4);
    expect(relaid.topOf(const ListAnchor(2, 2)), 7);
    expect(relaid.topOf(const ListAnchor(3, 0)), isNull);
  });

  test('a zero-height item never anchors a row another item takes', () {
    final e = extents([2, 0, 0, 3]);
    expect(e.anchorAt(2), const ListAnchor(3, 0));
    expect(e.anchorAt(1), const ListAnchor(0, 1));
    expect(e.topOf(const ListAnchor(1, 5)), 2);
  });

  test('ten thousand items sum and anchor', () {
    final e = extents(List.generate(10000, (i) => i % 3 + 1));
    expect(e.total, 19999);
    expect(e.anchorAt(19998), const ListAnchor(9999, 0));
    e.record(0, 4, 'v');
    expect(e.total, 20002);
    expect(e.itemTop(9999), 20001);
  });
  // CTUI-108: a disposed owner may still be held; its extents keep no
  // running-sum buffer the size of the list it had.
  test('dispose drops every item and gives back the sum buffer', () {
    final e = extents(List.generate(10000, (i) => 1));
    expect(e.itemTop(9999), 9999);
    expect(e.topsCapacity, greaterThan(10000));
    e.dispose();
    expect(e.length, 0);
    expect(e.topsCapacity, 1);
    expect(e.total, 0);
    // Still usable, as a list reset is.
    e
      ..length = 3
      ..record(0, 2, 'v')
      ..record(1, 3, 'v')
      ..record(2, 1, 'v');
    expect(e.itemTop(2), 5);
    expect(e.total, 6);
  });

  test("a scroll controller's dispose releases its extents' buffer", () {
    final controller = ScrollController();
    final e = controller.itemExtents
      ..width = 80
      ..length = 5000;
    for (var i = 0; i < 5000; i++) {
      e.record(i, 1, 'v');
    }
    expect(e.itemTop(4999), 4999);
    controller.dispose();
    expect(e.length, 0);
    expect(e.topsCapacity, 1);
  });

  group('tester: extent cache and anchor boundaries', () {
    test(
      'dropping a cached prefix and recording out of order updates every sum',
      () {
        final e = extents([2, 10, 3, 4]);
        expect(e.total, 19);
        e.drop(0);
        e.drop(0);
        expect(e.total, 17);
        expect(e.itemTop(3), 13);
        e.record(2, 0, 'next');
        e.record(0, 7, 'next');
        expect(e.total, 21);
        expect(
          [for (var i = 0; i <= e.length; i++) e.itemTop(i)],
          [0, 7, 17, 17, 21],
        );
      },
    );

    test(
      'truncate to empty and regrow never reuses stale heights or versions',
      () {
        final e = extents([2, 10, 3]);
        expect(e.total, 15);
        e.length = 0;
        expect(e.total, 0);
        expect(e.anchorAt(0), isNull);
        e.length = 3;
        expect([for (var i = 0; i < 3; i++) e.heightOf(i)], [null, null, null]);
        e.record(2, 8, 'v');
        expect(e.total, 8);
        expect(e.anchorAt(0), const ListAnchor(2, 0));
        expect(e.topOf(const ListAnchor(2, 100)), 7);
      },
    );

    test(
      'null versions cache normally and clear removes every known height',
      () {
        final e = extents([2, 10, 3]);
        e.record(1, 10, null);
        e.checkVersions((i) => i == 1 ? null : 'v');
        expect(e.total, 15);
        e.checkVersions((i) => 'v');
        expect(e.heightOf(1), isNull);
        expect(e.total, 5);
        e.clear();
        expect(e.total, 0);
        expect(
          [for (var i = 0; i < 3; i++) e.isKnown(i)],
          [false, false, false],
        );
        e.record(0, 1, null);
        expect(e.total, 1);
      },
    );

    test('anchors resolve exact boundaries and clamp a folded item', () {
      final e = extents([0, 2, 0, 3, 0]);
      expect(e.anchorAt(-1), const ListAnchor(1, 0));
      expect(e.anchorAt(1), const ListAnchor(1, 1));
      expect(e.anchorAt(2), const ListAnchor(3, 0));
      expect(e.anchorAt(4), const ListAnchor(3, 2));
      final anchor = e.anchorAt(4)!;
      e.record(1, 10, 'v');
      e.record(3, 1, 'v');
      expect(e.topOf(anchor), 10);
      e.length = 3;
      expect(e.topOf(anchor), isNull);
    });

    test(
      'width zero invalidates measurements and restoring width measures anew',
      () {
        final e = extents([1, 3]);
        expect(e.total, 4);
        e.width = 0;
        expect(e.total, 0);
        e.record(0, 0, 'v');
        e.width = 0;
        expect(e.isKnown(0), isTrue);
        e.width = 120;
        expect(e.isKnown(0), isFalse);
        e.record(1, 2, 'v');
        expect(e.total, 2);
      },
    );
  });

  group('tester CTUI-108: disposal at cache boundaries', () {
    test('empty and partially built prefixes dispose repeatedly', () {
      final e = ItemExtents();
      e.dispose();
      expect(e.topsCapacity, 1);
      e.length = 10000;
      e.record(0, 7, Object());
      e.record(9999, 3, Object());
      expect(e.itemTop(1), 7);
      expect(e.topsCapacity, greaterThan(10000));
      e.length = 0;
      e.dispose();
      e.dispose();
      expect(e.total, 0);
      expect(e.topsCapacity, 1);
      expect(e.anchorAt(0), isNull);
    });

    test(
      'reuse after disposal forgets versions through zero and one width',
      () {
        final e = extents([2, 10, 3]);
        expect(e.total, 15);
        e.dispose();
        for (final width in [0, 1, 80, 120]) {
          e
            ..width = width
            ..length = 2;
          expect(e.heightOf(0), isNull);
          expect(e.heightOf(1), isNull);
          for (var i = 0; i < 1000; i++) {
            e.record(1, i, ('new', i));
          }
          expect(e.itemTop(1), 0);
          expect(e.total, 999);
          expect(e.anchorAt(998), const ListAnchor(1, 998));
          e.dispose();
          expect(e.topsCapacity, 1);
        }
      },
    );
  });
}

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  _testerExactExtentBoundaries();
  for (final count in [2000, 10000]) {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('exact $count rows bound widget work at $size', (t) async {
        final scroll = ScrollController();
        final rebuild = ValueNotifier(0);
        final probe = _Probe();
        var projections = 0, versions = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: rebuild,
            builder: (_) => ListView.builder(
              controller: scroll,
              itemCount: count,
              itemVersion: (_) {
                versions++;
                return 0;
              },
              itemExtentVersion: 'stable',
              itemExtentBuilder: (_, width) {
                projections++;
                return 1;
              },
              itemBuilder: (_, i) => probe.row(1),
            ),
          ),
          size: size,
        );
        expect(projections, count);
        expect(versions, 0);
        expect(probe.builds, lessThanOrEqualTo(size.height * 2));
        expect(scroll.contentRows, count);
        for (final offset in [1, count ~/ 2, count - size.height]) {
          probe.clear();
          projections = 0;
          scroll.jumpTo(offset);
          rebuild.value++;
          await t.pump();
          expect(scroll.offset, offset);
          expect(projections, 0);
          expect(versions, 0);
          expect(probe.builds, lessThanOrEqualTo(size.height * 4));
          expect(probe.layouts, lessThanOrEqualTo(size.height * 4));
        }
        probe.clear();
        projections = 0;
        await t.resize(Size(size.width - 10, size.height));
        expect(projections, count);
        expect(probe.builds, lessThanOrEqualTo(size.height * 2));
        expect(probe.layouts, lessThanOrEqualTo(size.height * 4));
        projections = 0;
        await t.resize(Size(size.width - 10, size.height - 2));
        expect(projections, 0);
        projections = 0;
        await t.resize(size);
        expect(projections, count, reason: 'only current width is retained');
        t.dispose();
        rebuild.dispose();
        scroll.dispose();
      });
    }
  }

  testWidgets('null revisions reproject captured inputs on rebuild', (t) async {
    final rebuild = ValueNotifier(0);
    final scroll = ScrollController();
    var height = 1, projections = 0;
    await t.pumpWidget(
      ListenableBuilder(
        listenable: rebuild,
        builder: (_) => ListView.builder(
          controller: scroll,
          itemCount: 50,
          itemExtentBuilder: (_, width) {
            projections++;
            return height;
          },
          itemBuilder: (_, i) => SizedBox(height: height),
        ),
      ),
    );
    expect(scroll.contentRows, 50);
    projections = 0;
    height = 2;
    rebuild.value++;
    await t.pump();
    expect(projections, 50);
    expect(scroll.contentRows, 100);
    t.dispose();
    rebuild.dispose();
    scroll.dispose();
  });

  testWidgets('explicit revision updates heights, count and anchored offset', (
    t,
  ) async {
    final revision = ValueNotifier(0);
    final scroll = ScrollController();
    var count = 100, height = 1, projections = 0;
    await t.pumpWidget(
      ListenableBuilder(
        listenable: revision,
        builder: (_) => ListView.builder(
          controller: scroll,
          itemCount: count,
          itemExtentVersion: revision.value,
          itemExtentBuilder: (_, width) {
            projections++;
            return height;
          },
          itemBuilder: (_, i) => SizedBox(height: height),
        ),
      ),
    );
    scroll.jumpTo(50);
    await t.pump();
    height = 3;
    projections = 0;
    revision.value++;
    await t.pump();
    expect(projections, count);
    expect(scroll.offset, 150);
    expect(scroll.itemRows(50), 3);
    count = 80;
    projections = 0;
    revision.value++;
    await t.pump();
    expect(projections, 80);
    expect(scroll.contentRows, 240);
    t.dispose();
    revision.dispose();
    scroll.dispose();
  });

  testWidgets('zero-width round trip reprojects the cleared exact cache', (
    t,
  ) async {
    var projections = 0;
    final scroll = ScrollController();
    await t.pumpWidget(
      ListView.builder(
        controller: scroll,
        itemCount: 100,
        itemExtentVersion: 0,
        itemExtentBuilder: (_, width) {
          projections++;
          return 1;
        },
        itemBuilder: (_, i) => Text('row $i'),
      ),
    );
    expect(projections, 100);
    await t.resize(const Size(0, 24));
    expect(scroll.contentRows, 0);
    projections = 0;
    await t.resize(const Size(80, 24));
    expect(projections, 100);
    expect(t.screen, shows('row 0'));
    t.dispose();
    scroll.dispose();
  });

  testWidgets('zero-height runs mount only positive choices', (t) async {
    final probe = _Probe();
    final scroll = ScrollController();
    await t.pumpWidget(
      ListView.builder(
        controller: scroll,
        itemCount: 10000,
        itemExtentVersion: 0,
        itemExtentBuilder: (i, _) => i % 1000 == 0 ? 1 : 0,
        itemBuilder: (_, i) => probe.row(i % 1000 == 0 ? 1 : 0),
      ),
    );
    expect(scroll.contentRows, 10);
    expect(probe.builds, lessThanOrEqualTo(20));
    expect(probe.layouts, lessThanOrEqualTo(20));
    t.dispose();
    scroll.dispose();
  });

  testWidgets('exact and measured paths can replace one another', (t) async {
    final exact = ValueNotifier(true);
    final scroll = ScrollController();
    var projections = 0;
    await t.pumpWidget(
      ListenableBuilder(
        listenable: exact,
        builder: (_) => ListView.builder(
          controller: scroll,
          itemCount: 50,
          itemExtentVersion: 0,
          itemExtentBuilder: exact.value
              ? (_, width) {
                  projections++;
                  return 1;
                }
              : null,
          itemVersion: (_) => 'row',
          itemBuilder: (_, i) => Text('row $i'),
        ),
      ),
    );
    expect(projections, 50);
    exact.value = false;
    await t.pump();
    expect(scroll.contentRows, 50);
    projections = 0;
    exact.value = true;
    await t.pump();
    expect(projections, 50);
    expect(t.screen, shows('row 0'));
    t.dispose();
    exact.dispose();
    scroll.dispose();
  });

  testWidgets('negative exact extents are rejected', (t) async {
    await expectLater(
      t.pumpWidget(
        ListView.builder(
          itemCount: 1,
          itemExtentBuilder: (_, width) => -1,
          itemBuilder: (_, i) => Text('bad'),
        ),
      ),
      throwsArgumentError,
    );
  });

  testWidgets('a visible row must agree with its exact extent', (t) async {
    await expectLater(
      t.pumpWidget(
        ListView.builder(
          itemCount: 1,
          itemExtentBuilder: (_, width) => 1,
          itemBuilder: (_, i) => const SizedBox(height: 2),
        ),
      ),
      throwsStateError,
    );
  });
}

class _Probe {
  var builds = 0, layouts = 0;
  Widget row(int height) {
    builds++;
    return _MeasuredRow(this, height);
  }

  void clear() {
    builds = 0;
    layouts = 0;
  }
}

class _MeasuredRow extends LeafRenderObjectWidget {
  const _MeasuredRow(this.probe, this.height);
  final _Probe probe;
  final int height;
  @override
  RenderBox createRenderObject(BuildContext context) =>
      _MeasuredBox(probe, height);
}

class _MeasuredBox extends RenderBox {
  _MeasuredBox(this.probe, this.height);
  final _Probe probe;
  final int height;
  @override
  void performLayout() {
    probe.layouts++;
    size = Size(constraints.maxWidth, height);
  }

  @override
  void paint(Canvas canvas, Offset origin) {}
}

void _testerExactExtentBoundaries() {
  group('tester: U54b exact extent lifetime', () {
    testWidgets(
      'zero-height viewport retains scalar cache without mounting rows',
      (t) async {
        final scroll = ScrollController();
        final probe = _Probe();
        var projections = 0;
        await t.pumpWidget(
          ListView.builder(
            controller: scroll,
            itemCount: 2000,
            itemExtentVersion: 0,
            itemExtentBuilder: (_, width) {
              projections++;
              expect(width, 1);
              return 1;
            },
            itemBuilder: (_, i) => probe.row(1),
          ),
          size: const Size(1, 0),
        );
        expect(projections, 2000);
        expect(probe.builds, 0);
        expect(scroll.contentRows, 2000);
        projections = 0;
        await t.resize(const Size(1, 1));
        expect(projections, 0);
        expect(probe.builds, lessThanOrEqualTo(2));
        scroll.jumpTo(1999);
        await t.pump();
        expect(scroll.offset, 1999);
        await t.resize(const Size(1, 0));
        expect(projections, 0);
        t.dispose();
        scroll.dispose();
      },
    );

    testWidgets(
      'a thousand revisions before a frame project only the latest generation',
      (t) async {
        final revision = ValueNotifier(0);
        final scroll = ScrollController();
        var projections = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: revision,
            builder: (_) => ListView.builder(
              controller: scroll,
              itemCount: 2000,
              itemExtentVersion: revision.value,
              itemExtentBuilder: (_, width) {
                projections++;
                return revision.value == 1000 ? 2 : 1;
              },
              itemBuilder: (_, i) =>
                  SizedBox(height: revision.value == 1000 ? 2 : 1),
            ),
          ),
          size: const Size(80, 24),
        );
        projections = 0;
        for (var i = 1; i <= 1000; i++) {
          revision.value = i;
        }
        await t.pump();
        expect(projections, 2000);
        expect(scroll.contentRows, 4000);
        expect(scroll.itemRows(1999), 2);
        await t.pumpWidget(const SizedBox());
        projections = 0;
        revision.value++;
        await t.pump();
        expect(
          projections,
          0,
          reason: 'unmounted list observes no later revision',
        );
        t.dispose();
        revision.dispose();
        scroll.dispose();
      },
    );

    testWidgets(
      'switching exact and measured paths drops incompatible geometry',
      (t) async {
        final mode = ValueNotifier(0);
        final scroll = ScrollController();
        var projections = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: mode,
            builder: (_) => ListView.builder(
              controller: scroll,
              itemCount: 30,
              itemExtentVersion: 0,
              itemVersion: (_) => 0,
              itemExtentBuilder: mode.value == 1
                  ? null
                  : (_, width) {
                      projections++;
                      return mode.value == 0 ? 1 : 3;
                    },
              itemBuilder: (_, i) => SizedBox(height: mode.value + 1),
            ),
          ),
          size: const Size(120, 40),
        );
        expect(scroll.contentRows, 30);
        mode.value = 1;
        await t.pump();
        expect(scroll.contentRows, 60);
        projections = 0;
        mode.value = 2;
        await t.pump();
        expect(projections, 30);
        expect(scroll.contentRows, 90);
        expect(scroll.itemRows(29), 3);
        t.dispose();
        mode.dispose();
        scroll.dispose();
      },
    );

    testWidgets(
      'offscreen extent mismatch is checked when its row enters view',
      (t) async {
        final scroll = ScrollController();
        final built = <int>{};
        await t.pumpWidget(
          ListView.builder(
            controller: scroll,
            itemCount: 2000,
            itemExtentVersion: 0,
            itemExtentBuilder: (_, width) => 1,
            itemBuilder: (_, i) {
              built.add(i);
              return SizedBox(height: i == 1500 ? 2 : 1);
            },
          ),
          size: const Size(80, 24),
        );
        expect(built, isNot(contains(1500)));
        scroll.jumpTo(1500);
        await expectLater(t.pump(), throwsStateError);
        expect(built, contains(1500));
        t.dispose();
        scroll.dispose();
      },
    );
  });
}

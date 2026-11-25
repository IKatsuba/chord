import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const sizes = [Size(120, 40), Size(80, 24)];
const count = 200;

/// One list's entries and its retained controller, as a session keeps them.
class Session {
  Session(this.name, {Follow follow = Follow.none})
    : lines = ValueNotifier([
        for (var i = 0; i < count; i++) '$name $i${i.isEven ? '\n.' : ''}',
      ]),
      controller = ScrollController(follow: follow);

  final String name;
  final ValueNotifier<List<String>> lines;
  final ScrollController controller;
}

/// The list of the picked session, keyed by it, so every switch builds a
/// new viewport over that session's controller; [builds] counts items built.
class Switcher {
  Switcher({this.versioned = true});

  final bool versioned;
  final a = Session('a');
  final b = Session('b', follow: Follow.bottom);
  late final picked = ValueNotifier(a);
  var builds = 0;

  Widget get widget => ListenableBuilder(
    listenable: picked,
    builder: (context) {
      final s = picked.value;
      return ListenableBuilder(
        key: ValueKey(s.name),
        listenable: s.lines,
        builder: (context) => ListView.builder(
          controller: s.controller,
          itemCount: s.lines.value.length,
          itemVersion: versioned ? (i) => s.lines.value[i] : null,
          itemBuilder: (context, i) {
            builds++;
            return Text(s.lines.value[i]);
          },
        ),
      );
    },
  );

  Future<void> show(WidgetTester t, Session s) async {
    builds = 0;
    picked.value = s;
    await t.pump();
  }
}

void main() {
  for (final size in sizes) {
    group('at ${size.width}x${size.height}', () {
      testWidgets('a switch back with unchanged versions measures nothing', (
        t,
      ) async {
        final w = Switcher();
        await t.pumpWidget(w.widget, size: size);
        expect(w.builds, greaterThanOrEqualTo(count));
        await w.show(t, w.b);
        expect(w.builds, greaterThanOrEqualTo(count), reason: 'b is new');
        await w.show(t, w.a);
        expect(w.builds, lessThanOrEqualTo(size.height));
        expect(t.screen.lines.first, 'a 0');
        await w.show(t, w.b);
        expect(w.builds, lessThanOrEqualTo(size.height));
        expect(t.screen.lines.last, 'b 199');
        expect(w.b.controller.contentRows, count * 3 ~/ 2);
      });

      testWidgets('an entry changed while away is measured again', (t) async {
        final w = Switcher();
        await t.pumpWidget(w.widget, size: size);
        w.a.controller.jumpTo(30);
        await t.pump();
        expect(t.screen.lines.first, 'a 20');
        await w.show(t, w.b);
        // Above the view: it moves the view's entry down by its new rows.
        w.a.lines.value = [...w.a.lines.value]..[5] = 'a 5\n1\n2\n3\n4';
        // In the view: drawn at its new height.
        w.a.lines.value = [...w.a.lines.value]..[21] = 'a 21\nx\ny';
        await w.show(t, w.a);
        expect(w.builds, lessThanOrEqualTo(size.height + 1));
        expect(w.a.controller.contentRows, count * 3 ~/ 2 + 6);
        expect(t.screen.lines.take(5), ['a 20', '.', 'a 21', 'x', 'y']);
        expect(t.screen.lines[5], 'a 22');
      });

      testWidgets('a width changed while away measures every entry', (t) async {
        final w = Switcher();
        await t.pumpWidget(w.widget, size: size);
        await w.show(t, w.b);
        await t.resize(Size(size.width - 10, size.height));
        w.builds = 0;
        await w.show(t, w.a);
        expect(w.builds, greaterThanOrEqualTo(count));
        expect(t.screen.lines.first, 'a 0');
      });

      testWidgets('without itemVersion a switch measures every entry', (
        t,
      ) async {
        final w = Switcher(versioned: false);
        await t.pumpWidget(w.widget, size: size);
        await w.show(t, w.b);
        await w.show(t, w.a);
        expect(w.builds, greaterThanOrEqualTo(count));
        expect(w.a.controller.contentRows, count * 3 ~/ 2);
      });

      testWidgets('entries cut or added while away', (t) async {
        final w = Switcher();
        await t.pumpWidget(w.widget, size: size);
        await w.show(t, w.b);
        w.b.lines.value = w.b.lines.value.sublist(0, 100);
        await w.show(t, w.a);
        await w.show(t, w.b);
        expect(w.builds, lessThanOrEqualTo(size.height));
        expect(w.b.controller.contentRows, 150);
        expect(t.screen.lines.last, 'b 99');
        await w.show(t, w.a);
        w.b.lines.value = [...w.b.lines.value, 'b new\n1\n2'];
        await w.show(t, w.b);
        // Only the new entry is measured, beyond what is in sight.
        expect(w.builds, lessThanOrEqualTo(size.height + 1));
        expect(w.b.controller.contentRows, 153);
        expect(t.screen.lines.sublist(size.height - 3), ['b new', '1', '2']);
      });

      testWidgets('a scrolled-back list lands on its entry after a switch', (
        t,
      ) async {
        final w = Switcher();
        await t.pumpWidget(w.widget, size: size);
        await w.show(t, w.b);
        w.b.controller.jumpTo(w.b.controller.itemTop(101));
        await t.pump();
        expect(t.screen.lines.first, 'b 101');
        for (var round = 0; round < 3; round++) {
          await w.show(t, w.a);
          // Entries above b's view grow while it is away.
          w.b.lines.value = [...w.b.lines.value]..[round] = 'b\n1\n2\n3';
          await w.show(t, w.b);
          expect(w.builds, lessThanOrEqualTo(size.height + 1));
          expect(t.screen.lines.first, 'b 101');
          expect(w.b.controller.isFollowing, isFalse);
        }
      });
    });
  }

  group('tester: retained extents across detached edge cases', () {
    testWidgets(
      'unversioned offscreen content changed while detached is measured',
      (t) async {
        final w = Switcher(versioned: false);
        await t.pumpWidget(w.widget, size: const Size(80, 24));
        await w.show(t, w.b);
        w.a.lines.value = [...w.a.lines.value]..[190] = 'changed\nextra\nlast';
        await w.show(t, w.a);
        expect(w.builds, greaterThanOrEqualTo(count));
        expect(w.a.controller.contentRows, 301);
        expect(w.a.controller.itemRows(190), 3);
        expect(w.a.controller.itemTop(count), 301);
      },
    );

    testWidgets('zero-height cached entries can grow while detached', (
      t,
    ) async {
      final c = ScrollController();
      var grown = false;
      var builds = 0;
      Widget view() => ListView.builder(
        controller: c,
        itemCount: 200,
        itemVersion: (i) => (i, i == 100 && grown),
        itemBuilder: (_, i) {
          builds++;
          return i == 100 && !grown
              ? const SizedBox(height: 0)
              : Text('row $i');
        },
      );
      await t.pumpWidget(view(), size: const Size(80, 24));
      expect(c.contentRows, 199);
      await t.pumpWidget(Text('away'));
      grown = true;
      builds = 0;
      await t.pumpWidget(view());
      expect(c.contentRows, 200);
      expect(c.itemTop(101), 101);
      expect(c.itemRows(100), 1);
      expect(builds, 25);
    });

    for (final size in sizes) {
      testWidgets(
        'a thousand detached updates use only final versions at $size',
        (t) async {
          final w = Switcher();
          await t.pumpWidget(w.widget, size: size);
          await w.show(t, w.b);
          for (var i = 0; i < 1000; i++) {
            w.a.lines.value = [...w.a.lines.value]
              ..[0] = 'changed $i\nextra\nend';
          }
          await w.show(t, w.a);
          expect(w.a.controller.contentRows, 301);
          expect(t.screen.lines.take(3), ['changed 999', 'extra', 'end']);
          expect(w.builds, lessThanOrEqualTo(size.height + 1));
        },
      );

      testWidgets(
        'empty while detached then refilled has no stale prefix at $size',
        (t) async {
          final w = Switcher();
          await t.pumpWidget(w.widget, size: size);
          w.a.controller.jumpTo(100);
          await t.pump();
          await w.show(t, w.b);
          w.a.lines.value = [];
          await w.show(t, w.a);
          expect(w.a.controller.contentRows, 0);
          expect(
            (w.a.controller.firstVisible, w.a.controller.lastVisible),
            (-1, -1),
          );
          await w.show(t, w.b);
          w.a.lines.value = ['new\nsecond'];
          await w.show(t, w.a);
          expect(w.a.controller.contentRows, 2);
          expect(w.a.controller.itemTop(1), 2);
          expect(t.screen.lines.take(2), ['new', 'second']);
        },
      );

      testWidgets('reattachment preserves ANSI and grapheme cells at $size', (
        t,
      ) async {
        final c = ScrollController();
        final line = '\x1b[31m界é🙂${'x' * (size.width - 6)}界\x1b[0m';
        var builds = 0;
        Widget view() => ListView.builder(
          controller: c,
          itemCount: 100,
          itemVersion: (i) => (i, line),
          itemBuilder: (_, i) {
            builds++;
            return Text.ansi(line, softWrap: false);
          },
        );
        await t.pumpWidget(view(), size: size);
        c.jumpTo(25);
        await t.pump();
        final before = t.screen.text;
        await t.pumpWidget(Text('away'), size: size);
        builds = 0;
        await t.pumpWidget(view(), size: size);
        expect(builds, size.height);
        expect(c.offset, 25);
        expect(t.screen.text, before);
        for (var y = 0; y < size.height; y++) {
          expect(t.screen.charAt(0, y), '界');
          expect(t.screen.charAt(2, y), 'é');
          expect(t.screen.charAt(3, y), '🙂');
          expect(t.screen.charAt(size.width - 1, y), ' ');
        }
      });
    }

    for (final tiny in [
      const Size(0, 0),
      const Size(0, 1),
      const Size(1, 0),
      const Size(1, 1),
    ]) {
      testWidgets('switch through $tiny recovers full geometry', (t) async {
        final w = Switcher();
        await t.pumpWidget(w.widget, size: const Size(80, 24));
        await w.show(t, w.b);
        await t.resize(tiny);
        await w.show(t, w.a);
        await t.resize(const Size(80, 24));
        expect(w.a.controller.contentRows, 300);
        expect(t.screen.lines.first, 'a 0');
        expect(w.a.controller.itemTop(count), 300);
      });
    }

    testWidgets(
      'changing controller on a mounted viewport checks its own versions',
      (t) async {
        final a = ScrollController();
        final b = ScrollController();
        var picked = a;
        var prefix = 'a';
        var builds = 0;
        Widget view() => ListView.builder(
          controller: picked,
          itemCount: 200,
          itemVersion: (i) => (prefix, i),
          itemBuilder: (_, i) {
            builds++;
            return Text('$prefix $i${prefix == 'b' ? '\nextra' : ''}');
          },
        );
        await t.pumpWidget(view(), size: const Size(80, 24));
        picked = b;
        prefix = 'b';
        await t.pumpWidget(view());
        expect(b.contentRows, 400);
        picked = a;
        prefix = 'a';
        builds = 0;
        await t.pumpWidget(view());
        expect(a.contentRows, 200);
        expect(builds, lessThan(100));
        expect(t.screen.lines.first, 'a 0');
      },
    );
  });

  testWidgets('a disposed controller lets go of its heights', (t) async {
    final s = Session('a');
    await t.pumpWidget(
      ListView.builder(
        controller: s.controller,
        itemCount: count,
        itemVersion: (i) => s.lines.value[i],
        itemBuilder: (_, i) => Text(s.lines.value[i]),
      ),
      size: const Size(80, 24),
    );
    expect(s.controller.contentRows, count * 3 ~/ 2);
    await t.pumpWidget(Text(''), size: const Size(80, 24));
    s.controller.dispose();
    // ignore: invalid_use_of_internal_member
    expect(s.controller.itemExtents.length, 0);
  });
}

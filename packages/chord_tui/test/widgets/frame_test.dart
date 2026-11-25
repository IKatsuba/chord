import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A value that layout sets without notifying, and tells after layout.
class Measured extends ChangeNotifier {
  int value = 0;
  var inLayout = false;
  var layouts = 0;
}

/// Sets [measured] to its height on every layout, plus [bump] per layout.
class Reporter extends LeafRenderObjectWidget {
  const Reporter(this.measured, {this.bump = 0});

  final Measured measured;
  final int bump;

  @override
  RenderBox createRenderObject(BuildContext context) =>
      RenderReporter(context.owner, measured, bump);
}

class RenderReporter extends RenderBox {
  RenderReporter(this.owner, this.measured, this.bump);

  final BuildOwner owner;
  final Measured measured;
  final int bump;

  @override
  void performLayout() {
    size = constraints.biggest;
    measured.inLayout = true;
    measured.layouts++;
    final next = bump == 0 ? size.height : measured.value + bump;
    if (next != measured.value) {
      measured.value = next;
      owner.afterLayout(measured.notifyListeners);
    }
    measured.inLayout = false;
  }

  @override
  void paint(Canvas canvas, Offset origin) {}
}

/// [measured]'s value drawn above a [Reporter] that sets it.
Widget app(Measured measured, {int bump = 0}) => Column(
  children: [
    ListenableBuilder(
      listenable: measured,
      builder: (context) => Text('value ${measured.value}'),
    ),
    Expanded(child: Reporter(measured, bump: bump)),
  ],
);

/// Mounts one item from inside layout, as a list does.
class Builder extends RenderObjectWidget {
  const Builder();

  @override
  Element createElement() => BuilderElement(this);

  @override
  RenderBox createRenderObject(BuildContext context) => RenderBuilder();
}

class BuilderElement extends RenderObjectElement {
  BuilderElement(super.widget);

  Element? item;
  var structureDuringBuild = false;

  RenderBox? build() {
    owner.buildDuringLayout(() {
      item = updateChild(item, Column(children: [Text('built'), Text('in')]));
      structureDuringBuild = owner.structureChanged;
      return item;
    });
    return RenderObjectElement.firstRenderObject(item);
  }

  @override
  void mount(Element? parent) {
    super.mount(parent);
    (renderObject as RenderBuilder).element = this;
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    if (item != null) visitor(item!);
  }

  @override
  void syncRenderChildren() {}
}

class RenderBuilder extends RenderBox {
  late BuilderElement element;
  RenderBox? child;

  @override
  void performLayout() {
    child = element.build();
    child!.layout(constraints.loosen());
    size = constraints.biggest;
  }

  @override
  void paint(Canvas canvas, Offset origin) => child?.paint(canvas, origin);
}

void main() {
  group('the frame', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'one pump shows what layout measured, at ${size.width}x${size.height}',
        (tester) async {
          final m = Measured();
          await tester.pumpWidget(app(m), size: size);
          expect(tester.screen.lines.first, 'value ${size.height - 1}');
        },
      );
    }

    testWidgets('listeners are never called during layout', (tester) async {
      final m = Measured();
      var calledInLayout = false;
      m.addListener(() => calledInLayout |= m.inLayout);
      await tester.pumpWidget(app(m));
      await tester.resize(const Size(80, 10));
      expect(calledInLayout, isFalse);
      expect(tester.screen.lines.first, 'value 9');
    });

    testWidgets('a frame lays out at most twice; later changes wait', (
      tester,
    ) async {
      final m = Measured();
      var frames = 0;
      await tester.pumpWidget(app(m, bump: 1));
      // Every layout changes the value: two layouts a frame, never a loop,
      // and the screen shows the first layout's value.
      expect(m.layouts, 2);
      expect(tester.screen.lines.first, 'value 1');
      final host = AppHost(app(m, bump: 1), onNeedsFrame: () => frames++);
      frames = 0;
      m.layouts = 0;
      host.drawFrame(const Size(80, 24));
      expect(m.layouts, 2);
      expect(frames, greaterThan(0));
      host.dispose();
    });

    testWidgets('a layout that changes nothing lays out once', (tester) async {
      final m = Measured();
      await tester.pumpWidget(app(m));
      m.layouts = 0;
      await tester.pump();
      expect(m.layouts, 1);
    });
  });

  group('BuildOwner.buildDuringLayout', () {
    testWidgets('mounts and syncs the item, leaving structureChanged alone', (
      tester,
    ) async {
      await tester.pumpWidget(const Builder());
      expect(tester.screen.lines.take(2), ['built', 'in']);
      expect(tester.host.owner.structureChanged, isFalse);
      await tester.pump();
      expect(tester.host.owner.structureChanged, isFalse);
      expect(tester.screen.lines.take(2), ['built', 'in']);
    });

    test('restores structureChanged when the build throws', () {
      final owner = BuildOwner()..structureChanged = false;
      expect(
        () => owner.buildDuringLayout(() {
          owner.structureChanged = true;
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(owner.structureChanged, isFalse);
    });
  });
  group('tester: bounded frame progression', () {
    for (final size in [const Size(80, 24), const Size(120, 40)]) {
      testWidgets('second-layout updates appear next frame at $size', (
        tester,
      ) async {
        final m = Measured();
        await tester.pumpWidget(app(m, bump: 1), size: size);
        for (var frame = 1; frame <= 5; frame++) {
          expect(m.layouts, frame * 2);
          expect(m.value, frame * 2);
          expect(tester.screen.lines.first, 'value ${frame * 2 - 1}');
          if (frame < 5) await tester.pump();
        }
      });
    }

    testWidgets(
      'resize settles on the same pump and stable geometry takes one pass',
      (tester) async {
        final m = Measured();
        await tester.pumpWidget(app(m), size: const Size(120, 40));
        for (final size in [
          const Size(80, 24),
          const Size(120, 40),
          const Size(1, 1),
        ]) {
          m.layouts = 0;
          await tester.resize(size);
          expect(m.value, size.height - 1);
          expect(m.layouts, 2);
          if (size.width > 1) {
            expect(tester.screen.lines.first, 'value ${size.height - 1}');
          }
          m.layouts = 0;
          await tester.pump();
          expect(m.layouts, 1);
        }
      },
    );

    test('layout callbacks added during delivery wait for the next flush', () {
      final owner = BuildOwner();
      final seen = <int>[];
      owner.afterLayout(() {
        seen.add(1);
        owner.afterLayout(() => seen.add(3));
      });
      owner.afterLayout(() => seen.add(2));
      expect(seen, isEmpty);
      owner.flushAfterLayout();
      expect(seen, [1, 2]);
      owner.flushAfterLayout();
      owner.flushAfterLayout();
      expect(seen, [1, 2, 3]);
    });

    test(
      'nested layout builds preserve an already-dirty structure on success and throw',
      () {
        final owner = BuildOwner()..structureChanged = true;
        owner.buildDuringLayout(() {
          owner.structureChanged = false;
          owner.buildDuringLayout(() {
            owner.structureChanged = true;
            return null;
          });
          expect(owner.structureChanged, isFalse);
          return null;
        });
        expect(owner.structureChanged, isTrue);
        expect(
          () => owner.buildDuringLayout(() {
            owner.structureChanged = false;
            throw StateError('tester failure');
          }),
          throwsStateError,
        );
        expect(owner.structureChanged, isTrue);
      },
    );
  });
}

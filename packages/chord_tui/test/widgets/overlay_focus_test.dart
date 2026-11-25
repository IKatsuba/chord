import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// A focusable line that shows `[label]` when focused.
class Field extends StatefulWidget {
  const Field(this.label, {super.key, this.autofocus = false});

  final String label;
  final bool autofocus;

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  late final node = FocusNode(debugLabel: widget.label);

  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    autofocus: widget.autofocus,
    child: ListenableBuilder(
      listenable: node,
      builder: (_) =>
          Text(node.hasPrimaryFocus ? '[${widget.label}]' : widget.label),
    ),
  );
}

String? focused(WidgetTester t) => t.focusManager.primaryFocus?.debugLabel;

OverlayState overlayOf(WidgetTester t) {
  OverlayState? found;
  void walk(Element e) {
    if (e is StatefulElement && e.state is OverlayState) {
      found ??= e.state as OverlayState;
    }
    e.visitChildren(walk);
  }

  walk(t.host.rootElement);
  return found!;
}

/// An entry of fields, in a column at the top left.
OverlayEntry fields(List<Widget> children, {bool requestFocus = true}) =>
    OverlayEntry(
      requestFocus: requestFocus,
      builder: (_) => Align(
        alignment: Alignment.bottomRight,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );

/// The app: app-wide Actions above the overlay, a base of fields under
/// base-only Actions, and an optional target row.
Widget app({
  List<Widget>? base,
  List<String>? log,
  LayerLink? link,
  ValueNotifier<int>? targetRow,
}) => Actions(
  bindings: [Binding('ctrl+q', 'Quit', () => log?.add('quit'))],
  child: Overlay(
    initialEntries: [
      OverlayEntry(
        builder: (_) => Actions(
          bindings: [
            Binding('x', 'Base x', () => log?.add('base x')),
            Binding('ctrl+x a', 'Base chord', () => log?.add('chord')),
          ],
          child: Column(
            children: [
              ...base ?? [Field('A', autofocus: true), Field('B')],
              if (link != null)
                ListenableBuilder(
                  listenable: targetRow!,
                  builder: (_) => targetRow.value < 0
                      ? const SizedBox()
                      : Padding(
                          padding: EdgeInsets.only(top: targetRow.value),
                          child: CompositedTransformTarget(
                            link: link,
                            child: const SizedBox(height: 0),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    ],
  ),
);

void main() {
  testerEdges();
  group('FocusScope', () {
    testWidgets('tab stays inside the scope, which holds focus if empty', (
      t,
    ) async {
      await t.pumpWidget(
        Column(
          children: [
            Field('out'),
            FocusScope(
              child: Column(
                children: [Field('in1', autofocus: true), Field('in2')],
              ),
            ),
          ],
        ),
      );
      expect(focused(t), 'in1');
      await t.press('tab');
      expect(focused(t), 'in2');
      await t.press('tab');
      expect(focused(t), 'in1');
      await t.press('shift+tab');
      expect(focused(t), 'in2');

      final scope = FocusScopeNode(debugLabel: 'empty');
      await t.pumpWidget(
        Column(
          children: [
            Field('out'),
            FocusScope(node: scope, autofocus: true, child: Text('nothing')),
          ],
        ),
      );
      expect(t.focusManager.primaryFocus, scope);
      await t.press('tab');
      expect(t.focusManager.primaryFocus, scope);
      scope.dispose();
    });
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('an entry takes focus and gives it back at $size', (t) async {
      await t.pumpWidget(app(), size: size);
      expect(focused(t), 'A');
      await t.press('tab');
      expect(focused(t), 'B');
      final entry = fields([Field('X', autofocus: true), Field('Y')]);
      overlayOf(t).insert(entry);
      await t.pump();
      expect(focused(t), 'X');
      expect(t.screen, shows('[X]'));
      final help = t.focusManager.activeBindings.map((b) => b.description);
      expect(help, containsAll(['Next field', 'Previous field', 'Quit']));
      expect(help, isNot(contains('Base x')));
      await t.press('tab');
      expect(focused(t), 'Y');
      await t.press('tab');
      expect(focused(t), 'X');
      entry.remove();
      await t.pump();
      expect(focused(t), 'B');
      expect(t.screen, shows('[B]'));
    });
  }

  testWidgets('base keys are out of reach, app keys are not', (t) async {
    final log = <String>[];
    await t.pumpWidget(app(log: log));
    final entry = fields([Text('no fields')]);
    overlayOf(t).insert(entry);
    await t.pump();
    expect(t.focusManager.primaryFocus, isA<FocusScopeNode>());
    await t.press('x');
    await t.press('ctrl+q');
    expect(log, ['quit']);
    entry.remove();
    await t.pump();
    await t.press('x');
    expect(log, ['quit', 'base x']);
  });

  testWidgets('a pending chord ends when focus changes scope', (t) async {
    final log = <String>[];
    await t.pumpWidget(app(log: log));
    await t.press('ctrl+x');
    expect(t.focusManager.pendingChord, isNotEmpty);
    overlayOf(t).insert(fields([Field('X', autofocus: true)]));
    await t.pump();
    expect(t.focusManager.pendingChord, isEmpty);
    await t.press('a');
    expect(log, isEmpty);
  });

  testWidgets('a gone saved node falls back to the most recent one', (t) async {
    final showB = ValueNotifier(true);
    await t.pumpWidget(
      app(
        base: [
          Field('A', autofocus: true),
          ListenableBuilder(
            listenable: showB,
            builder: (_) => showB.value ? Field('B') : const SizedBox(),
          ),
        ],
      ),
    );
    await t.press('tab');
    expect(focused(t), 'B');
    final entry = fields([Field('X', autofocus: true)]);
    overlayOf(t).insert(entry);
    await t.pump();
    showB.value = false;
    await t.pump();
    expect(focused(t), 'X');
    entry.remove();
    await t.pump();
    expect(focused(t), 'A');
  });

  testWidgets('with nothing to go back to, focus is cleared', (t) async {
    await t.pumpWidget(app(base: [Text('no fields')]));
    final entry = fields([Field('X', autofocus: true)]);
    overlayOf(t).insert(entry);
    await t.pump();
    expect(focused(t), 'X');
    entry.remove();
    await t.pump();
    expect(t.focusManager.primaryFocus, isNull);
  });

  testWidgets('nested entries give focus back in stack order', (t) async {
    await t.pumpWidget(app());
    final overlay = overlayOf(t);
    final e1 = fields([Field('X', autofocus: true)]);
    final e2 = fields([Field('Z', autofocus: true)]);
    overlay.insert(e1);
    await t.pump();
    overlay.insert(e2);
    await t.pump();
    expect(focused(t), 'Z');
    e2.remove();
    await t.pump();
    expect(focused(t), 'X');
    e1.remove();
    await t.pump();
    expect(focused(t), 'A');
  });

  testWidgets('closing a covered entry leaves the top one focused', (t) async {
    await t.pumpWidget(app());
    final overlay = overlayOf(t);
    final e1 = fields([Field('X', autofocus: true)]);
    final e2 = fields([Field('Z', autofocus: true)]);
    overlay.insert(e1);
    await t.pump();
    overlay.insert(e2);
    await t.pump();
    e1.remove();
    await t.pump();
    expect(focused(t), 'Z');
    e2.remove();
    await t.pump();
    expect(focused(t), 'A', reason: 'past the removed entry, to its origin');
  });

  testWidgets('a passive entry leaves focus and Tab to the page', (t) async {
    await t.pumpWidget(app());
    overlayOf(
      t,
    ).insert(fields([Field('X', autofocus: true)], requestFocus: false));
    await t.pump();
    expect(focused(t), 'A');
    expect(t.screen, shows('X'));
    await t.press('tab');
    expect(focused(t), 'B');
    await t.press('tab');
    expect(focused(t), 'A');
    final help = t.focusManager.activeBindings.map((b) => b.description);
    expect(help, isNot(contains('Next field')));
  });

  testWidgets('losing the link or the room suspends the entry', (t) async {
    final log = <String>[];
    final link = LayerLink();
    final row = ValueNotifier(5);
    await t.pumpWidget(app(log: log, link: link, targetRow: row));
    final entry = OverlayEntry(
      builder: (_) => CompositedTransformFollower(
        link: link,
        followerAnchor: Alignment.bottomLeft,
        child: Actions(
          bindings: [Binding('y', 'Entry y', () => log.add('entry y'))],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Field('X'), Field('Y', autofocus: true)],
          ),
        ),
      ),
    );
    overlayOf(t).insert(entry);
    await t.pump();
    expect(focused(t), 'Y');
    await t.press('shift+tab');
    expect(focused(t), 'X');

    row.value = -1;
    await t.pump();
    expect(focused(t), 'A');
    expect(t.screen, isNot(shows('X')));
    await t.press('y');
    expect(log, isEmpty);

    row.value = 5;
    await t.pump();
    expect(focused(t), 'X', reason: 'back where it was');
    await t.press('y');
    expect(log, ['entry y']);
  });

  testWidgets('no room suspends the entry until rows come back', (t) async {
    final link = LayerLink();
    final showA = ValueNotifier(true);
    await t.pumpWidget(
      app(
        base: [
          ListenableBuilder(
            listenable: showA,
            builder: (_) =>
                showA.value ? Field('A', autofocus: true) : const SizedBox(),
          ),
        ],
        link: link,
        targetRow: ValueNotifier(0),
      ),
    );
    overlayOf(t).insert(
      OverlayEntry(
        builder: (_) => CompositedTransformFollower(
          link: link,
          followerAnchor: Alignment.bottomLeft,
          child: Field('X', autofocus: true),
        ),
      ),
    );
    await t.pump();
    // The target is at row 1, under A: one row of room.
    expect(focused(t), 'X');
    showA.value = false;
    await t.pump();
    // At row 0 there is no row above it: nothing shows, nothing is focused.
    expect(t.screen.text, isNot(contains('X')));
    expect(t.focusManager.primaryFocus, isNull);
    showA.value = true;
    await t.pump();
    expect(focused(t), 'X');
  });

  testWidgets('a newer focused entry keeps focus when an older relinks', (
    t,
  ) async {
    final link = LayerLink();
    final row = ValueNotifier(5);
    await t.pumpWidget(app(link: link, targetRow: row));
    final overlay = overlayOf(t);
    overlay.insert(
      OverlayEntry(
        builder: (_) => CompositedTransformFollower(
          link: link,
          followerAnchor: Alignment.bottomLeft,
          child: Field('X', autofocus: true),
        ),
      ),
    );
    await t.pump();
    expect(focused(t), 'X');
    row.value = -1;
    await t.pump();
    expect(focused(t), 'A');
    overlay.insert(fields([Field('Z', autofocus: true)]));
    await t.pump();
    expect(focused(t), 'Z');
    row.value = 5;
    await t.pump();
    expect(focused(t), 'Z');
  });

  testWidgets('a follower under a wrapper suspends the entry too', (t) async {
    final log = <String>[];
    final link = LayerLink();
    final row = ValueNotifier(5);
    await t.pumpWidget(app(log: log, link: link, targetRow: row));
    overlayOf(t).insert(
      OverlayEntry(
        builder: (_) => Padding(
          padding: EdgeInsets.zero,
          child: CompositedTransformFollower(
            link: link,
            followerAnchor: Alignment.bottomLeft,
            child: Actions(
              bindings: [Binding('y', 'Entry y', () => log.add('entry y'))],
              child: Field('X', autofocus: true),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    expect(focused(t), 'X');
    // Unlinked: hidden, and neither focus nor its keys stay in it.
    row.value = -1;
    await t.pump();
    expect(focused(t), 'A');
    await t.press('y');
    expect(log, isEmpty);
    row.value = 5;
    await t.pump();
    expect(focused(t), 'X');
  });

  testWidgets('a follower under a wrapper with no room takes no focus', (
    t,
  ) async {
    final link = LayerLink();
    await t.pumpWidget(
      app(
        base: [Field('A', autofocus: true)],
        link: link,
        targetRow: ValueNotifier(0),
      ),
    );
    // Anchored below the window: no rows at all.
    overlayOf(t).insert(
      OverlayEntry(
        builder: (_) => Padding(
          padding: EdgeInsets.zero,
          child: CompositedTransformFollower(
            link: link,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 99),
            child: Field('X', autofocus: true),
          ),
        ),
      ),
    );
    await t.pump();
    expect(t.screen, isNot(shows('X')));
    expect(focused(t), 'A');
  });

  testWidgets('a disposed node is never focused or traversed to', (t) async {
    final b = FocusNode(debugLabel: 'B');
    await t.pumpWidget(
      app(
        base: [
          Field('A', autofocus: true),
          Focus(focusNode: b, child: Text('B')),
          Field('C'),
        ],
      ),
    );
    await t.press('tab');
    expect(focused(t), 'B');
    final entry = fields([Field('X', autofocus: true)]);
    overlayOf(t).insert(entry);
    await t.pump();
    // Disposed while still in the tree: it can never take focus again.
    b.dispose();
    entry.remove();
    await t.pump();
    expect(focused(t), 'A');
    await t.press('tab');
    expect(focused(t), 'C');
    await t.press('tab');
    expect(focused(t), 'A');
  });

  testWidgets('an unlinked follower with an empty child lets go of focus', (
    t,
  ) async {
    final log = <String>[];
    final rows = ValueNotifier(0);
    await t.pumpWidget(
      app(log: log, link: LayerLink(), targetRow: ValueNotifier(-1)),
    );
    overlayOf(t).insert(
      OverlayEntry(
        builder: (_) => CompositedTransformFollower(
          link: LayerLink(),
          showWhenUnlinked: true,
          child: Actions(
            bindings: [Binding('y', 'Entry y', () => log.add('entry y'))],
            child: ListenableBuilder(
              listenable: rows,
              builder: (_) => SizedBox(
                height: rows.value,
                child: Field('X', autofocus: true),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    expect(focused(t), 'A');
    await t.press('y');
    expect(log, isEmpty);
    rows.value = 1;
    await t.pump();
    expect(focused(t), 'X');
    await t.press('y');
    expect(log, ['entry y']);
  });
}

void testerEdges() {
  group('tester: overlay focus lifecycle edges', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('closing resets an entry chord before base keys at $size', (
        t,
      ) async {
        final log = <String>[];
        await t.pumpWidget(app(log: log), size: size);
        final entry = OverlayEntry(
          builder: (_) => Actions(
            bindings: [
              Binding('ctrl+x a', 'Layer chord', () => log.add('layer')),
            ],
            child: Field('X', autofocus: true),
          ),
        );
        overlayOf(t).insert(entry);
        await t.pump();
        await t.press('ctrl+x');
        expect(t.focusManager.pendingChord, isNotEmpty);
        entry.remove();
        await t.pump();
        expect(t.focusManager.pendingChord, isEmpty);
        await t.press('a');
        expect(log, isEmpty);
        await t.press('ctrl+x a');
        expect(log, ['chord']);
      });

      testWidgets('focused scope survives a thousand invalidations at $size', (
        t,
      ) async {
        await t.pumpWidget(app(), size: size);
        final entry = fields([Field('X', autofocus: true), Field('Y')]);
        overlayOf(t).insert(entry);
        await t.pump();
        await t.press('tab');
        final node = t.focusManager.primaryFocus;
        final scope = node!.parent;
        for (var i = 0; i < 1000; i++) {
          entry.markNeedsBuild();
        }
        await t.pump();
        expect(t.focusManager.primaryFocus, same(node));
        expect(node.parent, same(scope));
        await t.press('shift+tab');
        expect(focused(t), 'X');
        await t.press('tab');
        expect(focused(t), 'Y');
      });

      testWidgets(
        'passive follower preserves editing through relink and resize at $size',
        (t) async {
          final editing = TextEditingController();
          final prompt = FocusNode(debugLabel: 'prompt');
          final present = ValueNotifier(true);
          addTearDown(editing.dispose);
          addTearDown(prompt.dispose);
          addTearDown(present.dispose);
          final link = LayerLink();
          final layer = OverlayEntry(
            requestFocus: false,
            builder: (_) => CompositedTransformFollower(
              link: link,
              followerAnchor: Alignment.topLeft,
              child: Field('passive', autofocus: true),
            ),
          );
          await t.pumpWidget(
            Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => Column(
                    children: [
                      TextInput(
                        controller: editing,
                        focusNode: prompt,
                        autofocus: true,
                      ),
                      ListenableBuilder(
                        listenable: present,
                        builder: (_) => present.value
                            ? CompositedTransformTarget(
                                link: link,
                                child: const SizedBox(height: 0),
                              )
                            : const SizedBox(),
                      ),
                    ],
                  ),
                ),
                layer,
              ],
            ),
            size: size,
          );
          await t.paste('界🙂e\u0301');
          for (final linked in [false, true]) {
            present.value = linked;
            await t.pump();
            expect(t.focusManager.primaryFocus, prompt);
            await t.resize(const Size(1, 1));
            await t.resize(size);
            expect(t.focusManager.primaryFocus, prompt);
          }
          await t.press('left');
          await t.press('right');
          await t.paste('!');
          expect(editing.text, '界🙂e\u0301!');
          layer.remove();
          await t.pump();
          expect(t.focusManager.primaryFocus, prompt);
        },
      );

      testWidgets(
        'zero-sized focused entry restores and reclaims focus at $size',
        (t) async {
          await t.pumpWidget(app(), size: size);
          final entry = fields([Field('X', autofocus: true)]);
          overlayOf(t).insert(entry);
          await t.pump();
          expect(focused(t), 'X');
          await t.resize(Size.zero);
          expect(focused(t), isNot('X'));
          expect(
            t.focusManager.activeBindings.map((b) => b.description),
            isNot(contains('Next field')),
          );
          expect(t.focusManager.pendingChord, isEmpty);
          await t.resize(const Size(1, 1));
          expect(focused(t), 'X');
          await t.resize(size);
          expect(focused(t), 'X');
          entry.remove();
          await t.pump();
          expect(focused(t), 'A');
        },
      );
    }

    testWidgets('closing two covered layers in one frame preserves top focus', (
      t,
    ) async {
      await t.pumpWidget(app());
      final overlay = overlayOf(t);
      final entries = [
        for (final name in ['X', 'Y', 'Z'])
          fields([Field(name, autofocus: true)]),
      ];
      for (final entry in entries) {
        overlay.insert(entry);
        await t.pump();
      }
      entries[1].remove();
      entries[0].remove();
      await t.pump();
      expect(focused(t), 'Z');
      entries[2].remove();
      await t.pump();
      expect(focused(t), 'A');
    });

    testWidgets('an ineligible saved node falls back then rejoins traversal', (
      t,
    ) async {
      final eligible = ValueNotifier(true);
      final node = FocusNode(debugLabel: 'B');
      addTearDown(eligible.dispose);
      addTearDown(node.dispose);
      await t.pumpWidget(
        app(
          base: [
            Field('A', autofocus: true),
            ListenableBuilder(
              listenable: eligible,
              builder: (_) => Focus(
                focusNode: node,
                canRequestFocus: eligible.value,
                child: Text('B'),
              ),
            ),
            Field('C'),
          ],
        ),
      );
      await t.press('tab');
      expect(focused(t), 'B');
      final entry = fields([Field('X', autofocus: true)]);
      overlayOf(t).insert(entry);
      await t.pump();
      eligible.value = false;
      await t.pump();
      entry.remove();
      await t.pump();
      expect(focused(t), 'A');
      await t.press('tab');
      expect(focused(t), 'C');
      eligible.value = true;
      await t.pump();
      await t.press('shift+tab');
      expect(focused(t), 'B');
    });
  });
}

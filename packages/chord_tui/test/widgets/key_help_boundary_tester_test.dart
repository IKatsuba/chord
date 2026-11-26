import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget _snapshot(void Function(List<Binding>, List<KeyCombo>) seen) =>
    KeyHelp.builder(
      builder: (_, bindings, pending) {
        seen(bindings, pending);
        return const SizedBox();
      },
    );

void main() {
  group('tester: key help boundary layout and dispatch', () {
    for (final size in const [
      Size.zero,
      Size(1, 1),
      Size(120, 40),
      Size(80, 24),
      Size(43, 37),
    ]) {
      testWidgets('filtering and dispatch are independent of room at $size', (
        t,
      ) async {
        var inner = <Binding>[];
        var outer = <Binding>[];
        final fired = <String>[];
        await t.pumpWidget(
          Actions(
            bindings: [Binding('g', 'Host', () => fired.add('host'))],
            child: Column(
              children: [
                Expanded(
                  child: KeyHelpBoundary(
                    taken: {KeyCombo.parse('ctrl+q')},
                    child: Actions(
                      bindings: [
                        Binding('x', '界🙂e\u0301', () => fired.add('inner')),
                        Binding('ctrl+q', 'Quit', () => fired.add('taken')),
                      ],
                      child: Focus(
                        autofocus: true,
                        child: Column(
                          children: [
                            _snapshot((bindings, _) => inner = bindings),
                            const KeyHelp(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _snapshot((bindings, _) => outer = bindings),
              ],
            ),
          ),
          size: size,
        );
        expect(inner.map((b) => b.description), ['界🙂e\u0301']);
        expect(outer.map((b) => b.description), ['界🙂e\u0301', 'Host']);
        expect(() => inner.clear(), throwsUnsupportedError);
        if (size.width >= 43) expect(t.screen, shows('x 界🙂e\u0301'));
        await t.press('g');
        await t.press('x');
        await t.press('ctrl+q');
        expect(fired, ['host', 'inner', 'taken']);
      });
    }

    testWidgets('an unbounded help row keeps only its embedded bindings', (
      t,
    ) async {
      await t.pumpWidget(
        Actions(
          bindings: [Binding('g', 'Host', () {})],
          child: Row(
            children: [
              Column(
                children: [
                  KeyHelpBoundary(
                    child: Actions(
                      bindings: [Binding('x', 'Inner', () {})],
                      child: const Focus(autofocus: true, child: KeyHelp()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      expect(t.screen.text, 'x Inner');
    });
  });

  group('tester: key help boundary live ownership', () {
    testWidgets('focus outside empties inside help and returning restores it', (
      t,
    ) async {
      final innerFocus = FocusNode();
      final outerFocus = FocusNode();
      addTearDown(innerFocus.dispose);
      addTearDown(outerFocus.dispose);
      var listed = <Binding>[];
      await t.pumpWidget(
        Actions(
          bindings: [Binding('g', 'Host', () {})],
          child: Column(
            children: [
              Focus(focusNode: outerFocus, child: Text('outside')),
              KeyHelpBoundary(
                child: Actions(
                  bindings: [Binding('x', 'Inner', () {})],
                  child: Focus(
                    focusNode: innerFocus,
                    autofocus: true,
                    child: _snapshot((bindings, _) => listed = bindings),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      expect(listed.map((b) => b.description), ['Inner']);
      outerFocus.requestFocus();
      await t.pump();
      expect(listed, isEmpty);
      innerFocus.requestFocus();
      await t.pump();
      expect(listed.map((b) => b.description), ['Inner']);
    });

    testWidgets('taken changes during a pending chord affect help only', (
      t,
    ) async {
      final taken = ValueNotifier<Set<KeyCombo>>(const {});
      addTearDown(taken.dispose);
      var inner = <Binding>[];
      var innerPending = <KeyCombo>[];
      var outer = <Binding>[];
      var outerPending = <KeyCombo>[];
      var fired = 0;
      final cached = Actions(
        bindings: [Binding('ctrl+x a', 'Inner', () => fired++)],
        child: Focus(
          autofocus: true,
          child: _snapshot((bindings, pending) {
            inner = bindings;
            innerPending = pending;
          }),
        ),
      );
      await t.pumpWidget(
        Actions(
          bindings: [Binding('g', 'Host', () {})],
          child: Column(
            children: [
              ListenableBuilder(
                listenable: taken,
                builder: (_) =>
                    KeyHelpBoundary(taken: taken.value, child: cached),
              ),
              _snapshot((bindings, pending) {
                outer = bindings;
                outerPending = pending;
              }),
            ],
          ),
        ),
      );
      await t.press('ctrl+x');
      expect(innerPending.map((k) => k.toString()), ['ctrl+x']);
      for (var i = 0; i < 1000; i++) {
        taken.value = i.isEven ? const {} : {KeyCombo.parse('ctrl+x')};
      }
      await t.pump();
      expect(inner, isEmpty);
      expect(innerPending, isEmpty);
      expect(outer, isEmpty);
      expect(outerPending, isEmpty);
      expect(t.focusManager.pendingChord.map((k) => k.toString()), ['ctrl+x']);
      taken.value = const {};
      await t.pump();
      expect(inner.map((b) => b.description), ['Inner']);
      expect(innerPending.map((k) => k.toString()), ['ctrl+x']);
      await t.press('a');
      expect(fired, 1);
    });

    testWidgets(
      'removing a boundary leaves chord cancellation with the focus manager',
      (t) async {
        final shown = ValueNotifier(true);
        addTearDown(shown.dispose);
        var listed = <Binding>[];
        await t.pumpWidget(
          Actions(
            bindings: [Binding('x', 'Host', () {})],
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: shown,
                  builder: (_) => shown.value
                      ? KeyHelpBoundary(
                          taken: {KeyCombo.parse('ctrl+x')},
                          child: Actions(
                            bindings: [Binding('ctrl+x a', 'Hidden', () {})],
                            child: const Focus(
                              autofocus: true,
                              child: KeyHelp(),
                            ),
                          ),
                        )
                      : Focus(autofocus: true, child: Text('replacement')),
                ),
                _snapshot((bindings, _) => listed = bindings),
              ],
            ),
          ),
        );
        await t.press('ctrl+x');
        expect(t.focusManager.pendingChord, isNotEmpty);
        shown.value = false;
        await t.pump();
        // Both focus nodes are in the same scope: listing must not change
        // the manager's existing rule for when a chord is cancelled.
        expect(t.focusManager.pendingChord, isNotEmpty);
        expect(listed, isEmpty);
        await t.press('esc');
        expect(t.focusManager.pendingChord, isEmpty);
        expect(listed.map((b) => b.description), ['Host']);
        await t.resize(const Size(43, 37));
        expect(listed.map((b) => b.description), ['Host']);
      },
    );
  });
}

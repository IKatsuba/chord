import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/selection.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  for (final spelling in ['v c', 'ctrl+x ctrl+c']) {
    test('semantic copy $spelling precedes form and modal shadowing', () {
      final manager = FocusManager();
      var kind = SelectionKind.shown;
      var copied = 0, cleared = 0, typed = 0, shadowed = 0;
      KeyContext context() => KeyContext(
        state: const AppState(),
        history: const history.History(),
        rows: 24,
        selection: kind,
      );
      final selected = selectionCopyBinding(context, (steps) {
        expect(steps.single, isA<CopySelection>());
        copied++;
      }, keys: spelling);
      final bindings = windowBindings(context, (_) {}, selectionCopy: selected);
      final outer = FocusNode()
        ..attach(manager.root)
        ..bindings = bindings;
      final modal =
          FocusNode(
              onKey: (_) {
                typed++;
                return true;
              },
            )
            ..attach(outer)
            ..bindings = [Binding(spelling, 'Shadow', () => shadowed++)]
            ..requestFocus();
      outer.onKeyCapture = (event) => selectionKeyCapture(
        event,
        manager: manager,
        selectionCopy: selected,
        ordinaryCtrlC: bindings.singleWhere(
          (b) => b.chord == Chord.parse('ctrl+c'),
        ),
        bindings: bindings,
        context: context,
        clearSelection: () {
          cleared++;
          kind = SelectionKind.none;
        },
      );
      for (final combo in Chord.parse(spelling).combos) {
        manager.dispatchKey(combo.toEvent());
      }
      expect((copied, cleared, typed, shadowed), (1, 0, 0, 0));
      expect(manager.pendingChord, isEmpty);
      manager.dispatchKey(const KeyEvent('z'));
      expect((copied, cleared, typed, shadowed), (1, 1, 1, 0));
      modal.dispose();
      outer.dispose();
      manager.dispose();
    });
  }

  test(
    'pending default CtrlC cancels prefix and executes ordinary policy fresh',
    () {
      final manager = FocusManager();
      var kind = SelectionKind.shown;
      var draft = 'draft';
      var copied = 0, clears = 0;
      KeyContext context() => KeyContext(
        state: AppState(draft: draft),
        history: const history.History(),
        rows: 24,
        selection: kind,
      );
      void play(List<Step> steps) {
        if (steps.any((s) => s is CopySelection)) copied++;
        if (steps.any((s) => s is ShowDraft)) draft = '';
      }

      final selected = selectionCopyBinding(context, play);
      final bindings = windowBindings(context, play, selectionCopy: selected);
      final node = FocusNode()
        ..attach(manager.root)
        ..bindings = bindings
        ..requestFocus();
      node.onKeyCapture = (event) => selectionKeyCapture(
        event,
        manager: manager,
        selectionCopy: selected,
        ordinaryCtrlC: bindings.singleWhere(
          (b) => b.chord == Chord.parse('ctrl+c'),
        ),
        bindings: bindings,
        context: context,
        clearSelection: () {
          kind = SelectionKind.none;
          clears++;
        },
      );
      manager.dispatchKey(const KeyEvent('x', ctrl: true));
      expect(manager.pendingChord, isNotEmpty);
      expect(kind, SelectionKind.shown);
      manager.dispatchKey(const KeyEvent('c', ctrl: true));
      expect(manager.pendingChord, isEmpty);
      expect(draft, isEmpty);
      expect(copied, 0);
      expect(clears, greaterThanOrEqualTo(1));
      node.dispose();
      manager.dispose();
    },
  );
}

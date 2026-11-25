import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/selection.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';
import 'keys_test.dart' show waiting;

class Harness {
  Harness(
    this.selection, {
    this.copyKeys = 'ctrl+shift+c',
    this.state = const AppState(draft: 'draft'),
  }) {
    final selected = selectionCopyBinding(context, play, keys: copyKeys);
    final picked = codePickBindings(context, play);
    final bindings = windowBindings(
      context,
      play,
      selectionCopy: selected,
      pickedBindings: picked,
    );
    outer = FocusNode()
      ..attach(manager.root)
      ..bindings = bindings;
    form =
        FocusNode(
            onKey: (event) {
              if (event.char != null && !event.ctrl && !event.alt) {
                typed.add(event.char!);
                beforeTyping = (selection, picking);
                return true;
              }
              if (['up', 'down', 'escape'].contains(event.key)) {
                modal++;
                return true;
              }
              return false;
            },
          )
          ..attach(outer)
          ..bindings = [
            Binding('c', 'Modal choice', () => modal++),
            Binding('esc', 'Leave modal', () => modal++),
          ]
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
      clearSelection: () => selection = SelectionKind.none,
      endPicking: () => picking = false,
      pickedBindings: picked,
    );
  }
  final manager = FocusManager();
  late final FocusNode outer, form;
  final String copyKeys;
  SelectionKind selection;
  AppState state;
  bool picking = true;
  var modal = 0;
  final effects = <Step>[], typed = <String>[];
  (SelectionKind, bool)? beforeTyping;
  KeyContext context() => KeyContext(
    state: state,
    history: const history.History(),
    rows: 24,
    selection: selection,
    picking: picking,
  );
  void play(List<Step> steps) {
    effects.addAll(steps);
    if (steps.any(
      (s) => s is CopySelection || s is CopyCodePick || s is EndCodePick,
    )) {
      picking = false;
    }
  }

  void press(String keys) {
    for (final combo in Chord.parse(keys).combos) {
      manager.dispatchKey(combo.toEvent());
    }
  }

  void dispose() {
    form.dispose();
    outer.dispose();
    manager.dispose();
  }
}

void main() {
  for (final phase in [SelectionKind.shown, SelectionKind.copying]) {
    for (final keys in ['ctrl+c', 'ctrl+shift+c']) {
      test(
        '$phase selection copy $keys wins over real picking and form/modal',
        () {
          final h = Harness(phase);
          addTearDown(h.dispose);
          h.press(keys);
          expect(h.effects.single, isA<CopySelection>());
          expect(h.picking, isFalse);
          expect(h.selection, phase);
          expect(h.typed, isEmpty);
          expect(h.modal, 0);
        },
      );
    }
    for (final keys in ['up', 'down', 'c', 'esc']) {
      test(
        '$phase pick action $keys clears range before current mode effect',
        () {
          final h = Harness(phase);
          addTearDown(h.dispose);
          h.press(keys);
          expect(h.selection, SelectionKind.none);
          expect(h.effects.single, switch (keys) {
            'c' => isA<CopyCodePick>(),
            'esc' => isA<EndCodePick>(),
            _ => isA<MoveCodePick>(),
          });
          expect(h.typed, isEmpty);
          expect(h.modal, 0);
        },
      );
    }
  }
  test(
    'pending prefix preserves both, dropped suffix clears both without replay',
    () {
      final h = Harness(SelectionKind.shown);
      addTearDown(h.dispose);
      h.press('ctrl+x');
      expect(h.selection, SelectionKind.shown);
      expect(h.picking, isTrue);
      h.press('z');
      expect(h.selection, SelectionKind.none);
      expect(h.picking, isFalse);
      expect(h.effects, isEmpty);
      expect(h.typed, isEmpty);
      expect(h.manager.pendingChord, isEmpty);
    },
  );
  test('default pending CtrlC clears both before ordinary draft policy', () {
    final h = Harness(SelectionKind.shown);
    addTearDown(h.dispose);
    h.press('ctrl+x ctrl+c');
    expect(h.selection, SelectionKind.none);
    expect(h.picking, isFalse);
    expect(h.effects.first, isA<Dispatch>());
    expect(h.effects.last, isA<ShowDraft>());
    expect(h.effects.any((s) => s is CopySelection), isFalse);
  });
  for (final rebound in ['v c', 'ctrl+x ctrl+c']) {
    test(
      'rebound selection copy $rebound and prefix beat form and picking',
      () {
        final h = Harness(SelectionKind.shown, copyKeys: rebound);
        addTearDown(h.dispose);
        h.press(rebound);
        expect(h.effects.single, isA<CopySelection>());
        expect(h.picking, isFalse);
        expect(h.typed, isEmpty);
        expect(h.modal, 0);
      },
    );
  }
  test('picked r dispatches current run policy without typing', () {
    final h = Harness(SelectionKind.shown);
    addTearDown(h.dispose);
    h.press('r');
    expect(h.selection, SelectionKind.none);
    expect(h.beforeTyping, isNull);
    expect(h.typed, isEmpty);
    expect(h.effects.single, isA<RunCodePick>());
  });
  for (final state in [
    const AppState(),
    waiting(overflow: true),
    waiting(help: true, panelOverflow: true),
  ]) {
    test(
      'scroll ownership ${state.requestOverflows}/${state.shortcuts.help} controls preservation',
      () {
        final h = Harness(SelectionKind.shown, state: state);
        addTearDown(h.dispose);
        h.press('pagedown');
        final transcript = !state.requestOverflows && !state.shortcuts.help;
        expect(
          h.selection,
          transcript ? SelectionKind.shown : SelectionKind.none,
        );
        expect(h.picking, transcript);
        expect(
          h.effects.single,
          transcript
              ? isA<Dispatch>()
              : state.shortcuts.help
              ? isA<ScrollPanel>()
              : isA<ScrollRequest>(),
        );
      },
    );
  }
}

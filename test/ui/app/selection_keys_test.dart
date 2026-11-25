import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/selection.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord/ui/shortcuts/keys.dart' as help;
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

import 'keys_test.dart' show waiting;

void main() {
  KeyContext context(
    SelectionKind selection, [
    AppState state = const AppState(),
  ]) => KeyContext(
    state: state,
    history: const history.History(),
    rows: 24,
    selection: selection,
  );

  test(
    'shown and copying selection own CtrlC before draft and quit effects',
    () {
      for (final kind in [SelectionKind.shown, SelectionKind.copying]) {
        for (final key in ['ctrl+c', 'ctrl+shift+c']) {
          final steps = keySteps(
            Chord.parse(key),
            context(kind, const AppState(draft: 'draft', quitArmed: true)),
          );
          expect(steps.single, isA<CopySelection>());
          expect(preservesSelection(steps), isTrue);
        }
      }
      expect(
        keySteps(Chord.parse('ctrl+shift+c'), context(SelectionKind.none)),
        isEmpty,
      );
      expect(
        keySteps(Chord.parse('ctrl+c'), context(SelectionKind.none)).single,
        isA<Dispatch>(),
      );
    },
  );

  test(
    'only transcript scrolling preserves ranges, request and panel keys clear',
    () {
      for (final key in ['pageup', 'shift+down', 'home', 'end']) {
        expect(
          preservesSelection(
            keySteps(Chord.parse(key), context(SelectionKind.shown)),
          ),
          isTrue,
        );
        expect(
          preservesSelection(
            keySteps(
              Chord.parse(key),
              context(SelectionKind.shown, waiting(overflow: true)),
            ),
          ),
          isFalse,
        );
        expect(
          preservesSelection(
            keySteps(
              Chord.parse(key),
              context(
                SelectionKind.shown,
                waiting(help: true, panelOverflow: true),
              ),
            ),
          ),
          isFalse,
        );
      }
      expect(preservesSelectionPrefix(const KeyEvent('x', ctrl: true)), isTrue);
      expect(preservesSelectionPrefix(const KeyEvent('v')), isFalse);
      expect(preservesSelectionPrefix(const KeyEvent('space')), isFalse);
    },
  );

  test(
    'selection and pick bindings describe current actions without a dormant run action',
    () {
      final bindings = windowBindings(
        () => context(SelectionKind.none),
        (_) {},
      );
      expect(
        bindings
            .singleWhere((b) => b.chord == Chord.parse('ctrl+shift+c'))
            .description,
        'Copy selection',
      );
      expect(help.shortcuts.where((s) => s.does == 'to copy').single.presses, [
        'ctrl+c',
        'ctrl+shift+c',
      ]);
      expect(bindings.any((b) => b.chord == Chord.parse('ctrl+x b')), isTrue);
      expect(bindings.any((b) => b.chord == Chord.parse('r')), isFalse);
      final picked = windowBindings(
        () => const KeyContext(
          state: AppState(),
          history: history.History(),
          rows: 24,
          picking: true,
        ),
        (_) {},
      );
      expect(
        picked.singleWhere((b) => b.chord == Chord.parse('r')).description,
        'Put picked block in the prompt',
      );
      final codeHelp = help.shortcuts.singleWhere((s) => s.key == 'c r');
      expect(codeHelp.does, 'to copy or put in the prompt');
      expect(codeHelp.presses, ['c', 'r']);
    },
  );

  test('selection palettes use original slate and inverse-only plain mode', () {
    expect(chordDark.selection.bg, const IndexedColor(66));
    expect(chordLight.selection.bg, const IndexedColor(152));
    expect(chordPlain.selection.bg, isNull);
    expect(chordPlain.selection.isInverse, isTrue);
  });
}

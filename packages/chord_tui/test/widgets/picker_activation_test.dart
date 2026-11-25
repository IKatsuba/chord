import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

final _items = [
  for (var i = 1; i <= 12; i++) PickerItem(value: i, label: 'Choice $i'),
];

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('disabled picker ignores keys and focus at $size', (t) async {
      final enabled = ValueNotifier(false);
      final node = FocusNode();
      final picks = <int>[];
      var canceled = 0;
      var ancestor = 0;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: enabled,
          builder: (context) => Actions(
            bindings: [Binding('ctrl+x', 'Ancestor', () => ancestor++)],
            child: Column(
              children: [
                Picker<int>(
                  items: _items,
                  enabled: enabled.value,
                  focusNode: node,
                  onSelected: picks.add,
                  onCanceled: () => canceled++,
                  maxVisibleRows: 4,
                ),
                const KeyHelp(),
              ],
            ),
          ),
        ),
        size: size,
      );
      expect(node.hasFocus, isFalse);
      expect(t.screen, isNot(shows('❯')));
      expect(t.screen, shows('1.  Choice 1'));
      expect(t.screen, shows('… +'));
      node.requestFocus();
      await t.pump();
      expect(node.hasFocus, isFalse);
      for (final key in [
        'down',
        'j',
        'k',
        'up',
        '1',
        'enter',
        'esc',
        '/',
        'pageup',
        'pagedown',
        'home',
        'end',
        'tab',
      ]) {
        await t.press(key);
      }
      expect(picks, isEmpty);
      expect(canceled, 0);
      expect(t.focusManager.activeBindings.map((b) => b.description), [
        'Ancestor',
      ]);
      await t.press('ctrl+x');
      expect(ancestor, 1);
      enabled.value = true;
      await t.pump();
      expect(node.hasFocus, isFalse);
      node.requestFocus();
      await t.pump();
      await t.press('down down enter');
      expect(picks, [3]);
      enabled.value = false;
      await t.pump();
      expect(node.hasFocus, isFalse);
      expect(t.screen, isNot(shows('❯')));
      enabled.value = true;
      await t.pump();
      expect(node.hasFocus, isFalse);
      node.requestFocus();
      await t.pump();
      await t.press('enter');
      expect(picks, [3, 3]);
      t.dispose();
      expect(node.isDisposed, isFalse);
      enabled.dispose();
      node.dispose();
    });

    testWidgets(
      'disable filter keeps query and selection without stealing focus at $size',
      (t) async {
        final enabled = ValueNotifier(true);
        final node = FocusNode();
        final picks = <int>[];
        await t.pumpWidget(
          ListenableBuilder(
            listenable: enabled,
            builder: (context) => Picker<int>(
              items: _items,
              enabled: enabled.value,
              focusNode: node,
              searchable: true,
              onSelected: picks.add,
              onCanceled: () {},
            ),
          ),
          size: size,
        );
        await t.press('/');
        await t.type('Choice 2');
        expect(t.screen, shows('Filter: Choice 2'));
        expect(node.hasFocus, isTrue);
        enabled.value = false;
        await t.pump();
        expect(node.hasFocus, isFalse);
        expect(t.screen, shows('Filter: Choice 2'));
        expect(t.screen, isNot(shows('❯')));
        node.requestFocus();
        await t.pump();
        expect(node.hasFocus, isFalse);
        await t.type('X');
        enabled.value = true;
        await t.pump();
        expect(node.hasFocus, isFalse);
        expect(t.screen, shows('Filter: Choice 2'));
        node.requestFocus();
        await t.pump();
        await t.press('enter');
        expect(picks, [2]);
        t.dispose();
        enabled.dispose();
        node.dispose();
      },
    );
  }

  testWidgets(
    'supplied focus nodes detach on replacement and remain caller owned',
    (t) async {
      var first = FocusNode();
      final second = FocusNode();
      final which = ValueNotifier<FocusNode?>(first);
      final picks = <int>[];
      await t.pumpWidget(
        ListenableBuilder(
          listenable: which,
          builder: (context) => Picker<int>(
            items: _items,
            focusNode: which.value,
            onSelected: picks.add,
            onCanceled: () {},
          ),
        ),
      );
      expect(first.hasFocus, isTrue);
      which.value = second;
      await t.pump();
      expect(first.attached, isFalse);
      expect(second.hasFocus, isTrue);
      expect(first.isDisposed, isFalse);
      first.dispose();
      await t.press('2');
      expect(picks, [2]);
      which.value = null;
      await t.pump();
      expect(second.attached, isFalse);
      expect(second.isDisposed, isFalse);
      await t.press('3');
      expect(picks, [2, 3]);
      which.value = first = FocusNode();
      await t.pump();
      await t.press('4');
      expect(picks, [2, 3, 4]);
      t.dispose();
      expect(first.attached, isFalse);
      expect(first.isDisposed, isFalse);
      first.dispose();
      second.dispose();
      which.dispose();
    },
  );
}

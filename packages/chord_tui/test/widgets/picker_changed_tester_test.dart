import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _items = [
  PickerItem(value: 'a', label: '界🙂e\u0301\x1b[31mA\x1b[0m'),
  PickerItem(value: 'b', label: '🙂界e\u0301\x1b[32mB\x1b[0m'),
  PickerItem(value: 'c', label: 'e\u0301界🙂C'),
];

void main() {
  group('tester highlight notification boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('tiny resizes and unbounded layout preserve value at $size', (
        t,
      ) async {
        final changed = <String>[];
        final selected = <String>[];
        await t.pumpWidget(
          Column(
            children: [
              Picker<String>(
                items: _items,
                onChanged: changed.add,
                onSelected: selected.add,
                onCanceled: () {},
                maxVisibleRows: 3,
              ),
            ],
          ),
          size: size,
        );
        await t.press('down');
        expect(changed, ['b']);
        for (final tiny in const [Size(1, 1), Size(0, 0), Size(7, 3)]) {
          await t.resize(tiny);
          expect(changed, ['b']);
        }
        await t.resize(size);
        await t.press('enter');
        expect(selected, ['b']);
        expect(changed, ['b']);
        expect(t.screen.text, isNot(contains('\x1b')));
        await t.press('down');
        expect(changed, ['b', 'c']);
      });

      testWidgets('callback focus transfer preserves highlight at $size', (
        t,
      ) async {
        final picker = FocusNode();
        final outside = FocusNode();
        final changed = <String>[];
        final selected = <String>[];
        await t.pumpWidget(
          Column(
            children: [
              Picker<String>(
                items: _items,
                focusNode: picker,
                onChanged: (value) {
                  changed.add(value);
                  outside.requestFocus();
                },
                onSelected: selected.add,
                onCanceled: () {},
              ),
              Focus(focusNode: outside, child: Text('Outside')),
            ],
          ),
          size: size,
        );
        await t.press('down');
        expect(outside.hasFocus, isTrue);
        await t.press('down enter');
        expect(changed, ['b']);
        expect(selected, isEmpty);
        picker.requestFocus();
        await t.pump();
        await t.press('enter');
        expect(selected, ['b']);
        expect(changed, ['b']);
        t.dispose();
        picker.dispose();
        outside.dispose();
      });
    }

    testWidgets('a reentrant key sees the already updated semantic highlight', (
      t,
    ) async {
      final changed = <String>[];
      final selected = <String>[];
      await t.pumpWidget(
        Picker<String>(
          items: _items,
          onChanged: (value) {
            changed.add(value);
            if (value == 'b') t.host.handleKey(const KeyEvent('down'));
          },
          onSelected: selected.add,
          onCanceled: () {},
        ),
      );
      await t.press('down');
      expect(changed, ['b', 'c']);
      await t.press('enter');
      expect(selected, ['c']);
      expect(changed, ['b', 'c']);
    });

    testWidgets('a thousand reconciliations emit only the final highlight', (
      t,
    ) async {
      final items = ValueNotifier<List<PickerItem<int>>>([
        const PickerItem(value: 0, label: 'Initial'),
      ]);
      final changed = <int>[];
      await t.pumpWidget(
        ListenableBuilder(
          listenable: items,
          builder: (_) => Picker<int>(
            items: items.value,
            onChanged: changed.add,
            onSelected: (_) {},
            onCanceled: () {},
          ),
        ),
      );
      for (var i = 1; i <= 1000; i++) {
        items.value = [PickerItem(value: i, label: 'Choice $i')];
        t.host.owner.buildScope();
      }
      expect(changed, isEmpty);
      await t.pump();
      expect(changed, [1000]);
      await t.pump();
      expect(changed, [1000]);
      t.dispose();
      items.dispose();
    });
  });
}

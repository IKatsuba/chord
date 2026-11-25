import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

List<PickerItem<String>> _items(List<String> values) => [
  for (final value in values) PickerItem(value: value, label: value),
];

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('highlight changes preview without accepting at $size', (
      t,
    ) async {
      final changed = <String>[];
      final selected = <String>[];
      await t.pumpWidget(
        Picker<String>(
          items: _items(['one', 'two', 'three']),
          onChanged: changed.add,
          onSelected: selected.add,
          onCanceled: () {},
        ),
        size: size,
      );
      expect(changed, isEmpty);
      await t.press('up');
      expect(changed, isEmpty);
      await t.press('down');
      await t.press('j');
      await t.press('down');
      expect(changed, ['two', 'three']);
      await t.press('enter');
      await t.press('1');
      expect(selected, ['three', 'one']);
      expect(changed, ['two', 'three']);
      await t.press('k');
      expect(changed, ['two', 'three', 'two']);
      await t.resize(const Size(30, 8));
      await t.resize(size);
      expect(changed, ['two', 'three', 'two']);
    });

    testWidgets(
      'filter keeps equal values and reports empty recovery at $size',
      (t) async {
        final changed = <String>[];
        await t.pumpWidget(
          Picker<String>(
            items: _items(['apple', 'banana']),
            searchable: true,
            onChanged: changed.add,
            onSelected: (_) {},
            onCanceled: () {},
          ),
          size: size,
        );
        await t.press('/');
        await t.type('a');
        expect(changed, isEmpty);
        await t.type('n');
        expect(changed, ['banana']);
        await t.type('z');
        expect(changed, ['banana']);
        await t.press('backspace');
        expect(changed, ['banana', 'banana']);
      },
    );

    testWidgets('tall-row scrolling does not report a new value at $size', (
      t,
    ) async {
      final changed = <String>[];
      await t.pumpWidget(
        Picker<String>(
          items: _items(['first\nsecond\nthird\nfourth', 'next']),
          maxVisibleRows: 2,
          onChanged: changed.add,
          onSelected: (_) {},
          onCanceled: () {},
          itemBuilder: (_, item, _) => Text(item.label),
        ),
        size: size,
      );
      await t.press('down');
      expect(changed, isEmpty);
      await t.press('down');
      expect(changed, isEmpty);
      await t.press('down');
      expect(changed, ['next']);
    });
  }

  testWidgets(
    'item reconciliation defers, coalesces and uses current callback',
    (t) async {
      final items = ValueNotifier(_items(['a', 'b']));
      final changed = <String>[];
      final callback = ValueNotifier<void Function(String)>(changed.add);
      var building = false;
      await t.pumpWidget(
        ListenableBuilder(
          listenable: items,
          builder: (_) {
            building = true;
            final picker = ListenableBuilder(
              listenable: callback,
              builder: (_) => Picker<String>(
                items: items.value,
                onChanged: (v) {
                  expect(building, isFalse);
                  callback.value(v);
                },
                onSelected: (_) {},
                onCanceled: () {},
              ),
            );
            building = false;
            return picker;
          },
        ),
      );
      items.value = _items(['b']);
      t.host.owner.buildScope();
      expect(changed, isEmpty);
      items.value = _items(['a', 'b']);
      t.host.owner.buildScope();
      await t.pump();
      // Reconciliation retained b when a returned; only the final b is new.
      expect(changed, ['b']);
      items.value = _items(['c']);
      t.host.owner.buildScope();
      callback.value = (v) => changed.add('current $v');
      await t.pump();
      expect(changed, ['b', 'current c']);
      items.value = _items(['c', 'd']);
      await t.pump();
      items.value = _items(['d', 'c']);
      await t.pump();
      expect(changed, ['b', 'current c']);
      t.dispose();
      items.dispose();
      callback.dispose();
    },
  );

  testWidgets('reconciliation returning to the original value emits nothing', (
    t,
  ) async {
    final items = ValueNotifier(_items(['a']));
    final changed = <String>[];
    await t.pumpWidget(
      ListenableBuilder(
        listenable: items,
        builder: (_) => Picker<String>(
          items: items.value,
          onChanged: changed.add,
          onSelected: (_) {},
          onCanceled: () {},
        ),
      ),
    );
    items.value = _items(['b']);
    t.host.owner.buildScope();
    items.value = _items(['a']);
    t.host.owner.buildScope();
    await t.pump();
    expect(changed, isEmpty);
    t.dispose();
    items.dispose();
  });

  testWidgets('nullable choices report only non-null highlight changes', (
    t,
  ) async {
    final changed = <String?>[];
    await t.pumpWidget(
      Picker<String?>(
        items: const [
          PickerItem(value: null, label: 'None'),
          PickerItem(value: 'b', label: 'B'),
        ],
        onChanged: changed.add,
        onSelected: (_) {},
        onCanceled: () {},
      ),
    );
    expect(changed, isEmpty);
    await t.press('down');
    expect(changed, ['b']);
    await t.press('up');
    expect(changed, ['b']);
    await t.press('down');
    expect(changed, ['b', 'b']);
  });

  testWidgets('empty and removal invalidate queued notifications', (t) async {
    final items = ValueNotifier(_items(['a']));
    final visible = ValueNotifier(true);
    final changed = <String>[];
    await t.pumpWidget(
      ListenableBuilder(
        listenable: visible,
        builder: (_) => visible.value
            ? ListenableBuilder(
                listenable: items,
                builder: (_) => Picker<String>(
                  items: items.value,
                  onChanged: changed.add,
                  onSelected: (_) {},
                  onCanceled: () {},
                ),
              )
            : Text('removed'),
      ),
    );
    items.value = _items(['b']);
    t.host.owner.buildScope();
    items.value = [];
    t.host.owner.buildScope();
    await t.pump();
    expect(changed, isEmpty);
    items.value = _items(['a']);
    await t.pump();
    expect(changed, ['a']);
    items.value = _items(['b']);
    t.host.owner.buildScope();
    visible.value = false;
    await t.pump();
    expect(changed, ['a']);
    t.dispose();
    items.dispose();
    visible.dispose();
  });

  testWidgets('preview can rebuild items or remove the picker reentrantly', (
    t,
  ) async {
    final items = ValueNotifier(_items(['a', 'b', 'c']));
    final visible = ValueNotifier(true);
    final changed = <String>[];
    await t.pumpWidget(
      ListenableBuilder(
        listenable: visible,
        builder: (_) => visible.value
            ? ListenableBuilder(
                listenable: items,
                builder: (_) => Picker<String>(
                  items: items.value,
                  onChanged: (v) {
                    changed.add(v);
                    if (v == 'b') {
                      items.value = _items(['b', 'c']);
                    } else {
                      visible.value = false;
                    }
                  },
                  onSelected: (_) {},
                  onCanceled: () {},
                ),
              )
            : Text('removed'),
      ),
    );
    await t.press('down');
    expect(changed, ['b']);
    await t.press('down');
    expect(changed, ['b', 'c']);
    expect(t.screen, shows('removed'));
    t.dispose();
    items.dispose();
    visible.dispose();
  });

  testWidgets('enable and initial seed updates do not notify or reset', (
    t,
  ) async {
    final enabled = ValueNotifier(true);
    final changed = <String>[];
    await t.pumpWidget(
      ListenableBuilder(
        listenable: enabled,
        builder: (_) => Picker<String>(
          items: _items(['a', 'b']),
          initialValue: enabled.value ? 'a' : 'b',
          enabled: enabled.value,
          onChanged: changed.add,
          onSelected: (_) {},
          onCanceled: () {},
        ),
      ),
    );
    enabled.value = false;
    await t.pump();
    enabled.value = true;
    await t.pump();
    expect(changed, isEmpty);
    await t.press('down');
    expect(changed, ['b']);
    t.dispose();
    enabled.dispose();
  });
}

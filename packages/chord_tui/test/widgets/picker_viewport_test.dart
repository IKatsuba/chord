import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  final items = [
    for (var i = 1; i <= 20; i++) PickerItem(value: i, label: 'Choice $i'),
  ];
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final initial in [4, 18]) {
      testWidgets(
        'optional initial viewport reveals $initial minimally at $size',
        (t) async {
          final picks = <int>[];
          await t.pumpWidget(
            Picker<int>(
              items: items,
              initialValue: initial,
              maxVisibleRows: 7,
              showInitialSelectionAtTop: false,
              countHiddenItemsAbove: true,
              onSelected: picks.add,
              onCanceled: () {},
            ),
            size: size,
          );
          expect(t.screen.text, contains('Choice $initial'));
          if (initial == 4) expect(t.screen.text, contains('Choice 1\n'));
          expect(t.screen.text, contains('… +14 more'));
          await t.press('enter');
          expect(picks, [initial]);
          await t.resize(const Size(80, 24));
          if (initial == 4) expect(t.screen, shows('Choice 1'));
          await t.resize(const Size(30, 8));
          await t.press('enter');
          expect(picks, [initial, initial]);
          await t.press(
            'down down down down down down down down down down down down down down down down down down down down',
          );
          expect(t.screen.text, contains('Choice 20'));
          expect(t.screen.text, contains('… +14 more'));
        },
      );
    }
    testWidgets(
      'zero first viewport preserves optional opening policy at $size',
      (t) async {
        await t.pumpWidget(
          Picker<int>(
            items: items,
            initialValue: 4,
            maxVisibleRows: 7,
            showInitialSelectionAtTop: false,
            countHiddenItemsAbove: true,
            onSelected: (_) {},
            onCanceled: () {},
          ),
          size: const Size(0, 0),
        );
        await t.resize(size);
        expect(t.screen.text, contains('Choice 1\n'));
        expect(t.screen.text, contains('Choice 4'));
      },
    );
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'equivalent items and count policy updates retain last selection at $size',
      (t) async {
        final revision = ValueNotifier(0);
        final countsAbove = ValueNotifier(true);
        final picks = <int>[];
        final choices = items.take(8).toList();
        await t.pumpWidget(
          ListenableBuilder(
            listenable: revision,
            builder: (context) => ListenableBuilder(
              listenable: countsAbove,
              builder: (context) => Picker<int>(
                items: revision.value == 0 ? choices : [...choices],
                maxVisibleRows: 4,
                countHiddenItemsAbove: countsAbove.value,
                searchable: true,
                onSelected: picks.add,
                onCanceled: () {},
              ),
            ),
          ),
          size: size,
        );
        await t.press('/');
        await t.type('Choice');
        await t.press('enter');
        await t.press('down down down down down down down');
        expect(t.screen, shows('Choice 8'));
        revision.value++;
        await t.pump();
        expect(t.screen, shows('Choice 8'));
        expect(t.screen, shows('… +5 more'));
        // Keep the list identity stable while only the footer policy changes.
        revision.value = 0;
        await t.pump();
        countsAbove.value = false;
        await t.pump();
        expect(t.screen, shows('Choice 8'));
        countsAbove.value = true;
        await t.pump();
        expect(t.screen, shows('Choice 8'));
        expect(t.screen, shows('… +5 more'));
        await t.press('enter');
        expect(picks, [8]);
      },
    );
  }
  testWidgets('opening policy toggles settle a stable items viewport', (
    t,
  ) async {
    final atTop = ValueNotifier(false);
    final picks = <int>[];
    await t.pumpWidget(
      ListenableBuilder(
        listenable: atTop,
        builder: (context) => Picker<int>(
          items: items,
          initialValue: 4,
          maxVisibleRows: 7,
          showInitialSelectionAtTop: atTop.value,
          onSelected: picks.add,
          onCanceled: () {},
        ),
      ),
    );
    expect(t.screen, shows('Choice 1'));
    atTop.value = true;
    await t.pump();
    expect(t.screen.lines.first, contains('Choice 4'));
    atTop.value = false;
    await t.pump();
    expect(t.screen.lines.first, contains('Choice 4'));
    await t.press('enter');
    expect(picks, [4]);
  });
  testWidgets('default initial placement still opens at the highlighted row', (
    t,
  ) async {
    await t.pumpWidget(
      Picker<int>(
        items: items,
        initialValue: 4,
        maxVisibleRows: 7,
        onSelected: (_) {},
        onCanceled: () {},
      ),
    );
    expect(t.screen.lines.first, contains('Choice 4'));
    expect(t.screen.text, isNot(contains('Choice 1\n')));
  });
  testWidgets(
    'optional opening on a tall row keeps its first line and no footer',
    (t) async {
      await t.pumpWidget(
        Picker<int>(
          items: const [
            PickerItem(value: 1, label: 'before'),
            PickerItem(value: 2, label: 'a\nb\nc\nd\ne\nf'),
          ],
          initialValue: 2,
          maxVisibleRows: 4,
          showInitialSelectionAtTop: false,
          countHiddenItemsAbove: true,
          itemBuilder: (context, item, _) => Text(item.label),
          onSelected: (_) {},
          onCanceled: () {},
        ),
      );
      expect(t.screen.text, contains('a'));
      expect(t.screen.text, isNot(contains('more')));
    },
  );
}

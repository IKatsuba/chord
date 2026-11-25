import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'optional navigation wraps arrows and j k at both ends at $size',
      (t) async {
        final picks = <int>[];
        await t.pumpWidget(
          Picker<int>(
            items: [
              for (var i = 1; i <= 3; i++)
                PickerItem(value: i, label: 'Choice $i'),
            ],
            wrapNavigation: true,
            onSelected: picks.add,
            onCanceled: () {},
          ),
          size: size,
        );
        await t.press('up enter down enter k enter j enter');
        expect(picks, [3, 1, 3, 1]);
        await t.press('down down down enter');
        expect(picks.last, 1);
      },
    );
  }
  for (final width in [80, 24, 12]) {
    testWidgets('own numbered label wraps from number column in $width cells', (
      t,
    ) async {
      final label =
          '1. Allow this command in the current folder and do not ask again';
      final picks = <int>[];
      final expected = TextLayout.compute(
        TextSpan(label),
        maxWidth: width - 2,
      ).lines.map((row) => row.map((g) => g.text).join()).toList();
      await t.pumpWidget(
        Column(
          children: [
            Picker<int>(
              items: [PickerItem(value: 1, label: label)],
              showNumbers: false,
              maxVisibleRows: 20,
              itemBuilder: (context, item, _) => Text(item.label),
              onSelected: picks.add,
              onCanceled: () {},
            ),
            Text('AFTER'),
          ],
        ),
        size: Size(width, 40),
      );
      expect(t.screen.lines.take(expected.length), [
        for (final (i, text) in expected.indexed) (i == 0 ? '❯ ' : '  ') + text,
      ]);
      expect(t.screen.lines[expected.length], 'AFTER');
      await t.press('1');
      expect(picks, [1]);
    });
  }
  testWidgets('one tall choice reads to its edge before wrapping', (t) async {
    final picks = <int>[];
    await t.pumpWidget(
      Picker<int>(
        items: [
          const PickerItem(value: 1, label: 'a\nb\nc\nd\ne\nf'),
          const PickerItem(value: 2, label: 'last'),
        ],
        wrapNavigation: true,
        maxVisibleRows: 4,
        itemBuilder: (context, item, _) => Text(item.label),
        onSelected: picks.add,
        onCanceled: () {},
      ),
    );
    await t.press('down enter');
    expect(picks, [1]);
    for (var i = 0; i < 10; i++) {
      await t.press('down');
      if (t.screen.text.contains('❯ 2. last')) break;
    }
    await t.press('enter down enter');
    expect(picks, [1, 2, 1]);
  });
}

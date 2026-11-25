import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('omitted keys reach parent unchanged in both modes at $size', (
      t,
    ) async {
      final omitted = ValueNotifier<Set<String>>({
        'pageup',
        'pagedown',
        'shift+pageup',
        'shift+pagedown',
        'down',
        '1',
        'esc',
      });
      final hits = <String>[];
      final picks = <int>[];
      var canceled = 0;
      final items = [
        for (var i = 1; i <= 10; i++) PickerItem(value: i, label: 'Item $i'),
      ];
      await t.pumpWidget(
        ListenableBuilder(
          listenable: omitted,
          builder: (context) => Actions(
            bindings: [
              for (final key in [
                'pageup',
                'pagedown',
                'shift+pageup',
                'shift+pagedown',
                'down',
                '1',
                'esc',
              ])
                Binding(key, 'Outer $key', () => hits.add(key)),
            ],
            child: Picker<int>(
              items: items,
              searchable: true,
              unhandledKeys: omitted.value,
              onSelected: picks.add,
              onCanceled: () => canceled++,
              maxVisibleRows: 4,
            ),
          ),
        ),
        size: size,
      );
      final before = t.screen.lines;
      await t.press('pageup pagedown shift+pageup shift+pagedown down 1 esc');
      expect(hits, [
        'pageup',
        'pagedown',
        'shift+pageup',
        'shift+pagedown',
        'down',
        '1',
        'esc',
      ]);
      expect(t.screen.lines, before);
      expect(picks, isEmpty);
      expect(canceled, 0);
      expect(
        t.focusManager.activeBindings
            .where((b) => b.chord.toString() == 'pagedown')
            .map((b) => b.description),
        ['Outer pagedown'],
      );
      await t.press('/');
      await t.type('Item');
      await t.press('esc pageup pagedown shift+pageup shift+pagedown');
      expect(hits.skip(7), [
        'esc',
        'pageup',
        'pagedown',
        'shift+pageup',
        'shift+pagedown',
      ]);
      expect(t.screen, shows('Filter: Item'));
      // Enter remains TextInput's submission, returning to navigation.
      await t.press('enter');
      omitted.value = {};
      await t.pump();
      await t.press('down enter');
      expect(picks, [2]);
      // KeyCombo-equivalent spellings are compared by parsed value.
      omitted.value = {'ESCAPE'};
      await t.pump();
      await t.press('esc');
      expect(hits.last, 'esc');
      expect(canceled, 0);
      t.dispose();
      omitted.dispose();
    });
  }
  testWidgets('invalid omitted key fails at mount', (t) async {
    await expectLater(
      t.pumpWidget(
        Picker<int>(
          items: const [],
          onSelected: (_) {},
          onCanceled: () {},
          unhandledKeys: const {'bogus+x'},
        ),
      ),
      throwsA(anything),
    );
  });
}

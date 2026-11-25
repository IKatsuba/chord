import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: minimal Picker viewport updates', () {
    for (final size in [const Size(80, 24), const Size(120, 40)]) {
      testWidgets(
        'removal reorder and bursts retain selected value in view at $size',
        (t) async {
          List<PickerItem<int>> choices(Iterable<int> values) => [
            for (final i in values)
              PickerItem(value: i, label: 'Choice $i 界👩‍💻e\u0301'),
          ];
          final items = ValueNotifier(choices(List.generate(12, (i) => i + 1)));
          final picks = <int>[];
          try {
            await t.pumpWidget(
              ListenableBuilder(
                listenable: items,
                builder: (_) => Picker<int>(
                  items: items.value,
                  initialValue: 9,
                  showInitialSelectionAtTop: false,
                  countHiddenItemsAbove: true,
                  maxVisibleRows: 4,
                  onSelected: picks.add,
                  onCanceled: () {},
                ),
              ),
              size: size,
            );
            expect(t.screen, shows('Choice 9 界👩‍💻e\u0301'));
            items.value = choices([7, 8, 9, 10, 11, 12]);
            await t.pump();
            await t.press('enter');
            expect(picks, [9]);
            expect(t.screen, shows('Choice 9 界👩‍💻e\u0301'));
            items.value = choices([12, 11, 10, 9, 8, 7]);
            await t.pump();
            await t.press('enter');
            expect(picks, [9, 9]);
            expect(t.screen, shows('Choice 9 界👩‍💻e\u0301'));
            for (var i = 0; i < 1000; i++) {
              items.value = choices(i.isEven ? [7, 8, 9, 10] : [10, 9, 8, 7]);
            }
            await t.pump();
            await t.resize(const Size(0, 0));
            await t.resize(const Size(1, 1));
            await t.resize(size);
            expect(t.screen, shows('Choice 9 界👩‍💻e\u0301'));
            await t.press('enter');
            expect(picks, [9, 9, 9]);
          } finally {
            t.dispose();
            items.dispose();
          }
        },
      );
    }
  });
}

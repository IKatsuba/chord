import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _items = [
  PickerItem(value: 0, label: 'First'),
  PickerItem(value: 1, label: 'Second'),
  PickerItem(value: 2, label: 'Third'),
];

void main() {
  testWidgets('negative projection reaches the normal build error boundary', (
    t,
  ) async {
    Object? caught;
    await t.pumpWidget(
      ErrorBoundary(
        onError: (error, stack) {
          caught = error;
        },
        errorBuilder: (_, error, stack) => Text('Exact height rejected'),
        child: Picker<int>(
          items: _items,
          itemExtentVersion: 0,
          itemExtentBuilder: (_, positions, width) => -1,
          itemBuilder: (_, item, positions) => Text(item.label),
          onSelected: (_) {
            fail('Rejected choices must not be accepted');
          },
          onCanceled: () {},
        ),
      ),
    );
    expect(caught, isArgumentError);
    expect(t.screen, shows('Exact height rejected'));
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'failed projection disables old choices and recovers at $size',
      (t) async {
        final height = ValueNotifier(1);
        final picks = <int>[];
        await t.pumpWidget(
          ListenableBuilder(
            listenable: height,
            builder: (_) => Column(
              children: [
                Expanded(
                  child: Picker<int>(
                    items: _items,
                    initialValue: 1,
                    itemExtentVersion: height.value,
                    itemExtentBuilder: (_, positions, width) => height.value,
                    itemBuilder: (_, item, positions) => Text(item.label),
                    onSelected: picks.add,
                    onCanceled: () {},
                  ),
                ),
                const KeyHelp(),
              ],
            ),
          ),
          size: size,
        );
        expect(t.screen, shows('Second'));
        height.value = -1;
        await t.pump();
        expect(t.screen, shows('Negative content height'));
        expect(t.screen.text, isNot(contains('Choose highlighted item')));
        await t.press('enter 1 down enter');
        expect(picks, isEmpty);
        height.value = 1;
        await t.pump();
        expect(t.screen, shows('Second'));
        expect(picks, isEmpty, reason: 'recovery never replays rejected input');
        await t.press('enter');
        expect(picks, [1]);
        t.dispose();
        height.dispose();
      },
    );
  }
}

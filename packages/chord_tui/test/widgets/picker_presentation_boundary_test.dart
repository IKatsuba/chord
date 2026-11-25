import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: Picker presentation boundaries', () {
    for (final count in [0, 1]) {
      testWidgets('circular navigation remains safe with $count choices', (
        t,
      ) async {
        final picks = <int>[];
        await t.pumpWidget(
          Picker<int>(
            items: [
              for (var i = 0; i < count; i++)
                PickerItem(value: i, label: '1. 界👩‍💻e\u0301'),
            ],
            wrapNavigation: true,
            showNumbers: false,
            onSelected: picks.add,
            onCanceled: () {},
          ),
          size: const Size(1, 1),
        );
        await t.press('up down k j enter 1');
        expect(picks, count == 0 ? isEmpty : [0, 0]);
        await t.resize(const Size(0, 0));
        await t.press('up down k j enter 1');
        expect(picks, count == 0 ? isEmpty : [0, 0]);
        await t.resize(const Size(80, 24));
        await t.press('up down k j enter');
        expect(picks, count == 0 ? isEmpty : [0, 0, 0]);
      });
    }

    testWidgets('disabled and omitted keys take precedence over wrapping', (
      t,
    ) async {
      final enabled = ValueNotifier(true);
      final node = FocusNode();
      final picks = <int>[];
      var parent = 0;
      try {
        await t.pumpWidget(
          ListenableBuilder(
            listenable: enabled,
            builder: (context) => Actions(
              bindings: [Binding('up', 'Parent up', () => parent++)],
              child: Picker<int>(
                items: const [
                  PickerItem(value: 1, label: '1. first'),
                  PickerItem(value: 2, label: '2. last'),
                ],
                enabled: enabled.value,
                focusNode: node,
                wrapNavigation: true,
                showNumbers: false,
                unhandledKeys: const {'up'},
                onSelected: picks.add,
                onCanceled: () {},
              ),
            ),
          ),
        );
        await t.press('up enter');
        expect(parent, 1);
        expect(picks, [1]);
        enabled.value = false;
        await t.pump();
        await t.press('down k j enter 2 up');
        expect(parent, 2);
        expect(picks, [1]);
        enabled.value = true;
        await t.pump();
        node.requestFocus();
        await t.pump();
        await t.press('k enter');
        expect(picks, [1, 2]);
      } finally {
        t.dispose();
        enabled.dispose();
        node.dispose();
      }
    });

    testWidgets(
      'numberless Unicode content has only marker gutter after resize',
      (t) async {
        final numbers = ValueNotifier(false);
        try {
          await t.pumpWidget(
            ListenableBuilder(
              listenable: numbers,
              builder: (context) => Picker<int>(
                items: const [
                  PickerItem(value: 1, label: '1. 界👩‍💻e\u0301\nnext'),
                ],
                showNumbers: numbers.value,
                itemBuilder: (_, item, _) => Text(item.label),
                onSelected: (_) {},
                onCanceled: () {},
              ),
            ),
            size: const Size(10, 24),
          );
          expect(t.screen.lines.take(2), ['❯ 1. 界👩‍💻e\u0301', '  next']);
          expect(t.screen.styleAt(2, 1), ThemeData.dark().focus);
          for (final size in [const Size(80, 24), const Size(120, 40)]) {
            await t.resize(size);
            numbers.value = true;
            await t.pump();
            expect(t.screen.lines.first, '❯ 1. 1. 界👩‍💻e\u0301');
            numbers.value = false;
            await t.pump();
            expect(t.screen.lines.take(2), ['❯ 1. 界👩‍💻e\u0301', '  next']);
          }
        } finally {
          t.dispose();
          numbers.dispose();
        }
      },
    );
  });
}

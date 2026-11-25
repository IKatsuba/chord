import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: Picker activation boundaries', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'enable preserves sibling focus and disabled traversal at $size',
        (t) async {
          final active = ValueNotifier(false);
          final picker = FocusNode();
          final editor = FocusNode();
          final text = TextEditingController();
          final picks = <String>[];
          try {
            await t.pumpWidget(
              ListenableBuilder(
                listenable: active,
                builder: (context) => Column(
                  children: [
                    TextInput(
                      controller: text,
                      focusNode: editor,
                      autofocus: true,
                    ),
                    Picker<String>(
                      enabled: active.value,
                      focusNode: picker,
                      items: const [
                        PickerItem(value: 'wide', label: '界👩‍💻e\u0301'),
                      ],
                      onSelected: picks.add,
                      onCanceled: () {},
                    ),
                  ],
                ),
              ),
              size: size,
            );
            await t.press('tab');
            expect(picker.hasFocus, isFalse);
            editor.requestFocus();
            active.value = true;
            await t.pump();
            expect(editor.hasFocus, isTrue);
            expect(picker.hasFocus, isFalse);
            await t.type('x');
            expect(text.text, 'x');
            expect(picks, isEmpty);
            picker.requestFocus();
            await t.pump();
            await t.press('enter');
            expect(picks, ['wide']);
            active.value = false;
            await t.pump();
            await t.press('tab');
            expect(picker.hasFocus, isFalse);
            expect(editor.hasFocus, isTrue);
            active.value = true;
            await t.pump();
            expect(editor.hasFocus, isTrue);
            expect(t.screen, isNot(shows('❯')));
          } finally {
            t.dispose();
            active.dispose();
            picker.dispose();
            editor.dispose();
            text.dispose();
          }
        },
      );
    }

    testWidgets('empty disabled picker recovers through zero and one cell', (
      t,
    ) async {
      final active = ValueNotifier(false);
      final items = ValueNotifier<List<PickerItem<int>>>(const []);
      final node = FocusNode();
      final picks = <int>[];
      try {
        await t.pumpWidget(
          ListenableBuilder(
            listenable: active,
            builder: (context) => ListenableBuilder(
              listenable: items,
              builder: (context) => Picker<int>(
                items: items.value,
                enabled: active.value,
                focusNode: node,
                onSelected: picks.add,
                onCanceled: () {},
              ),
            ),
          ),
        );
        expect(t.screen, shows('No choices.'));
        await t.resize(const Size(0, 0));
        await t.press('enter 1 down');
        await t.resize(const Size(1, 1));
        items.value = const [PickerItem(value: 7, label: '界👩‍💻e\u0301')];
        await t.pump();
        active.value = true;
        await t.pump();
        expect(node.hasFocus, isFalse);
        await t.resize(const Size(80, 24));
        node.requestFocus();
        await t.pump();
        expect(t.screen, shows('界👩‍💻e\u0301'));
        await t.press('enter');
        expect(picks, [7]);
      } finally {
        t.dispose();
        node.dispose();
        active.dispose();
        items.dispose();
      }
    });
  });
}

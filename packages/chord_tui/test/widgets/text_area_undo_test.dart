import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('undo and redo edit through Actions at $size', (t) async {
      final c = TextAreaController(text: 'original');
      final changes = <String>[];
      await t.pumpWidget(
        Column(
          children: [
            TextArea(controller: c, autofocus: true, onChanged: changes.add),
            const KeyHelp(),
          ],
        ),
        size: size,
      );
      await t.press('ctrl+u');
      await t.press('ctrl+z');
      expect(c.text, 'original');
      expect(t.screen, shows('original'));
      await t.press('ctrl+y');
      expect(c.text, '');
      expect(changes, ['', 'original', '']);
      expect(
        t.focusManager.activeBindings.map((b) => b.description),
        containsAll(['Undo', 'Redo']),
      );
    });
  }
  group('tester U2 widget undo lifecycle', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('typing paste resize and focus retain undo at $size', (
        t,
      ) async {
        final c = TextAreaController();
        final focus = FocusNode();
        addTearDown(c.dispose);
        addTearDown(focus.dispose);
        final changes = <String>[];
        await t.pumpWidget(
          TextArea(
            controller: c,
            focusNode: focus,
            autofocus: true,
            onChanged: changes.add,
          ),
          size: size,
        );
        await t.type('ab');
        await t.press('ctrl+z');
        expect(c.text, 'a');
        await t.press('ctrl+z');
        expect(c.text, '');
        await t.press('ctrl+y');
        await t.press('ctrl+y');
        await t.paste('界🙂e\u0301\r\ntail');
        final pasted = (c.text, c.cursor);
        focus.unfocus();
        await t.resize(const Size(1, 1));
        focus.requestFocus();
        await t.pump();
        await t.press('ctrl+z');
        expect((c.text, c.cursor), ('ab', 2));
        await t.resize(const Size(0, 0));
        await t.press('ctrl+y');
        expect((c.text, c.cursor), pasted);
        await t.resize(size);
        expect(t.screen, shows('tail'));
        expect(changes, [
          'a',
          'ab',
          'a',
          '',
          'a',
          'ab',
          'ab界🙂e\u0301\ntail',
          'ab',
          'ab界🙂e\u0301\ntail',
        ]);
      });
    }

    testWidgets('excluded undo keys reach ancestors without editing', (
      t,
    ) async {
      final c = TextAreaController()..insert('draft');
      addTearDown(c.dispose);
      final keys = <String>[];
      await t.pumpWidget(
        Actions(
          bindings: [
            Binding('ctrl+z', 'Outer undo', () => keys.add('undo')),
            Binding('ctrl+y', 'Outer redo', () => keys.add('redo')),
          ],
          child: TextArea(
            controller: c,
            autofocus: true,
            unhandledKeys: const {'ctrl+z', 'ctrl+y'},
          ),
        ),
      );
      await t.press('ctrl+z');
      await t.press('ctrl+y');
      expect(keys, ['undo', 'redo']);
      expect(c.text, 'draft');
    });

    testWidgets('escape payload survives undo and redo as literal text', (
      t,
    ) async {
      final c = TextAreaController();
      addTearDown(c.dispose);
      await t.pumpWidget(TextArea(controller: c, autofocus: true));
      await t.paste('a\x1b[31mred\x1b[0m');
      final payload = c.text;
      await t.press('ctrl+z');
      expect(c.text, '');
      await t.press('ctrl+y');
      expect(c.text, payload);
      expect(t.screen.text, isNot(contains('\x1b')));
      await t.pumpWidget(Text('removed'));
      c.undo();
      c.redo();
      await t.pump();
      expect(t.screen, shows('removed'));
    });
  });
}

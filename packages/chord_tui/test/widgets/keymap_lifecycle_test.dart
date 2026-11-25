import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: keymap inheritance and dispatch lifecycle', () {
    test('map entry order does not affect equality or hash', () {
      final a = KeymapData({
        'one': [Chord.parse('a')],
        'two': [Chord.parse('b')],
      });
      final b = KeymapData({
        'two': [Chord.parse('b')],
        'one': [Chord.parse('a')],
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets('inner keymap replaces outer keys through resize $size', (
        t,
      ) async {
        var calls = 0;
        await t.pumpWidget(
          Keymap(
            data: KeymapData({'run': []}),
            child: Keymap(
              data: const KeymapData(),
              child: Actions(
                bindings: [Binding('r', 'Run', () => calls++, id: 'run')],
                child: Focus(autofocus: true, child: Text('界👩‍💻é')),
              ),
            ),
          ),
          size: size,
        );
        for (final room in [
          const Size(0, 0),
          const Size(1, 1),
          const Size(80, 24),
          const Size(120, 40),
          size,
        ]) {
          await t.resize(room);
          await t.press('r');
        }
        expect(calls, 5);
      });

      testWidgets('pending chord resolves against current keys $size', (
        t,
      ) async {
        var calls = 0;
        final data = ValueNotifier(
          KeymapData({
            'run': [Chord.parse('ctrl+x a')],
          }),
        );
        addTearDown(data.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: data,
            builder: (_) => Keymap(
              data: data.value,
              child: Actions(
                bindings: [Binding('r', 'Run', () => calls++, id: 'run')],
                child: Focus(autofocus: true, child: KeyHelp()),
              ),
            ),
          ),
          size: size,
        );
        await t.press('ctrl+x');
        data.value = KeymapData({
          'run': [Chord.parse('ctrl+x b')],
        });
        await t.pump();
        await t.press('a');
        expect(calls, 0);
        await t.press('ctrl+x b');
        expect(calls, 1);
        await t.press('ctrl+x');
        data.value = const KeymapData({'run': []});
        await t.pump();
        await t.press('b');
        expect(calls, 1);
        expect(t.screen.text, isNot(contains('Run')));
      });

      testWidgets('a thousand replacements publish only latest keys $size', (
        t,
      ) async {
        var calls = 0;
        final data = ValueNotifier(const KeymapData());
        addTearDown(data.dispose);
        final focus = FocusNode();
        final other = FocusNode();
        await t.pumpWidget(
          ListenableBuilder(
            listenable: data,
            builder: (_) => Keymap(
              data: data.value,
              child: Actions(
                bindings: [Binding('r', 'Run', () => calls++, id: 'run')],
                child: Column(
                  children: [
                    Focus(
                      focusNode: focus,
                      autofocus: true,
                      child: Text('first'),
                    ),
                    Focus(focusNode: other, child: Text('second')),
                  ],
                ),
              ),
            ),
          ),
          size: size,
        );
        for (var i = 0; i < 1000; i++) {
          data.value = KeymapData({
            'run': [Chord.parse(i.isEven ? 'a' : 'b')],
          });
        }
        await t.pump();
        other.requestFocus();
        await t.press('b');
        focus.requestFocus();
        await t.press('r a b');
        expect(calls, 2);
        await t.pumpWidget(Text('removed'), size: size);
        await t.press('b');
        expect(calls, 2);
      });
    }
  });
}

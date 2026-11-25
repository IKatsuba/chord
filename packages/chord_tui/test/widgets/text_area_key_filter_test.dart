import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'live key filter retains same-frame draft? input and native undo at $size',
      (t) async {
        final controller = TextAreaController();
        addTearDown(controller.dispose);
        var help = 0;
        await t.pumpWidget(
          Actions(
            bindings: [Binding('?', 'Help on empty text', () => help++)],
            child: TextArea(
              controller: controller,
              autofocus: true,
              shouldHandleKey: (event) =>
                  event.key != '?' || controller.text.isNotEmpty,
            ),
          ),
          size: size,
        );
        await t.type('draft?');
        expect(controller.text, 'draft?');
        expect(help, 0);
        await t.press('ctrl+z');
        expect(controller.text, 'draft');
        await t.press('ctrl+y');
        expect(controller.text, 'draft?');
      },
    );
    testWidgets(
      'empty input delegates immediately after same-frame clear at $size',
      (t) async {
        final controller = TextAreaController(text: 'draft');
        addTearDown(controller.dispose);
        var help = 0;
        await t.pumpWidget(
          Actions(
            bindings: [
              Binding('?', 'Help on empty text', () => help++),
              Binding('ctrl+c', 'Clear', controller.clear),
            ],
            child: TextArea(
              controller: controller,
              autofocus: true,
              shouldHandleKey: (event) =>
                  event.key != '?' || controller.text.isNotEmpty,
            ),
          ),
          size: size,
        );
        t.host.handleKey(KeyCombo.parse('ctrl+c').toEvent());
        t.host.handleKey(KeyCombo.parse('?').toEvent());
        await t.pump();
        expect(controller.text, '');
        expect(help, 1);
      },
    );
    testWidgets(
      'a null filter keeps current typing and paste behavior at $size',
      (t) async {
        final controller = TextAreaController();
        addTearDown(controller.dispose);
        var help = 0;
        await t.pumpWidget(
          Actions(
            bindings: [Binding('?', 'Outer help', () => help++)],
            child: TextArea(controller: controller, autofocus: true),
          ),
          size: size,
        );
        await t.type('?');
        await t.paste('pasted?');
        expect(controller.text, '?pasted?');
        expect(help, 0);
      },
    );
  }

  group('tester: live printable delegation boundaries', () {
    testWidgets(
      'delegated punctuation invokes the outer action once without an undo edit',
      (t) async {
        final controller = TextAreaController(text: '界👩‍💻e\u0301');
        addTearDown(controller.dispose);
        var actions = 0;
        var changed = 0;
        var localKeys = 0;
        await t.pumpWidget(
          Actions(
            bindings: [Binding('?', 'Outer', () => actions++)],
            child: TextArea(
              controller: controller,
              autofocus: true,
              shouldHandleKey: (event) => event.key != '?',
              onKey: (_) {
                localKeys++;
                return false;
              },
              onChanged: (_) => changed++,
            ),
          ),
        );
        await t.press('?');
        expect(actions, 1);
        expect(localKeys, 0);
        expect(changed, 0);
        expect(controller.text, '界👩‍💻e\u0301');
        await t.press('ctrl+z');
        expect(controller.text, '界👩‍💻e\u0301');
      },
    );

    testWidgets(
      'a thousand events read the live closure and paste bypasses the filter',
      (t) async {
        final controller = TextAreaController();
        addTearDown(controller.dispose);
        var delegate = true;
        var actions = 0;
        var filters = 0;
        await t.pumpWidget(
          Actions(
            bindings: [Binding('a', 'Outer a', () => actions++)],
            child: TextArea(
              controller: controller,
              autofocus: true,
              shouldHandleKey: (_) {
                filters++;
                return !delegate;
              },
            ),
          ),
        );
        for (var i = 0; i < 1000; i++) {
          t.host.handleKey(const KeyEvent('a'));
        }
        expect(actions, 1000);
        expect(controller.text, '');
        delegate = false;
        t.host.handleKey(const KeyEvent('a'));
        expect(actions, 1000);
        expect(controller.text, 'a');
        final beforePaste = filters;
        await t.paste('👩‍💻e\u0301界\x1b[31m?');
        expect(filters, beforePaste);
        expect(controller.text, 'a👩‍💻e\u0301界\x1b[31m?');
        await t.press('ctrl+z');
        expect(controller.text, 'a');
      },
    );

    testWidgets(
      'filter replacement and focus return preserve controller ownership',
      (t) async {
        final controller = TextAreaController();
        final focus = FocusNode();
        final other = FocusNode();
        final delegate = ValueNotifier(true);
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        addTearDown(other.dispose);
        addTearDown(delegate.dispose);
        var actions = 0;
        await t.pumpWidget(
          Actions(
            bindings: [Binding('?', 'Outer', () => actions++)],
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: delegate,
                  builder: (_) => TextArea(
                    controller: controller,
                    focusNode: focus,
                    autofocus: true,
                    shouldHandleKey: delegate.value ? (_) => false : null,
                  ),
                ),
                Focus(focusNode: other, child: Text('other')),
              ],
            ),
          ),
        );
        await t.press('?');
        expect(actions, 1);
        other.requestFocus();
        await t.press('?');
        expect(actions, 2);
        delegate.value = false;
        await t.pump();
        focus.requestFocus();
        await t.press('?');
        expect(controller.text, '?');
        expect(actions, 2);
        delegate.value = true;
        await t.pump();
        await t.press('?');
        expect(controller.text, '?');
        expect(actions, 3);
      },
    );

    for (final size in [const Size(0, 0), const Size(1, 1)]) {
      testWidgets('delegation survives $size and visible resize', (t) async {
        final controller = TextAreaController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        var actions = 0;
        await t.pumpWidget(
          Actions(
            bindings: [Binding('?', 'Outer', () => actions++)],
            child: TextArea(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              shouldHandleKey: (_) => false,
            ),
          ),
          size: size,
        );
        await t.resize(const Size(80, 24));
        focus.requestFocus();
        await t.press('?');
        expect(actions, 1);
        expect(controller.text, '');
      });
    }
  });
}

import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

FormController _controller([String text = '']) => FormController(
  fields: [TextFormItem(name: 'text', label: '界🙂e\u0301', initialValue: text)],
);

Widget _form(
  FormController controller, {
  FocusNode? node,
  bool enabled = true,
}) => Form(
  controller: controller,
  focusNode: node,
  enabled: enabled,
  onSubmitted: (_) {},
  onCanceled: () {},
);

void main() {
  group('tester CTUI-70: partial list keys and retained values', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a digit picks an offscreen choice with only two field rows at $size',
        (t) async {
          final controller = FormController(
            fields: [
              ChoiceFormItem<int>(
                name: 'choice',
                label: 'Choice',
                options: [
                  for (var i = 1; i <= 12; i++)
                    PickerItem(value: i, label: 'Option $i 界🙂e\u0301'),
                ],
              ),
            ],
          );
          addTearDown(controller.dispose);
          await t.pumpWidget(
            Form(
              controller: controller,
              maxRows: 2,
              onSubmitted: (_) {},
              onCanceled: () {},
            ),
            size: size,
          );
          await t.press('space');
          expect(t.screen.text, isNot(contains('Option 9')));
          await t.press('9');
          expect(controller.value.values['choice'], 9);
          expect(controller.value.listOpen, isFalse);
          await t.press('right');
          expect(t.screen.text, contains('Option 9 界🙂e\u0301'));
          await t.press('esc');
          expect(controller.value.values['choice'], 9);
        },
      );

      testWidgets(
        'multiselect highlight survives viewport changes and toggles at $size',
        (t) async {
          final controller = FormController(
            fields: [
              MultiChoiceFormItem<int>(
                name: 'many',
                label: 'Many',
                options: [
                  for (var i = 1; i <= 12; i++)
                    PickerItem(value: i, label: 'Option $i 界🙂e\u0301'),
                ],
              ),
            ],
          );
          addTearDown(controller.dispose);
          Widget view(int limit) => Form(
            controller: controller,
            maxRows: limit,
            onSubmitted: (_) {},
            onCanceled: () {},
          );
          await t.pumpWidget(view(4), size: size);
          await t.press('space');
          for (var i = 0; i < 11; i++) {
            await t.press('down');
          }
          await t.press('space');
          expect(controller.value.values['many'], [12]);
          for (final limit in [0, 1, 2, 8, 4]) {
            await t.pumpWidget(view(limit), size: size);
            expect(controller.value.highlighted, 11);
            if (limit >= 2) {
              expect(t.screen.text, contains('Option 12 界🙂e\u0301'));
            }
          }
          await t.resize(
            size == const Size(120, 40)
                ? const Size(80, 24)
                : const Size(120, 40),
          );
          await t.press('enter');
          expect(controller.value.listOpen, isFalse);
          expect(controller.value.values['many'], [12]);
          await t.press('space');
          await t.press('space');
          expect(controller.value.values, isNot(contains('many')));
        },
      );
    }
  });

  group('tester form widget boundaries', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'zero, one, narrow and resize retain grapheme editing $size',
        (t) async {
          final controller = _controller('界🙂e\u0301');
          addTearDown(controller.dispose);
          await t.pumpWidget(_form(controller), size: size);
          await t.press('left');
          await t.press('backspace');
          expect(controller.value.values['text'], '界e\u0301');
          for (final next in [
            Size.zero,
            const Size(1, 1),
            const Size(8, 4),
            size,
          ]) {
            await t.resize(next);
          }
          await t.press('right');
          await t.type('👩‍💻');
          expect(controller.value.values['text'], '界e\u0301👩‍💻');
          expect(controller.value.cursor, 3);
          expect(t.screen.text, contains('界e\u0301👩‍💻'));
        },
      );

      testWidgets(
        'wide clusters at either clipping edge keep full controller text $size',
        (t) async {
          final controller = _controller();
          addTearDown(controller.dispose);
          for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
            for (final width in [10, 11, 12]) {
              controller.value = FormData.initial([
                TextFormItem(
                  name: 'text',
                  label: 'N',
                  initialValue: 'x$cluster$cluster',
                ),
              ]);
              await t.pumpWidget(
                SizedBox(width: width, child: _form(controller)),
                size: size,
              );
              await t.press('home');
              await t.press('delete');
              expect(controller.value.values['text'], '$cluster$cluster');
              await t.press('end');
              await t.press('backspace');
              expect(controller.value.values['text'], cluster);
            }
          }
        },
      );
    }

    testWidgets('unbounded constraints produce a finite form', (t) async {
      final controller = _controller('value');
      addTearDown(controller.dispose);
      await t.pumpWidget(Row(children: [_form(controller)]));
      expect(t.screen.text, contains('value'));
      await t.press('end');
      await t.type('x');
      expect(controller.value.values['text'], 'valuex');
    });

    testWidgets(
      'thousand controller updates settle once and old controller detaches',
      (t) async {
        final old = _controller(), fresh = _controller('fresh');
        addTearDown(old.dispose);
        addTearDown(fresh.dispose);
        await t.pumpWidget(_form(old));
        for (var i = 0; i < 1000; i++) {
          old.value = old.value.type('x');
        }
        await t.pump();
        expect((old.value.values['text'] as String).length, 1000);
        await t.pumpWidget(_form(fresh));
        expect(old.hasListeners, isFalse);
        expect(fresh.hasListeners, isTrue);
        old.value = old.value.type('late');
        await t.pump();
        expect(t.screen.text, contains('fresh'));
        await t.pumpWidget(const SizedBox());
        expect(fresh.hasListeners, isFalse);
      },
    );

    testWidgets(
      'removed form ignores timer updates and borrowed nodes survive',
      (t) async {
        final controller = _controller();
        final node = FocusNode(), other = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(node.dispose);
        addTearDown(other.dispose);
        await t.pumpWidget(
          Column(
            children: [
              _form(controller, node: node),
              Focus(focusNode: other, child: Text('other')),
            ],
          ),
        );
        await t.type('one');
        other.requestFocus();
        await t.pump();
        await t.type('lost');
        expect(controller.value.values['text'], 'one');
        node.requestFocus();
        await t.pump();
        await t.type('two');
        expect(controller.value.values['text'], 'onetwo');
        final timer = Timer.periodic(
          const Duration(milliseconds: 1),
          (_) => controller.value = controller.value.type('x'),
        );
        addTearDown(timer.cancel);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 5));
        expect(controller.hasListeners, isFalse);
        expect(node.isDisposed, isFalse);
        timer.cancel();
      },
    );

    testWidgets(
      'rebinding changes actions and disabled form never invokes them',
      (t) async {
        final controller = _controller();
        addTearDown(controller.dispose);
        var canceled = 0;
        Widget app(bool enabled) => Keymap(
          data: KeymapData({
            'form.cancel': [Chord.parse('ctrl+q')],
            'form.next': [Chord.parse('ctrl+n')],
          }),
          child: Form(
            controller: controller,
            enabled: enabled,
            onSubmitted: (_) {},
            onCanceled: () => canceled++,
          ),
        );
        await t.pumpWidget(app(true));
        await t.press('esc');
        expect(canceled, 0);
        await t.press('ctrl+q');
        expect(canceled, 1);
        await t.press('ctrl+n');
        expect(controller.value.focus, FormFocus.submit);
        await t.pumpWidget(app(false));
        await t.press('ctrl+q');
        expect(canceled, 1);
        await t.pumpWidget(app(true));
        await t.press('ctrl+q');
        expect(canceled, 2);
      },
    );

    testWidgets(
      'editing aliases, list escape and application keys stay in their contexts',
      (t) async {
        final controller = FormController(
          fields: const [
            TextFormItem(name: 'text', label: 'T', initialValue: 'ab cd'),
            ChoiceFormItem<int>(
              name: 'choice',
              label: 'C',
              options: [PickerItem(value: 1, label: 'one')],
            ),
          ],
        );
        addTearDown(controller.dispose);
        var canceled = 0, appKeys = 0;
        await t.pumpWidget(
          Actions(
            bindings: [
              for (final key in [
                'shift+up',
                'shift+down',
                'pageup',
                'pagedown',
                'ctrl+o',
                'ctrl+c',
              ])
                Binding(key, 'Application key', () => appKeys++),
            ],
            child: Form(
              controller: controller,
              onSubmitted: (_) {},
              onCanceled: () => canceled++,
            ),
          ),
        );
        await t.press('ctrl+a right delete end backspace ctrl+w');
        expect(controller.value.values['text'], 'a ');
        await t.press('ctrl+u');
        expect(controller.value.values, isEmpty);
        await t.type('ab cd');
        await t.press('home right right ctrl+k');
        expect(controller.value.values['text'], 'ab');
        await t.press('ctrl+e ctrl+u');
        expect(controller.value.values, isEmpty);
        await t.press('tab right esc');
        expect(controller.value.listOpen, isFalse);
        expect(canceled, 0);
        await t.press('space enter delete');
        expect(controller.value.values, isEmpty);
        await t.press('shift+tab');
        expect(controller.value.focus, const FormFocus.field(0));
        for (final key in [
          'shift+up',
          'shift+down',
          'pageup',
          'pagedown',
          'ctrl+o',
          'ctrl+c',
        ]) {
          await t.press(key);
        }
        expect(appKeys, 6);
        await t.press('esc');
        expect(canceled, 1);
      },
    );

    testWidgets(
      'escape bytes remain data and cannot recolor adjacent widgets',
      (t) async {
        final controller = _controller('a\x1b[31mb\x1b[0mc');
        addTearDown(controller.dispose);
        await t.pumpWidget(
          Column(children: [_form(controller), Text('sentinel')]),
        );
        expect(controller.value.values['text'], 'a\x1b[31mb\x1b[0mc');
        final row = t.screen.lines.indexOf('sentinel');
        expect(row, greaterThanOrEqualTo(0));
        expect(t.screen.styleAt(0, row), Style.plain);
      },
    );
  });
}

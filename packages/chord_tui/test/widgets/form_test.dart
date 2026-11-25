import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// The seven fields of the original's `form` fixture, one of each kind.
List<FormItem> seven() => [
  TextFormItem(
    name: 'name',
    label: 'Project name',
    description: 'Lowercase, dashes allowed',
    required: true,
    validator: (text) => text.length < 3 ? 'At least 3 characters' : null,
  ),
  const TextFormItem(name: 'email', label: 'Contact email'),
  NumberFormItem(
    name: 'replicas',
    label: 'Replicas',
    integer: true,
    initialValue: 2,
    required: true,
    validator: (text) {
      final n = int.tryParse(text);
      return n != null && n >= 1 && n <= 9
          ? null
          : 'A whole number from 1 to 9';
    },
  ),
  const NumberFormItem(
    name: 'ratio',
    label: 'Traffic share',
    description: 'Share of traffic sent here, from 0 to 1',
  ),
  const BoolFormItem(name: 'public', label: 'Public', initialValue: false),
  const ChoiceFormItem<String>(
    name: 'region',
    label: 'Region',
    required: true,
    options: [
      PickerItem(value: 'eu', label: 'Europe'),
      PickerItem(value: 'us', label: 'United States'),
      PickerItem(value: 'ap', label: 'Asia Pacific'),
    ],
  ),
  const MultiChoiceFormItem<String>(
    name: 'tags',
    label: 'Tags',
    options: [
      PickerItem(value: 'web', label: 'web'),
      PickerItem(value: 'api', label: 'api'),
      PickerItem(value: 'worker', label: 'worker'),
    ],
  ),
];

/// A form of [fields] with what it gave in [log].
Widget formOf(
  List<String> log,
  FormController controller, {
  int? maxRows,
  bool enabled = true,
  bool decline = true,
  bool leave = false,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Form(
      controller: controller,
      maxRows: maxRows,
      enabled: enabled,
      submitLabel: 'Accept',
      onSubmitted: (values) => log.add('$values'),
      onCanceled: () => log.add('cancel'),
      onDeclined: decline ? () => log.add('decline') : null,
      onLeave: leave ? () => log.add('leave') : null,
    ),
    Text('below'),
  ],
);

/// [seven] with Region given twelve options, as example/form.dart's
/// --long-list (design CTUI-70).
List<FormItem> sevenLong() => [
  for (final field in seven())
    field.name == 'region'
        ? ChoiceFormItem<int>(
            name: 'region',
            label: 'Region',
            required: true,
            options: [
              for (final (i, label) in const [
                'Europe',
                'United States',
                'Asia Pacific',
                'Canada',
                'Japan',
                'India',
                'Brazil',
                'Australia',
                'South Africa',
                'Middle East',
                'Mexico',
                'Korea',
              ].indexed)
                PickerItem(value: i, label: label),
            ],
          )
        : field,
];

Future<void> times(WidgetTester t, String key, int n) async {
  for (var i = 0; i < n; i++) {
    await t.press(key);
  }
}

void main() {
  // CTUI-70: a block taller than maxRows keeps the focused field and its
  // highlighted option in view, its options in a window that follows.
  group('a block taller than maxRows', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('the open list scrolls a window around its highlight, at '
          '$size', (t) async {
        final form = FormController(fields: sevenLong());
        await t.pumpWidget(formOf([], form, maxRows: 8), size: size);
        await times(t, 'down', 5);
        await t.press('space');
        await times(t, 'down', 6);
        expect(t.screen.lines.take(10).map((line) => line.trimRight()), [
          '    ↑ 5 more fields',
          '❯ * Region         ▾',
          '                     ↑ 4 more options',
          '                     5. Japan',
          '                     6. India',
          '                   ❯ 7. Brazil',
          '                     ↓ 5 more options',
          '    ↓ 1 more field',
          '',
          '  Accept   Decline',
        ]);
        // The option count rows dim, at the options' label column.
        expect(t.screen.styleAt(21, 2).isDim, isTrue);
      });

      testWidgets('maxRows 0 draws the buttons with no blank row above, at '
          '$size', (t) async {
        final form = FormController(fields: sevenLong());
        await t.pumpWidget(formOf([], form, maxRows: 0), size: size);
        expect(t.screen.lines.first.trimRight(), '  Accept   Decline');
      });
    }
  });

  final dark = ThemeData.dark();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final wide = size.width >= 100;

    testWidgets('each kind in its row, the focused one marked, at $size', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        formOf(log, FormController(fields: seven())),
        size: size,
      );
      expect(t.screen.lines.take(14), [
        '❯ * Project name',
        '                   Lowercase, dashes allowed',
        '    Contact email  not set',
        '  ✔ Replicas       2',
        '    Traffic share  not set',
        '  ✔ Public         ☐ No',
        '  * Region         not set',
        '    Tags           not set',
        '',
        '  Accept   Decline',
        '',
        wide
            ? 'Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel'
            : 'Type to fill in · ↑↓ to move · Esc to cancel',
        'below',
        '',
      ]);
      expect(t.screen.styleAt(0, 0), dark.focus);
      expect(t.screen.styleAt(2, 0), dark.error);
      expect(t.screen.styleAt(4, 0), dark.focus.merge(Style.bold));
      expect(t.screen.styleAt(19, 0).isInverse, isTrue, reason: 'the cursor');
      expect(t.screen.styleAt(2, 3), dark.dim);
      expect(t.screen.styleAt(19, 2), dark.dim);
    });

    testWidgets('typing, a wrong value shown on leaving, and fixing it, at '
        '$size', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        formOf(log, FormController(fields: seven())),
        size: size,
      );
      await t.type('ab');
      expect(t.screen.lines.first, '❯   Project name   ab');
      expect(t.screen.styleAt(21, 0).isInverse, isTrue);
      await t.press('left');
      expect(t.screen.styleAt(20, 0).isInverse, isTrue);
      await t.press('down');
      expect(t.screen.lines.take(3), [
        '  ⚠ Project name   ab',
        '                   At least 3 characters',
        '❯   Contact email',
      ]);
      expect(t.screen.styleAt(19, 1), dark.error);
      await t.press('up');
      // The focused field's problem colours its label.
      expect(t.screen.styleAt(4, 0), dark.error.merge(Style.bold));
      await t.press('end');
      await t.type('c');
      expect(t.screen.lines.take(2), [
        '❯ ✔ Project name   abc',
        '                   Lowercase, dashes allowed',
      ]);
      await t.press('down');
      await t.paste('a@b\n.c');
      expect(t.screen.lines[1], '❯ ✔ Contact email  a@b .c');
      await t.press('ctrl+w');
      expect(t.screen.lines[1], '❯ ✔ Contact email  a@b');
      await t.press('ctrl+u');
      expect(t.screen.lines[1], '❯   Contact email');
    });

    testWidgets('a number field takes only number characters, at $size', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        formOf(log, FormController(fields: seven())),
        size: size,
      );
      await times(t, 'down', 3);
      await t.type('x0.5y');
      expect(t.screen.lines[3], '❯ ✔ Traffic share  0.5');
    });

    testWidgets('a choice list opens under its field and picks by number, at '
        '$size', (t) async {
      final log = <String>[];
      final form = FormController(fields: seven());
      await t.pumpWidget(formOf(log, form), size: size);
      await times(t, 'down', 5);
      await t.press('space');
      expect(t.screen.lines.skip(5).take(4), [
        '❯ * Region         ▾',
        '                   ❯ 1. Europe',
        '                     2. United States',
        '                     3. Asia Pacific',
      ]);
      expect(t.screen.styleAt(21, 6), dark.focus);
      await t.press('j');
      await t.press('down');
      await t.press('k');
      expect(t.screen.lines[7], '                   ❯ 2. United States');
      await t.press('3');
      expect(t.screen.lines[5], '❯ ✔ Region         Asia Pacific');
      await t.press('right');
      expect(t.screen.lines[8], '                   ❯ 3. Asia Pacific ✔');
      await t.press('left');
      expect(t.screen.lines[6], '    Tags           not set');
      await t.press('backspace');
      expect(form.value.values.containsKey('region'), isFalse);
    });

    testWidgets('a multi list ticks with Space and closes with Enter, at '
        '$size', (t) async {
      final log = <String>[];
      final form = FormController(fields: seven());
      await t.pumpWidget(formOf(log, form), size: size);
      await times(t, 'down', 6);
      await t.press('right');
      await t.press('space');
      await t.press('down');
      await t.press('down');
      await t.press('space');
      expect(t.screen.lines.skip(7).take(3), [
        '                     ☒ web',
        '                     ☐ api',
        '                   ❯ ☒ worker',
      ]);
      await t.press('enter');
      expect(t.screen.lines[6], '❯ ✔ Tags           web, worker');
      await t.press('up');
      await t.press('up');
      await t.press('space');
      expect(t.screen.lines[4], '❯ ✔ Public         ☒ Yes');
    });

    testWidgets('a refused submit counts the problems; a valid one sends the '
        'values, at $size', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        formOf(log, FormController(fields: seven())),
        size: size,
      );
      await times(t, 'tab', 7);
      expect(t.screen.lines[8], '❯ Accept   Decline');
      expect(t.screen.styleAt(2, 8), dark.success.merge(Style.bold));
      await t.press('enter');
      expect(log, isEmpty);
      expect(t.screen.lines.first, '❯ ⚠ Project name');
      expect(t.screen.lines[1], '                   Required');
      expect(t.screen.text, contains('  Accept   Decline     2 fields to fix'));
      await t.type('demo');
      await times(t, 'enter', 5);
      await t.press('space');
      await t.press('1');
      expect(t.screen.text, isNot(contains('to fix')));
      await times(t, 'tab', 2);
      await t.press('enter');
      expect(log, ['{name: demo, replicas: 2, public: false, region: eu}']);
    });

    testWidgets('decline, cancel and leaving from the buttons, at $size', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        formOf(log, FormController(fields: seven()), leave: true),
        size: size,
      );
      await t.press('esc');
      expect(log, ['cancel']);
      await times(t, 'down', 7);
      await t.press('down');
      expect(log.last, 'leave');
      await t.press('right');
      expect(t.screen.lines[8], '  Accept ❯ Decline');
      expect(t.screen.styleAt(11, 8), dark.error);
      expect(
        t.screen.lines[10],
        '←→ to switch · Enter to decline · Esc to cancel',
      );
      await t.press('enter');
      expect(log.last, 'decline');
      await t.press('left');
      await t.press('shift+tab');
      expect(t.screen.lines[6], startsWith('❯   Tags'));
    });

    testWidgets('with no decline the buttons are one, at $size', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        formOf(log, FormController(fields: const []), decline: false),
        size: size,
      );
      expect(t.screen.lines.take(3), [
        '❯ Accept',
        '',
        'Enter to accept · Esc to cancel',
      ]);
      await t.press('right');
      await t.press('enter');
      expect(log, ['{}']);
    });

    testWidgets('scrolls by whole fields past maxRows, at $size', (t) async {
      final log = <String>[];
      await t.pumpWidget(
        formOf(log, FormController(fields: seven()), maxRows: 8),
        size: size,
      );
      await times(t, 'down', 5);
      await t.press('space');
      expect(t.screen.lines.take(8), [
        '    ↑ 3 more fields',
        '    Traffic share  not set',
        '  ✔ Public         ☐ No',
        '❯ * Region         ▾',
        '                   ❯ 1. Europe',
        '                     2. United States',
        '                     3. Asia Pacific',
        '    Tags           not set',
      ]);
      expect(t.screen.styleAt(4, 0), dark.dim);
    });

    testWidgets('disabled, it keeps its state and draws no marks, no hint and '
        'takes no keys, at $size', (t) async {
      final log = <String>[];
      final form = FormController(fields: seven());
      await t.pumpWidget(formOf(log, form), size: size);
      await t.type('demo');
      await t.pumpWidget(formOf(log, form, enabled: false), size: size);
      expect(t.screen.lines.first, '  ✔ Project name   demo');
      expect(t.screen.text, isNot(contains('❯')));
      expect(t.screen.text, isNot(contains('Esc to cancel')));
      await t.type('x');
      await t.press('esc');
      expect(log, isEmpty);
      expect(form.value.values['name'], 'demo');
      await t.pumpWidget(formOf(log, form), size: size);
      await t.type('x');
      expect(form.value.values['name'], 'demox');
    });

    testWidgets('its keys are bound with descriptions and form ids, at $size', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        formOf(log, FormController(fields: seven())),
        size: size,
      );
      final bound = {
        for (final b in t.focusManager.activeBindings)
          if (b.id?.startsWith('form.') ?? false) '${b.chord}': b.description,
      };
      expect(bound, containsPair('down', 'Next field'));
      expect(bound, containsPair('shift+tab', 'Previous field'));
      expect(bound, containsPair('escape', 'Cancel'));
      expect(bound, containsPair('ctrl+w', 'Delete word'));
      expect(bound.keys, isNot(contains('pgup')));
      expect(bound.keys, isNot(contains('ctrl+o')));
    });
  }

  testWidgets('a label wider than a third of the width is cut', (t) async {
    final log = <String>[];
    await t.pumpWidget(
      formOf(
        log,
        FormController(
          fields: const [
            TextFormItem(
              name: 'n',
              label: 'A label far too long to fit a third of the box',
              initialValue: 'value',
            ),
          ],
        ),
      ),
      size: const Size(30, 10),
    );
    expect(t.screen.lines.first, '❯ ✔ A label far value');
  });
}

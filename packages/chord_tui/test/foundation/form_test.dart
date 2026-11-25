import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const _regions = [
  PickerItem(value: 'eu', label: 'Europe'),
  PickerItem(value: 'us', label: 'United States'),
  PickerItem(value: 'ap', label: 'Asia Pacific'),
];

List<FormItem> fields() => [
  TextFormItem(
    name: 'name',
    label: 'Project name',
    description: 'Lowercase, dashes allowed',
    required: true,
    validator: (text) => text.length < 3 ? 'At least 3 characters' : null,
  ),
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
  const NumberFormItem(name: 'ratio', label: 'Traffic share'),
  const BoolFormItem(name: 'public', label: 'Public', initialValue: false),
  const ChoiceFormItem<String>(
    name: 'region',
    label: 'Region',
    required: true,
    options: _regions,
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
  const UnsupportedFormItem(name: 'when', label: 'When'),
];

FormData at(int index) {
  var form = FormData.initial(fields());
  for (var i = 0; i < index; i++) {
    form = form.next();
  }
  return form;
}

/// Design CTUI-70's form: six fields above Region's twelve options, one
/// below.
List<FormItem> _tall() => [
  for (final name in ['a', 'b', 'c', 'd', 'e'])
    TextFormItem(name: name, label: name),
  ChoiceFormItem<int>(
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
  ),
  const TextFormItem(name: 'tags', label: 'Tags'),
];

/// Region focused, its list open, the highlight on option [on] (from 1).
FormData _region({int on = 1, bool problem = false}) {
  var form = FormData.initial(_tall());
  if (problem) {
    // A refused submit shows Region's problem and focuses it.
    form = form.submit().form;
    expect(form.focused?.name, 'region');
  } else {
    for (var i = 0; i < 5; i++) {
      form = form.next();
    }
  }
  form = form.openList();
  for (var i = 1; i < on; i++) {
    form = form.nextOption();
  }
  return form;
}

/// [rows] as the design's captures read them.
List<String> _read(List<FormRow> rows) => [
  for (final row in rows)
    switch (row) {
      FormFieldRow(:final item, :final focused) =>
        '${focused ? '❯' : ' '} ${item.label}',
      FormOptionRow(:final number, :final label, :final highlighted) =>
        '${highlighted ? '❯' : ' '} $number. $label',
      FormMoreRow(:final up, :final count) =>
        '${up ? '↑' : '↓'} $count more field${count == 1 ? '' : 's'}',
      FormMoreOptionsRow(:final up, :final count) =>
        '${up ? '↑' : '↓'} $count more option${count == 1 ? '' : 's'}',
      FormNoteRow(:final text) => text,
    },
];

/// A text field of at least three characters.
TextFormItem _short(String name) => TextFormItem(
  name: name,
  label: name,
  validator: (text) => text.length < 3 ? 'At least 3 characters' : null,
);

/// No more than [limit] rows, the focused field's and, with a list open,
/// its highlighted option among them.
void _bounded(FormData form, int limit) {
  final rows = form.rows(limit);
  expect(rows.length, lessThanOrEqualTo(limit));
  if (limit >= 1 && form.focus.onField) {
    expect(rows.whereType<FormFieldRow>().any((r) => r.focused), isTrue);
  }
  if (limit >= 2 && form.listOpen) {
    expect(rows.whereType<FormOptionRow>().any((r) => r.highlighted), isTrue);
  }
}

void _tallTests() {
  group('CTUI-70: a block taller than the limit', () {
    test('the highlight on the first option: the first page', () {
      final form = _region();
      expect(_read(form.rows(8)), [
        '↑ 5 more fields',
        '❯ Region',
        '❯ 1. Europe',
        '  2. United States',
        '  3. Asia Pacific',
        '  4. Canada',
        '↓ 8 more options',
        '↓ 1 more field',
      ]);
      _bounded(form, 8);
    });

    test('the highlight on 7: on the last row of its window', () {
      final form = _region(on: 7);
      expect(_read(form.rows(8)), [
        '↑ 5 more fields',
        '❯ Region',
        '↑ 4 more options',
        '  5. Japan',
        '  6. India',
        '❯ 7. Brazil',
        '↓ 5 more options',
        '↓ 1 more field',
      ]);
      _bounded(form, 8);
    });

    test('the highlight on the last option', () {
      final form = _region(on: 12);
      expect(_read(form.rows(8)), [
        '↑ 5 more fields',
        '❯ Region',
        '↑ 8 more options',
        '  9. South Africa',
        '  10. Middle East',
        '  11. Mexico',
        '❯ 12. Korea',
        '↓ 1 more field',
      ]);
      _bounded(form, 8);
    });

    test("a shown problem is claimed before more options", () {
      final form = _region(problem: true);
      expect(_read(form.rows(8)), [
        '↑ 5 more fields',
        '❯ Region',
        '❯ 1. Europe',
        '  2. United States',
        '  3. Asia Pacific',
        '↓ 9 more options',
        'Required',
        '↓ 1 more field',
      ]);
      _bounded(form, 8);
    });

    test('tiny limits claim the field, the highlight, then fields above', () {
      final form = _region();
      expect(form.rows(0), isEmpty);
      expect(_read(form.rows(1)), ['❯ Region']);
      expect(_read(form.rows(2)), ['❯ Region', '❯ 1. Europe']);
      expect(_read(form.rows(3)), [
        '↑ 5 more fields',
        '❯ Region',
        '❯ 1. Europe',
      ]);
      for (var limit = 0; limit <= 12; limit++) {
        _bounded(form, limit);
        _bounded(_region(on: 7), limit);
        _bounded(_region(on: 12, problem: true), limit);
      }
    });

    test('a two-row block before the focused field no longer hides it', () {
      // a, left wrong, shows its problem (two rows); the focus on b.
      var form = FormData.initial([
        _short('a'),
        const TextFormItem(name: 'b', label: 'b'),
        const TextFormItem(name: 'c', label: 'c'),
      ]);
      form = form.type('x').next();
      expect(form.focused?.name, 'b');
      expect(_read(form.rows(2)), ['↑ 1 more field', '❯ b']);
      _bounded(form, 2);
    });

    test('the focus on a button anchors the first field, cut when tall', () {
      var form = FormData.initial([
        _short('a'),
        const TextFormItem(name: 'b', label: 'b'),
      ]);
      form = form.type('x').next().next();
      expect(form.focus.onField, isFalse);
      // a's block, field and problem, is taller than one row.
      expect(_read(form.rows(1)), ['  a']);
      expect(_read(form.rows(2)), ['  a', '↓ 1 more field']);
    });
  });
}

void main() {
  _tallTests();
  test('opens with initial values and the focus on the first field, or on '
      'submit with none', () {
    final form = FormData.initial(fields());
    expect(form.focus, const FormFocus.field(0));
    expect(form.values, {'replicas': 2, 'public': false});
    expect(FormData.initial(const []).focus, FormFocus.submit);
    expect(
      FormData.initial(const [
        ChoiceFormItem<String>(
          name: 'r',
          label: 'R',
          options: _regions,
          initialValue: 'us',
        ),
        MultiChoiceFormItem<String>(
          name: 't',
          label: 'T',
          options: _regions,
          initialValue: ['ap', 'eu'],
        ),
        NumberFormItem(name: 'n', label: 'N', initialValue: 2.5),
        TextFormItem(name: 'e', label: 'E', initialValue: ''),
      ]).values,
      {
        'r': 'us',
        't': ['eu', 'ap'],
        'n': 2.5,
      },
    );
  });

  test(
    'typing edits through the cursor, and pasted line breaks are spaces',
    () {
      var form = at(0).type('ab').type('d').cursorLeft().type('c');
      expect((form.values['name'], form.cursor), ('abcd', 3));
      form = form.cursorHome().deleteToEnd();
      expect(form.values.containsKey('name'), isFalse);
      form = form.type('one\ntwo\r\nthree').deleteWordBefore();
      expect(form.values['name'], 'one two ');
      form = form.cursorLeft().cursorLeft().deleteToStart();
      expect((form.values['name'], form.cursor), ('o ', 0));
      form = form.delete().cursorEnd().backspace();
      expect(form.values['name'], null);
    },
  );

  test('a grapheme typed in pieces counts once for the cursor', () {
    var form = FormData.initial(const [
      TextFormItem(name: 't', label: 'T', initialValue: '界é'),
    ]);
    expect(form.cursor, 2);
    form = form.type('👩').type('\u200d').type('💻');
    expect((form.values['t'], form.cursor), ('界é👩‍💻', 3));
    form = form.cursorLeft().type('x');
    expect((form.values['t'], form.cursor), ('界éx👩‍💻', 3));
    form = form.cursorEnd().backspace();
    expect((form.values['t'], form.cursor), ('界éx', 3));
  });

  test('a number field takes only what a number holds, and submits a num', () {
    var form = at(1).backspace().type('x').type('1.5').type('7');
    // '1.5' holds a point, which a whole number cannot: none of it goes.
    expect(form.values['replicas'], 7);
    form = form.next().type('a').type('.5');
    expect(form.values['ratio'], 0.5);
    form = form.backspace().backspace().type('-.').next();
    expect(form.problems['ratio'], 'Not a number');
    expect(form.shown, contains('ratio'));
    expect(
      FormData.initial(const [
        NumberFormItem(name: 'n', label: 'N', integer: true),
      ]).type('+').next().problems,
      {'n': 'Not a whole number'},
    );
  });

  test(
    'a number no Dart int or JSON can carry is a problem, never a crash',
    () {
      var form = FormData.initial(const [
        NumberFormItem(name: 'n', label: 'N', integer: true),
        NumberFormItem(name: 'f', label: 'F'),
      ]);
      form = form.type('9223372036854775808').next().type('1' * 400 + '.5');
      expect(form.problems, {'n': 'Not a whole number', 'f': 'Not a number'});
      expect(form.values, isEmpty);
      final refused = form.next().submit();
      expect(refused.values, isNull);
      expect(refused.form.focus, const FormFocus.field(0));
      // The largest a 64-bit int holds still goes.
      expect(
        FormData.initial(const [
          NumberFormItem(name: 'n', label: 'N', integer: true),
        ]).type('9223372036854775807').submit().values,
        {'n': 9223372036854775807},
      );
      // A validator's words still say it.
      expect(
        FormData.initial([
          NumberFormItem(
            name: 'n',
            label: 'N',
            integer: true,
            validator: (_) => 'A whole number from 1 to 9',
          ),
        ]).type('99999999999999999999').problems,
        {'n': 'A whole number from 1 to 9'},
      );
    },
  );

  test('an initial number that is not finite leaves the field unset', () {
    for (final value in [
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ]) {
      expect(
        FormData.initial([
          NumberFormItem(name: 'n', label: 'N', initialValue: value),
        ]).values,
        isEmpty,
      );
    }
    expect(
      FormData.initial(const [
        NumberFormItem(name: 'n', label: 'N', initialValue: 2.0),
      ]).values,
      {'n': 2},
    );
  });

  test('moving never turns an empty required field red; leaving a wrong one '
      'shows it', () {
    var form = at(0).next();
    expect(form.shown, isEmpty);
    expect(form.rows().whereType<FormNoteRow>(), isEmpty);
    form = form.previous().type('ab').next();
    expect(form.shown, {'name'});
    final [field, note, ...] = form.rows();
    expect((field as FormFieldRow).status, FormFieldStatus.invalid);
    expect((note as FormNoteRow).text, 'At least 3 characters');
    expect(note.error, isTrue);
    // Checked on every keystroke once shown.
    form = form.previous().type('c');
    expect((form.rows().first as FormFieldRow).status, FormFieldStatus.valid);
  });

  test('a refused submit shows every problem, counts them and focuses the '
      'first', () {
    var form = at(7);
    expect(form.focus, FormFocus.submit);
    final refused = form.submit();
    expect(refused.values, isNull);
    form = refused.form;
    expect(form.focus, const FormFocus.field(0));
    expect(form.problems, {'name': 'Required', 'region': 'Required'});
    expect(form.toFix, 2);
    expect(form.shown, {'name', 'region'});
    form = form.type('demo');
    expect(form.toFix, 1);
    for (var i = 0; i < 4; i++) {
      form = form.next();
    }
    form = form.openList().pick(2);
    expect(form.toFix, 0);
    final accepted = form.next().next().next().submit();
    expect(accepted.values, {
      'name': 'demo',
      'replicas': 2,
      'public': false,
      'region': 'us',
    });
  });

  test('a choice list opens on what it holds and picks by number or Enter', () {
    var form = at(4).openList();
    expect(form.highlighted, 0);
    form = form.nextOption().nextOption().nextOption();
    expect(form.highlighted, 2);
    form = form.pick();
    expect((form.values['region'], form.listOpen), ('ap', false));
    form = form.openList();
    expect(form.highlighted, 2);
    final options = form.rows().whereType<FormOptionRow>().toList();
    expect(
      [for (final o in options) (o.number, o.current, o.highlighted)],
      [(1, false, false), (2, false, false), (3, true, true)],
    );
    expect(form.pick(9).listOpen, isTrue, reason: 'no ninth option');
    expect(form.closeList().values['region'], 'ap');
    expect(form.closeList().clear().values.containsKey('region'), isFalse);
  });

  test("a multi list ticks in the options' order and Enter closes it", () {
    var form = at(5).openList().nextOption().nextOption().tick();
    form = form.previousOption().previousOption().tick();
    expect(form.values['tags'], ['web', 'worker']);
    expect(
      [for (final o in form.rows().whereType<FormOptionRow>()) o.ticked],
      [true, false, true],
    );
    form = form.tick().closeList();
    expect(form.values['tags'], ['worker']);
    expect((form.rows()[5] as FormFieldRow).value.text, 'worker');
  });

  test('a yes-or-no toggles and clears; an unsupported field is never set', () {
    var form = at(3).toggle();
    expect(form.values['public'], true);
    expect((form.rows()[3] as FormFieldRow).value.text, '☒ Yes');
    form = form.clear().next().next().next();
    expect(form.values.containsKey('public'), isFalse);
    expect(form.type('x').values.containsKey('when'), isFalse);
    final row = form.rows().whereType<FormFieldRow>().last;
    expect((row.value.text, row.value.dim), ("can't be filled in here", true));
  });

  test('scrolls by whole fields, the focused one and its list in view', () {
    final form = at(4).openList();
    final rows = form.rows(8);
    expect(rows.length, lessThanOrEqualTo(8));
    expect((rows.first as FormMoreRow).count, 2);
    expect((rows.first as FormMoreRow).up, isTrue);
    expect(
      [
        for (final row in rows)
          if (row is FormFieldRow) row.item.name,
      ],
      ['ratio', 'public', 'region'],
    );
    expect((rows.last as FormMoreRow).up, isFalse);
    expect(at(0).rows(4), [
      isA<FormFieldRow>(),
      isA<FormNoteRow>(),
      isA<FormFieldRow>(),
      isA<FormMoreRow>().having((r) => r.count, 'count', 5),
    ]);
  });

  test('the hint names the keys for where the focus is, long when wide', () {
    expect(
      at(0).hint(120),
      'Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel',
    );
    expect(at(0).hint(80), 'Type to fill in · ↑↓ to move · Esc to cancel');
    expect(at(3).hint(80), 'Space to toggle · ↑↓ to move · Esc to cancel');
    expect(at(4).hint(80), '→ or Space to choose · ↑↓ to move · Esc to cancel');
    expect(at(6).hint(80), '↑↓ to move · Esc to cancel');
    expect(
      at(4).openList().hint(120),
      '↑↓ to move · 1–3 or Enter to pick · ← to close the list · Esc to cancel',
    );
    expect(
      at(5).openList().hint(80),
      '↑↓ · Space to tick · Enter or ← to close · Esc to cancel',
    );
    expect(
      at(7).hint(80, submitLabel: 'Accept'),
      '←→ to switch · Enter to accept · Esc to cancel',
    );
    expect(
      at(7).toDecline().hint(80, submitLabel: 'Accept'),
      '←→ to switch · Enter to decline · Esc to cancel',
    );
    expect(
      at(7).hint(80, submitLabel: 'Save', declineLabel: null),
      'Enter to save · Esc to cancel',
    );
  });

  test('a yes-or-no field takes a validator of its answer', () {
    final form = FormData.initial([
      BoolFormItem(
        name: 'agree',
        label: 'Agree',
        initialValue: false,
        validator: (value) => value ? null : 'Must agree',
      ),
    ]);
    expect(form.problems, {'agree': 'Must agree'});
    expect(form.toggle().problems, isEmpty);
  });

  test('the buttons are one stop; left and right switch them', () {
    final form = at(7);
    expect(form.next(), same(form));
    expect(form.toDecline().focus, FormFocus.decline);
    expect(form.toDecline().toSubmit().focus, FormFocus.submit);
    expect(form.previous().focus, const FormFocus.field(6));
  });
}

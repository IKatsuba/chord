// The original's tests/ui/dialogs/form_test.ts, for what the port keeps in
// lib/ui/dialogs/form.dart: a schema's fields, their defaults, the words
// for what is wrong, and how an answer reads back. The keys themselves are
// the framework's Form, tested in its own package.
import 'package:chord/ui/dialogs/form.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

import '../../fixtures/forms.dart';

FormData open([Map<String, Object?> schema = formSchema]) =>
    FormData.initial(fieldsOf(schema));

String? check(Map<String, Object?> property, Object? value) =>
    checkValue(property, value);

void main() {
  test('each property is a field of its kind, titled, in order', () {
    final fields = fieldsOf(formSchema);
    expect(
      [
        for (final f in fields)
          (f.name, f.label, f.runtimeType.toString(), f.required),
      ],
      [
        ('name', 'Project name', 'TextFormItem', true),
        ('email', 'Contact email', 'TextFormItem', false),
        ('replicas', 'Replicas', 'NumberFormItem', true),
        ('ratio', 'Traffic share', 'NumberFormItem', false),
        ('public', 'Public', 'BoolFormItem', false),
        ('region', 'Region', 'ChoiceFormItem<String>', true),
        ('tags', 'Tags', 'MultiChoiceFormItem<String>', false),
      ],
    );
    expect((fields[2] as NumberFormItem).integer, isTrue);
    expect((fields[3] as NumberFormItem).integer, isFalse);
    final region = (fields[5] as ChoiceFormItem<String>).options[1];
    expect((region.value, region.label), ('us', 'United States'));
    expect(
      [
        for (final o in (fields[6] as MultiChoiceFormItem<String>).options)
          o.label,
      ],
      ['web', 'api', 'worker'],
    );
    expect(fields.first.description, 'Lowercase, dashes allowed');
  });

  test('a property without a title is labelled by its name', () {
    final [field] = fieldsOf({
      'type': 'object',
      'properties': {
        'port': {'type': 'integer'},
      },
    });
    expect(field.label, 'port');
  });

  test('a type a form cannot ask for is kept, unset, and blocks Accept if '
      'required', () {
    final form = open({
      'type': 'object',
      'properties': {
        'blob': {'type': 'object'},
      },
      'required': ['blob'],
    });
    expect(form.fields.single, isA<UnsupportedFormItem>());
    final row = form.rows().single as FormFieldRow;
    expect(row.status, FormFieldStatus.required);
    expect(row.value.text, "can't be filled in here");
    expect(form.next().submit().values, isNull);
  });

  test('the form opens with defaults set; unset fields are not sent', () {
    expect(open().values, {'replicas': 2, 'public': false});
    expect(
      open({
        'type': 'object',
        'properties': {
          'r': {
            'type': 'string',
            'enum': ['a', 'b'],
            'default': 'c',
          },
          't': {
            'type': 'array',
            'items': {
              'type': 'string',
              'enum': ['a', 'b'],
            },
            'default': ['b', 'z'],
          },
          's': {'type': 'string', 'default': ''},
        },
      }).values,
      {
        't': ['b'],
      },
    );
  });

  test('a form with no fields accepts with no content', () {
    final form = open({'type': 'object', 'properties': <String, Object?>{}});
    expect(form.focus, FormFocus.submit);
    expect(form.submit().values, <String, Object>{});
  });

  test('Accept on an invalid form is refused, every problem shown in '
      'words', () {
    var form = open().type('ab').next().type('ops@').next().backspace();
    form = form.type('12');
    final refused = form.submit();
    expect(refused.values, isNull);
    expect(refused.form.focused?.name, 'name');
    expect(refused.form.toFix, 4);
    expect(
      [
        for (final row in refused.form.rows())
          if (row is FormNoteRow && row.error) row.text,
      ],
      [
        'At least 3 characters',
        'Not an email address, such as name@example.com',
        'A whole number from 1 to 9',
        'Required',
      ],
    );
    expect(refused.form.type('c').toFix, 3);
  });

  test('Accept on a valid form answers with the values in their schema '
      'types', () {
    var form = open().type('web-app').next().type('ops@example.io').next();
    form = form.backspace().type('3').next().type('0.25').next().toggle();
    form = form.next().openList().pick(2).next().openList().tick();
    form = form.nextOption().nextOption().tick().closeList();
    expect(form.submit().values, {
      'name': 'web-app',
      'email': 'ops@example.io',
      'replicas': 3,
      'ratio': 0.25,
      'public': true,
      'region': 'us',
      'tags': ['web', 'worker'],
    });
  });

  group('each rule reads in plain words', () {
    for (final (keyword, property, value, words)
        in <(String, Map<String, Object?>, Object?, String)>[
          (
            'maxLength',
            {'type': 'string', 'maxLength': 2},
            'abc',
            'At most 2 characters',
          ),
          (
            'minLength',
            {'type': 'string', 'minLength': 1},
            '',
            'At least 1 character',
          ),
          (
            'pattern',
            {'type': 'string', 'pattern': r'^[a-z-]+$'},
            'A',
            r'Must match ^[a-z-]+$',
          ),
          (
            'format uri',
            {'type': 'string', 'format': 'uri'},
            'nope',
            'Not a URL, such as https://example.com',
          ),
          (
            'format date',
            {'type': 'string', 'format': 'date'},
            '2026-13-01',
            'Not a date, such as 2026-10-06',
          ),
          (
            'format date-time',
            {'type': 'string', 'format': 'date-time'},
            'soon',
            'Not a date and time, such as 2026-10-06T14:30:00Z',
          ),
          (
            'format email',
            {'type': 'string', 'format': 'email'},
            'ops@',
            'Not an email address, such as name@example.com',
          ),
          (
            'minimum',
            {'type': 'integer', 'minimum': 1},
            0,
            'A whole number of 1 or more',
          ),
          (
            'maximum',
            {'type': 'number', 'maximum': 1},
            2,
            'A number of 1 or less',
          ),
          (
            'both bounds',
            {'type': 'integer', 'minimum': 1, 'maximum': 9},
            12,
            'A whole number from 1 to 9',
          ),
          (
            'minItems',
            {
              'type': 'array',
              'minItems': 2,
              'items': {
                'type': 'string',
                'enum': ['a', 'b', 'c'],
              },
            },
            ['a'],
            'Pick at least 2',
          ),
          (
            'maxItems',
            {
              'type': 'array',
              'maxItems': 1,
              'items': {
                'anyOf': [
                  {'const': 'a', 'title': 'A'},
                  {'const': 'b', 'title': 'B'},
                ],
              },
            },
            ['a', 'b'],
            'Pick at most 1',
          ),
          (
            'items',
            {
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': ['a'],
              },
            },
            ['z'],
            'Not one of the choices',
          ),
          (
            'enum',
            {
              'type': 'string',
              'enum': ['x'],
            },
            'y',
            'Not one of the choices',
          ),
          (
            'oneOf',
            {
              'type': 'string',
              'oneOf': [
                {'const': 'eu'},
                {'const': 'us'},
              ],
            },
            'zz',
            'Not one of the choices',
          ),
        ]) {
      test(keyword, () => expect(check(property, value), words));
    }

    test("a string's format is reported before its lengths and pattern, as "
        "zod builds them", () {
      const property = {
        'type': 'string',
        'minLength': 3,
        'pattern': '^z',
        'format': 'email',
      };
      for (final value in ['a', 'abc']) {
        expect(
          check(property, value),
          'Not an email address, such as name@example.com',
        );
      }
      // Its lengths before its pattern.
      expect(
        check({'type': 'string', 'minLength': 3, 'pattern': '^z'}, 'a'),
        'At least 3 characters',
      );
    });

    test('a number field reads its typed text that is no number as its '
        'bounds', () {
      final [field] = fieldsOf({
        'type': 'object',
        'properties': {
          'whole': {'type': 'integer'},
        },
      });
      final form = FormData.initial([field]).type('1.5');
      // A point is not typed into a whole number: none of it goes.
      expect(form.values, isEmpty);
      final typed = FormData.initial([field]).type('-').next();
      expect(typed.problems, {'whole': 'A whole number'});
    });

    test('a valid value has no words, and a schema the package cannot build '
        'leaves values unchecked', () {
      expect(check({'type': 'string', 'maxLength': 5}, 'abc'), isNull);
      expect(check({'type': 'string', 'pattern': '('}, 'abc'), isNull);
    });
  });

  test("a yes-or-no field is checked by its schema's const and enum", () {
    for (final property in [
      {'type': 'boolean', 'const': true, 'default': false},
      {
        'type': 'boolean',
        'enum': [true],
        'default': false,
      },
    ]) {
      final form = open({
        'type': 'object',
        'properties': {'agree': property},
      });
      expect(form.problems, {'agree': 'Not one of the choices'});
      expect(form.next().submit().values, isNull);
      expect(form.toggle().submit().values, {'agree': true});
    }
  });

  test("a schema the package cannot build as a whole leaves every field "
      "unchecked, as zod's fallback does", () {
    final form = open({
      'type': 'object',
      'properties': {
        'a': {'type': 'string', 'pattern': '('},
        'b': {'type': 'string', 'maxLength': 2},
      },
    }).type('x').next().type('abc');
    expect(form.problems, isEmpty);
    expect(form.next().submit().values, {'a': 'x', 'b': 'abc'});
  });

  test('an answered form reads back as the form showed it', () {
    const content = {
      'name': 'web-app',
      'replicas': 3,
      'public': true,
      'region': 'us',
      'tags': ['web', 'worker'],
    };
    expect(answeredRows(formSchema, content), [
      (label: 'Project name', value: 'web-app'),
      (label: 'Replicas', value: '3'),
      (label: 'Public', value: 'Yes'),
      (label: 'Region', value: 'United States'),
      (label: 'Tags', value: 'web, worker'),
    ]);
    expect(answeredText(content), 'Answered · 5 fields');
    expect(
      answeredRows(
        {
          'type': 'object',
          'properties': {
            'n': {'type': 'number'},
            'r': {'type': 'number'},
          },
        },
        {'n': 3.0, 'r': 0.25},
      ),
      [(label: 'n', value: '3'), (label: 'r', value: '0.25')],
    );
    expect(answeredText({'name': 'x'}), 'Answered · 1 field');
    expect(answeredText(null), 'Answered');
  });

  test('a link names its host, and only a web link has one', () {
    expect(
      linkHost('https://example.com/oauth/authorize?client=abc'),
      'example.com',
    );
    expect(linkHost('file:///etc/passwd'), isNull);
    expect(linkHost('not a url'), isNull);
    // As the original's WHATWG URL reads them.
    expect(linkHost(' https://example.com/x '), 'example.com');
    expect(linkHost('https://[::1]:443/x'), '[::1]');
    expect(linkHost('https://bücher.example/x'), 'xn--bcher-kva.example');
    expect(linkHost('https://BÜCHER.example/x'), 'xn--bcher-kva.example');
    expect(linkHost('HTTPS://User:pw@Example.COM:8080/x'), 'example.com');
  });
}

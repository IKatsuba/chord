import 'package:chord/ui/dialogs/form.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

FormData _open(
  Map<String, Object?> properties, {
  List<String> required = const [],
}) => FormData.initial(
  fieldsOf({'type': 'object', 'properties': properties, 'required': required}),
);

void main() {
  group('tester schema form integration', () {
    test(
      'both boolean const directions and enum defaults revalidate on toggles',
      () {
        for (final allowed in [true, false]) {
          for (final rule in [
            <String, Object?>{'const': allowed},
            <String, Object?>{
              'enum': [allowed],
            },
          ]) {
            var form = _open({
              'b': {'type': 'boolean', ...rule, 'default': !allowed},
            });
            expect(form.problems, {'b': 'Not one of the choices'});
            form = form.submit().form;
            expect(form.toFix, 1);
            form = form.toggle();
            expect(form.problems, isEmpty);
            expect(form.submit().values, {'b': allowed});
            expect(form.toggle().submit().values, isNull);
          }
        }
      },
    );

    test(
      'one malformed property disables all schema validators but keeps required and syntax checks',
      () {
        var calls = 0;
        final properties = <String, Object?>{
          'bad': {'type': 'string', 'pattern': '('},
          'text': {'type': 'string', 'maxLength': 1},
          'flag': {'type': 'boolean', 'const': true, 'default': false},
          'number': {'type': 'integer', 'minimum': 1},
          'missing': {'type': 'string'},
        };
        final fields = fieldsOf(
          {
            'type': 'object',
            'properties': properties,
            'required': ['missing'],
          },
          check: (_, _) {
            calls++;
            return 'should not run';
          },
        );
        final form = FormData.initial(
          fields,
        ).type('x').next().type('too long').next().next().type('-');
        expect(form.problems, {
          'number': 'A whole number of 1 or more',
          'missing': 'Required',
        });
        expect(calls, 0);
        expect(form.submit().values, isNull);
      },
    );

    test('combined text constraints report the first failed keyword only', () {
      final property = <String, Object?>{
        'type': 'string',
        'minLength': 3,
        'pattern': '^z',
        'format': 'email',
      };
      expect(
        checkValue(property, 'a'),
        'Not an email address, such as name@example.com',
      );
      expect(
        checkValue(property, 'abc'),
        'Not an email address, such as name@example.com',
      );
      expect(
        checkValue(property, 'zabc'),
        'Not an email address, such as name@example.com',
      );
      expect(checkValue(property, 'z@example.com'), isNull);
    });

    test(
      'choice constraints and multi bounds remain active with titled options',
      () {
        var form = _open({
          'c': {
            'type': 'string',
            'oneOf': [
              {'const': 'a', 'title': 'Alpha'},
              {'const': 'b', 'title': 'Beta'},
            ],
            'pattern': '^a',
          },
          'm': {
            'type': 'array',
            'items': {
              'anyOf': [
                {'const': 'a', 'title': 'Alpha'},
                {'const': 'b', 'title': 'Beta'},
              ],
            },
            'minItems': 2,
            'maxItems': 2,
          },
        });
        form = form.openList().pick(2);
        expect(form.problems, {'c': 'Must match ^a'});
        form = form.openList().pick(1).next().openList().tick();
        expect(form.problems, {'m': 'Pick at least 2'});
        form = form.nextOption().tick().closeList();
        expect(form.submit().values, {
          'c': 'a',
          'm': ['a', 'b'],
        });
      },
    );

    test(
      'inclusive and exclusive numeric limits and multipleOf keep numeric wording',
      () {
        const property = <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
          'exclusiveMinimum': 0,
          'multipleOf': 0.25,
        };
        for (final value in [-0.25, 0, 0.1, 1.25]) {
          expect(checkValue(property, value), 'A number from 0 to 1');
        }
        for (final value in [0.25, 0.5, 1]) {
          expect(checkValue(property, value), isNull);
        }
        final fields = fieldsOf({
          'type': 'object',
          'properties': {'n': property},
        });
        expect(FormData.initial(fields).type('-.').problems, {
          'n': 'A number from 0 to 1',
        });
      },
    );

    test(
      'answered rows retain schema order titles and unknown-option fallbacks',
      () {
        final schema = <String, Object?>{
          'type': 'object',
          'properties': {
            'yes': {'type': 'boolean', 'title': 'Allowed'},
            'choice': {
              'type': 'string',
              'oneOf': [
                {'const': 'a', 'title': 'Alpha'},
              ],
            },
            'multi': {
              'type': 'array',
              'items': {
                'enum': ['x', 'y'],
              },
            },
            'missing': {'type': 'string'},
          },
        };
        expect(
          answeredRows(schema, {
            'extra': 'ignored',
            'multi': ['y', 'unknown'],
            'choice': 'other',
            'yes': false,
          }),
          [
            (label: 'Allowed', value: 'No'),
            (label: 'choice', value: 'other'),
            (label: 'multi', value: 'y, unknown'),
          ],
        );
        expect(answeredText({}), 'Answered');
        expect(answeredText({'a': false}), 'Answered · 1 field');
      },
    );

    test('integral double answers read as the original number', () {
      expect(
        answeredRows(
          {
            'type': 'object',
            'properties': {
              'n': {'type': 'number'},
            },
          },
          {'n': 3.0},
        ),
        [(label: 'n', value: '3')],
      );
    });

    test('link host normalizes whitespace IPv6 and international names', () {
      expect(linkHost('https://[::1]:443/x'), '[::1]');
      expect(linkHost(' https://example.com/x '), 'example.com');
      expect(linkHost('https://bücher.example/x'), 'xn--bcher-kva.example');
      expect(linkHost('https://BÜCHER.example/x'), 'xn--bcher-kva.example');
    });

    test(
      'link destination ignores credentials ports paths and unsupported schemes',
      () {
        expect(linkHost('HTTPS://EXAMPLE.COM:443/path'), 'example.com');
        expect(
          linkHost(
            'https://person:secret@actual.example:8443/path?redirect=other.example',
          ),
          'actual.example',
        );
        for (final url in [
          'javascript:alert(1)',
          'file:///etc/passwd',
          'mailto:a@example.com',
          '/relative',
          'https://',
        ]) {
          expect(linkHost(url), isNull, reason: url);
        }
      },
    );
  });
}

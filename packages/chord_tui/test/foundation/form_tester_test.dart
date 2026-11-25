import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

FormData _number(String text, {bool integer = false}) => FormData.initial([
  NumberFormItem(name: 'n', label: 'N', integer: integer),
]).type(text);

void main() {
  group('tester CTUI-70: every long-list anchor', () {
    for (final multiple in [false, true]) {
      test(
        'all highlights stay visible within every small limit, multi=$multiple',
        () {
          final options = [
            for (var i = 0; i < 12; i++)
              PickerItem(value: i, label: 'Option $i 界🙂e\u0301'),
          ];
          final fields = <FormItem>[
            const TextFormItem(name: 'before', label: 'Before'),
            if (multiple)
              MultiChoiceFormItem<int>(
                name: 'list',
                label: 'List',
                options: options,
              )
            else
              ChoiceFormItem<int>(
                name: 'list',
                label: 'List',
                options: options,
              ),
            const TextFormItem(name: 'after', label: 'After'),
          ];
          var form = FormData.initial(fields).next().openList();
          for (var highlight = 0; highlight < 12; highlight++) {
            for (var limit = -2; limit <= 16; limit++) {
              final rows = form.rows(limit);
              expect(rows.length, lessThanOrEqualTo(limit < 0 ? 0 : limit));
              if (limit > 0) {
                expect(
                  rows
                      .whereType<FormFieldRow>()
                      .where((row) => row.focused)
                      .single
                      .item
                      .name,
                  'list',
                );
              }
              if (limit >= 2) {
                expect(
                  rows
                      .whereType<FormOptionRow>()
                      .where((row) => row.highlighted)
                      .single
                      .label,
                  'Option $highlight 界🙂e\u0301',
                );
              }
              expect(form.highlighted, highlight);
              expect(form.listOpen, isTrue);
            }
            form = form.nextOption();
          }
        },
      );
    }
  });

  group('tester form reducer boundaries', () {
    test('signed integer endpoints submit and either overflow is refused', () {
      for (final text in ['-9223372036854775808', '9223372036854775807']) {
        final form = _number(text, integer: true);
        expect(form.problems, isEmpty);
        expect(form.submit().values, {'n': int.parse(text)});
        expect(jsonEncode(form.values), isNotEmpty);
      }
      for (final text in ['-9223372036854775809', '+9223372036854775808']) {
        final form = _number(text, integer: true);
        expect(form.problems, {'n': 'Not a whole number'});
        expect(form.values, isEmpty);
        expect(form.submit().values, isNull);
      }
    });

    test(
      'decimal signs, leading and trailing points agree with submission',
      () {
        for (final pair in <(String, num)>[
          ('+.5', 0.5),
          ('-.5', -0.5),
          ('+1.', 1),
          ('-0', 0),
          ('00.25', 0.25),
        ]) {
          final form = _number(pair.$1);
          expect(form.problems, isEmpty, reason: pair.$1);
          expect(form.submit().values, {'n': pair.$2});
        }
        for (final text in ['+', '-', '.', '+.', '1.2.3', '1--2']) {
          final form = _number(text);
          expect(form.problems, {'n': 'Not a number'}, reason: text);
          expect(form.submit().values, isNull);
          expect(form.values, isEmpty);
        }
      },
    );

    test(
      'range validators see exact text and reject either side inclusively',
      () {
        for (final text in ['-1.01', '-1', '0', '1', '1.01']) {
          final seen = <String>[];
          final form = FormData.initial([
            NumberFormItem(
              name: 'n',
              label: 'N',
              validator: (raw) {
                seen.add(raw);
                final number = num.tryParse(raw);
                return number != null && number >= -1 && number <= 1
                    ? null
                    : 'Range -1 to 1';
              },
            ),
          ]).type(text);
          final accepted = text == '-1' || text == '0' || text == '1';
          expect(form.submit().values != null, accepted);
          expect(seen, everyElement(text));
        }
      },
    );

    test('grapheme edits preserve old snapshots and count clusters', () {
      final original = FormData.initial(const [
        TextFormItem(name: 't', label: 'T'),
      ]).type('界👩‍💻e\u0301');
      expect(original.cursor, 3);
      final edited = original.cursorLeft().backspace().type('🙂');
      expect(edited.values, {'t': '界🙂e\u0301'});
      expect(edited.cursor, 2);
      expect(original.values, {'t': '界👩‍💻e\u0301'});
      expect(original.cursor, 3);
      expect(() => original.fields.clear(), throwsUnsupportedError);
    });

    test(
      'invalid choice defaults and empty lists stay safe through all actions',
      () {
        var form = FormData.initial(const [
          ChoiceFormItem<String>(
            name: 'c',
            label: 'C',
            initialValue: 'missing',
            options: [],
          ),
          MultiChoiceFormItem<String>(
            name: 'm',
            label: 'M',
            initialValue: ['missing'],
            options: [],
          ),
          UnsupportedFormItem(name: 'u', label: 'U', required: true),
        ]);
        for (var i = 0; i < 3; i++) {
          form = form
              .openList()
              .nextOption()
              .previousOption()
              .pick(9)
              .tick()
              .closeList();
          expect(form.values, isEmpty);
          form = form.next();
        }
        expect(form.submit().values, isNull);
        expect(form.submit().form.focus, const FormFocus.field(2));
        expect(form.problems, {'u': 'Required'});
      },
    );

    test(
      'finite defaults and non-finite defaults agree with required validation',
      () {
        for (final initial in <num>[0, -0.5, 1.5, -9223372036854775808]) {
          final form = FormData.initial([
            NumberFormItem(name: 'n', label: 'N', initialValue: initial),
          ]);
          expect(form.problems, isEmpty);
          expect(form.values, {'n': initial});
        }
        for (final initial in [
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ]) {
          final form = FormData.initial([
            NumberFormItem(
              name: 'n',
              label: 'N',
              required: true,
              initialValue: initial,
            ),
          ]);
          expect(form.problems, {'n': 'Required'});
          expect(form.values, isEmpty);
        }
      },
    );
  });
}

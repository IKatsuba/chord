import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/ui/prompt/commands.dart';
import 'package:test/test.dart';

void main() {
  group('tester command input boundaries', () {
    test('malformed advertisements do not hide valid Unicode commands', () {
      final items = commandItems([
        acp.AvailableCommand.fromJson({'name': 7, 'description': 'bad name'}),
        acp.AvailableCommand.fromJson({'name': 'bad', 'description': 7}),
        acp.AvailableCommand.fromJson({
          'name': '界🙂e\u0301',
          'description': '  First line\r\nsecond line  ',
        }),
        acp.AvailableCommand.fromJson({'name': 'blank', 'description': ' \n '}),
      ]);
      final unicode = items.singleWhere((i) => i.name == '界🙂e\u0301');
      expect(unicode.local, isFalse);
      expect(unicode.description, 'First line');
      expect(items.where((i) => i.name == 'bad'), isEmpty);
      expect(items.singleWhere((i) => i.name == 'blank').description, isNull);
      final sent =
          submitted('/界🙂e\u0301  argument\nsecond line') as SendSubmitted;
      expect(sent.text, '/界🙂e\u0301  argument\nsecond line');
    });

    test(
      'typed local arguments survive whitespace while completion drops them',
      () {
        final typed =
            submitted(' \n/model\t界🙂e\u0301\nnext  ') as LocalSubmitted;
        expect(typed.name, 'model');
        expect(typed.args, '界🙂e\u0301\nnext');
        final completed =
            submitted('/mo stale', const CommandItem('model', ''))
                as LocalSubmitted;
        expect(completed.name, 'model');
        expect(completed.args, isEmpty);
        for (final input in ['/model\t', '/model\n', '/model argument']) {
          expect(commandQuery(input), isNull);
        }
        expect(
          submitted('/resume\nprivate argument'),
          isA<LocalSubmitted>()
              .having((s) => s.name, 'name', 'resume')
              .having((s) => s.args, 'args', 'private argument'),
        );
      },
    );
  });
}

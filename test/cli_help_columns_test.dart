import 'package:chord/cli.dart';
import 'package:test/test.dart';

void main() {
  test('every option of chord --help starts its words in one column, '
      '-r, --resume [id] included (CTUI-149)', () {
    final lines = chordHelp.split('\n');
    final options = lines
        .skip(lines.indexOf('Options:') + 1)
        .takeWhile((line) => line.isNotEmpty)
        .toList();
    expect(options, contains(startsWith('  -r, --resume [id] ')));
    final columns = {
      for (final line in options)
        RegExp(r'^ +\S.*?\S {2,}').firstMatch(line)!.end,
    };
    expect(columns, hasLength(1), reason: options.join('\n'));
  });
}

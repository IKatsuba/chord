import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

SelectionSource _source(String text, {SelectionSource? previous}) =>
    SelectionSource.markdown(
      id: 'reply',
      revision: text,
      text: text,
      previous: previous,
    );

void main() {
  for (final (name, text, closed, code) in [
    ('EOF open', '```sh\necho', false, 'echo'),
    ('opening only', '```', false, ''),
    ('EOF closer', '```sh\necho\n```', true, 'echo'),
    ('empty closed', '```\n```', true, ''),
    ('empty open', '```\n', false, ''),
    ('tildes', '~~~sh\necho\n~~~~', true, 'echo'),
    ('longer closer', '````sh\necho\n`````', true, 'echo'),
    ('short fence is body', '````\necho\n```', false, 'echo\n```'),
    ('info string is body', '```\necho\n```sh', false, 'echo\n```sh'),
    ('wrong marker is body', '```\necho\n~~~', false, 'echo\n~~~'),
    ('blank code rows', '```\n\techo\n\n```', true, '\techo\n'),
    ('indented complete', '    echo', true, 'echo'),
    ('quoted closed', '> ```sh\n> echo\n> ```', true, 'echo'),
    ('quoted open', '> ```sh\n> echo', false, 'echo'),
    ('list closed', '- item\n\n  ```sh\n  echo\n  ```', true, 'echo'),
    ('list open', '- item\n\n  ```sh\n  echo', false, 'echo'),
    (
      'nested quote/list',
      '> - item\n>\n>   ```sh\n>   echo\n>   ```',
      true,
      'echo',
    ),
  ]) {
    test('public parser adapter records $name', () {
      final blocks = _source(text).codeBlocks;
      expect(blocks, hasLength(1));
      expect(blocks.single.complete, closed);
      expect(blocks.single.text, code);
      expect(() => blocks.clear(), throwsUnsupportedError);
    });
  }
  test(
    'appended closer updates completeness without mutating an old descriptor',
    () {
      final open = _source('```sh\necho');
      final before = open.codeBlocks.single;
      final closed = _source('```sh\necho\n```', previous: open);
      final after = closed.codeBlocks.single;
      expect(before.complete, isFalse);
      expect(after.complete, isTrue);
      expect(after.id, before.id);
      expect(open.codeBlocks.single.complete, isFalse);
      expect(after.id.sourceId, 'reply');
    },
  );
}

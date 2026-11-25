import 'package:characters/characters.dart';
import 'package:chord/ui/prompt/mentions.dart';
import 'package:test/test.dart';

void main() {
  group('tester: mention grapheme and snapshot boundaries', () {
    test(
      'joined trigger clusters replace literally at start, prefix and multiline',
      () {
        for (final prefix in ['', '界👩‍💻é ', 'before\n界 ']) {
          for (final mark in ['\u0301\u0308', '\u20e3', '\u200d', '👩‍💻']) {
            for (final trigger in ['@', '@@', '@@"']) {
              final typed = '$prefix$trigger$mark';
              final draft =
                  '$typed-tail${trigger == '@@"' ? '"' : ''}  suffix\nnext';
              final cursor = typed.characters.length;
              final mention = completionAt(draft, cursor)!;
              expect(mention.start, prefix.characters.length);
              expect(mention.query, mark);
              const name = '界 é👩‍💻';
              final inserted = mention is AgentMention
                  ? insertAgentMention(draft, cursor, mention, name)
                  : insertMention(draft, cursor, mention, name);
              final written = '${trigger == '@' ? '@' : '@@'}"$name"';
              expect(inserted.text, '$prefix$written  suffix\nnext');
              expect(inserted.cursor, '$prefix$written '.characters.length);
              expect(completionAt(inserted.text, inserted.cursor), isNull);
              expect(
                mentionsIn(inserted.text),
                trigger == '@' ? [name] : isEmpty,
              );
            }
          }
        }
      },
    );

    test(
      'matcher freezes one candidate identity and replacement invalidates old work',
      () async {
        final matcher = MentionMatcher();
        addTearDown(matcher.dispose);
        final items = ['café', '界same'];
        expect(await matcher.match(items, ''), ['café', '界same']);
        items.add('new');
        expect(await matcher.match(items, ''), ['café', '界same']);
        final pending = matcher.match(items, 'cafe');
        final replacement = List<String>.of(items);
        expect(await matcher.match(replacement, ''), replacement);
        expect(await pending, isNull);
        final result = (await matcher.match(replacement, 'new'))!;
        expect(result, ['new']);
        expect(() => result.add('other'), throwsUnsupportedError);
      },
    );
  });
}

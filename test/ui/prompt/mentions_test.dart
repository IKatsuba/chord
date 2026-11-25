import 'dart:async';
import 'package:characters/characters.dart';
import 'package:chord/ui/prompt/mentions.dart';
import 'package:test/test.dart';

void main() {
  test(
    'trigger-boundary graphemes keep valid starts and exact literal insertion',
    () {
      for (final prefix in ['', 'word ', 'one\n🙂 ']) {
        for (final mark in ['\u0301', '\uFE0F']) {
          for (final trigger in ['@', '@@', '@@"']) {
            final typed = '$prefix$trigger$mark';
            final draft = '$typed-tail${trigger == '@@"' ? '"' : ''} suffix';
            final cursor = typed.characters.length;
            final mention = completionAt(draft, cursor)!;
            expect(mention.start, prefix.characters.length, reason: draft);
            expect(mention.query, mark);
            final name = '${mark}name file.md';
            final inserted = mention is AgentMention
                ? insertAgentMention(draft, cursor, mention, name)
                : insertMention(draft, cursor, mention, name);
            final expected =
                '$prefix${trigger == '@' ? '@' : '@@'}"$name" suffix';
            expect(inserted.text, expected);
            expect(
              inserted.cursor,
              expected
                  .substring(0, expected.indexOf(' suffix') + 1)
                  .characters
                  .length,
            );
          }
        }
      }
    },
  );
  test('file query boundaries, cursor prefixes, multiline and graphemes', () {
    for (final (text, query, start) in [
      ('@', '', 0),
      ('look at @src/ma', 'src/ma', 8),
      ('one\ntwo @a', 'a', 8),
      ('🙂e\u0301 @解析', '解析', 3),
      ('\t@a', 'a', 1),
    ]) {
      final m = mentionAt(text, text.characters.length)!;
      expect((m.query, m.start), (query, start));
      expect(m, Mention(query: query, start: start));
    }
    expect(mentionAt('@src/main.ts', 4)?.query, 'src');
    for (final text in [
      'me@example.com',
      '@a ',
      'plain',
      '@@parser',
      '@@"bugfix 2',
    ]) {
      expect(mentionAt(text, text.characters.length), isNull, reason: text);
    }
    expect(mentionAt('@a', -1), isNull);
    expect(mentionAt('@a', 99), isNull);
  });
  test(
    'agent precedence and completed quotes containing @ cannot reopen files',
    () {
      for (final (text, query, start, quoted) in [
        ('@@', '', 0, false),
        ('ask @@Parser', 'Parser', 4, false),
        ('one\n@@"bugfix 2', 'bugfix 2', 4, true),
        ('@@"', '', 0, true),
        ('🙂 @@"a @notes.md', 'a @notes.md', 2, true),
      ]) {
        final m = completionAt(text, text.characters.length)!;
        expect(m, isA<AgentMention>());
        expect((m.query, m.start, m.quoted), (query, start, quoted));
      }
      for (final text in [
        'a@@parser',
        '@@parser ',
        '@@"bugfix 2"',
        '@@"a @notes.md"',
        '@@"a @notes.md"x',
      ]) {
        expect(
          completionAt(text, text.characters.length),
          isNull,
          reason: text,
        );
      }
      expect(completionAt('@@"a @hidden" @real', 19)?.query, 'real');
    },
  );
  test(
    'file insertion replaces full token and retains suffix, quoting and end cursor',
    () {
      for (final (draft, cursor, path, expected) in [
        (
          'look at @stt please',
          12,
          'src/ui/state.ts',
          'look at @src/ui/state.ts please',
        ),
        ('@a', 2, 'a.ts', '@a.ts '),
        ('@srcmain', 4, 'b.ts', '@b.ts '),
        ('one\n@my', 7, 'my f.md', 'one\n@"my f.md" '),
        ('🙂e\u0301 @paold\nnext', 6, '解析 x.md', '🙂e\u0301 @"解析 x.md" \nnext'),
      ]) {
        final inserted = insertMention(
          draft,
          cursor,
          mentionAt(draft, cursor)!,
          path,
        );
        expect(inserted.text, expected);
        final lineEnd = expected.indexOf('\n', expected.indexOf('@'));
        final end = lineEnd < 0 ? expected.length : lineEnd;
        final separator = expected.indexOf(' please');
        expect(
          inserted.cursor,
          expected
              .substring(0, separator >= 0 ? separator + 1 : end)
              .characters
              .length,
        );
      }
    },
  );
  test(
    'agent insertion consumes quoted closer, preserves suffix and excludes attachments',
    () {
      for (final name in [
        'parser',
        'bugfix 2',
        '解析🚀',
        r'a\b',
        "a'b",
        '@notes.md',
        'reader @notes.md',
        'a\u00a0@notes.md',
      ]) {
        const draft = 'first @first.ts\nask @@old-tail @keep.ts\n@last.ts';
        final cursor = 'first @first.ts\nask @@old'.characters.length;
        final inserted = insertAgentMention(
          draft,
          cursor,
          agentMentionAt(draft, cursor)!,
          name,
        );
        final token = '@@${RegExp(r'\s').hasMatch(name) ? '"$name"' : name}';
        expect(inserted.text, 'first @first.ts\nask $token @keep.ts\n@last.ts');
        expect(
          inserted.cursor,
          'first @first.ts\nask $token '.characters.length,
        );
        expect(completionAt(inserted.text, inserted.cursor), isNull);
        expect(mentionsIn(inserted.text), ['first.ts', 'keep.ts', 'last.ts']);
      }
      for (final (draft, cursor, name, expected) in [
        ('@@"unfinished name', 5, 'parser', '@@parser '),
        ('@@p  please', 3, 'parser', '@@parser  please'),
        (
          'one\n@@"bugfix 2" please',
          10,
          'bugfix 3',
          'one\n@@"bugfix 3" please',
        ),
      ]) {
        expect(
          insertAgentMention(
            draft,
            cursor,
            agentMentionAt(draft, cursor)!,
            name,
          ).text,
          expected,
        );
      }
    },
  );
  test(
    'attachment scan consumes agent tokens and preserves literal file order',
    () {
      expect(
        mentionsIn(
          '@a.ts and @"my notes.md"\nthen @src/b.ts, not me@there.com',
        ),
        ['a.ts', 'my notes.md', 'src/b.ts,'],
      );
      expect(mentionsIn('@@parser @@"bugfix 2"'), isEmpty);
      expect(mentionsIn('@@"unfinished @hidden\n@real.ts'), ['real.ts']);
      expect(mentionsIn('@@ @a.ts'), ['a.ts']);
      expect(mentionsIn('@a @@"reader @hidden" @a @b'), ['a', 'a', 'b']);
      expect(mentionsIn('a lone @ and none'), isEmpty);
    },
  );
  test('first files cap and exact name dedup retain source order', () {
    final files = List.generate(150, (i) => '$i');
    expect(firstFiles(files), files.take(100));
    expect(() => firstFiles(files).clear(), throwsUnsupportedError);
    final recipients = [(1, 'main'), (2, 'coder'), (3, 'coder'), (4, 'Coder')];
    expect(mentionRecipients(recipients, nameOf: (r) => r.$2), [
      recipients[0],
      recipients[1],
      recipients[3],
    ]);
  });
  test(
    'approved async matcher keeps original scoring, shorter ties and cap',
    () async {
      final matcher = MentionMatcher();
      addTearDown(matcher.dispose);
      final files = [
        'README.md',
        'deno.json',
        'src/main.tsx',
        'src/ui/App.tsx',
        'src/ui/state.ts',
        'tests/state_test.ts',
      ];
      expect(await matcher.match(files, 'stt'), [
        'src/ui/state.ts',
        'tests/state_test.ts',
      ]);
      expect((await matcher.match(files, 'APP'))!.first, 'src/ui/App.tsx');
      expect(await matcher.match(files, 'zzz'), isEmpty);
      expect(await matcher.match(files, ''), files);
      final names = ['parser-long', 'parser', 'bugfix 2', 'main'];
      expect(await matcher.match(names, 'PRS'), ['parser', 'parser-long']);
      expect(await matcher.match(names, 'bf2'), ['bugfix 2']);
      final many = List.generate(5000, (i) => 'src/file$i.ts');
      expect((await matcher.match(many, 'file'))!.length, 100);
    },
  );
  test(
    'match yields and superseded candidates/query/disposal publish null',
    () async {
      final matcher = MentionMatcher();
      final files = List.generate(5000, (i) => 'src/file$i.ts');
      var done = false, ticked = false;
      final old = matcher.match(files, 'file1').then((r) {
        done = true;
        return r;
      });
      expect(done, isFalse);
      final timer = Completer<void>();
      Timer.run(() {
        ticked = true;
        expect(done, isFalse);
        timer.complete();
      });
      await timer.future;
      final current = matcher.match(files, 'file42');
      expect(await old, isNull);
      expect((await current)!.first, 'src/file42.ts');
      expect(ticked, isTrue);
      final replaced = matcher.match(files, 'file');
      expect(await matcher.match(['literal'], ''), ['literal']);
      expect(await replaced, isNull);
      final pending = matcher.match(files, 'file');
      matcher.dispose();
      matcher.dispose();
      expect(await pending, isNull);
      expect(await matcher.match(files, ''), isNull);
    },
  );
}

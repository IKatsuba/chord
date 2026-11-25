import 'package:chord/ui/prompt/search.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:test/test.dart';

const prompts = [
  'fix the login bug in auth.ts',
  'explain the auth flow',
  '!echo auth ok',
  'explain the auth flow',
  'what is next',
];
Search typed(String query) => searched(emptySearch, prompts, query);
(String, int?, bool) facts(Search value) =>
    (value.query, value.match, value.failed);

void main() {
  _testerSearchBoundaries();
  test('newest literal case-sensitive prompt wins at its last occurrence', () {
    expect(typed('auth').match, 3);
    expect(matched(typed('auth'), prompts), 'explain the auth flow');
    expect(matched(typed('next'), prompts), 'what is next');
    expect(typed('AUTH').match, isNull);
    expect(typed('AUTH').failed, isTrue);
    expect(matched(typed('!'), prompts), '!echo auth ok');
  });

  test(
    'empty query matches nothing and clears a previously retained match',
    () {
      expect(facts(typed('')), facts(emptySearch));
      expect(matched(emptySearch, prompts), isNull);
      expect(searchedOlder(emptySearch, prompts), same(emptySearch));
      final failed = searched(typed('auth'), prompts, 'missing');
      expect(facts(searched(failed, prompts, '')), facts(emptySearch));
      expect(searched(emptySearch, [], 'x').failed, isTrue);
    },
  );

  test(
    'older skips earlier duplicate prompts and exhaustion retains the match',
    () {
      final second = searchedOlder(typed('auth'), prompts);
      final third = searchedOlder(second, prompts);
      expect(matched(second, prompts), '!echo auth ok');
      expect(matched(third, prompts), 'fix the login bug in auth.ts');
      expect(third.failed, isFalse);
      final past = searchedOlder(third, prompts);
      expect(past.match, third.match);
      expect(past.failed, isTrue);
      expect(searchLabel(past), 'no matching prompt:');
      expect(searchedOlder(past, prompts), same(past));
    },
  );

  test('query change restarts at newest and a miss retains the old match', () {
    final second = searchedOlder(typed('auth'), prompts);
    final narrowed = searched(second, prompts, 'auth f');
    expect(narrowed.match, 3);
    expect(searchLabel(narrowed), 'search prompts:');
    final missed = searched(narrowed, prompts, 'auth fz');
    expect(missed.match, narrowed.match);
    expect(missed.failed, isTrue);
    expect(searched(missed, prompts, 'auth f').failed, isFalse);
  });

  test('editing deletes one code point before modifier handling', () {
    expect(editedQuery('au', 't'), 'aut');
    expect(editedQuery('aut', '', backspace: true), 'au');
    expect(editedQuery('a😀', '', delete: true), 'a');
    expect(editedQuery('', '', backspace: true), '');
    expect(editedQuery('é', '', backspace: true), 'e');
    expect(editedQuery('👩‍💻', '', ctrl: true, delete: true), '👩‍');
    expect(editedQuery('au', 'r', ctrl: true), isNull);
    expect(editedQuery('au', 'b', meta: true), isNull);
  });

  test('paste searches its first line and strips only Unicode Cc controls', () {
    for (final separator in ['\n', '\r\n', '\r']) {
      expect(editedQuery('', 'one${separator}two'), 'one');
    }
    expect(editedQuery('au', '\t'), isNull);
    expect(editedQuery('', '\nignored'), isNull);
    expect(editedQuery('', 'a\u0000\u001f\u007f\u0085\u009fb'), 'ab');
    expect(editedQuery('', '\u200d\uFEFF'), '\u200d\uFEFF');
    expect(editedQuery('x', ''), isNull);
  });

  test(
    'literal pattern never interprets metacharacters or normalizes Unicode',
    () {
      expect(queryPattern(''), isNull);
      expect(queryPattern('a.b')!.allMatches('a.b axb a.b').map((m) => m[0]), [
        'a.b',
        'a.b',
      ]);
      for (final query in ['[x]', '(a)', r'$^.*+?{}|\', '界😀', 'é']) {
        final text = '$query $query';
        expect(queryPattern(query)!.allMatches(text).map((m) => m[0]), [
          query,
          query,
        ]);
      }
      expect(searched(emptySearch, ['é'], 'é').match, isNull);
    },
  );

  test(
    'piece projection preserves text and all nonoverlapping literal hits',
    () {
      expect(foundPieces('fix auth', ''), [(text: 'fix auth', found: false)]);
      expect(foundPieces('auth or auth', 'auth'), [
        (text: 'auth', found: true),
        (text: ' or ', found: false),
        (text: 'auth', found: true),
      ]);
      expect(foundPieces('say 👩‍💻\tauth.', 'auth'), [
        (text: 'say 👩‍💻\t', found: false),
        (text: 'auth', found: true),
        (text: '.', found: false),
      ]);
      expect(foundPieces('', 'auth'), [(text: '', found: false)]);
      expect(foundPieces('aaa', 'aa'), [
        (text: 'aa', found: true),
        (text: 'a', found: false),
      ]);
      expect(foundPieces('xxxx', 'xx'), [
        (text: 'xx', found: true),
        (text: 'xx', found: true),
      ]);
      const multiline = 'a\n界😀needle\nneedle';
      expect(
        foundPieces(multiline, 'needle').map((p) => p.text).join(),
        multiline,
      );
      expect(
        foundPieces(multiline, 'needle').where((p) => p.found),
        hasLength(2),
      );
    },
  );

  test(
    'control-bearing multiline history is searched whole without editing it',
    () {
      var h = const history.History();
      for (final value in [
        'auth one',
        'auth\u000cform feed\nnext',
        'auth two',
        'auth one',
      ]) {
        h = history.recorded(h, value);
      }
      final snapshot = List.of(h.prompts);
      final found = searched(emptySearch, h.prompts, 'form');
      expect(found.match, 1);
      expect(matched(found, h.prompts), 'auth\u000cform feed\nnext');
      expect(searched(emptySearch, h.prompts, 'feed\nnext').match, 1);
      expect(h.prompts, snapshot);
      expect(h.index, isNull);
      expect(h.draft, '');
      expect(matched(const Search(match: 99), h.prompts), isNull);
    },
  );
}

void _testerSearchBoundaries() {
  group('tester: U27a literal search boundaries', () {
    test(
      'distinct history walk skips every older duplicate and restarts on query change',
      () {
        const entries = [
          'Auth',
          'xauth',
          'AUTH',
          'auth',
          'xauth',
          'auth\nnext',
          'é',
          'é',
          'auth',
        ];
        final snapshot = List.of(entries);
        var state = searched(emptySearch, entries, 'auth');
        for (final expected in [8, 5, 4]) {
          expect(state.match, expected);
          expect(state.failed, isFalse);
          state = searchedOlder(state, entries);
        }
        expect(state.match, 4);
        expect(state.failed, isTrue);
        expect(searchedOlder(state, entries), same(state));
        state = searched(state, entries, 'Auth');
        expect(state.match, 0);
        expect(state.failed, isFalse);
        expect(searched(state, entries, 'é').match, 6);
        expect(searched(state, entries, 'é').match, 7);
        expect(entries, snapshot);
      },
    );

    test(
      'all non-line Cc controls strip while format characters and spaces survive',
      () {
        final controls = String.fromCharCodes([
          for (var i = 0; i <= 31; i++)
            if (i != 10 && i != 13) i,
          for (var i = 127; i <= 159; i++) i,
        ]);
        final preserved = String.fromCharCodes([
          160,
          8195,
          8203,
          8204,
          8205,
          8288,
          65279,
        ]);
        expect(editedQuery('saved', 'A${controls}B'), 'savedAB');
        expect(editedQuery('', preserved), preserved);
        expect(
          editedQuery(
            '',
            'first$controls${String.fromCharCodes([13, 10])}ignored',
          ),
          'first',
        );
        expect(editedQuery('saved', controls), isNull);
      },
    );

    test(
      'modified deletion removes one code point through a complete ZWJ sequence',
      () {
        var query = 'a👩‍💻é';
        for (final expected in ['a👩‍💻e', 'a👩‍💻', 'a👩‍', 'a👩', 'a', '']) {
          query = editedQuery(
            query,
            'ignored',
            ctrl: true,
            meta: true,
            delete: true,
          )!;
          expect(query, expected);
        }
        expect(editedQuery(query, 'ignored', backspace: true, ctrl: true), '');
        expect(editedQuery('keep', 'literal', ctrl: true), isNull);
        expect(editedQuery('keep', 'literal', meta: true), isNull);
      },
    );

    test(
      'piece runs preserve literal text and nonoverlapping counts across raw controls',
      () {
        final escape = String.fromCharCode(27),
            line = String.fromCharCode(10),
            tab = String.fromCharCode(9);
        for (final query in ['aa', '界🙂', 'é', '[x]', '.', escape, line]) {
          for (final text in [
            '$query$query',
            'prefix$tab$query$line$query suffix',
            'aaa',
            '$escape[31m$query$escape[0m',
          ]) {
            final pieces = foundPieces(text, query);
            expect(pieces.map((piece) => piece.text).join(), text);
            expect(
              pieces.where((piece) => piece.found).length,
              text.split(query).length - 1,
            );
            expect(
              pieces
                  .where((piece) => piece.found)
                  .every((piece) => piece.text == query),
              isTrue,
            );
            expect(
              pieces
                  .where((piece) => !piece.found)
                  .every((piece) => !piece.text.contains(query)),
              isTrue,
            );
          }
        }
      },
    );
  });
}

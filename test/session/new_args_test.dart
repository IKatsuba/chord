// The original's tests/session/new_args_test.ts.
import 'package:chord/session/new_args.dart';
import 'package:test/test.dart';

/// Interface draft I10's cases, as typed after `/new` and what they read
/// as; `chord acp`'s `/new` reads them through the same parser, and its
/// test shares this list.
const newArgsCases = <(String, NewArgs)>[
  ('codex --name code review', NewAsked(agent: 'codex', name: 'code review')),
  ('--name scout', NewAsked(name: 'scout')),
  ('codex --name', NewProblem(noName)),
  ('codex --name=x', NewProblem(notName)),
  ('codex extra', NewProblem(notName)),
];

void main() {
  group('I10', () {
    for (final (typed, read) in newArgsCases) {
      test('"$typed" reads as $read', () => expect(newArgs(typed), read));
    }

    test('the refusals say the usage in the words the window shows', () {
      expect(noName, '--name needs a name · /new [agent] --name <name>');
      expect(
        notName,
        '/new takes an agent, then --name <name> · /new [agent] --name <name>',
      );
    });
  });
  testerWhitespaceTests();
  group('CHD-627 literal name boundaries', () {
    for (final (typed, expected) in [
      ('--name a --name b', const NewAsked(name: 'a --name b')),
      ('--name x codex', const NewAsked(name: 'x codex')),
      ('fake --name --name=x', const NewAsked(agent: 'fake', name: '--name=x')),
      (
        '  fake\t--name  code  review  ',
        const NewAsked(agent: 'fake', name: 'code  review'),
      ),
      (r'--name $HOME; a | b', const NewAsked(name: r'$HOME; a | b')),
    ]) {
      test(
        '${typed.replaceAll('\t', r'\t')} keeps the name as literal text',
        () {
          expect(newArgs(typed), expected);
        },
      );
    }

    for (final typed in ['fake --name\t  ', 'fake\t--name\n']) {
      test('${typed.trim()} refuses a whitespace-only name', () {
        expect(newArgs(typed), const NewProblem(noName));
      });
    }
  });

  test("U+0085 is a literal name, as JavaScript's trim keeps it", () {
    expect(newArgs('--name \u0085'), const NewAsked(name: '\u0085'));
    expect(
      newArgs('fake --name a\u0085 '),
      const NewAsked(agent: 'fake', name: 'a\u0085'),
    );
  });

  group('newArgs', () {
    for (final (typed, read) in [
      ('', const NewAsked()),
      ('  ', const NewAsked()),
      ('codex', const NewAsked(agent: 'codex')),
      ('--name scout', const NewAsked(name: 'scout')),
      ('codex --name scout', const NewAsked(agent: 'codex', name: 'scout')),
      (
        'codex --name  the scout  ',
        const NewAsked(agent: 'codex', name: 'the scout'),
      ),
      ('--name codex --name', const NewAsked(name: 'codex --name')),
      ('--namex', const NewAsked(agent: '--namex')),
    ]) {
      test('"$typed" reads as $read', () => expect(newArgs(typed), read));
    }

    for (final typed in ['--name', '--name   ', 'codex --name']) {
      test('"$typed" is refused for want of a name', () {
        expect(newArgs(typed), const NewProblem(noName));
      });
    }

    for (final typed in [
      'codex scout',
      'codex --name=scout',
      'codex --other scout',
    ]) {
      test('"$typed" is refused for a word that is not --name', () {
        expect(newArgs(typed), const NewProblem(notName));
      });
    }
  });
}

void testerWhitespaceTests() {
  group('tester: JavaScript whitespace boundaries', () {
    test('every JavaScript trim character delimits runtime, flag and name', () {
      for (final code in [
        9,
        10,
        11,
        12,
        13,
        32,
        0xA0,
        0x1680,
        for (var code = 0x2000; code <= 0x200A; code++) code,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
        0xFEFF,
      ]) {
        final space = String.fromCharCode(code);
        expect(
          newArgs('${space}fake$space--name$space界🙂e\u0301$space'),
          const NewAsked(agent: 'fake', name: '界🙂e\u0301'),
          reason: 'U+${code.toRadixString(16)}',
        );
        expect(newArgs('fake$space--name$space'), const NewProblem(noName));
      }
    });
    test('non-whitespace Unicode stays literal in runtime and name', () {
      for (final code in [0x85, 0x180E, 0x200B, 0x2060]) {
        final literal = String.fromCharCode(code);
        expect(
          newArgs('${literal}fake --name $literal'),
          NewAsked(agent: '${literal}fake', name: literal),
        );
      }
    });
  });
}

import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/start_layout.dart';
import 'package:chord/ui/dialogs/permission.dart';
import 'package:chord/ui/header/resumed.dart';
import 'package:chord/ui/pickers/picker.dart';
import 'package:chord/ui/transcript/message.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

List<String> texts(List<List<Glyph>> rows) => [
  for (final row in rows) row.map((g) => g.text).join(),
];

// Each case breaks differently under OpenTUI's word wrap, which these sites
// do not use: the original wraps them with wrap-ansi.
void main() {
  test('wrapLine keeps the indent on the first row only', () {
    expect(texts(wrapLine(const TextSpan('  ab abc/defghij'), 12)), [
      '  ab abc/def',
      'ghij',
    ]);
  });

  test('wrapLine shrinks an indent to leave a cell for the text', () {
    expect(texts(wrapLine(const TextSpan('      xyz'), 3)), ['  x', 'y', 'z']);
    for (final width in [1, 2, 5, 9]) {
      for (final row in wrapLine(
        const TextSpan('    abc/defghijkl mn'),
        width,
      )) {
        expect(TextLayout.lineWidth(row), lessThanOrEqualTo(width));
      }
    }
  });

  test('wrapLine drops a Unicode indent before wrapping, as trimStart', () {
    // Probed under bun with ../chord's message.ts wrapLine.
    expect(texts(wrapLine(const TextSpan('\u{A0}abc'), 5)), ['\u{A0}abc']);
    expect(
      texts(wrapLine(const TextSpan('\u{2003}\u{A0}abcdefghijkl mn'), 6)),
      ['\u{2003}\u{A0}abcd', 'efgh', 'ijkl', 'mn'],
    );
    expect(texts(wrapLine(const TextSpan('  \u{A0}x abcdefghij'), 8)), [
      '  \u{A0}x',
      'abcde',
      'fghij',
    ]);
    final styled = wrapLine(
      const TextSpan(
        '',
        children: [
          TextSpan(' \u{A0}'),
          TextSpan('ab', style: Style.bold),
        ],
      ),
      10,
    );
    expect(texts(styled), [' \u{A0}ab']);
    expect(styled.single.last.style.isBold, isTrue);
  });

  test('wrapLines wraps each line, a style holding across them', () {
    final rows = wrapLines(parseAnsi('\x1b[1mab abc/defghij\nkl\x1b[22m'), 10);
    expect(texts(rows), ['ab abc/def', 'ghij', 'kl']);
    expect(rows.last.first.style.isBold, isTrue);
  });

  test('start hints count wrap-ansi rows', () {
    expect(hintRows('abcd abcdefghijkl', 10), 2);
  });

  test("a resumed agent title wraps as the original's header", () {
    const facts = ResumedHeader('resumed · abcd abcdefghijkl', wrap: true);
    expect(resumedRows(facts, 20).split('\n'), [
      'resumed · abcd',
      'abcdefghijkl',
    ]);
    expect(resumedRows(facts, 10).split('\n'), [
      'resumed ·',
      'abcd abcde',
      'fghijkl',
    ]);
    const cut = ResumedHeader('resumed · abcd abcdefghijkl', wrap: false);
    expect(resumedRows(cut, 10), cut.text);
  });

  test('a hanging resume title wraps as choiceLines', () {
    final choice = (
      session: EarlierSession(
        resume: Resume(sessionId: 's', cwd: 'project'),
        lastUsedAt: '2000-01-01T00:00:00Z',
        prompt: 'x',
      ),
      label: '1h  abcd abcdefghijkl',
      hang: 4,
    );
    expect(sessionChoiceTitle(choice, 10), ['abcd abcde', 'fghijkl']);
    expect(sessionChoiceTitle(choice, 0), [
      for (final c in 'abcdabcdefghijkl'.split('')) c,
    ]);
  });

  test('a permission title wraps as wrapLine does', () {
    final request = requestRows(
      PermissionWait('p', title: 'abcd abcdefghijkl', options: const []),
      10,
    );
    expect(request.pinned, 'abcd abcde');
    expect(
      [
        for (final row in request.rows)
          if (row is RequestText) row.text,
      ],
      ['fghijkl'],
    );
  });
}

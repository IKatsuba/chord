// The form and link boxes as the original's Form.tsx and Link.tsx draw
// them, standalone: the box, its heading, held between turns, and a link
// that is no web link.
import 'package:chord/session/elicitations.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/form.dart';
import 'package:chord/ui/dialogs/form_box.dart';
import 'package:chord/ui/dialogs/link.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/forms.dart';

const _form = FormWait('f', 'Set up the deploy target', schema: formSchema);

Widget formBox(
  List<ElicitationReply> replies, {
  FormWait wait = _form,
  bool held = false,
  bool between = false,
  int rows = 40,
  int? maxRows,
}) => Column(
  children: [
    FormBox(
      wait: wait,
      agent: 'fake',
      controller: FormController(fields: fieldsOf(wait.schema)),
      windowRows: rows,
      held: held,
      between: between,
      attendKey: 'ctrl+x a',
      maxRows: maxRows,
      focusNode: FocusNode(),
      onAnswer: replies.add,
    ),
  ],
);

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the form box at $size', (t) async {
      final replies = <ElicitationReply>[];
      await t.pumpWidget(formBox(replies), size: size);
      final w = size.width.toInt();
      String row(String text) => '│ ${text.padRight(w - 4)} │';
      expect(t.screen.lines.take(19).toList(), [
        '',
        '╭${'─' * (w - 2)}╮',
        row('fake asks for input'),
        row('Set up the deploy target'),
        row(''),
        row('❯ * Project name'),
        row('                   Lowercase, dashes allowed'),
        row('    Contact email  not set'),
        row('  ✔ Replicas       2'),
        row('    Traffic share  not set'),
        row('  ✔ Public         ☐ No'),
        row('  * Region         not set'),
        row('    Tags           not set'),
        row(''),
        row('  Accept   Decline'),
        row(''),
        row(
          size.width >= 100
              ? 'Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel'
              : 'Type to fill in · ↑↓ to move · Esc to cancel',
        ),
        '╰${'─' * (w - 2)}╯',
        '',
      ]);
    });

    testWidgets('held between turns: no marks, no keys, the key that takes '
        'them at $size', (t) async {
      final replies = <ElicitationReply>[];
      await t.pumpWidget(
        formBox(replies, held: true, between: true),
        size: size,
      );
      final text = t.screen.text;
      // Between turns, main names itself.
      expect(text, contains('main asks for input · between turns'));
      expect(text, isNot(contains('❯')));
      expect(text, contains('ctrl+x a to answer'));
      expect(text, isNot(contains('Esc to cancel')));
      await t.press('esc');
      expect(replies, isEmpty);
    });

    testWidgets('a link that is no web link offers only Decline at $size', (
      t,
    ) async {
      final answers = <LinkAnswer>[];
      final node = FocusNode();
      await t.pumpWidget(
        Column(
          children: [
            LinkBox(
              wait: const LinkWait('l', 'Open this', 'file:///etc/passwd'),
              agent: 'fake',
              focusNode: node,
              onAnswer: answers.add,
            ),
          ],
        ),
        size: size,
      );
      node.requestFocus();
      await t.pump();
      final text = t.screen.text;
      expect(text, contains('Not a web link'));
      expect(text, contains('1. Decline'));
      expect(text, isNot(contains('Open in the browser')));
      await t.press('enter');
      await t.press('esc');
      expect(answers, [LinkAnswer.decline, LinkAnswer.cancel]);
    });
  }

  testWidgets('a long message is cut with … to leave the fields three rows', (
    t,
  ) async {
    final replies = <ElicitationReply>[];
    await t.pumpWidget(
      formBox(
        replies,
        wait: FormWait(
          'f',
          List.filled(40, 'word').join(' '),
          schema: formSchema,
        ),
        rows: 16,
      ),
      size: const Size(40, 20),
    );
    // formRowLimit(16) is 12: 8 rows of chrome leave 4, and the message 1.
    final message = t.screen.lines[3];
    expect(message, contains('word…'));
    expect(
      t.screen.lines[4].trim(),
      '│                                      │',
    );
  });

  testWidgets("a record names who asked, or hangs under the call it came "
      "out of, in its outcome's colour", (t) async {
    final dark = ThemeData.dark();
    await t.pumpWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TranscriptEntry(
            ElicitationEntry('t', _form, ElicitationOutcome.declined),
            agent: 'fake',
          ),
          TranscriptEntry(
            ElicitationEntry(
              't',
              const LinkWait(
                'l',
                'Sign in',
                'https://x.example',
                toolCallId: 'c',
              ),
              ElicitationOutcome.accepted,
            ),
            agent: 'fake',
          ),
        ],
      ),
      size: const Size(80, 24),
    );
    expect(t.screen.lines.take(4), [
      '',
      '⏺ fake asked: Set up the deploy target',
      '  ⎿  Declined',
      '  ⎿  Opened https://x.example',
    ]);
    expect(t.screen.styleAt(5, 2), dark.error);
    expect(t.screen.styleAt(5, 3), dark.link);
  });

  testWidgets('held on a short screen, its body folds under … N more lines '
      'and keeps the key that takes it', (t) async {
    final replies = <ElicitationReply>[];
    await t.pumpWidget(
      formBox(replies, held: true, between: true, maxRows: 16),
      size: const Size(80, 24),
    );
    final text = t.screen.text;
    // 13 lines into 11 rows: 10 shown, the fold line the 11th, then the
    // blank row and the hint.
    expect(t.screen.lines.where((l) => l.startsWith('│')), hasLength(13));
    expect(text, contains('│   … 3 more lines'));
    expect(text, contains('ctrl+x a to answer'));
    expect(text, isNot(contains('Accept')));
    // Not held, nothing folds.
    await t.pumpWidget(formBox(replies, maxRows: 16), size: const Size(80, 24));
    expect(t.screen.text, contains('Accept   Decline'));
    expect(t.screen.text, isNot(contains('more lines')));
  });

  testWidgets('a link between turns names main', (t) async {
    await t.pumpWidget(
      Column(
        children: [
          LinkBox(
            wait: const LinkWait('l', 'Sign in', 'https://example.com'),
            agent: 'fake',
            between: true,
            held: true,
            attendKey: 'ctrl+x a',
            onAnswer: (_) {},
          ),
        ],
      ),
      size: const Size(80, 24),
    );
    expect(
      t.screen.text,
      contains('main asks you to open a link · between turns'),
    );
  });

  test('a fold shows what fits and counts the rest', () {
    expect(foldOf(5, 5), (shown: 5, more: 0));
    expect(foldOf(14, 11), (shown: 10, more: 4));
    expect(foldOf(3, 0), (shown: 0, more: 3));
    expect(moreLines(1), '… 1 more line');
  });

  test('the box takes at most the window less seven rows, never under 12', () {
    expect(formRowLimit(40), 33);
    expect(formRowLimit(10), 12);
    expect(messageRows('one\ntwo\nthree\nfour', 20, 6), 3);
    expect(messageRows('one', 20, 6), 1);
  });
}

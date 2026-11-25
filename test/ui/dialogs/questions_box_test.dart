// The question box as the original's Questions.tsx draws it, standalone:
// its steps, rows and hint, keys and paste, a secret, the countdown, a
// description too tall for the box, and held between turns.
import 'package:chord/session/elicitations.dart' hide answerOf;
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/questions.dart';
import 'package:chord/ui/dialogs/questions_box.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../../fixtures/questions.dart';

/// [form] asked as the enrichers read it, at [at].
FormWait _asked(Map<String, Object?> form, {num? at}) {
  final [message] = enricherRelay(m1Enrichers).fromAgent({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'elicitation/create',
    'params': {...form, 'sessionId': 's'},
  });
  final params = recordOf(message['params']);
  return FormWait(
    'e1',
    form['message'] as String,
    schema: recordOf(form['requestedSchema']),
    questions: questionsOf(params),
    at: at,
  );
}

Widget _box(
  FormWait wait,
  List<ElicitationReply> replies, {
  int rows = 40,
  bool held = false,
  bool between = false,
  num Function()? now,
  void Function(AskState state)? onFill,
  AskState? filled,
  FocusNode? focusNode,
}) => Column(
  children: [
    QuestionBox(
      wait: wait,
      questions: wait.questions!,
      agent: 'fake',
      windowRows: rows,
      held: held,
      between: between,
      attendKey: 'ctrl+x a',
      focusNode: focusNode,
      filled: filled,
      onFill: onFill,
      now: now ?? () => 0,
      onAnswer: replies.add,
    ),
  ],
);

/// The screen's line that holds [text].
String _lineWith(WidgetTester t, String text) =>
    t.screen.lines.firstWhere((line) => line.contains(text));

late FocusNode _focus;

void main() {
  setUp(() => _focus = FocusNode());

  group('CTUI-68 tester: Note ownership and lifecycle', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'two interior cursors survive an actual remount and tiny resizes at $size',
        (t) async {
          final wait = _asked(claudeQuestionsForm);
          final firstFocus = FocusNode(), nextFocus = FocusNode();
          final replies = <ElicitationReply>[];
          AskState kept = const AskState(
            step: 0,
            row: 2,
            answers: {
              'question_0': QuestionAnswer(own: 'abcd'),
              'question_1': QuestionAnswer(own: 'wxyz'),
            },
            noteCursors: {'question_0': 2, 'question_1': 1},
          );
          try {
            await t.pumpWidget(
              _box(
                wait,
                replies,
                rows: size.height.toInt(),
                filled: kept,
                focusNode: firstFocus,
                onFill: (state) => kept = state,
              ),
              size: size,
            );
            firstFocus.requestFocus();
            await t.pump();
            await t.paste('界🙂e\u0301');
            expect(kept.answers['question_0']?.own, 'ab界🙂e\u0301cd');
            await t.press('tab');
            for (var index = 0; index < 3; index++) {
              await t.press('down');
            }
            await t.type('Y');
            expect(kept.answers['question_1']?.own, 'wYxyz');
            await t.pumpWidget(const SizedBox(), size: size);
            await t.pumpWidget(
              _box(
                wait,
                replies,
                rows: size.height.toInt(),
                filled: kept,
                focusNode: nextFocus,
                onFill: (state) => kept = state,
              ),
              size: size,
            );
            nextFocus.requestFocus();
            await t.pump();
            await t.type('Z');
            expect(kept.answers['question_1']?.own, 'wYZxyz');
            for (final resized in const [Size(24, 10), Size.zero, Size(1, 1)]) {
              await t.resize(resized);
            }
            await t.resize(size);
            await t.press('shift+tab');
            await t.press('down');
            await t.press('down');
            await t.type('X2');
            expect(kept.answers['question_0']?.own, 'ab界🙂e\u0301X2cd');
            expect(kept.answers['question_0']?.picks, isEmpty);
            expect(replies, isEmpty);
          } finally {
            t.dispose();
            firstFocus.dispose();
            nextFocus.dispose();
          }
        },
      );

      testWidgets(
        'held reactivation and a replaced parent focus node retain Note editing at $size',
        (t) async {
          final oldFocus = FocusNode(),
              newFocus = FocusNode(),
              outside = FocusNode();
          final config = ValueNotifier<({bool held, FocusNode node})>((
            held: false,
            node: oldFocus,
          ));
          AskState kept = const AskState(
            step: 0,
            row: 3,
            answers: {'next': QuestionAnswer(own: 'abcd')},
            noteCursors: {'next': 2},
          );
          final replies = <ElicitationReply>[];
          final wait = _asked(codexQuestionsForm);
          try {
            await t.pumpWidget(
              ListenableBuilder(
                listenable: config,
                builder: (_) => Column(
                  children: [
                    _box(
                      wait,
                      replies,
                      rows: size.height.toInt(),
                      held: config.value.held,
                      filled: kept,
                      focusNode: config.value.node,
                      onFill: (state) => kept = state,
                    ),
                    Focus(focusNode: outside, child: Text('outside')),
                  ],
                ),
              ),
              size: size,
            );
            oldFocus.requestFocus();
            await t.pump();
            await t.type('X');
            expect(kept.answers['next']?.own, 'abXcd');
            config.value = (held: true, node: newFocus);
            outside.requestFocus();
            await t.pump();
            await t.type('2');
            expect(kept.answers['next']?.own, 'abXcd');
            config.value = (held: false, node: newFocus);
            await t.pump();
            newFocus.requestFocus();
            await t.pump();
            await t.type('Y2');
            expect(kept.answers['next']?.own, 'abXY2cd');
            expect(kept.answers['next']?.picks, isEmpty);
            expect(replies, isEmpty);
          } finally {
            t.dispose();
            config.dispose();
            oldFocus.dispose();
            newFocus.dispose();
            outside.dispose();
          }
        },
      );
    }

    test(
      'removing a live countdown cancels its periodic timer and callbacks',
      () {
        fakeAsync((clock) {
          final tester = WidgetTester();
          void settle(Future<void> future) {
            var done = false;
            future.then((_) => done = true);
            clock.elapse(Duration.zero);
            expect(done, isTrue);
          }

          var updates = 0;
          settle(
            tester.pumpWidget(
              _box(
                _asked(codexQuestionsForm, at: 0),
                [],
                now: () => clock.elapsed.inMilliseconds,
                onFill: (_) => updates++,
              ),
            ),
          );
          expect(clock.periodicTimerCount, 1);
          clock.elapse(const Duration(seconds: 2));
          settle(tester.pump());
          expect(tester.screen, shows('answers itself in 4:58'));
          settle(tester.pumpWidget(const SizedBox()));
          expect(clock.periodicTimerCount, 0);
          final before = updates;
          clock.elapse(const Duration(minutes: 10));
          settle(tester.pump());
          expect(updates, before);
          expect(tester.screen.text, isEmpty);
          tester.dispose();
        });
      },
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final rows = size.height.toInt();
    final wide = size.width >= 100;

    testWidgets("claude's questions one at a time, then Submit, the answers "
        'under its fields at $size', (t) async {
      final replies = <ElicitationReply>[];
      await t.pumpWidget(
        _box(
          _asked(claudeQuestionsForm),
          replies,
          rows: rows,
          focusNode: _focus,
        ),
        size: size,
      );
      _focus.requestFocus();
      await t.pump();
      final first = t.screen.text;
      expect(first, contains('fake asks you 2 questions'));
      expect(first, contains('← ◉ Language   ○ Checks   ○ Submit →'));
      expect(first, contains('Which language should helper scripts use?'));
      expect(first, contains('❯ 1. Deno (TypeScript) (Recommended)'));
      expect(first, contains('Runs from source with inline npm: and jsr:'));
      expect(first, contains('  2. Python'));
      expect(first, contains('Note  Type your own answer, or add a note to'));
      expect(
        first,
        contains(
          wide
              ? 'Enter to pick · 1–2 · ↑↓ to move · ←→ or Tab for the '
                    'questions · Esc to cancel'
              : 'Enter to pick · 1–2 · ↑↓ · ←→ questions · Esc to cancel',
        ),
      );
      if (!wide) {
        // A Note placeholder too long for 80 columns is cut at its end.
        expect(_lineWith(t, 'Note  '), matches(RegExp(r'…\s*│$')));
      }

      await t.press('enter');
      expect(
        t.screen.text,
        contains('Which checks should run before a commit? (pick any)'),
      );
      await t.press('space');
      await t.press('down');
      await t.press('down');
      await t.press('space');
      expect(t.screen.text, contains('❯ [✔] 3. Tests'));
      // A multi-select's rows stay in line as its ticks change.
      int column(String text) => _lineWith(t, text).indexOf(text);
      expect(column('[ ] 2. Lint'), column('[✔] 1. Types'));
      expect(column('[✔] 3. Tests'), column('[✔] 1. Types'));

      await t.press('enter');
      expect(t.screen.text, contains('Checks    Types, Tests'));
      expect(
        t.screen.text,
        contains('Language  Deno (TypeScript) (Recommended)'),
      );
      expect(t.screen.text, contains('❯ 1. Send the answers'));
      expect(t.screen.text, contains('  2. Skip these questions'));
      await t.press('enter');
      expect(replies.single.toJson(), {
        'action': 'accept',
        'content': {
          'question_0': 'Deno (TypeScript) (Recommended)',
          'question_1': ['Types', 'Tests'],
        },
      });
    });

    testWidgets("codex's questions: its wait, a secret typed as dots, and "
        'Send out of reach until it has its answers at $size', (t) async {
      final replies = <ElicitationReply>[];
      await t.pumpWidget(
        _box(
          _asked(codexQuestionsForm, at: 1000),
          replies,
          rows: rows,
          focusNode: _focus,
          now: () => 1000 + 28500,
        ),
        size: size,
      );
      _focus.requestFocus();
      await t.pump();
      expect(t.screen.text, contains('answers itself in 4:32'));
      expect(
        t.screen.text,
        contains('← * ◉ Next step   * ○ Token   ○ Submit →'),
      );
      expect(t.screen.text, contains('Note  Additional answer or note'));
      await t.press('tab');
      expect(
        t.screen.text,
        contains('Paste the API token for the staging deploy.'),
      );
      await t.type('sk-1');
      expect(t.screen.text, contains('❯ ••••'));
      await t.press('tab');
      expect(
        t.screen.text,
        contains('Next step  no answer yet, and fake needs one'),
      );
      expect(t.screen.text, contains('Token      ••••'));
      expect(t.screen.text, contains('❯ 2. Skip these questions'));
      expect(t.screen.text, isNot(contains('sk-1')));
      await t.press('esc');
      expect(replies.single, isA<CancelReply>());
    });

    testWidgets('a paste goes into the text row, a secret as dots, and picks '
        'nothing on an option at $size', (t) async {
      final replies = <ElicitationReply>[];
      await t.pumpWidget(
        _box(
          _asked(codexQuestionsForm),
          replies,
          rows: rows,
          focusNode: _focus,
        ),
        size: size,
      );
      _focus.requestFocus();
      await t.pump();
      await t.paste('2');
      expect(t.screen.text, contains('❯ 1. Plan a change (Recommended)'));
      await t.press('tab');
      await t.paste('sk-1');
      expect(t.screen.text, contains('❯ ••••'));
      await t.press('tab');
      expect(t.screen.text, contains('Token      ••••'));
      expect(t.screen.text, contains('Next step  no answer yet'));
    });

    testWidgets('digits typed into a text row type, and the Note keeps its '
        'text and cursor across steps at $size', (t) async {
      final replies = <ElicitationReply>[];
      AskState? kept;
      await t.pumpWidget(
        _box(
          _asked(codexQuestionsForm),
          replies,
          rows: rows,
          focusNode: _focus,
          onFill: (state) => kept = state,
        ),
        size: size,
      );
      _focus.requestFocus();
      await t.pump();
      await t.press('2');
      expect(t.screen.text, contains('Paste the API token'));
      await t.type('12 3');
      expect(t.screen.text, contains('❯ ••••'));
      await t.press('shift+tab');
      for (var i = 0; i < 3; i++) {
        await t.press('down');
      }
      await t.type('tests first');
      await t.press('left');
      expect(kept?.answers['next']?.own, 'tests first');
      await t.press('tab');
      await t.press('tab');
      expect(
        t.screen.text,
        contains('Next step  Review existing work · tests first'),
      );
      await t.press('1');
      expect(replies.single.toJson(), {
        'action': 'accept',
        'content': {
          'next': 'Review existing work',
          'next_note': 'tests first',
          'token': '12 3',
        },
      });
    });

    testWidgets("the Note's placeholder is the original textarea's grey, "
        'not dim, focused or not at $size', (t) async {
      await t.pumpWidget(
        _box(_asked(codexQuestionsForm), [], rows: rows, focusNode: _focus),
        size: size,
      );
      _focus.requestFocus();
      await t.pump();
      for (final keys in [
        <String>[],
        ['down', 'down', 'down'],
      ]) {
        for (final key in keys) {
          await t.press(key);
        }
        final y = t.screen.lines.indexWhere(
          (line) => line.contains('Additional answer or note'),
        );
        final x = t.screen.lines[y].indexOf('Additional');
        // The placeholder right after `Note  `, focused or not.
        expect(t.screen.lines[y], contains('Note  Additional'));
        final style = t.screen.styleAt(x + 1, y);
        expect(style.fg, const RgbColor(0x66, 0x66, 0x66));
        expect(style.isDim, isFalse);
      }
    });

    testWidgets('a box shown again on its Note gives the Note the keys, '
        'typing at the cursor left at $size', (t) async {
      final replies = <ElicitationReply>[];
      AskState? kept;
      // Left on the Note of codex's first question, the cursor after
      // "tests".
      const filled = AskState(
        step: 0,
        row: 3,
        answers: {'next': QuestionAnswer(own: 'tests first')},
        noteCursors: {'next': 5},
      );
      await t.pumpWidget(
        _box(
          _asked(codexQuestionsForm),
          replies,
          rows: rows,
          filled: filled,
          onFill: (state) => kept = state,
          focusNode: _focus,
        ),
        size: size,
      );
      // The window gives the box its keys, as it does when it shows it.
      _focus.requestFocus();
      await t.pump();
      await t.type('X2');
      expect(kept?.answers['next']?.own, 'testsX2 first');
      expect(kept?.answers['next']?.picks, isEmpty);
      expect(replies, isEmpty);
    });

    testWidgets("each question's Note keeps its own cursor across steps and "
        'a remount at $size', (t) async {
      AskState? kept;
      const filled = AskState(
        step: 0,
        row: 2,
        answers: {
          'question_0': QuestionAnswer(own: 'abcd'),
          'question_1': QuestionAnswer(own: 'wxyz'),
        },
        noteCursors: {'question_0': 2, 'question_1': 1},
      );
      await t.pumpWidget(
        _box(
          _asked(claudeQuestionsForm),
          [],
          rows: rows,
          filled: filled,
          onFill: (state) => kept = state,
          focusNode: _focus,
        ),
        size: size,
      );
      _focus.requestFocus();
      await t.pump();
      await t.type('X');
      expect(kept?.answers['question_0']?.own, 'abXcd');
      await t.press('tab');
      for (var i = 0; i < 3; i++) {
        await t.press('down');
      }
      await t.type('Y');
      expect(kept?.answers['question_1']?.own, 'wYxyz');
      await t.press('shift+tab');
      for (var i = 0; i < 2; i++) {
        await t.press('down');
      }
      await t.type('Z');
      expect(kept?.answers['question_0']?.own, 'abXZcd');
    });

    testWidgets('held between turns: no marks, no keys, the key that takes '
        'them at $size', (t) async {
      final replies = <ElicitationReply>[];
      await t.pumpWidget(
        _box(
          _asked(claudeQuestionsForm),
          replies,
          rows: rows,
          focusNode: _focus,
          held: true,
          between: true,
        ),
        size: size,
      );
      _focus.requestFocus();
      await t.pump();
      expect(
        t.screen.text,
        contains('main asks you 2 questions · between turns'),
      );
      expect(t.screen.text, contains('ctrl+x a to answer'));
      expect(t.screen.text, isNot(contains('❯')));
      expect(t.screen.text, isNot(contains('Esc to cancel')));
      await t.press('enter');
      await t.press('esc');
      expect(replies, isEmpty);
    });
  }

  testWidgets('the countdown runs from when the request came, and goes on as '
      'it is drawn again', (t) async {
    for (final (now, left) in const [
      (1000 + 60000, 'answers itself in 4:00'),
      // Switched away and back two minutes later: drawn afresh.
      (1000 + 180000, 'answers itself in 2:00'),
    ]) {
      await t.pumpWidget(
        _box(
          _asked(codexQuestionsForm, at: 1000),
          [],
          rows: 24,
          now: () => now,
        ),
        size: const Size(80, 24),
      );
      expect(t.screen.text, contains(left));
      await t.pumpWidget(const SizedBox(), size: const Size(80, 24));
    }
  });

  testWidgets("an option's description longer than an 80x24 box is cut, and "
      'the hint stays on screen', (t) async {
    final long = [
      for (var index = 0; index < 60; index++) 'word$index',
    ].join(' ');
    final questions = Questions(QuestionsAgent.claude, [
      Question(
        id: 'q',
        text: 'Which one?',
        options: [
          QuestionOption(value: 'a', title: 'First', description: long * 4),
          const QuestionOption(value: 'b', title: 'Second'),
        ],
        multiSelect: false,
        required: false,
      ),
    ]);
    await t.pumpWidget(
      _box(
        FormWait(
          'e1',
          'Which one?',
          schema: const {'type': 'object', 'properties': {}},
          questions: questions,
        ),
        [],
        rows: 24,
      ),
      size: const Size(80, 24),
    );
    final frame = t.screen.text;
    expect(frame, contains('❯ 1. First'));
    expect(frame, contains('…'));
    expect(frame, contains('↓ 1 more'));
    expect(frame, contains('Esc to cancel'));
    expect(frame, contains('╰'));
  });
}

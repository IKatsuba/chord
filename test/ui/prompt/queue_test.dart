import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart' show MessageFrom;
import 'package:chord/ui/prompt/queue.dart';
import 'package:chord/ui/prompt/queue_view.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _main = MessageFrom('main', reachable: true);
const _parser = MessageFrom('parser', runtime: 'fake', reachable: true);

void main() {
  _testerMixedMessageQueue();
  test('restores queued prompts before the draft, preserving whitespace', () {
    expect(
      restoredDraft([
        const QueuedPrompt('1', 'one\ntwo'),
        const QueuedPrompt('2', ''),
        const QueuedPrompt('3', ' '),
      ], 'draft'),
      'one\ntwo\n \ndraft',
    );
    expect(restoredDraft([], ''), '');
    expect(restoredDraft([const QueuedPrompt('1', 'one')], ''), 'one');
  });

  test('queue uses a sixth of the window, at least two rows', () {
    expect(queueRowLimit(0), 2);
    expect(queueRowLimit(12), 2);
    expect(queueRowLimit(24), 4);
    expect(queueRowLimit(40), 6);
  });

  test('shows first lines with multiline marks and after-answer headers', () {
    final rows = queueRows([
      const QueuedPrompt('1', 'one\ntwo'),
      const QueuedPrompt('2', 'next', afterAnswer: true),
      const QueuedPrompt('3', 'trailing\n'),
    ], 3).cast<PromptQueueRow>();
    expect(rows.map((row) => row.text), ['one …', 'next', 'trailing …']);
    expect(rows.map((row) => row.header), [null, 'after your answer: ', null]);
  });

  test('folds newest prompts, counting the row reserved for more', () {
    final queue = [
      for (var i = 1; i <= 5; i++) QueuedPrompt('$i', 'prompt $i'),
    ];
    final rows = queueRows(queue, 3);
    expect((rows[0] as PromptQueueRow).text, 'prompt 1');
    expect((rows[1] as PromptQueueRow).text, 'prompt 2');
    expect((rows[2] as MoreQueueRow).count, 3);
    expect((queueRows(queue, 1).single as MoreQueueRow).count, 5);
    expect(queueRows([], 2), isEmpty);
    expect(queueRows(queue, 5), hasLength(5));
    expect(queue.length, 5);
  });
  group('tester U5 queue selection and restoration', () {
    test('restoration filters only empty strings and never trims payloads', () {
      final queue = [
        const QueuedPrompt('1', ''),
        const QueuedPrompt('2', '  '),
        const QueuedPrompt('3', '\n'),
        const QueuedPrompt('4', '界🙂e\u0301\r\nlast', afterAnswer: true),
        const QueuedPrompt('5', ''),
      ];
      expect(restoredDraft(queue, '\t'), '  \n\n\n界🙂e\u0301\r\nlast\n\t');
      expect(restoredDraft([], 'draft'), 'draft');
      expect(restoredDraft([const QueuedPrompt('1', '')], ''), '');
      expect(queue.map((p) => p.text), [
        '',
        '  ',
        '\n',
        '界🙂e\u0301\r\nlast',
        '',
      ]);
    });

    test('every fitting limit keeps oldest rows and exact hidden count', () {
      final queue = [
        for (var i = 0; i < 7; i++) QueuedPrompt('$i', 'prompt $i'),
      ];
      for (var limit = 1; limit <= 9; limit++) {
        final rows = queueRows(queue, limit);
        final visible = limit < 7 ? limit - 1 : 7;
        expect(rows.whereType<PromptQueueRow>().map((r) => r.text), [
          for (var i = 0; i < visible; i++) 'prompt $i',
        ]);
        if (limit < 7) {
          expect(rows.length, limit);
          expect((rows.last as MoreQueueRow).count, 7 - visible);
        } else {
          expect(rows, hasLength(7));
          expect(rows.whereType<MoreQueueRow>(), isEmpty);
        }
      }
      expect(queue.map((p) => p.turnId), ['0', '1', '2', '3', '4', '5', '6']);
    });

    test('blank first lines and trailing breaks still mark multiline text', () {
      final queue = [
        const QueuedPrompt('1', '\nsecond', afterAnswer: true),
        const QueuedPrompt('2', '界🙂\n'),
        const QueuedPrompt('3', 'with\u000cform feed'),
        const QueuedPrompt('4', ''),
      ];
      final rows = queueRows(queue, 4).cast<PromptQueueRow>();
      expect(rows.map((r) => r.text), [
        ' …',
        '界🙂 …',
        'with\u000cform feed',
        '',
      ]);
      expect(rows.map((r) => r.header), [
        'after your answer: ',
        null,
        null,
        null,
      ]);
      final again = queueRows(queue, 2);
      expect((again.first as PromptQueueRow).header, 'after your answer: ');
      expect((again.last as MoreQueueRow).count, 3);
      expect(rows.map((r) => r.text), [
        ' …',
        '界🙂 …',
        'with\u000cform feed',
        '',
      ]);
    });

    test('row budget changes at sixths including both terminal sizes', () {
      for (final (height, expected) in [
        (-1, 2),
        (1, 2),
        (11, 2),
        (12, 2),
        (17, 2),
        (18, 3),
        (23, 3),
        (24, 4),
        (29, 4),
        (30, 5),
        (40, 6),
        (42, 7),
      ]) {
        expect(queueRowLimit(height), expected, reason: 'height $height');
      }
    });
  });

  group('messages held above the prompt', () {
    test('a message is ← from its sender, held ones say what they wait on', () {
      final rows = queueRows([
        const QueuedPrompt(
          '1',
          'Then the docs, once the tests pass.',
          afterCalls: true,
          from: _main,
        ),
        const QueuedPrompt(
          '2',
          'Then the docs, once the tests pass.',
          afterAnswer: true,
          from: _main,
        ),
        const QueuedPrompt(
          '3',
          'All 214 parser tests pass now.',
          from: _parser,
        ),
        const QueuedPrompt('4', 'first\nsecond', from: _parser),
      ], 6).cast<MessageQueueRow>();
      expect(
        [for (final row in rows) '${row.header}${row.text}'],
        [
          'from @main · after the running calls: '
              'Then the docs, once the tests pass.',
          'from @main · after your answer: Then the docs, once the tests pass.',
          'from @parser · fake: All 214 parser tests pass now.',
          'from @parser · fake: first …',
        ],
      );
    });

    test(
      "another's message never comes into the box, nor does Tab send it",
      () {
        final queue = [
          const QueuedPrompt('1', 'from main', from: _main),
          const QueuedPrompt('2', 'mine'),
        ];
        expect(restoredDraft(queue, 'typed'), 'mine\ntyped');
        expect(sendable([queue.first]), isFalse);
        expect(sendable(queue), isTrue);
      },
    );

    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('held rows draw the header whole and cut only the text, at '
          '$size', (t) async {
        await t.pumpWidget(
          Queue(
            queue: [
              const QueuedPrompt(
                '1',
                'Then the docs, once the tests pass.',
                afterCalls: true,
                from: _main,
              ),
              const QueuedPrompt(
                '2',
                'Then the docs, once the tests pass.',
                afterAnswer: true,
                from: _main,
              ),
              const QueuedPrompt(
                '3',
                'All 214 parser tests pass now.',
                from: _parser,
              ),
              QueuedPrompt(
                '4',
                'head${'x' * 150}tail',
                afterCalls: true,
                from: const MessageFrom(
                  'a rather long agent name',
                  runtime: 'claude',
                  reachable: true,
                ),
              ),
            ],
            limit: 6,
          ),
          size: size,
        );
        final rows = [for (final row in t.screen.lines) row.trimRight()];
        expect(rows.take(3), [
          ' ← from @main · after the running calls: '
              'Then the docs, once the tests pass.',
          ' ← from @main · after your answer: Then the docs, once the tests '
              'pass.',
          ' ← from @parser · fake: All 214 parser tests pass now.',
        ]);
        expect(
          rows[3],
          startsWith(
            ' ← from @a rather long agent name · claude · after the running '
            'calls: hea',
          ),
        );
        expect(rows[3], endsWith('ail'));
        expect(rows[3], contains('...'));
        for (var x = 1; x < rows[0].length; x++) {
          if (rows[0][x] == ' ') continue;
          expect(t.screen.styleAt(x, 0).isDim, isTrue, reason: 'cell $x');
        }
      });
    }
  });
}

void _testerMixedMessageQueue() {
  group('CTUI-35 tester: mixed held queue overflow', () {
    test(
      'oldest-first folding counts all rows but restoration keeps only personal drafts',
      () {
        const queue = [
          QueuedPrompt('own', 'personal'),
          QueuedPrompt('calls', 'message one', from: _parser, afterCalls: true),
          QueuedPrompt('answer', 'message two', from: _main, afterAnswer: true),
          QueuedPrompt('held', 'personal held', afterAnswer: true),
          QueuedPrompt('steer', 'already steering', steering: true),
          QueuedPrompt('taken', 'already taken', taken: true),
        ];
        final rows = queueRows(queue, 4);
        expect((rows[0] as PromptQueueRow).text, 'personal');
        expect(
          (rows[1] as MessageQueueRow).header,
          'from @parser · fake · after the running calls: ',
        );
        expect(
          (rows[2] as MessageQueueRow).header,
          'from @main · after your answer: ',
        );
        expect((rows[3] as MoreQueueRow).count, 3);
        expect(
          restoredDraft(queue, 'unfinished'),
          'personal\npersonal held\nunfinished',
        );
        expect(sendable(queue.sublist(1)), isFalse);
        expect(sendable(queue), isTrue);
        expect(queue, hasLength(6));
      },
    );
  });
}

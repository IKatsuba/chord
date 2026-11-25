import 'package:chord/ui/prompt/history.dart';
import 'package:test/test.dart';

void main() {
  test('records oldest first and collapses only consecutive duplicates', () {
    var history = const History();
    for (final prompt in ['one', 'one', 'two', 'one']) {
      history = recorded(history, prompt);
    }
    expect(history.prompts, ['one', 'two', 'one']);
    expect(history.index, isNull);
    expect(history.draft, '');
    expect(() => history.prompts.add('changed'), throwsUnsupportedError);
  });

  test('walks older and newer, restoring the draft beyond the newest', () {
    final history = recorded(recorded(const History(), 'one'), 'two\nlines');
    final first = older(history, 'unfinished')!;
    expect(first.text, 'two\nlines');
    expect(first.history.draft, 'unfinished');
    final second = older(first.history, first.text)!;
    expect(second.text, 'one');
    expect(older(second.history, second.text), isNull);
    final third = newer(second.history)!;
    expect(third.text, 'two\nlines');
    final restored = newer(third.history)!;
    expect(restored.text, 'unfinished');
    expect(restored.history.index, isNull);
    expect(restored.history.draft, '');
    expect(newer(restored.history), isNull);
    expect(history.index, isNull);
  });

  test('an empty history and a newer step outside a walk do nothing', () {
    expect(older(const History(), 'draft'), isNull);
    expect(newer(const History()), isNull);
  });

  test('an untouched recalled multiline prompt keeps walking', () {
    final recall = older(recorded(const History(), 'one\ntwo'), 'draft')!;
    expect(walking(recall.history, recall.text), isTrue);
    expect(walking(recall.history, 'one\ntwo!'), isFalse);
    expect(walking(const History(), ''), isFalse);
  });

  test('leaving and recording end a walk and discard its saved draft', () {
    final recall = older(recorded(const History(), 'one'), 'draft')!;
    final outside = left(recall.history);
    expect(outside.index, isNull);
    expect(outside.draft, '');
    expect(identical(left(outside), outside), isTrue);
    final sent = recorded(recall.history, 'one');
    expect(sent.prompts, ['one']);
    expect(sent.index, isNull);
    expect(sent.draft, '');
    expect(identical(sent.prompts, recall.history.prompts), isTrue);
  });
  group('tester U4 faithful history walks', () {
    test('original control-character case survives both directions', () {
      var h = const History();
      for (final text in ['first', 'with\u000cform feed', 'last']) {
        h = recorded(h, text);
      }
      final last = older(h, 'draft')!;
      final middle = older(last.history, last.text)!;
      expect(middle.text, 'with\u000cform feed');
      expect(older(middle.history, middle.text)!.text, 'first');
      expect(newer(middle.history)!.text, 'last');
      expect((h.index, h.draft), (null, ''));
    });

    test('boundary attempts preserve the saved Unicode multiline draft', () {
      final sent = recorded(recorded(const History(), ''), '界🙂e\u0301\nline');
      const draft = '  draft\n\x1b[31m  ';
      var step = older(sent, draft)!;
      final snapshot = step.history;
      step = older(step.history, 'ignored')!;
      expect(step.text, '');
      for (var i = 0; i < 3; i++) {
        expect(older(step.history, 'ignored'), isNull);
      }
      expect(walking(step.history, ''), isTrue);
      step = newer(step.history)!;
      expect(step.text, '界🙂e\u0301\nline');
      expect(walking(step.history, step.text), isTrue);
      expect(walking(step.history, '${step.text}!'), isFalse);
      step = newer(step.history)!;
      expect(step.text, draft);
      expect((step.history.index, step.history.draft), (null, ''));
      expect(newer(step.history), isNull);
      expect((snapshot.index, snapshot.draft), (1, draft));
      expect((sent.index, sent.draft), (null, ''));
      expect(identical(sent.prompts, step.history.prompts), isTrue);
    });

    test('leaving restarts at newest and saves a fresh draft', () {
      final sent = recorded(recorded(const History(), 'old'), 'new');
      final recall = older(older(sent, 'old draft')!.history, '')!;
      final outside = left(recall.history);
      final restart = older(outside, 'fresh draft')!;
      expect(restart.text, 'new');
      expect(newer(restart.history)!.text, 'fresh draft');
      expect(recall.history.draft, 'old draft');
      expect(outside.prompts, ['old', 'new']);
    });

    test('record during walking retains snapshots and exact whitespace', () {
      final first = recorded(const History(), 'same');
      final second = recorded(first, 'same ');
      final recall = older(second, 'draft')!;
      final third = recorded(recall.history, 'same');
      expect(first.prompts, ['same']);
      expect(second.prompts, ['same', 'same ']);
      expect(third.prompts, ['same', 'same ', 'same']);
      expect((third.index, third.draft), (null, ''));
      expect(older(third, '')!.text, 'same');
      expect((recall.history.index, recall.history.draft), (1, 'draft'));
    });
  });
}

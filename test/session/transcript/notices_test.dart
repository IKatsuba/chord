// From the original's tests/session/transcript/notices_test.ts; subagents'
// notices wait for subagents (M4).
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

TranscriptAction notice(Map<String, Object?> fields, [String turnId = 't1']) =>
    UpdateAction(
      turnId,
      acp.SessionUpdate.fromJson({'sessionUpdate': 'notice', ...fields}),
    );

TranscriptAction chunk(String text) => UpdateAction(
  't1',
  acp.SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
);

const prompt = PromptAction('t1', 'go', 0);

List<Object?> kinds(Transcript state) => [
  for (final entry in state.entries) describedEntry(entry)['kind'],
];

void main() {
  test('a notice in a turn is an entry of its own that closes the reply '
      'block, the next chunk opening another', () {
    final state = fold([
      prompt,
      chunk('Running the suite. '),
      notice({
        'severity': 'warning',
        'title': 'Fast mode turned off',
        'description': 'Rate limit reached.',
      }),
      chunk('Done.'),
    ]);
    expect(state.entries.map(describedEntry).toList(), [
      {'turnId': 't1', 'kind': 'user', 'text': 'go'},
      {'turnId': 't1', 'kind': 'assistant', 'text': 'Running the suite. '},
      {
        'turnId': 't1',
        'kind': 'notice',
        'severity': 'warning',
        'title': 'Fast mode turned off',
        'description': 'Rate limit reached.',
      },
      {'turnId': 't1', 'kind': 'assistant', 'text': 'Done.'},
    ]);
  });

  test('two notices alike are two entries: notices carry no id and are '
      'never merged', () {
    final twice = notice({'severity': 'info', 'title': 'Same'});
    expect(kinds(fold([prompt, twice, twice])), ['user', 'notice', 'notice']);
  });

  test('a severity the schema leaves open draws as info; a description null '
      'or empty is none', () {
    final state = fold([
      prompt,
      notice({'severity': 'critical', 'title': 'Odd', 'description': null}),
      notice({'severity': 'error', 'title': 'Bad', 'description': ''}),
    ]);
    expect(state.entries.skip(1).map(describedEntry).toList(), [
      {'turnId': 't1', 'kind': 'notice', 'severity': 'info', 'title': 'Odd'},
      {'turnId': 't1', 'kind': 'notice', 'severity': 'error', 'title': 'Bad'},
    ]);
  });

  test('a notice after the turn was answered, or before any turn, is drawn '
      'under the turn id it came with', () {
    final after = fold([
      prompt,
      chunk('Done.'),
      const ResultAction('t1', TurnAnswered('end_turn')),
      notice({'severity': 'info', 'title': 'Later'}),
    ]);
    expect(describedEntry(after.entries.last), {
      'turnId': 't1',
      'kind': 'notice',
      'severity': 'info',
      'title': 'Later',
    });
    expect(
      fold([
        notice({'severity': 'warning', 'title': 'Early'}, 'start'),
      ]).entries.map(describedEntry).toList(),
      [
        {
          'turnId': 'start',
          'kind': 'notice',
          'severity': 'warning',
          'title': 'Early',
        },
      ],
    );
  });

  test('a notice with no title is malformed and leaves the transcript', () {
    final before = fold([prompt]);
    final after = fold([
      notice({'severity': 'info'}),
    ], before);
    expect(after.entries, before.entries);
  });

  test('notices preserve reply boundaries across thinking and every '
      'severity', () {
    final state = fold([
      prompt,
      chunk('Before'),
      for (final severity in ['info', 'warning', 'error', 'WARNING', ''])
        notice({
          'severity': severity,
          'title': severity.isEmpty ? 'Empty' : severity,
        }),
      UpdateAction(
        't1',
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': 'Considering'},
        }),
      ),
      chunk('After'),
    ]);
    expect(kinds(state), [
      'user',
      'assistant',
      'notice',
      'notice',
      'notice',
      'notice',
      'notice',
      'thought',
      'assistant',
    ]);
    expect(
      [
        for (final entry in state.entries)
          if (entry is NoticeEntry) entry.severity,
      ],
      [
        NoticeSeverity.info,
        NoticeSeverity.warning,
        NoticeSeverity.error,
        NoticeSeverity.info,
        NoticeSeverity.info,
      ],
    );
  });

  test("a record's notice replays as its own entry", () {
    final history = recordActions([
      {
        'type': 'session',
        'version': 1,
        'sessionId': 's',
        'agent': 'a',
        'cwd': '/w',
        'at': 0,
      },
      {'type': 'prompt', 'turnId': 't1', 'prompt': 'go', 'at': 1, 'images': 0},
      {
        'type': 'update',
        'turnId': 't1',
        'update': {
          'sessionUpdate': 'notice',
          'severity': 'warning',
          'title': 'Kept',
        },
      },
    ]);
    expect(history.omitted, isFalse);
    expect(
      fold(history.actions).entries.whereType<NoticeEntry>().single.title,
      'Kept',
    );
  });

  group('tester: notice lifecycle boundaries', () {
    test('late notice preserves cancelled turn and next prompt boundary', () {
      final cancelled = fold([
        prompt,
        chunk('Working.'),
        const CancelAction('t1', 1),
        const ResultAction('t1', TurnAnswered('cancelled')),
      ]);
      final late = fold([
        notice({'severity': 'warning', 'title': 'After cancellation'}),
      ], cancelled);
      expect(late.turn, same(cancelled.turn));
      expect(late.entries.take(cancelled.entries.length), cancelled.entries);
      expect((late.entries.last as NoticeEntry).title, 'After cancellation');
      final next = fold([const PromptAction('t2', 'Again', 2)], late);
      expect(next.entries.take(late.entries.length), late.entries);
      expect(describedEntry(next.entries.last), {
        'turnId': 't2',
        'kind': 'user',
        'text': 'Again',
      });
    });

    test(
      'a thousand equal notices stay distinct without mutating past state',
      () {
        final before = fold([prompt, chunk('Before')]);
        final burst = notice({'severity': 'info', 'title': 'Repeated'});
        final after = fold([
          for (var i = 0; i < 1000; i++) burst,
          chunk('After'),
        ], before);
        expect(before.entries, hasLength(2));
        expect(after.entries.whereType<NoticeEntry>(), hasLength(1000));
        expect(after.entries.whereType<AssistantEntry>(), hasLength(2));
      },
    );
  });
}

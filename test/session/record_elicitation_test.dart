// The original's record.ts for forms and links: an `asked` line, and an
// `answered` line once it was asked, an accepted form's values left out of
// the file; a replay draws each record, and one never answered as
// cancelled.
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'recording_test.dart' show lines, opening;

const _form = FormWait(
  'f',
  'Set up the deploy target',
  schema: {'type': 'object', 'properties': <String, Object?>{}},
);
const _link = LinkWait('l', 'Sign in', 'https://example.com/sign-in');

void main() {
  test(
    'a form asked in a session let go is not answered into the next',
    () async {
      final writes = <String, List<String>>{};
      var records = 0;
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'fixture-${records++}',
        now: () => 1,
        append: (path, text) async => (writes[path] ??= []).add(text),
      );
      recording.opened(opening('old'));
      recording.heard(const Transcribed(CycleStartedAction('c1', 5)));
      recording.heard(
        Transcribed(ElicitationRequestedAction('c1', _form.asked(at: 7))),
      );
      recording.heard(const Cleared());
      recording.opened(opening('new'));
      recording.heard(const Transcribed(CycleStartedAction('c2', 9)));
      // The same id, answered after the clear, belongs to no record.
      recording.heard(
        const Transcribed(
          ElicitationSettledAction('c2', 'f', ElicitationDeclined()),
        ),
      );
      await recording.flushed();
      expect(writes, hasLength(2));
      final answered = [
        for (final file in writes.values)
          for (final line in lines(file.join()))
            if (line['type'] == 'answered') line,
      ];
      expect(answered, isEmpty);
    },
  );

  test('asked and answered lines, without a form\'s values', () async {
    final writes = <String>[];
    final recording = FileRecording(
      'state',
      failed: fail,
      uuid: () => 'fixture',
      now: () => 1,
      append: (path, text) async => writes.add(text),
    );
    recording.opened(opening('id'));
    recording.heard(const Transcribed(CycleStartedAction('c1', 5)));
    for (final action in <TranscriptAction>[
      ElicitationRequestedAction('c1', _form.asked(at: 7)),
      const ElicitationSettledAction(
        'c1',
        'f',
        ElicitationAccepted({'token': 'secret'}),
      ),
      const ElicitationRequestedAction('c1', _link),
      const ElicitationSettledAction('c1', 'l', ElicitationAccepted()),
      const ElicitationRequestedAction('c1', FormWait('g', 'Left open')),
      // Never asked in this record: no line.
      const ElicitationSettledAction('c1', 'x', ElicitationDeclined()),
    ]) {
      recording.heard(Transcribed(action));
    }
    await recording.flushed();
    final written = [
      for (final line in lines(writes.join()))
        if (line['type'] == 'asked' || line['type'] == 'answered') line,
    ];
    expect(written, [
      {
        'type': 'asked',
        'turnId': 'c1',
        'wait': {
          'id': 'f',
          'message': 'Set up the deploy target',
          'mode': 'form',
          'schema': {'type': 'object', 'properties': <String, Object?>{}},
        },
      },
      {
        'type': 'answered',
        'turnId': 'c1',
        'id': 'f',
        'answer': {'type': 'accepted'},
      },
      {
        'type': 'asked',
        'turnId': 'c1',
        'wait': {
          'id': 'l',
          'message': 'Sign in',
          'mode': 'url',
          'url': 'https://example.com/sign-in',
        },
      },
      {
        'type': 'answered',
        'turnId': 'c1',
        'id': 'l',
        'answer': {'type': 'accepted'},
      },
      {
        'type': 'asked',
        'turnId': 'c1',
        'wait': {
          'id': 'g',
          'message': 'Left open',
          'mode': 'form',
          'schema': <String, Object?>{},
        },
      },
    ]);

    // Replayed under a prompt's turn, as the preparation isolate hands it
    // back.
    final past = PreparedHistory.fromJson(
      recordActions([
        {
          'type': 'prompt',
          'turnId': 'c1',
          'at': 1,
          'prompt': 'form',
          'images': 0,
        },
        ...written,
      ]).toJson(),
    );
    final transcript = past.actions.fold(Transcript.empty, reduceTranscript);
    expect(transcript.asking, isEmpty);
    expect(
      [
        for (final entry in transcript.entries.whereType<ElicitationEntry>())
          (entry.wait.id, entry.outcome, entry.content),
      ],
      [
        ('f', ElicitationOutcome.accepted, null),
        ('l', ElicitationOutcome.accepted, null),
        ('g', ElicitationOutcome.cancelled, null),
      ],
    );
  });

  test('a malformed asked or answered line is no entry', () {
    expect(RecordEntry.view({'type': 'asked', 'turnId': 't'}), isNull);
    expect(
      RecordEntry.view({
        'type': 'answered',
        'turnId': 't',
        'id': 'f',
        'answer': {'type': 'maybe'},
      }),
      isNull,
    );
  });
}

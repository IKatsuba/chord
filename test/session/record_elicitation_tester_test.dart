import 'dart:io';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'recording_test.dart' show opening, lines;

void main() {
  group('tester elicitation record persistence ownership', () {
    test(
      'real file and preparation worker retain outcomes but redact accepted values',
      () async {
        final root = Directory.systemTemp.createTempSync('form-record-tester-');
        addTearDown(() => root.deleteSync(recursive: true));
        final recording = FileRecording(
          root.path,
          failed: fail,
          uuid: () => 'fixture',
          now: () => 1,
        );
        recording.opened(opening('session'));
        recording.sent('turn', 'form', 0, [], 1);
        const form = FormWait(
          'form',
          'Input',
          schema: {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
            },
          },
        );
        recording.heard(
          const Transcribed(ElicitationRequestedAction('turn', form)),
        );
        recording.heard(
          const Transcribed(
            ElicitationSettledAction(
              'turn',
              'form',
              ElicitationAccepted({'name': 'private-submitted-value'}),
            ),
          ),
        );
        recording.heard(
          const Transcribed(
            ElicitationRequestedAction(
              'turn',
              LinkWait('link', 'Open', 'https://example.com'),
            ),
          ),
        );
        recording.heard(
          const Transcribed(
            ElicitationSettledAction('turn', 'link', ElicitationDeclined()),
          ),
        );
        recording.heard(
          const Transcribed(
            ElicitationRequestedAction(
              'turn',
              FormWait('unfinished', 'Left open'),
            ),
          ),
        );
        await recording.flushed();
        final path = recording.path!;
        final raw = File(path).readAsStringSync();
        expect(raw, isNot(contains('private-submitted-value')));
        final past = PreparedHistory.fromJson(
          (await readRecordedHistory(path)).toJson(),
        );
        final transcript = past.actions.fold(
          Transcript.empty,
          reduceTranscript,
        );
        final records = transcript.entries
            .whereType<ElicitationEntry>()
            .toList();
        expect(records.map((e) => (e.wait.id, e.outcome, e.content)), [
          ('form', ElicitationOutcome.accepted, null),
          ('link', ElicitationOutcome.declined, null),
          ('unfinished', ElicitationOutcome.cancelled, null),
        ]);
        expect(transcript.asking, isEmpty);
        recording.heard(const Closing());
        await recording.flushed();
      },
    );

    test(
      'opening directly without clear cannot answer a retired request into the new file',
      () async {
        final writes = <String, List<String>>{};
        var index = 0;
        final recording = FileRecording(
          'state',
          failed: fail,
          uuid: () => 'file-${index++}',
          now: () => 1,
          append: (path, text) async => (writes[path] ??= []).add(text),
        );
        recording.opened(opening('old'));
        recording.sent('old-turn', 'form', 0, [], 1);
        recording.heard(
          const Transcribed(
            ElicitationRequestedAction('old-turn', FormWait('same', 'Old')),
          ),
        );
        recording.opened(opening('new'));
        recording.sent('new-turn', 'form', 0, [], 2);
        recording.heard(
          const Transcribed(
            ElicitationSettledAction('new-turn', 'same', ElicitationDeclined()),
          ),
        );
        await recording.flushed();
        expect(writes, hasLength(2));
        final newLines = lines(writes.values.last.join());
        expect(newLines.where((l) => l['type'] == 'answered'), isEmpty);
        recording.heard(
          const Transcribed(
            ElicitationRequestedAction('new-turn', FormWait('same', 'New')),
          ),
        );
        recording.heard(
          const Transcribed(
            ElicitationSettledAction(
              'new-turn',
              'same',
              ElicitationAccepted({'secret': 'redact-me'}),
            ),
          ),
        );
        await recording.flushed();
        final newRaw = writes.values.last.join();
        expect(newRaw, isNot(contains('redact-me')));
        expect(
          lines(newRaw).where((l) => l['type'] == 'answered'),
          hasLength(1),
        );
        recording.heard(const Closing());
        await recording.flushed();
      },
    );
  });
}

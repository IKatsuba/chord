// The original's record.ts for an agent's own cycle (CHD-426): no line of
// its own, but work the session spent on, as a prompt's turn is: what was
// held is kept from then, and its updates, cancel, result and cost follow, and replay
// under its turn id, a cost after a clear into the record it was in.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:test/test.dart';

import 'recording_test.dart' show lines, opening, update;

void main() {
  test(
    'a cycle begins the record and writes its lines under its turn',
    () async {
      final writes = <String, List<String>>{};
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'fixture',
        now: () => 1,
        append: (path, text) async => (writes[path] ??= []).add(text),
      );
      recording.opened(opening('id'));
      recording.heard(update('before'));
      await recording.flushed();
      expect(writes, isEmpty);

      recording.heard(const Transcribed(CycleStartedAction('c1', 5)));
      recording.heard(update('the build passed', 'c1'));
      recording.heard(const Transcribed(CancelAction('c1', 6)));
      recording.heard(
        const Transcribed(
          ResultAction('c1', TurnAnswered(acp.StopReason.cancelled)),
        ),
      );
      recording.heard(
        const Transcribed(
          UsageAction(
            'c1',
            TurnFigures(turnId: 'c1', usage: {'inputTokens': 3}),
          ),
        ),
      );
      await recording.flushed();
      final written = lines(writes.values.single.join());
      expect(written.map((e) => e['type']), [
        'session',
        'opened',
        'state',
        'update',
        'update',
        'cancel',
        'result',
        'usage',
      ]);
      expect(
        [for (final e in written.skip(4)) e['turnId']],
        ['c1', 'c1', 'c1', 'c1'],
      );

      // Replayed, the cycle's lines and its own cost row fold under its turn.
      final replayed = recordActions(written).actions;
      expect(
        [
          for (final action in replayed)
            if (action.turnId == 'history-c1') action.runtimeType,
        ],
        [UpdateAction, CancelAction, ResultAction, UsageAction],
      );

      // Cleared during it, the cost it says after goes to this record.
      recording.heard(const Cleared());
      recording.heard(
        const RetiredUsage(
          TurnFigures(turnId: 'c1', usage: {'inputTokens': 4}),
        ),
      );
      await recording.flushed();
      final last = lines(writes.values.single.join()).last;
      expect((last['type'], last['turnId']), ('usage', 'c1'));
    },
  );
}

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'replay_test.dart' show fold, prompt, update;

void main() {
  group('tester CTUI-167: legacy plan replay continuity', () {
    for (final id in ['', 'legacy', '界🙂e\u0301']) {
      test(
        'legacy id $id stays ignored through replacement and round trip',
        () {
          final reports = <Map<String, Object?>>[
            {
              'sessionUpdate': 'plan',
              'planId': id,
              'entries': [
                {
                  'content': 'first 界🙂e\u0301',
                  'priority': 'high',
                  'status': 'pending',
                },
              ],
            },
            {
              'sessionUpdate': 'plan',
              'planId': 'another',
              'entries': [
                {
                  'content': 'replaced',
                  'priority': 'low',
                  'status': 'in_progress',
                },
              ],
            },
          ];
          final recorded = recordActions([
            prompt('t', 'work'),
            for (final report in reports)
              {'type': 'update', 'turnId': 't', 'update': report},
          ]);
          final live = fold([
            const PromptAction('t', 'work', 1),
            for (final report in reports)
              UpdateAction('t', acp.SessionUpdate.fromJson(report)),
          ]);
          final copied = PreparedHistory.fromJson(recorded.toJson());
          expect(recorded.omitted, isFalse);
          expect(copied.omitted, isFalse);
          final restored = fold(copied.actions);
          expect(restored.planId, isNull);
          expect(restored.plan.map((entry) => entry.content), ['replaced']);
          expect(
            restored.plan.map((entry) => entry.content),
            live.plan.map((entry) => entry.content),
          );
        },
      );
    }

    test(
      'an empty legacy plan clears the earlier plan without an omission',
      () {
        final recorded = recordActions([
          update('plan', {
            'entries': [
              {'content': 'old', 'priority': 'medium', 'status': 'pending'},
            ],
          }),
          update('plan', {'planId': 'empty', 'entries': <Object?>[]}),
        ]);
        expect(recorded.omitted, isFalse);
        expect(fold(recorded.actions).plan, isEmpty);
        expect(fold(recorded.actions).planId, isNull);
      },
    );
  });
}

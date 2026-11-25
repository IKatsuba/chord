import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/status/facts.dart';
import 'package:test/test.dart';

import '../../session/transcript/fold.dart';

void main() {
  test(
    'one history batch replaces detached history and seeds current opening facts',
    () {
      const resumed = Resume(
        sessionId: 'id',
        cwd: 'fixture',
        title: 'Opened title',
        lastUsedAt: 1.25,
      );
      const current = AgentState(
        modes: {'currentModeId': 'B', 'availableModes': <Object?>[]},
      );
      final actions = <TranscriptAction>[
        const PromptAction('history-same', 'past', 1.25),
        say('history-same', 'saved'),
        update('history-same', {
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'historical',
        }),
        const ResultAction('history-same', TurnAnswered('end_turn')),
      ];
      final event = HistoryReplayed(
        actions,
        state: current,
        resumed: resumed,
        omitted: true,
      );
      actions.clear();
      final old = reduceApp(
        AppState.starting,
        const Transcribed(PromptAction('old', 'old document', 0)),
      );
      final next = reduceApp(old, event);
      expect(
        next.transcript.entries.whereType<UserEntry>().single.text,
        'past',
      );
      expect(next.agent, same(current));
      expect(statusFactsOf(next.agent, next.transcript).mode, 'B');
      expect(next.resumed, same(resumed));
      expect(next.omittedHistory, isTrue);
      expect(
        old.transcript.entries.whereType<UserEntry>().single.text,
        'old document',
      );
      expect(
        () => event.actions.add(const DisconnectedAction('bad')),
        throwsUnsupportedError,
      );
      final changed = reduceApp(
        next,
        const AgentStateChanged(AgentState.empty),
      );
      expect(changed.resumed, same(resumed));
      expect(changed.omittedHistory, isTrue);
      final cleared = reduceApp(changed, const Cleared());
      expect(cleared.resumed, isNull);
      expect(cleared.omittedHistory, isFalse);
      expect(cleared.transcript.entries, isEmpty);
    },
  );

  test(
    'equal persisted ids in a replacement never reuse old document tokens',
    () {
      final event = HistoryReplayed([
        const PromptAction('history-id', 'same', 1),
        const ResultAction('history-id', TurnAnswered('end_turn')),
      ], state: AgentState.empty);
      final first = reduceApp(AppState.starting, event);
      final next = reduceApp(reduceApp(first, const Cleared()), event);
      expect(
        next.transcript.entries.single.turnId,
        first.transcript.entries.single.turnId,
      );
      expect(
        next.transcript.entries.single.identity,
        isNot(same(first.transcript.entries.single.identity)),
      );
      expect(next.omittedHistory, isFalse);
    },
  );
}

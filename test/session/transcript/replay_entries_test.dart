import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

void main() {
  test(
    'detached replay equals ordinary fold for supported history and malformed recovery',
    () {
      final actions = <TranscriptAction>[
        const ShellReplayedAction(
          'shell',
          ShellRun(command: 'pwd', stdout: 'fixture', running: false, code: 0),
        ),
        const PromptAction('one', 'hello', 1.25),
        say('one', 'first'),
        say('one', ' second'),
        think('one', 'thinking'),
        update('one', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'tool',
          'title': 'Read',
          'kind': 'read',
        }),
        update('one', {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'tool',
          'status': 'completed',
        }),
        plan('one', [('complete', 'completed')]),
        update('one', {
          'sessionUpdate': 'usage_update',
          'used': 1.25,
          'size': 8.5,
        }),
        update('one', {
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'plan',
        }),
        const CancelAction('one', 1.5),
        const ResultAction('one', TurnAnswered('cancelled')),
        const PromptAction('two', 'second', 2.25),
        update('two', {'sessionUpdate': 'tool_call'}),
        say('two', 'still works'),
        const ResultAction('two', TurnFailed('failed', code: -32000)),
      ];
      final ordinary = fold(actions), replayed = replayTranscript(actions);
      expect(described(replayed), described(ordinary));
      expect(
        () => replayed.entries.add(const UserEntry('bad', 'mutation')),
        throwsUnsupportedError,
      );
      expect(() => replayed.plan.clear(), throwsUnsupportedError);
    },
  );

  test(
    'historical occurrences stay fresh across equal persisted ids and live replacements',
    () {
      final actions = <TranscriptAction>[
        const PromptAction('same', 'one', 1),
        say('same', 'a'),
        const ResultAction('same', TurnAnswered('end_turn')),
        const PromptAction('same', 'two', 2),
        say('same', 'b'),
        const ResultAction('same', TurnAnswered('end_turn')),
      ];
      final first = replayTranscript(actions),
          second = replayTranscript(actions);
      expect(first.entries.map((e) => e.identity).toSet(), hasLength(4));
      expect(
        first.entries.every(
          (e) => second.entries.every(
            (other) => !identical(e.identity, other.identity),
          ),
        ),
        isTrue,
      );
      final before = first.entries.last as AssistantEntry;
      final live = reduceTranscript(first, say('same', ' live'));
      expect((first.entries.last as AssistantEntry).text.text, 'b');
      expect((live.entries.last as AssistantEntry).text.text, 'b live');
      expect(live.entries.last.identity, same(before.identity));
      expect(live.entries.first, same(first.entries.first));
      expect(live.entries, isNot(same(first.entries)));
    },
  );

  test(
    '2000 historical turns copy final entries once at the writer boundary',
    () {
      final actions = <TranscriptAction>[
        for (var i = 0; i < 2000; i++) ...[
          PromptAction('turn-$i', 'prompt $i', i + .25),
          say('turn-$i', 'first'),
          say('turn-$i', ' second'),
          ResultAction('turn-$i', const TurnAnswered('end_turn')),
        ],
      ];
      final work = ReplayWork();
      final replayed = replayTranscript(actions, work: work);
      expect(replayed.entries, hasLength(4000));
      expect(work.appendedEntries, 4000);
      expect(work.replacedEntries, 2000);
      expect(work.copiedEntries, 4000);
      expect(replayed.turn, isA<Idle>());
      print(
        'replay turns=2000 appended=${work.appendedEntries} replaced=${work.replacedEntries} copied=${work.copiedEntries} finalEntries=${replayed.entries.length}',
      );
    },
  );
}

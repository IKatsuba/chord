import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

void main() {
  group('CTUI-26 U4a tester: middle-slot replay and publication isolation', () {
    test(
      'a thousand middle tool replacements copy only final entries and preserve live identity',
      () {
        final actions = <TranscriptAction>[
          const PromptAction('turn', 'work', 1.25),
          for (final id in ['first', 'second'])
            update('turn', {
              'sessionUpdate': 'tool_call',
              'toolCallId': id,
              'title': id,
            }),
          say('turn', 'later reply 界👩‍💻é'),
          for (var i = 0; i < 1000; i++)
            update('turn', {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': 'first',
              'title': 'revision $i',
            }),
          const ResultAction('turn', TurnAnswered('end_turn')),
        ];
        final work = ReplayWork();
        final replayed = replayTranscript(actions, work: work);
        expect(described(replayed), described(fold(actions)));
        expect(work.appendedEntries, 4);
        expect(work.replacedEntries, 1000);
        expect(work.copiedEntries, 4);
        final oldTool = replayed.entries.whereType<ToolEntry>().first;
        final live = reduceTranscript(
          replayed,
          update('turn', {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'first',
            'title': 'live replacement',
          }),
        );
        final liveTool = live.entries.whereType<ToolEntry>().first;
        expect(oldTool.call.title, 'revision 999');
        expect(liveTool.call.title, 'live replacement');
        expect(liveTool.identity, same(oldTool.identity));
        expect(live.entries.last, same(replayed.entries.last));
        expect(replayed.entries.map((e) => e.identity).toSet(), hasLength(4));
        expect(() => replayed.entries[1] = liveTool, throwsUnsupportedError);
      },
    );

    test(
      'empty replay and later replay leave published historical endings unchanged',
      () {
        final emptyWork = ReplayWork();
        final empty = replayTranscript(const [], work: emptyWork);
        expect(described(empty), described(Transcript.empty));
        expect(emptyWork.copiedEntries, 0);
        expect(
          () => empty.entries.add(const UserEntry('turn', 'bad')),
          throwsUnsupportedError,
        );
        final actions = <TranscriptAction>[
          const ShellReplayedAction(
            'shell',
            ShellRun(command: 'fixture', running: false, code: 7.25),
          ),
          const PromptAction('first', 'first', 1.25),
          const ResultAction(
            'first',
            TurnAnswered('cancelled', recordedStatus: 'completed'),
          ),
          const PromptAction('second', 'second', 2.25),
          const ResultAction(
            'second',
            TurnAnswered('end_turn', recordedStatus: 'cancelled'),
          ),
        ];
        final first = replayTranscript(actions);
        final snapshot = described(first);
        final next = replayTranscript(actions);
        expect(described(next), described(fold(actions)));
        expect(described(first), snapshot);
        expect(first.entries.whereType<ShellEntry>().single.run.code, 7.25);
        expect(
          first.entries.whereType<StoppedEntry>().single.reason,
          'cancelled',
        );
        expect(first.entries.whereType<CancelledEntry>(), hasLength(1));
        expect(
          next.entries.any(
            (e) =>
                first.entries.any((old) => identical(e.identity, old.identity)),
          ),
          isFalse,
        );
      },
    );
  });
}

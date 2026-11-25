import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../../tool/record_history.dart';

void main() {
  test(
    'omission belongs to exactly one publication, stays before live work and clears',
    () {
      final past = [
        const PromptAction('same', 'saved prompt', 1.25),
        const ResultAction('same', TurnAnswered('end_turn')),
      ];
      AppState publish(bool omitted) => reduceApp(
        AppState.starting,
        HistoryReplayed(past, state: AgentState.empty, omitted: omitted),
      );
      final supported = publish(false);
      expect(
        supported.transcript.entries.whereType<HistoryOmittedEntry>(),
        isEmpty,
      );
      final state = publish(true);
      final notice = state.transcript.entries
          .whereType<HistoryOmittedEntry>()
          .single;
      final live = reduceApp(
        state,
        const Transcribed(PromptAction('same', 'live prompt', 2.75)),
      );
      expect(live.transcript.entries.indexOf(notice), 1);
      expect(live.transcript.entries.last, isA<UserEntry>());
      final replaced = reduceApp(
        live,
        HistoryReplayed(past, state: AgentState.empty, omitted: true),
      );
      expect(
        replaced.transcript.entries.whereType<HistoryOmittedEntry>(),
        hasLength(1),
      );
      expect(reduceApp(replaced, const Cleared()).transcript.entries, isEmpty);
    },
  );
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'plain notice wraps once without role marker and survives resize $size',
      (t) async {
        final connection = StartConnection(command: 'unused', cwd: '.');
        addTearDown(connection.close);
        const selected = Resume(
          sessionId: 'saved',
          cwd: '.',
          prompt: 'saved prompt',
        );
        connection.app.value = reduceApp(
          const AppState(start: StartState(phase: StartPhase.connected)),
          HistoryReplayed(
            [
              const PromptAction('saved', 'saved prompt', 1),
              const ResultAction('saved', TurnAnswered('end_turn')),
            ],
            state: AgentState.empty,
            resumed: selected,
            omitted: true,
          ),
        );
        await t.pumpWidget(recordHistoryPreview(connection), size: size);
        expect(t.screen, shows('resumed · saved prompt'));
        expect(t.screen, shows(HistoryOmittedEntry.message));
        final line = t.screen.lines.singleWhere(
          (line) => line.contains('Some saved history'),
        );
        expect(line.trim(), HistoryOmittedEntry.message);
        connection.app.value = reduceApp(
          connection.app.value,
          Transcribed(
            UpdateAction(
              'live',
              acp.SessionUpdate.fromJson({
                'sessionUpdate': 'session_info_update',
                'title': 'Later live title',
              }),
            ),
          ),
        );
        await t.pump();
        expect(t.screen, shows('resumed · saved prompt'));
        expect(t.screen, isNot(shows('Later live title')));
        await t.resize(
          size == const Size(120, 40)
              ? const Size(80, 24)
              : const Size(120, 40),
        );
        expect(
          t.screen.lines.where((line) => line.contains('Some saved history')),
          hasLength(1),
        );
        connection.app.value = reduceApp(
          connection.app.value,
          const Transcribed(PromptAction('live', 'live prompt', 2)),
        );
        await t.pump();
        final lines = t.screen.lines;
        expect(
          lines.indexWhere((line) => line.contains('Some saved history')),
          lessThan(lines.indexWhere((line) => line.contains('live prompt'))),
        );
      },
    );
  }
}

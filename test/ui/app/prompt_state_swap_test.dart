import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: window prompt across repeated State swaps', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('keeps Unicode draft and undo through transitions at $size', (
        t,
      ) async {
        final connection = StartConnection(command: 'unused', cwd: '.');
        final plan = [
          acp.PlanEntry.fromJson({
            'content': 'Live step',
            'status': 'in_progress',
            'priority': 'medium',
          }),
        ];
        void show(bool planned, bool working) {
          connection.app.value = AppState(
            start: const StartState(phase: StartPhase.connected),
            transcript: model.Transcript(
              plan: planned ? plan : [],
              turn: working
                  ? model.Working('turn', DateTime.now().millisecondsSinceEpoch)
                  : const model.Idle(),
            ),
          );
        }

        try {
          show(false, false);
          await t.pumpWidget(
            TranscriptWindow(
              launch: const Launch(
                name: 'test',
                agent: null,
                agentCommand: 'unused',
                version: '0.0.1',
                directory: '.',
              ),
              connection: connection,
            ),
            size: size,
          );
          await t.paste('界👩‍💻e\u0301');
          await t.press('left');
          var inserted = '';
          for (final state in [
            (true, false),
            (false, true),
            (true, true),
            (false, false),
            (true, true),
            (false, false),
          ]) {
            show(state.$1, state.$2);
            await t.pump();
            await t.resize(
              t.size == const Size(80, 24)
                  ? const Size(120, 40)
                  : const Size(80, 24),
            );
            await t.type('x');
            expect(t.screen, shows('界👩‍💻${inserted}xe\u0301'));
            await t.press('ctrl+z');
            expect(t.screen, shows('界👩‍💻${inserted}e\u0301'));
            await t.press('ctrl+y');
            inserted += 'x';
            expect(t.screen, shows('界👩‍💻${inserted}e\u0301'));
            expect(t.screen.text.contains('Live step'), state.$1);
            expect(t.screen.text.contains('Working…'), state.$2);
          }
        } finally {
          t.dispose();
          await connection.close();
        }
      });
    }
  });
}

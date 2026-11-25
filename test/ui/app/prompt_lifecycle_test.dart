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
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'real window preserves prompt while live plan appears and clears at $size',
      (t) async {
        final connection = StartConnection(command: 'unused', cwd: '.');
        final plan = [
          acp.PlanEntry.fromJson({
            'content': 'A live step',
            'status': 'in_progress',
            'priority': 'medium',
          }),
        ];
        void show(List<acp.PlanEntry> entries, model.TurnState turn) {
          connection.app.value = AppState(
            start: const StartState(phase: StartPhase.connected),
            transcript: model.Transcript(plan: entries, turn: turn),
          );
        }

        show([], const model.Idle());
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
        await t.type('draft');
        await t.press('left');
        show(plan, const model.Idle());
        await t.pump();
        expect(t.screen, shows('A live step'));
        expect(t.screen, shows('│ › draft'));
        await t.type('X');
        expect(t.screen, shows('│ › drafXt'));
        show(
          plan,
          model.Working('turn', DateTime.now().millisecondsSinceEpoch),
        );
        await t.pump();
        expect(t.screen, shows('Working…'));
        await t.press('ctrl+z');
        expect(t.screen, shows('│ › draft'));
        show([], const model.Idle());
        await t.pump();
        await t.type('Y');
        expect(t.screen, shows('│ › drafYt'));
        expect(t.screen, isNot(shows('A live step')));
        expect(t.screen, isNot(shows('Working…')));
        t.dispose();
        await connection.close();
      },
    );
  }
}

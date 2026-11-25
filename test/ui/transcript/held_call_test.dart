// A call the person is still asked about waits on them, its turn over or
// not, as ../chord's Transcript.tsx passes `ended` (turnEnded and not
// asksFor): a request held between turns, or inside an agent's own cycle,
// still draws `⎿  Waiting…` under its call.
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    for (final (name, turn, waits) in [
      (
        'held inside a cycle',
        const model.AwaitingPermission(
          'cycle',
          0,
          [model.PermissionWait('p1', toolCallId: 'write')],
          between: true,
          cycle: true,
          cycleSince: 0,
        ),
        true,
      ),
      (
        'held between turns',
        const model.AwaitingPermission('cycle', 0, [
          model.PermissionWait('p1', toolCallId: 'write'),
        ], between: true),
        true,
      ),
      ('answered, the turn over', const model.Idle(), false),
    ]) {
      testWidgets(
        'a call $name ${waits ? 'waits' : 'does not wait'} at $size',
        (t) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await t.pumpWidget(
            Transcript(
              transcript: model.Transcript(
                entries: [
                  model.ToolEntry(
                    'cycle',
                    const model.ToolCall(
                      'write',
                      title: 'Write notes/build.md',
                      kind: 'edit',
                      status: 'pending',
                    ),
                  ),
                ],
                turn: turn,
              ),
              controller: scroll,
            ),
            size: size,
          );
          expect(t.screen, shows('Write'));
          expect(
            t.screen,
            waits ? shows('⎿  Waiting…') : isNot(shows('Waiting…')),
          );
        },
      );
    }
  }
}

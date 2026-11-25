// The window names its agent as ../chord's header does: by the name chord
// knows it (`codex`), not the catalog's display title (`Codex`).
import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'window_fake_test.dart' show until;

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a catalog agent is named as chord knows it at $size', (
      t,
    ) async {
      final agent = findAgent('codex')!;
      expect(agent.title, isNot(agent.name));
      final connection = StartConnection(
        command: 'codex',
        cwd: '/w',
        agent: agent.name,
        owner: Owned(),
        open:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) => Future.error(StateError('not here')),
      )..start();
      addTearDown(connection.close);
      await t.pumpWidget(
        TranscriptWindow(
          launch: Launch(
            name: agent.name,
            agent: agent,
            version: 'test',
            directory: 'project',
          ),
          connection: connection,
        ),
        size: size,
      );
      await until(() => connection.app.value.start.phase == StartPhase.failed);
      await t.pump();
      final header = t.screen.lines.take(4).join('\n');
      expect(header, contains(' codex'));
      expect(header, isNot(contains(agent.title)));
      expect(t.screen, shows('codex did not start:'));
    });
  }
}

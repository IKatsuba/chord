// A permission the agent asks between turns, held back from the keys, as
// the original's window keeps it (tests/ui/dialogs/PermissionBetween_test.tsx,
// the fake's mainbetween): Esc leaves it waiting, and once ctrl+x a has
// taken the keys into it, Esc denies it: the agent hears its reject_once
// option (the fake then says "Permission: deny.", which this agent does not).
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart' show heldBack;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'resume_window_test.dart' as resume;
import 'window_fake_test.dart' show until;

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('Esc leaves a held-back permission waiting; after ctrl+x a it '
        'denies it at $size', (t) async {
      late final MemoryAgentProcess process;
      process = MemoryAgentProcess(
        onSignal: (_) {
          if (process.exited) return;
          process.exit(const Exit(143, 'SIGTERM'));
          process.closeStdout();
          process.closeStderr();
        },
      );
      final answered = <Object?>{};
      final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
        for (final message in [...process.stdin.messages]) {
          final id = message['id'];
          final method = message['method'];
          if (id == null || method == null || !answered.add(id)) continue;
          process.send({
            'jsonrpc': '2.0',
            'id': id,
            'result': method == 'initialize'
                ? {'protocolVersion': 1}
                : {'sessionId': 's1'},
          });
        }
      });
      final connection = StartConnection(
        command: 'memory',
        cwd: '/w',
        agent: 'memory',
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
            }) => connectAgent(
              process,
              onTraffic: onTraffic,
              onPermission: onPermission,
              relay: relay,
              cancellationToken: cancellationToken,
            ),
      )..start();
      addTearDown(() async {
        timer.cancel();
        await connection.close();
      });
      await t.pumpWidget(
        TranscriptWindow(launch: resume.launch, connection: connection),
        size: size,
      );
      await until(
        () => connection.app.value.start.phase == StartPhase.connected,
      );
      process.send({
        'jsonrpc': '2.0',
        'id': 'ask-1',
        'method': 'session/request_permission',
        'params': {
          'sessionId': 's1',
          'toolCall': {'toolCallId': 'write-1', 'title': 'Write notes.txt'},
          'options': [
            {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
            {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
          ],
        },
      });
      await until(() {
        final turn = connection.app.value.transcript.turn;
        return turn is AwaitingPermission && turn.between;
      });
      // Held back from the keys: Esc is the interrupt, not a reply.
      expect(heldBack(connection.app.value), isTrue);
      await t.pump();
      expect(t.screen.lines.join('\n'), contains('Write notes'));
      Map<String, Object?>? answer() {
        for (final message in process.stdin.messages) {
          if (message['id'] == 'ask-1' && !message.containsKey('method')) {
            return message;
          }
        }
        return null;
      }

      final held = t.screen.lines.join('\n');
      await t.press('escape');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await t.pump();
      expect(answer(), isNull);
      expect(heldBack(connection.app.value), isTrue);
      expect(t.screen.lines.join('\n'), held);

      await t.press('ctrl+x');
      await t.press('a');
      expect(heldBack(connection.app.value), isFalse);
      await t.press('escape');
      await until(() => answer() != null);
      expect(answer()!['result'], {
        'outcome': {'outcome': 'selected', 'optionId': 'deny'},
      });
      await until(
        () => connection.app.value.transcript.turn is! AwaitingPermission,
      );
      await t.pump();
      expect(t.screen.lines.join('\n'), contains('Rejected Write notes.txt'));
    });
  }
}

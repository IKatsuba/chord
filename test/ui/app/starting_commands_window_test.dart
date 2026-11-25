// While the agent starts, Enter holds a prompt in the box and runs chord's
// own commands, as the original's submitSteps gates only prompts.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

/// A window whose agent never finishes starting.
Future<StartConnection> _starting(WidgetTester t, Size size) async {
  final hanging = Completer<Agent>();
  final c = StartConnection(
    command: 'fake',
    cwd: '.',
    agent: 'fake',
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
        }) => hanging.future,
  )..start();
  addTearDown(c.close);
  addTearDown(() {
    hanging.future.ignore();
    hanging.completeError(StateError('over'));
  });
  await t.pumpWidget(
    TranscriptWindow(
      launch: const Launch(
        name: 'fake',
        agent: null,
        agentCommand: 'fake',
        version: '0.0.1',
        directory: '.',
      ),
      connection: c,
    ),
    size: size,
  );
  return c;
}

void main() {
  group('tester: CTUI-76 held startup prompt ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('highlighted local prefix runs while starting at $size', (
        t,
      ) async {
        final c = await _starting(t, size);
        await t.type('/hel');
        await _settle(t);
        await t.press('enter');
        await _settle(t);
        expect(c.app.value.shortcuts.help, isTrue);
        expect(c.app.value.draft, '');
      });

      testWidgets('local panels run after a held Unicode prompt at $size', (
        t,
      ) async {
        final c = await _starting(t, size);
        const draft = '界🙂e\u0301';
        await t.type(draft);
        await t.press('enter');
        await _settle(t);
        expect(c.app.value.draft, draft);
        await t.press('ctrl+a ctrl+k');
        await t.type('/mcp');
        await t.press('enter');
        await _settle(t);
        expect(c.app.value.draft, '');
        expect(t.screen.text, contains('MCP servers'));
        expect(c.app.value.start.phase, isNot(StartPhase.connected));
        await t.resize(
          size.width == 120 ? const Size(80, 24) : const Size(120, 40),
        );
        await t.press('esc');
        await _settle(t);
        await t.type('/help');
        await t.press('enter');
        await _settle(t);
        expect(c.app.value.shortcuts.help, isTrue);
        await t.press('esc');
        await _settle(t);
        await t.type(draft);
        await t.press('enter');
        await _settle(t);
        expect(c.app.value.draft, draft);
        expect(c.app.value.start.phase, isNot(StartPhase.connected));
      });
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("chord's own commands run while the agent starts, and a "
        'prompt waits in the box, at $size', (t) async {
      final c = await _starting(t, size);
      expect(c.app.value.start.phase, isNot(StartPhase.connected));

      await t.type('/help');
      await t.press('enter');
      await _settle(t);
      expect(c.app.value.shortcuts.help, isTrue);
      expect(c.app.value.draft, '');
      await t.press('esc');
      await _settle(t);

      await t.type('/vim');
      await t.press('enter');
      await _settle(t);
      expect(c.app.value.vim, isNotNull);

      await t.type('/status');
      await t.press('enter');
      await _settle(t);
      expect(c.app.value.draft, '');
      expect(t.screen.text, contains('fake'));

      await t.type('hello');
      await t.press('enter');
      await _settle(t);
      expect(c.app.value.draft, 'hello');
    });
  }

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('Enter on a command the list highlights runs it while the '
        'agent starts, as the original submits the highlighted one, at '
        '$size', (t) async {
      final c = await _starting(t, size);
      await t.type('/hel');
      await _settle(t);
      await t.press('enter');
      await _settle(t);
      expect(c.app.value.shortcuts.help, isTrue);
      expect(c.app.value.draft, '');
    });
  }
}

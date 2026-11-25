// Monitors in the window, on the original's fake and chord's own server:
// their events as message rows of their lines as printed, as the
// original's tests/ui/agents/Monitors_test.tsx has them.
@Tags(['fake_agent'])
library;

import 'package:chord/server/server.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../../fixtures/runtimes.dart';
import 'editor_window_test.dart' show plainLaunch;

/// Main on the fake in the window, with chord's server and the host as the
/// launch wires them.
Future<StartConnection> monitorsWindow(WidgetTester t, Size size) async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  final fold = connection.fold;
  final host = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: connection.openChild,
    agents: connection.agents,
    opened: (key) => fold.dispatch(AgentOpened(key)),
    closed: (key, front) => fold.dispatch(SessionClosed(key, front)),
    server: server,
    cwd: runtimes.home.path,
  );
  connection
    ..server = server
    ..window = host
    ..start();
  addTearDown(() async {
    await connection.close();
    await server.close();
    runtimes.dispose();
  });
  await t.pumpWidget(
    TranscriptWindow(launch: plainLaunch, connection: connection),
    size: size,
  );
  await until(
    t,
    () => fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return connection;
}

Future<void> until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 750 && !done(); i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: t.screen.text);
}

void main() {
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("a monitor's event is a message row of its lines as printed, "
        'at $size', (t) async {
      await monitorsWindow(t, size);
      await t.type('monitors');
      await t.press('enter');
      await until(
        t,
        () => t.screen.text.contains(
          'Received the message from dev server errors · monitor.',
        ),
      );
      final rows = [for (final row in t.screen.lines) row.trimRight()];
      final header = rows.indexOf(' ← from dev server errors · monitor');
      expect(header, isNot(-1), reason: t.screen.text);
      if (size.width == 120) {
        expect(rows.sublist(header + 1, header + 3), [
          "   ⎿  ERROR [router] POST /login 500: Cannot read properties of "
              "undefined (reading 'trim')",
          '          at validate (src/routes/login.tsx:41:22)',
        ]);
      } else {
        expect(
          rows[header + 1],
          startsWith('   ⎿  ERROR [router] POST /login 500: Cannot read'),
        );
        expect(
          rows,
          contains('          at validate (src/routes/login.tsx:41:22)'),
        );
      }
    }, skip: skip);
  }

  // CTUI-84: the command breaks only at spaces, as wrap-ansi wraps it in
  // the original (tests/ui/agents captures), never after a slash or an
  // opening bracket.
  const commandRows = {
    120: [
      '   ⎿  \$ sleep 1; echo "ERROR [router] POST /login 500: Cannot read '
          'properties of undefined (reading \'trim\')"; echo "',
      '      at validate (src/routes/login.tsx:41:22)"; sleep 600',
      '      m1 · times out after 10m',
    ],
    80: [
      '   ⎿  \$ sleep 1; echo "ERROR [router] POST /login 500: Cannot read '
          'properties',
      '      of undefined (reading \'trim\')"; echo "    at validate',
      '      (src/routes/login.tsx:41:22)"; sleep 600',
      '      m1 · times out after 10m',
    ],
  };
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("a monitor's command wraps at spaces only, at $size", (
      t,
    ) async {
      await monitorsWindow(t, size);
      await t.type('monitors');
      await t.press('enter');
      await until(t, () => t.screen.text.contains('m1 · times out after 10m'));
      final rows = [for (final row in t.screen.lines) row.trimRight()];
      final call = rows.indexOf(' ⏺ Monitor(dev server errors)');
      expect(call, isNot(-1), reason: t.screen.text);
      final want = commandRows[size.width]!;
      expect(rows.sublist(call + 1, call + 1 + want.length), want);
    }, skip: skip);
  }
}

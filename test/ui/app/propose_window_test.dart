// propose_team in the window, on the original's fake and chord's own
// server: Team(bugfix) · proposal under its call while chord's save box
// asks to save it for this project, for every project, or to say what to
// change; picked, the call says where it was saved. At 120x40 and 80x24.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/server/server.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../../fixtures/runtimes.dart';
import 'editor_window_test.dart' show plainLaunch;

/// Main on the fake in the window, in a project with a config home.
Future<({StartConnection connection, String cwd})> _window(
  WidgetTester t,
  Size size,
) async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final home = runtimes.home.path;
  final configHome = p.join(home, 'config-home', '.config');
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: home,
    agent: 'fake',
    open: runtimes.opener,
  );
  final fold = connection.fold;
  final host = AgentsHost(
    runtimeNames: const ['fake', 'claude', 'codex'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: connection.openChild,
    agents: connection.agents,
    opened: (key) => fold.dispatch(AgentOpened(key)),
    closed: (key, front) => fold.dispatch(SessionClosed(key, front)),
    server: server,
    cwd: home,
    configHome: configHome,
    home: p.join(home, 'config-home'),
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
  await _until(
    t,
    () => fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return (connection: connection, cwd: home);
}

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 750 && !done(); i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: t.screen.text);
}

Future<void> _shows(WidgetTester t, String text) =>
    _until(t, () => t.screen.text.contains(text));

void main() {
  group('CTUI-37 tester: proposal box keys and resize', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'Esc declines, next proposal survives tiny room and key 2 saves user file at $size',
        (t) async {
          final (:connection, :cwd) = await _window(t, size);
          await t.type('propose');
          await t.press('enter');
          await _shows(t, 'Save team bugfix?');
          await t.press('esc');
          await _until(
            t,
            () =>
                connection.fold.stateOf(mainKey)!.transcript.turn is model.Idle,
          );
          final project = File(p.join(cwd, '.chord', 'teams', 'bugfix.md'));
          expect(project.existsSync(), isFalse);
          await t.type('reviewer on codex');
          await t.press('enter');
          await _shows(t, 'Save team bugfix?');
          for (final room in [
            const Size(0, 1),
            const Size(1, 1),
            const Size(30, 12),
            size,
          ]) {
            await t.resize(room);
          }
          await _shows(t, 'Save team bugfix?');
          await t.press('2');
          await _shows(t, 'Saved to ~/.config/chord/teams/bugfix.md');
          expect(project.existsSync(), isFalse);
          final user = File(
            p.join(
              cwd,
              'config-home',
              '.config',
              'chord',
              'teams',
              'bugfix.md',
            ),
          );
          expect(user.existsSync(), isTrue);
        },
        skip: fakeAgentSkip,
      );
    }
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the proposal draws under its call while the box asks, and '
        'picked, says where it was saved, at $size', (t) async {
      final (:connection, :cwd) = await _window(t, size);
      await t.type('propose');
      await t.press('enter');
      await _shows(t, 'Save team bugfix?');
      // Each choice names the file it writes.
      expect(t.screen.text, contains('.chord/teams/bugfix.md'));
      expect(t.screen.text, contains('~/.config/chord/teams/bugfix.md'));
      expect(t.screen.text, contains('Yes, for this project'));
      expect(t.screen.text, contains('Yes, for every project'));
      expect(t.screen.text, contains('No, tell fake what to change'));
      await t.press('1');
      await _shows(t, 'Saved to .chord/teams/bugfix.md');
      expect(
        File(p.join(cwd, '.chord', 'teams', 'bugfix.md')).existsSync(),
        isTrue,
      );
      expect(connection.agents.agents.children, isEmpty);
    }, skip: fakeAgentSkip);
  }
}

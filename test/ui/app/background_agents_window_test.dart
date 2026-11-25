// An agent's own subagents in the background, over the window, on the
// original's fake, as the original's tests/ui/background/
// BackgroundFrame_test.tsx and BackgroundView_test.tsx have them: counted on
// the summary line, listed in the view, x stopping one alone, a stop that
// is slow or refused said on its row or the hint line.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/acp/connection.dart' show windowCapabilities;
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/subagents.dart'
    show isRunning, subagentsIn;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';
import 'monitors_window_test.dart' show until;
import 'window_fake_test.dart' show launch;

/// The window on the fake, declaring subagents as chord's window does; its
/// connection, whose state a test may wait on.
Future<StartConnection> _window(WidgetTester t, Size size) async {
  final directory = Directory.systemTemp.createTempSync('chord-bg-agents-');
  final connection = StartConnection(
    command: fakeAgentCommand().map(shellWord).join(' '),
    cwd: directory.path,
    agent: 'fake',
    open: fakeOpenerWith(capabilities: windowCapabilities()),
    owner: Owned(),
  )..start();
  addTearDown(() async {
    await connection.close();
    directory.deleteSync(recursive: true);
  });
  await t.pumpWidget(
    TranscriptWindow(launch: launch, connection: connection),
    size: size,
  );
  await until(
    t,
    () => connection.app.value.start.phase == StartPhase.connected,
  );
  return connection;
}

/// [scenario] sent, then the view opened from the summary line once it
/// says [summary].
Future<void> _opened(WidgetTester t, String scenario, String summary) async {
  await t.type(scenario);
  await t.press('enter');
  await until(t, () => t.screen.text.contains(summary));
  await t.press('down');
  await t.press('enter');
  await t.pump();
}

void main() {
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets("x on a Claude agent stops it alone: its row leaves, its block "
        "Cancelled, and its parent's turn goes on, at $size", (t) async {
      await _window(t, size);
      await _opened(
        t,
        'claudebackground',
        "background  main's 2 agents running",
      );
      expect(t.screen.text, contains('❯ Run the test suite'));
      await t.press('x');
      // Stopped, it leaves, the ❯ on the row that took its place.
      await until(
        t,
        () => t.screen.text.contains('│ Background · 1 in this session'),
      );
      expect(t.screen.text, isNot(contains('Run the test suite  agent')));
      // The one the turn waits on runs on, and the turn ends on its own;
      // the last row leaving closes the view.
      await until(
        t,
        () => t.screen.text.contains(
          'The tests run on; I will say when they end.',
        ),
      );
      await until(t, () => !t.screen.text.contains('│ Background'));
      expect(t.screen.text, contains('⎿  Cancelled'));
      expect(t.screen.text, isNot(contains('Interrupted by user')));
    }, skip: skip);

    testWidgets('x on an agent that took its own stop back says so on the '
        'hint line, and stays running, at $size', (t) async {
      final connection = await _window(t, size);
      await _opened(t, 'claudenostop', "background  main's agent running");
      expect(t.screen.text, contains('❯ Run the test suite'));
      // Its agent withdraws the stop a step after it announced the agent,
      // which nothing on screen shows before x: x waits until chord has
      // taken the withdrawal in, the agent still at work.
      await until(t, () {
        final agents = subagentsIn(connection.app.value.transcript.entries);
        return agents.length == 1 &&
            isRunning(agents.single) &&
            !agents.single.cancellable;
      });
      await t.press('x');
      await until(t, () => t.screen.text.contains('this agent offers no stop'));
      expect(t.screen.text, isNot(contains('to stop · Esc to close')));
      expect(t.screen.text, contains('running'));
    }, skip: skip);

    testWidgets('a Claude agent that takes a while to stop reads stopping '
        'until it says it stopped, then leaves, and a second x changes '
        'nothing, at $size', (t) async {
      await _window(t, size);
      await _opened(t, 'claudeslowstop', "background  main's 2 agents running");
      expect(t.screen.text, contains('❯ Run the test suite'));
      await t.press('x');
      await until(t, () => t.screen.text.contains('■ stopping'));
      await t.press('x');
      await t.pump();
      expect(t.screen.text, contains('■ stopping'));
      expect(t.screen.text, isNot(contains('could not stop')));
      // Once it says it stopped, its row leaves.
      await until(
        t,
        () => !t.screen.text.contains('Run the test suite  agent'),
      );
      expect(t.screen.text, isNot(contains('■ stopped after')));
    }, skip: skip);

    testWidgets('an agent its agent says waits, with no request on screen, is '
        'asking: ● waiting on its row, at $size', (t) async {
      await _window(t, size);
      await _opened(t, 'claudewaiting', "background  ● main's agent asking");
      expect(t.screen.text, contains('● waiting'));
      // Its end takes its row and the line away.
      await until(
        t,
        () =>
            !t.screen.text.contains('│ Background') &&
            !t.screen.text.contains('background  '),
      );
    }, skip: skip);
  }
}

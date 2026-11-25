// The splash in the window, from the original's tests/ui/splash/Splash_test.tsx.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/keys.dart' as keys;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord/ui/splash/splash_widget.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../app/window_fake_test.dart' show until;

const launch = Launch(
  name: 'fake',
  agent: null,
  agentCommand: 'fake',
  version: '0.0.1',
  directory: '.',
);

/// A connection whose start [open] decides.
StartConnection connection(Future<Agent> Function() open) => StartConnection(
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
      }) => open(),
)..start();

Future<StartConnection> splashWindow(
  WidgetTester t,
  Size size, [
  Future<Agent> Function()? open,
]) async {
  // A start that never ends, so the splash stays, until the test is over.
  final hanging = Completer<Agent>();
  final c = connection(open ?? () => hanging.future);
  addTearDown(c.close);
  addTearDown(() {
    if (hanging.isCompleted) return;
    hanging.future.ignore();
    hanging.completeError(StateError('over'));
  });
  await t.pumpWidget(
    TranscriptWindow(launch: launch, connection: c, splash: true),
    size: size,
  );
  return c;
}

void main() {
  testWidgets('the splash holds the screen while the agent starts', (t) async {
    await splashWindow(t, const Size(80, 24));
    final lines = t.screen.lines;
    // Centred, as the 80×24 frames have it, and nothing of the window.
    expect(lines[16], contains('${' ' * 32}Starting fake…'));
    expect(lines.sublist(5, 15).any((l) => l.contains('██████')), isTrue);
    expect(t.screen.text, isNot(contains('chord v')));
    expect(t.screen.text, isNot(contains('╭')));
    expect(t.screen.styleAt(33, 16).isDim, isTrue);
  });

  testWidgets('at 120×40 it is centred too', (t) async {
    await splashWindow(t, const Size(120, 40));
    final lines = t.screen.lines;
    expect(lines[24], contains('${' ' * 52}Starting fake…'));
    expect(lines[13], startsWith('${' ' * 55}██▄'));
    expect(t.screen.text, isNot(contains('chord v')));
  });

  testWidgets('the mark drifts a step at a time on its own timer', (t) async {
    await splashWindow(t, const Size(80, 24));
    final first = t.screen.text;
    await t.pump(const Duration(milliseconds: 350));
    expect(t.screen.text, isNot(first));
    expect(t.screen.text, contains('Starting fake…'));
  });

  testWidgets('esc opens the window, which never hears it', (t) async {
    await splashWindow(t, const Size(80, 24));
    await t.press('esc');
    expect(t.screen.text, contains('chord v'));
    // The window's own line says the start goes on.
    expect(t.screen.text, contains('Starting fake…'));
    expect(t.screen.lines[16], isNot(contains('Starting fake…')));
  });

  testWidgets('ctrl+c on the splash arms the quit as the status line would', (
    t,
  ) async {
    await splashWindow(t, const Size(80, 24));
    await t.press('ctrl+c');
    expect(t.screen.text, contains('Press ctrl+c again to quit'));
    expect(t.screen.text, isNot(contains('chord v')));
  });

  testWidgets('a failed start cuts to the window and its error', (t) async {
    final c = await splashWindow(
      t,
      const Size(80, 24),
      () => Future.error(StateError('spawn fake ENOENT')),
    );
    await until(() => c.app.value.start.phase == StartPhase.failed);
    await t.pump();
    expect(t.screen.text, contains('chord v'));
    expect(t.screen.text, contains('spawn fake ENOENT'));
  });

  testWidgets('the splash is cut once the agent is up', (t) async {
    late final MemoryAgentProcess process;
    process = MemoryAgentProcess(
      onSignal: (_) {
        if (process.exited) return;
        process.exit(const Exit(143, 'SIGTERM'));
        process.closeStdout();
        process.closeStderr();
      },
    );
    final seen = <Object?>{};
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      for (final message in [...process.stdin.messages]) {
        final id = message['id'];
        final method = message['method'];
        if (id == null || method == null || !seen.add(id)) continue;
        process.send({
          'jsonrpc': '2.0',
          'id': id,
          'result': method == 'initialize'
              ? {'protocolVersion': 1}
              : {'sessionId': 's1'},
        });
      }
    });
    addTearDown(timer.cancel);
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
          }) => connectAgent(
            process,
            onTraffic: onTraffic,
            onPermission: onPermission,
            relay: relay,
            cancellationToken: cancellationToken,
          ),
    )..start();
    addTearDown(c.close);
    await t.pumpWidget(
      TranscriptWindow(launch: launch, connection: c, splash: true),
      size: const Size(80, 24),
    );
    expect(t.screen.text, contains('Starting fake…'));
    await until(() => c.app.value.start.phase == StartPhase.connected);
    await t.pump();
    expect(t.screen.text, contains('chord v'));
    expect(t.screen.text, isNot(contains('Starting fake…')));
  });

  for (final size in const [Size(80, 24), Size(120, 40)]) {
    testWidgets('keys on the splash are kept for the window, and esc opens '
        'it, at $size', (t) async {
      await splashWindow(t, size);
      await t.type('hi');
      expect(t.screen.text, isNot(contains('hi')));
      await t.press('esc');
      expect(t.screen.text, contains('chord v'));
      expect(t.screen.text, contains('› hi'));
      // The window's own line, under the prompt box, says the start goes on.
      final status = t.screen.lines.lastWhere((l) => l.trim().isNotEmpty);
      expect(status, contains('Starting fake…'));
    });

    testWidgets('while the agent starts Enter keeps the draft, at $size', (
      t,
    ) async {
      final c = await splashWindow(t, size);
      await t.press('esc');
      await t.type('hello');
      await t.press('enter');
      expect(t.screen.text, contains('› hello'));
      expect(c.app.value.transcript.entries, isEmpty);
    });

    testWidgets('ctrl+v says the agent has not started, and its failure '
        'replaces that, at $size', (t) async {
      final opening = Completer<Agent>();
      final c = await splashWindow(t, size, () => opening.future);
      await t.press('esc');
      await t.press('ctrl+v');
      await t.pump();
      expect(t.screen.text, contains('fake has not started yet'));
      opening.completeError(StateError('spawn fake ENOENT'));
      await until(() => c.app.value.start.phase == StartPhase.failed);
      await t.pump();
      expect(t.screen.text, contains('fake did not start: '));
      expect(t.screen.text, isNot(contains('has not started yet')));
    });
  }

  group('esc on the splash is a bound action', () {
    keys.KeyContext context({required bool splash}) => keys.KeyContext(
      state: const AppState(),
      history: const history.History(),
      rows: 24,
      splash: splash,
    );
    Binding? esc(keys.KeyContext Function() at) => keys
        .windowBindings(at, (_) {})
        .where((b) => b.chord == Chord.parse('esc'))
        .firstOrNull;

    test('it leaves the splash first, and says so', () {
      final on = context(splash: true);
      expect(keys.keySteps(Chord.parse('esc'), on), [isA<keys.LeaveSplash>()]);
      expect(esc(() => on)?.description, 'Show the window');
    });

    test("without the splash esc is the window's own", () {
      final off = context(splash: false);
      expect(
        keys.keySteps(Chord.parse('esc'), off),
        isNot(contains(isA<keys.LeaveSplash>())),
      );
      expect(esc(() => off)?.description, 'Interrupt turn or stop command');
    });
  });

  group('tester: splash timing and lifecycle', () {
    testWidgets('resize through tiny rooms and removal stops live animation', (
      t,
    ) async {
      await t.pumpWidget(const Splash(agent: '界👩‍💻é'));
      for (final size in const [
        Size(120, 40),
        Size(80, 24),
        Size(16, 9),
        Size(1, 1),
        Size(0, 0),
        Size(80, 24),
      ]) {
        await t.resize(size);
        expect(t.screen.lines, hasLength(size.height));
      }
      await t.pumpWidget(Text('after splash'));
      await t.pump(const Duration(milliseconds: 350));
      expect(t.screen.text, contains('after splash'));
      expect(t.screen.text, isNot(contains('Starting')));
    });

    testWidgets('slow hint appears in place until Esc reveals the window', (
      t,
    ) async {
      await splashWindow(t, const Size(80, 24));
      await t.pump(const Duration(milliseconds: 5200));
      expect(t.screen.text, contains('esc for the window · ctrl+c to quit'));
      expect(t.screen.text, contains('Starting fake… 5s'));
      await t.press('esc');
      expect(t.screen.text, contains('chord v'));
    });
  });
}

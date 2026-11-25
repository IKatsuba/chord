// Original Transcript/TranscriptBack window cases reached through the real
// fake-agent harness. No active permission scenarios, prompt history/queue UI,
// multi-session or mount-window behavior is in CTUI-16.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/start.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/dev.dart' show shellWord;
import '../../fixtures/fake_harness.dart';

const launch = Launch(
  name: 'fake',
  agent: null,
  agentCommand: 'fake',
  version: '0.0.1',
  directory: '/workspace/demo',
);

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('window state did not arrive before deadline');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<StartConnection> connected(
  WidgetTester tester,
  Size size, {
  List<String> flags = const [],
  void Function(int)? onPid,
}) async {
  final directory = Directory.systemTemp.createTempSync('chord-transcript-');
  final pids = <int>[];
  final connection = StartConnection(
    command: fakeAgentCommand(null, flags).map(shellWord).join(' '),
    cwd: directory.path,
    agent: 'fake',
    open: fakeSessionOpener((pid) {
      pids.add(pid);
      onPid?.call(pid);
    }),
    owner: Owned(),
  )..start();
  addTearDown(() async {
    await connection.close();
    expect(
      pids.where(
        (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
      ),
      isEmpty,
      reason: 'the fake agent is still running',
    );
    directory.deleteSync(recursive: true);
  });
  await tester.pumpWidget(
    StartWindow(launch: launch, connection: connection),
    size: size,
  );
  await until(() => connection.app.value.start.phase == StartPhase.connected);
  await tester.pump();
  expect(tester.screen, isNot(shows('Connected')));
  return connection;
}

Future<void> sent(
  WidgetTester tester,
  StartConnection connection,
  String prompt,
) async {
  await tester.type(prompt);
  await tester.press('enter');
  await until(
    () =>
        connection.app.value.transcript.entries.isNotEmpty &&
        connection.app.value.transcript.turn is model.Idle,
  );
  await tester.pump();
}

void main() {
  group('live transcript window', skip: fakeAgentSkip, () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final (scenario, visible) in [
        ('text', 'Hello, world.'),
        ('thought', 'Thinking…'),
        ('tools', 'Read(README.md)'),
        ('calls', 'Error:'),
        ('edit', '2 additions and 1 removal'),
        ('bash', 'Two files changed.'),
        ('shell', 'Exit code 1'),
        ('plan', 'Run the tests'),
        ('todos', 'todo tools: 1'),
        ('error', 'The fake agent failed on purpose.'),
        ('turnfailed', 'Request failed: the model is overloaded.'),
      ]) {
        testWidgets('$scenario through Enter at $size', (t) async {
          final connection = await connected(t, size);
          await sent(t, connection, scenario);
          expect(
            connection.app.value.transcript.entries.first,
            isA<model.UserEntry>(),
          );
          expect(
            (connection.app.value.transcript.entries.first as model.UserEntry)
                .text,
            scenario,
          );
          expect(t.screen, shows(visible));
          final bindings = {
            for (final b in t.focusManager.activeBindings)
              b.chord.toString(): b.description,
          };
          expect(bindings['enter'], 'Send prompt');
          expect(bindings['escape'], 'Interrupt turn or stop command');
          expect(bindings['ctrl+o'], 'Toggle transcript details');
          await t.press('ctrl+d');
          expect(t.exitRequested, isTrue);
        });
      }
      testWidgets(
        'rewrite and growing Markdown remain keyboard reachable at $size',
        (t) async {
          final connection = await connected(t, size);
          await sent(t, connection, 'rewrite');
          await t.press('home');
          expect(t.screen, shows('Updated'));
          expect(t.screen, shows('lines below'));
          await t.press('ctrl+o');
          await t.press('end');
          expect(t.screen, isNot(shows('lines below')));
          await t.type('markdown');
          await t.press('enter');
          await until(
            () => connection.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .any((e) => e.text.text.contains('That is the whole loop.')),
          );
          await until(() => connection.app.value.transcript.turn is model.Idle);
          await t.pump();
          await t.press('home');
          expect(t.screen, shows('rewrite'));
        },
      );
      testWidgets('idle exit has no receipt and the next send fails at $size', (
        t,
      ) async {
        late int pid;
        final connection = await connected(
          t,
          size,
          onPid: (value) => pid = value,
        );
        Process.killPid(-pid, ProcessSignal.sigkill);
        await until(() => connection.app.value.start.phase == StartPhase.gone);
        await t.pump();
        expect(connection.app.value.transcript.entries, isEmpty);
        expect(t.screen, isNot(shows('The agent exited')));
        await t.type('text');
        await t.press('enter');
        await until(
          () => connection.app.value.transcript.entries.any(
            (entry) => entry is model.ErrorEntry,
          ),
        );
        await t.pump();
        expect(t.screen, shows('The agent exited'));
        await t.press('ctrl+c');
        expect(t.exitRequested, isFalse);
        await t.press('ctrl+c');
        expect(t.exitRequested, isTrue);
      });
      testWidgets(
        'Esc interrupts slow output and keeps the partial reply at $size',
        (t) async {
          final connection = await connected(t, size);
          await t.type('slow');
          await t.press('enter');
          await until(
            () => connection.app.value.transcript.entries.any(
              (e) => e is model.AssistantEntry,
            ),
          );
          await t.press('esc');
          await until(
            () => connection.app.value.transcript.entries.any(
              (e) => e is model.CancelledEntry,
            ),
          );
          await t.pump();
          expect(t.screen, shows('Interrupted by user'));
          expect(
            connection.app.value.transcript.entries
                .whereType<model.AssistantEntry>(),
            isNotEmpty,
          );
        },
      );
      testWidgets(
        'long streamed reply holds the view and marks news then Enter follows at $size',
        (t) async {
          final connection = await connected(
            t,
            size,
            flags: ['--step-ms', '5'],
          );
          await t.type('long');
          await t.press('enter');
          await until(
            () => connection.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .any((e) => e.text.text.contains('Line 80')),
          );
          await t.pump();
          await t.press('pageup');
          final top = t.screen.lines[1];
          await until(
            () => connection.app.value.transcript.entries
                .whereType<model.AssistantEntry>()
                .any((e) => e.text.text.contains('Line 150')),
          );
          await t.pump();
          expect(t.screen.lines[1], top);
          expect(t.screen, shows('new output'));
          await t.press('end');
          expect(t.screen, isNot(shows('lines below')));
          await until(() => connection.app.value.transcript.turn is model.Idle);
          await t.press('home');
          await t.type('text');
          await t.press('enter');
          await until(
            () =>
                connection.app.value.transcript.entries
                    .whereType<model.UserEntry>()
                    .length ==
                2,
          );
          await t.pump();
          expect(t.screen, isNot(shows('lines below')));
        },
      );
    }
  });
}

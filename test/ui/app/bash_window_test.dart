@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';
import 'package:chord/acp/connection.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/shell.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../fixtures/fake_harness.dart';
import 'window_fake_test.dart' as fixture;

class _Process extends ShellProcess {
  _Process(this.options, this.autoStop);
  final ShellOptions options;
  final bool autoStop;
  final done = Completer<ShellEnd>();
  var stops = 0;
  @override
  Future<ShellEnd> get ended => done.future;
  @override
  void stop() {
    stops++;
    if (autoStop && !done.isCompleted) {
      done.complete(const ShellEnd(stopped: true));
    }
  }

  void finish([ShellEnd end = const ShellEnd(code: 0)]) {
    if (!done.isCompleted) done.complete(end);
  }
}

class _Runs {
  final commands = <String>[], processes = <_Process>[];
  var autoStop = true;
  ShellProcess run(String command, ShellOptions options) {
    commands.add(command);
    final process = _Process(options, autoStop);
    processes.add(process);
    return process;
  }
}

Future<({StartConnection connection, TrafficRecorder traffic, Owned owner})>
_window(
  WidgetTester t,
  Size size,
  _Runs runs, {
  List<String> flags = const [],
}) async {
  final dir = await Directory.systemTemp.createTemp('chord-bash-window-');
  final traffic = TrafficRecorder(), owner = Owned(), pids = <int>[];
  final open = fakeSessionOpener(pids.add);
  final c = StartConnection(
    command: fakeAgentCommand(null, flags),
    cwd: dir.path,
    agent: 'fake',
    owner: owner,
    open:
        ({
          required command,
          env,
          required cwd,
          required onTraffic,
          required onPermission,
          relay,
          cancellationToken,
        }) => open(
          command: command,
          env: env,
          cwd: cwd,
          onTraffic: (event) {
            traffic.add(event);
            onTraffic(event);
          },
          onPermission: onPermission,
          relay: relay,
          cancellationToken: cancellationToken,
        ),
  )..start();
  addTearDown(() async {
    for (final p in runs.processes) {
      p.finish(const ShellEnd(stopped: true));
    }
    await c.close();
    await Future.wait(owner.closeOwned());
    expect(
      pids.where(
        (pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0,
      ),
      isEmpty,
    );
    await dir.delete(recursive: true);
  });
  await fixture.until(() => c.app.value.start.phase == StartPhase.connected);
  await t.pumpWidget(
    TranscriptWindow(launch: fixture.launch, connection: c, runShell: runs.run),
    size: size,
  );
  return (connection: c, traffic: traffic, owner: owner);
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'typed bang same batch history overlap CtrlC and empty Backspace $size',
      (t) async {
        final runs = _Runs();
        final w = await _window(t, size, runs), c = w.connection;
        await t.type('!printf ready');
        expect(c.app.value.bash, isTrue);
        expect(c.app.value.draft, 'printf ready');
        expect(t.screen, shows('! for bash mode'));
        expect(
          c.app.value.transcript.entries.whereType<model.UserEntry>(),
          isEmpty,
        );
        await t.press('enter');
        expect(runs.commands, ['printf ready']);
        expect(c.app.value.bash, isFalse);
        expect(c.app.value.draft, '');
        expect(runs.processes.single.options.cwd, c.cwd);
        await t.press('up');
        expect(c.app.value.bash, isTrue);
        expect(c.app.value.draft, 'printf ready');
        await t.press('enter');
        expect(runs.commands.length, 1);
        expect(c.app.value.draft, 'printf ready');
        await t.press('ctrl+c');
        expect(c.app.value.bash, isTrue);
        expect(c.app.value.draft, '');
        await t.press('ctrl+x');
        await t.press('backspace');
        expect(c.app.value.bash, isTrue);
        await t.press('backspace');
        expect(c.app.value.bash, isFalse);
        await t.type('draft!');
        expect(c.app.value.bash, isFalse);
        expect(c.app.value.draft, 'draft!');
      },
      skip: fakeAgentSkip,
    );

    testWidgets(
      'paste multiline executes raw script and held context reaches fake once $size',
      (t) async {
        final runs = _Runs();
        final w = await _window(t, size, runs), c = w.connection;
        await t.paste('!echo one\necho two');
        expect(c.app.value.bash, isTrue);
        expect(c.app.value.draft, 'echo one\necho two');
        await t.press('enter');
        expect(runs.commands.single, 'echo one\necho two');
        runs.processes.single.options.onOutput!(
          ShellStream.stdout,
          '\u009b31mready\u009b0m\n',
        );
        runs.processes.single.finish();
        await fixture.until(() => c.app.value.held.isNotEmpty);
        await t.pump();
        await fixture.sent(t, c, 'text');
        final first = w.traffic.heard
            .whereType<ChordTraffic>()
            .map((e) => e.message)
            .where((m) => m['method'] == 'session/prompt')
            .last;
        final prompt =
            ((first['params'] as Map)['prompt'] as List).first as Map;
        expect(
          prompt['text'],
          '<bash-input>echo one\necho two</bash-input>\n<bash-stdout>ready</bash-stdout><bash-stderr></bash-stderr>\n\ntext',
        );
        expect(c.app.value.held, isEmpty);
        expect(
          c.app.value.transcript.entries
              .whereType<model.UserEntry>()
              .single
              .text,
          'text',
        );
        await fixture.sent(t, c, 'text');
        final second = w.traffic.heard
            .whereType<ChordTraffic>()
            .map((e) => e.message)
            .where((m) => m['method'] == 'session/prompt')
            .last;
        expect(((second['params'] as Map)['prompt'] as List).first, {
          'type': 'text',
          'text': 'text',
        });
      },
      skip: fakeAgentSkip,
    );

    testWidgets(
      'Escape stops nearer shell before agent turn, then restores queued context $size',
      (t) async {
        final runs = _Runs();
        final w = await _window(t, size, runs, flags: ['--step-ms', '50']),
            c = w.connection;
        await t.type('slow');
        await t.press('enter');
        await fixture.until(() => c.app.value.transcript.turn is! model.Idle);
        await t.type('!hold');
        await t.press('enter');
        await t.press('esc');
        expect(runs.processes.single.stops, greaterThanOrEqualTo(1));
        expect(c.app.value.transcript.turn, isNot(isA<model.Cancelling>()));
        await fixture.until(() => c.app.value.held.isNotEmpty);
        final held = List<String>.of(c.app.value.held);
        await t.type('queued');
        await t.press('enter');
        expect(c.app.value.queue.single.text, 'queued');
        expect(c.app.value.held, isEmpty);
        await t.press('esc');
        expect(c.app.value.queue, isEmpty);
        expect(c.app.value.draft, 'queued');
        expect(c.app.value.held, held);
        await fixture.until(() => c.app.value.transcript.turn is model.Idle);
      },
      skip: fakeAgentSkip,
    );

    testWidgets(
      'clear retires old local output and completion stays suppressed in bash $size',
      (t) async {
        final runs = _Runs()..autoStop = false;
        final w = await _window(t, size, runs), c = w.connection;
        await t.type('!/mo');
        expect(c.app.value.bash, isTrue);
        expect(t.screen.text, isNot(contains('Pick a model')));
        await t.press('enter');
        final old = runs.processes.single;
        await c.conversation.clear();
        await fixture.until(
          () => c.app.value.start.phase == StartPhase.connected,
        );
        expect(old.stops, greaterThanOrEqualTo(1));
        old.options.onOutput!(ShellStream.stdout, 'late');
        old.finish();
        await t.pump();
        expect(c.app.value.transcript.entries, isEmpty);
        expect(c.app.value.held, isEmpty);
        expect(c.app.value.bash, isFalse);
      },
      skip: fakeAgentSkip,
    );

    testWidgets(
      'shell close remains owned after unmount until injected cleanup completes $size',
      (t) async {
        final runs = _Runs()..autoStop = false;
        final w = await _window(t, size, runs);
        await t.type('!sleep');
        await t.press('enter');
        final process = runs.processes.single;
        await t.pumpWidget(const SizedBox(), size: size);
        expect(process.stops, greaterThanOrEqualTo(1));
        var closed = false;
        final closing = Future.wait(
          w.owner.closeOwned(),
        ).then((_) => closed = true);
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse);
        process.finish(const ShellEnd(stopped: true));
        await closing;
        expect(closed, isTrue);
      },
      skip: fakeAgentSkip,
    );
  }
}

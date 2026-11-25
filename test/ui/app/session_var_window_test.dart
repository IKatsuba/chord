// The window tells its terminal which session `--resume` would open, in
// the `chord_session` user variable, as the original's useSessionVar
// (src/ui/app/terminal.ts 67-120, App.tsx 1115-1131): empty at start and
// after /clear, the id once its first prompt is recorded, a resumed one's
// once it is open, an equal value never again.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/cli.dart';
import 'package:chord/notify.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart' show Resume, SessionRecord;
import 'package:chord/session/transcript/types.dart' show MessageFrom;
import 'package:chord/session/conversation.dart' show ConversationEvent;
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/crash_screen.dart';
import 'package:chord/ui/app/renderer.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake.dart';
import 'selection_window_test.dart' show RecordingTerminal;
import 'window_fake_test.dart' show until;

const _launch = Launch(
  name: 'memory',
  agent: null,
  agentCommand: 'memory',
  version: '0.0.1',
  directory: '/w',
);

/// An in-memory agent, a process of its own for each open, as /clear
/// starts one: it numbers new sessions `s1`, `s2`, … across them, loads
/// any session asked for, and answers each prompt at once.
final class _Agent {
  _Agent() {
    _timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      for (final (process, read) in [..._processes]) {
        final messages = process.stdin.messages;
        for (; read.value < messages.length; read.value++) {
          final message = messages[read.value];
          final id = message['id'];
          final method = message['method'];
          if (id == null || method == null || process.exited) continue;
          process.send({
            'jsonrpc': '2.0',
            'id': id,
            'result': switch (method) {
              'initialize' => {
                'protocolVersion': 1,
                'agentCapabilities': {'loadSession': true},
              },
              'session/new' => {'sessionId': 's${++_opened}'},
              'session/prompt' => {'stopReason': 'end_turn'},
              _ => <String, Object?>{},
            },
          });
        }
      }
    });
  }

  late final Timer _timer;
  final _processes = <(MemoryAgentProcess, _Read)>[];
  var _opened = 0;

  MemoryAgentProcess _start() {
    late final MemoryAgentProcess process;
    process = MemoryAgentProcess(
      onSignal: (_) {
        if (process.exited) return;
        process.exit(const Exit(143, 'SIGTERM'));
        process.closeStdout();
        process.closeStderr();
      },
    );
    _processes.add((process, _Read()));
    return process;
  }

  StartConnection connect({Resume? resume, Recording? recording}) =>
      StartConnection(
        command: 'memory',
        cwd: '/w',
        agent: 'memory',
        owner: Owned(),
        resume: resume,
        recording: recording,
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
              _start(),
              onTraffic: onTraffic,
              onPermission: onPermission,
              relay: relay,
              cancellationToken: cancellationToken,
            ),
      )..start();

  void stop() => _timer.cancel();
}

/// A record whose writes settle only when the test says.
final class _HeldRecording implements Recording {
  final held = Completer<void>();
  @override
  void opened(RecordingSession session) {}
  @override
  void sent(
    String turnId,
    String prompt,
    num images,
    List<Map<String, Object?>> links,
    num at, {
    List<Map<String, Object?>> resources = const [],
    String? into,
    MessageFrom? from,
  }) {}
  @override
  void heard(ConversationEvent event) {}
  @override
  Future<void> flushed() => held.future;
}

/// How far a process's requests have been answered.
final class _Read {
  var value = 0;
}

Future<(StartConnection, RecordingTerminal)> _open(
  WidgetTester t,
  Size size, {
  Resume? resume,
  Recording? recording,
  Notifications? notifications,
}) async {
  final agent = _Agent();
  final connection = agent.connect(resume: resume, recording: recording);
  final terminal = RecordingTerminal();
  addTearDown(() async {
    agent.stop();
    await connection.close();
  });
  await t.pumpWidget(
    TranscriptWindow(
      launch: _launch,
      connection: connection,
      terminal: terminal,
      notifications: notifications,
    ),
    size: size,
  );
  await until(() => connection.app.value.start.phase == StartPhase.connected);
  await t.pump();
  return (connection, terminal);
}

Future<void> _send(WidgetTester t, String text) async {
  await t.type(text);
  await t.press('enter');
  await t.pump();
}

void main() {
  group('tester CTUI-159: window written bytes', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final tmux in [false, true]) {
        testWidgets('first record, dedupe and clear at $size tmux=$tmux', (
          t,
        ) async {
          final held = _HeldRecording();
          final (c, terminal) = await _openBytes(
            t,
            size,
            tmux: tmux,
            recording: held,
          );
          expect(await terminal.bytes(), _expected('', tmux));
          await _send(t, 'hello');
          await until(() => c.conversation.resumable != null);
          expect(await terminal.bytes(), _expected('', tmux));
          held.held.complete();
          await until(() => terminal.variableWrites == 2);
          expect(
            await terminal.bytes(),
            _expected('', tmux) + _expected('s1', tmux),
          );
          await _send(t, 'again');
          await t.resize(
            size == const Size(120, 40)
                ? const Size(80, 24)
                : const Size(120, 40),
          );
          expect(terminal.variableWrites, 2);
          await _send(t, '/clear');
          await until(() => c.app.value.start.sessionId == 's2');
          expect(
            await terminal.bytes(),
            _expected('', tmux) + _expected('s1', tmux) + _expected('', tmux),
          );
          await _send(t, 'next');
          await until(() => terminal.variableWrites == 4);
          expect(
            await terminal.bytes(),
            _expected('', tmux) +
                _expected('s1', tmux) +
                _expected('', tmux) +
                _expected('s2', tmux),
          );
        });
      }
    }

    for (final tmux in [false, true]) {
      for (final option in ['--resume=saved', '--continue']) {
        testWidgets('$option resolves to the opened id tmux=$tmux', (t) async {
          final record = await _savedBytesRecord('saved', agent: 'claude');
          final outcome = await runCli(
            ['claude', '--agent-command', 'memory', option],
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            cwd: '/w',
            home: null,
            lookup: (_) async => 'memory',
            readSessionRecords: () async => [record],
            stateDirectory: () => Directory.systemTemp.path,
          );
          expect(outcome.code, 0);
          expect(outcome.launch!.resume!.sessionId, 'saved');
          final (_, terminal) = await _openBytes(
            t,
            const Size(80, 24),
            tmux: tmux,
            resume: outcome.launch!.resume,
          );
          await until(() => terminal.variableWrites > 0);
          expect(
            await terminal.bytes(),
            _expected('', tmux) + _expected('saved', tmux),
          );
        });
      }

      testWidgets('/resume pick overtakes a pending record tmux=$tmux', (
        t,
      ) async {
        final saved = await _savedBytesRecord('picked');
        final held = _HeldRecording();
        final (c, terminal) = await _openBytes(
          t,
          const Size(80, 24),
          tmux: tmux,
          recording: held,
          records: [saved],
        );
        await _send(t, 'hello');
        await until(() => c.conversation.resumable != null);
        await _send(t, '/resume');
        await t.press('enter');
        await until(() => c.app.value.start.sessionId == 'picked');
        await until(() => terminal.variableWrites == 2);
        held.held.complete();
        await t.pump();
        await t.pump();
        expect(
          await terminal.bytes(),
          _expected('', tmux) + _expected('picked', tmux),
        );
      });

      testWidgets(
        'lending defers bytes and resumed main overtakes old id tmux=$tmux',
        (t) async {
          final held = _HeldRecording();
          final (c, terminal) = await _openBytes(
            t,
            const Size(80, 24),
            tmux: tmux,
            recording: held,
          );
          await _send(t, 'hello');
          await until(() => c.conversation.resumable != null);
          terminal.events.add(TerminalState.suspended);
          await t.pump();
          held.held.complete();
          await t.pump();
          await t.pump();
          expect(await terminal.bytes(), _expected('', tmux));
          await c.conversation.resume(
            const Resume(sessionId: 'newer', cwd: '/w'),
          );
          await t.pump();
          expect(await terminal.bytes(), _expected('', tmux));
          terminal.events.add(TerminalState.active);
          await t.pump();
          expect(
            await terminal.bytes(),
            _expected('', tmux) + _expected('newer', tmux),
          );
        },
      );
    }

    for (final tmux in [false, true]) {
      testWidgets('clear overtakes the pending first id tmux=$tmux', (t) async {
        final held = _HeldRecording();
        final (c, terminal) = await _openBytes(
          t,
          const Size(80, 24),
          tmux: tmux,
          recording: held,
        );
        await _send(t, 'hello');
        await until(() => c.conversation.resumable != null);
        await _send(t, '/clear');
        await until(() => c.app.value.start.sessionId == 's2');
        held.held.complete();
        await t.pump();
        await t.pump();
        expect(await terminal.bytes(), _expected('', tmux));
        await _send(t, 'new prompt');
        await until(() => terminal.variableWrites == 2);
        expect(
          await terminal.bytes(),
          _expected('', tmux) + _expected('s2', tmux),
        );
      });
    }

    for (final exit in ['quit', 'dispose']) {
      testWidgets('$exit retires pending bytes and writes no trailing clear', (
        t,
      ) async {
        final held = _HeldRecording();
        final (c, terminal) = await _openBytes(
          t,
          const Size(80, 24),
          recording: held,
        );
        await _send(t, 'hello');
        await until(() => c.conversation.resumable != null);
        if (exit == 'quit') {
          await t.press('ctrl+d');
          expect(t.exitRequested, isTrue);
        } else {
          await t.pumpWidget(const SizedBox(), size: const Size(80, 24));
        }
        held.held.complete();
        await t.pump();
        await t.pump();
        expect(await terminal.bytes(), _expected('', false));
      });
    }

    group('cached process teardown', () {
      late List<String> teardownFixture;
      // The runner assigns setUpAll its fixed 12-minute scaffold timeout;
      // compilation stays outside each case's runtime bound.
      setUpAll(() {
        teardownFixture = fixtureCommand(
          'test/fixtures/session_var_teardown.dart',
        );
      });
      for (final mode in ['sighup', 'sigint', 'sigterm', 'crash']) {
        for (final settled in [false, true]) {
          test(
            '$mode teardown emits no late or trailing bytes settled=$settled',
            () async {
              final dir = Directory.systemTemp.createTempSync(
                'session-var-teardown-',
              );
              final output = File('${dir.path}/bytes');
              final process = await Process.start(
                teardownFixture.first,
                [...teardownFixture.skip(1), mode, '$settled', output.path],
                environment: {
                  'HOME': dir.path,
                  'XDG_CONFIG_HOME': dir.path,
                  'XDG_STATE_HOME': dir.path,
                },
              );
              final out = process.stdout.transform(utf8.decoder).join();
              final err = process.stderr.transform(utf8.decoder).join();
              int code;
              try {
                code = await process.exitCode.timeout(
                  const Duration(seconds: 20),
                );
              } on TimeoutException {
                process.kill(ProcessSignal.sigkill);
                await process.exitCode;
                rethrow;
              }
              final stderr = await err;
              await out;
              if (mode == 'crash') {
                expect(code, 1, reason: stderr);
                expect(
                  stderr,
                  contains('injected session variable drawing failure'),
                );
              } else {
                final signal = {
                  'sighup': ProcessSignal.sighup,
                  'sigint': ProcessSignal.sigint,
                  'sigterm': ProcessSignal.sigterm,
                }[mode]!;
                expect(
                  code,
                  anyOf(-signal.signalNumber, 128 + signal.signalNumber),
                  reason: stderr,
                );
              }
              expect(
                File('${output.path}.done').existsSync(),
                isTrue,
                reason: stderr,
              );
              expect(
                output.readAsStringSync(),
                _expected('', false) + (settled ? _expected('s1', false) : ''),
              );
              expect(
                Process.runSync('kill', ['-0', '${process.pid}']).exitCode,
                isNot(0),
              );
              dir.deleteSync(recursive: true);
            },
            timeout: const Timeout(Duration(seconds: 30)),
          );
        }
      }
    });
  });
  group('CTUI-159: the window tells chord_session', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('empty at start, the id once a prompt is recorded, never '
          'twice, empty after /clear, at $size', (t) async {
        final (connection, terminal) = await _open(t, size);
        expect(terminal.userVariables, [(sessionVarName, '')]);
        await _send(t, 'hello');
        await until(() => terminal.userVariables.length == 2);
        expect(terminal.userVariables.last, (sessionVarName, 's1'));
        await _send(t, 'again');
        await until(
          () =>
              connection.conversation.resumable != null &&
              connection.app.value.transcript.entries.length >= 2,
        );
        await t.press('x');
        await t.press('backspace');
        expect(terminal.userVariables, hasLength(2));
        await _send(t, '/clear');
        await until(() => terminal.userVariables.length == 3);
        expect(terminal.userVariables.last, (sessionVarName, ''));
        await until(() => connection.app.value.start.sessionId == 's2');
        await _send(t, 'next');
        await until(() => terminal.userVariables.length == 4);
        expect(terminal.userVariables, [
          (sessionVarName, ''),
          (sessionVarName, 's1'),
          (sessionVarName, ''),
          (sessionVarName, 's2'),
        ]);
      });

      testWidgets('a resumed session once it is open, with no prompt, at '
          '$size', (t) async {
        final (_, terminal) = await _open(
          t,
          size,
          resume: const Resume(sessionId: 'old-1', cwd: '/w'),
        );
        await until(() => terminal.userVariables.isNotEmpty);
        await t.pump();
        expect(terminal.userVariables.last, (sessionVarName, 'old-1'));
        expect(
          terminal.userVariables.where((each) => each.$2 == 'old-1'),
          hasLength(1),
        );
      });
    }

    testWidgets('a session picked to resume once it is open, after the one '
        'before', (t) async {
      final (connection, terminal) = await _open(t, const Size(80, 24));
      await _send(t, 'hello');
      await until(() => terminal.userVariables.length == 2);
      await connection.conversation.resume(
        const Resume(sessionId: 'old-2', cwd: '/w'),
      );
      await until(() => terminal.userVariables.length == 4);
      expect(terminal.userVariables, [
        (sessionVarName, ''),
        (sessionVarName, 's1'),
        (sessionVarName, ''),
        (sessionVarName, 'old-2'),
      ]);
    });

    testWidgets('recorded settles at the first prompt, afresh after /clear, '
        'at once for a resumed session', (t) async {
      final (connection, _) = await _open(t, const Size(80, 24));
      var settled = false;
      connection.conversation.recorded().then((_) => settled = true);
      await t.pump();
      expect(settled, isFalse);
      await _send(t, 'hello');
      await until(() => settled);
      await connection.conversation.clear();
      var again = false;
      connection.conversation.recorded().then((_) => again = true);
      await until(() => connection.app.value.start.sessionId == 's2');
      await t.pump();
      expect(again, isFalse);
      await connection.conversation.resume(
        const Resume(sessionId: 'old-3', cwd: '/w'),
      );
      var resumed = false;
      connection.conversation.recorded().then((_) => resumed = true);
      await until(() => resumed);
      expect(again, isFalse);
    });

    testWidgets('a record settled while the terminal is lent is told when it '
        'comes back', (t) async {
      final recording = _HeldRecording();
      final (_, terminal) = await _open(
        t,
        const Size(80, 24),
        recording: recording,
      );
      await _send(t, 'hello');
      terminal.events.add(TerminalState.suspended);
      await t.pump();
      recording.held.complete();
      await t.pump();
      await t.pump();
      expect(terminal.userVariables, [(sessionVarName, '')]);
      terminal.events.add(TerminalState.active);
      await t.pump();
      expect(terminal.userVariables, [
        (sessionVarName, ''),
        (sessionVarName, 's1'),
      ]);
    });

    testWidgets('a session cleared while the terminal is lent is not told of '
        'the one before it', (t) async {
      final recording = _HeldRecording();
      final (connection, terminal) = await _open(
        t,
        const Size(80, 24),
        recording: recording,
      );
      await _send(t, 'hello');
      await until(() => connection.conversation.resumable != null);
      terminal.events.add(TerminalState.suspended);
      await t.pump();
      await connection.conversation.clear();
      await until(() => connection.app.value.start.sessionId == 's2');
      await t.pump();
      recording.held.complete();
      await t.pump();
      await t.pump();
      terminal.events.add(TerminalState.active);
      await t.pump();
      expect(terminal.userVariables, [(sessionVarName, '')]);
    });

    testWidgets('a session resumed while the terminal is lent is told when it '
        'comes back', (t) async {
      final (connection, terminal) = await _open(t, const Size(80, 24));
      await _send(t, 'hello');
      await until(() => terminal.userVariables.length == 2);
      terminal.events.add(TerminalState.suspended);
      await t.pump();
      await connection.conversation.resume(
        const Resume(sessionId: 'old-4', cwd: '/w'),
      );
      await t.pump();
      expect(terminal.userVariables, hasLength(2));
      terminal.events.add(TerminalState.active);
      await t.pump();
      expect(terminal.userVariables, [
        (sessionVarName, ''),
        (sessionVarName, 's1'),
        (sessionVarName, 'old-4'),
      ]);
    });

    testWidgets('a record settled after quit writes nothing', (t) async {
      final recording = _HeldRecording();
      final (_, terminal) = await _open(
        t,
        const Size(80, 24),
        recording: recording,
      );
      await _send(t, 'hello');
      await t.press('ctrl+d');
      expect(t.exitRequested, isTrue);
      recording.held.complete();
      await t.pump();
      await t.pump();
      expect(terminal.userVariables, [(sessionVarName, '')]);
    });

    testWidgets('a record settled after the window is gone writes nothing', (
      t,
    ) async {
      final recording = _HeldRecording();
      final (_, terminal) = await _open(
        t,
        const Size(80, 24),
        recording: recording,
      );
      await _send(t, 'hello');
      await t.pumpWidget(const SizedBox(), size: const Size(80, 24));
      recording.held.complete();
      await Future<void>.delayed(Duration.zero);
      expect(terminal.userVariables, [(sessionVarName, '')]);
    });

    testWidgets('the same with notifications off', (t) async {
      final (_, terminal) = await _open(
        t,
        const Size(80, 24),
        notifications: const Notifications(
          channel: NotifChannel.off,
          env: TerminalEnv(),
        ),
      );
      expect(terminal.userVariables, [(sessionVarName, '')]);
      await _send(t, 'hello');
      await until(() => terminal.userVariables.length == 2);
      expect(terminal.userVariables.last, (sessionVarName, 's1'));
    });
  });
}

String _expected(String value, bool tmux) {
  final plain =
      '\x1b]1337;SetUserVar=chord_session=${base64.encode(utf8.encode(value))}\x07';
  return tmux
      ? '\x1bPtmux;${plain.replaceAll('\x1b', '\x1b\x1b')}\x1b\\'
      : plain;
}

class _ByteTerminal extends RecordingTerminal {
  _ByteTerminal(this.file, {bool tmux = false}) {
    sink = file.openWrite();
    output = StdioTerminal(
      input: const Stream.empty(),
      output: sink,
      environment: const {},
      tmuxPassthrough: tmux,
    );
  }
  final File file;
  late final IOSink sink;
  late final StdioTerminal output;
  var variableWrites = 0;
  @override
  void setUserVariable(String name, String value) {
    variableWrites++;
    output.setUserVariable(name, value);
  }

  Future<String> bytes() async {
    await sink.flush();
    return file.readAsStringSync();
  }

  Future<void> finish() async {
    await output.close();
    await sink.close();
    await events.close();
  }
}

Future<(StartConnection, _ByteTerminal)> _openBytes(
  WidgetTester t,
  Size size, {
  bool tmux = false,
  Resume? resume,
  Recording? recording,
  List<SessionRecord> records = const [],
}) async {
  final dir = Directory.systemTemp.createTempSync('session-var-bytes-');
  final agent = _Agent();
  final c = agent.connect(resume: resume, recording: recording);
  final terminal = _ByteTerminal(File('${dir.path}/bytes'), tmux: tmux);
  addTearDown(() async {
    agent.stop();
    await c.close();
    await terminal.finish();
    dir.deleteSync(recursive: true);
  });
  await t.pumpWidget(
    TranscriptWindow(
      launch: _launch,
      connection: c,
      terminal: terminal,
      notifications: const Notifications(
        channel: NotifChannel.off,
        env: TerminalEnv(),
      ),
      readSessionRecords: ({cancellationToken}) async => records,
    ),
    size: size,
  );
  await until(() => c.app.value.start.phase == StartPhase.connected);
  await t.pump();
  return (c, terminal);
}

Future<SessionRecord> _savedBytesRecord(
  String id, {
  String agent = 'memory',
}) async {
  final dir = Directory.systemTemp.createTempSync('session-var-saved-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/saved.jsonl');
  file.writeAsStringSync(
    [
      {
        'type': 'session',
        'version': 1,
        'sessionId': id,
        'agent': agent,
        'cwd': '/w',
        'at': 1,
      },
      {
        'type': 'prompt',
        'turnId': 'past',
        'prompt': 'saved',
        'images': 0,
        'at': 1,
      },
      {
        'type': 'result',
        'turnId': 'past',
        'result': {'status': 'completed', 'stopReason': 'end_turn'},
      },
    ].map(encodeRecord).join(),
  );
  return SessionRecord(
    path: file.path,
    sessionId: id,
    agent: agent,
    cwd: '/w',
    lastUsedAt: 1,
    prompt: 'saved',
  );
}

class _RunByteTerminal extends _ByteTerminal {
  _RunByteTerminal(super.file);
  final source = StreamController<String>();
  @override
  Stream<String> get input => source.stream;
  @override
  void write(String data) {
    if (data == '\x1b]11;?\x07') source.add('\x1b]11;rgb:0000/0000/0000\x07');
    if (data.contains('any key to quit')) source.add('x');
  }
}

/// Runs the literal signal/crash teardown against a fake terminal, no tty.
Future<void> runSessionVarTeardownFixture(List<String> args) async {
  final mode = args[0], settled = args[1] == 'true';
  final terminal = _RunByteTerminal(File(args[2]));
  final held = _HeldRecording(), agent = _Agent();
  final c = agent.connect(recording: held);
  final explode = ValueNotifier(false);
  final failure = WindowCrash();
  Future<void> trigger() async {
    await until(() => c.app.value.start.phase == StartPhase.connected);
    // Wait for runApp to own the window before typing into its fake input.
    await until(() => terminal.variableWrites == 1);
    terminal.source.add('hello\r');
    await until(() => c.conversation.resumable != null);
    if (settled) {
      held.held.complete();
      await until(() => terminal.variableWrites == 2);
    }
    if (mode != 'crash') {
      final signal = {
        'sighup': ProcessSignal.sighup,
        'sigint': ProcessSignal.sigint,
        'sigterm': ProcessSignal.sigterm,
      }[mode]!;
      Process.killPid(pid, signal);
    } else {
      explode.value = true;
    }
  }

  unawaited(trigger());
  await runApp(
    CrashBoundary(
      onCrash: failure.caught,
      child: ListenableBuilder(
        listenable: explode,
        builder: (_) {
          if (explode.value) {
            throw StateError('injected session variable drawing failure');
          }
          return TranscriptWindow(
            launch: _launch,
            connection: c,
            terminal: terminal,
          );
        },
      ),
    ),
    terminal: terminal,
    exitProcess: true,
    beforeExit: () async {
      if (!held.held.isCompleted) held.held.complete();
      await Future<void>.delayed(Duration.zero);
      await terminal.sink.flush();
      agent.stop();
      await c.close();
      await terminal.finish();
      await terminal.source.close();
      File('${args[2]}.done').writeAsStringSync('closed');
      failure.rethrowIfCaught();
    },
  );
}

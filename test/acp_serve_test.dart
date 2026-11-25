// `chord acp` on a process's streams, in memory: the by-hand note for a
// terminal alone, each signal's way out, a crash of chord, and EOF.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/rpc.dart' show ElicitationHandler;
import 'package:chord/acp/schema.dart' show ClientCapabilities;
import 'package:chord/acp_agent.dart';
import 'package:chord/mcp.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/settings.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart' show Lines;

const _start = AcpStart(
  agent: 'codex',
  flags: Flags(),
  launched: LoadedSettings(Settings(), [], []),
  noMcpServers: false,
  cwd: '/w',
  configHome: null,
  home: null,
);

/// `chord acp` served in memory, its streams and signals the test's.
final class _Served {
  _Served({bool terminal = false, AgentLauncher launch = _never}) {
    for (final signal in [
      ProcessSignal.sigterm,
      ProcessSignal.sigint,
      ProcessSignal.sighup,
    ]) {
      signals[signal] = StreamController<ProcessSignal>.broadcast();
    }
    host = serveAcp(
      _start,
      input: input.stream,
      sink: lines,
      stderr: said.add,
      exit: exits.add,
      stdinIsTerminal: terminal,
      watch: (signal) => signals[signal]!.stream,
      launch: launch,
      stateDir: '/state',
      // No real file is read under fake time.
      readMcp: ({required layers, required cwd}) async =>
          const ReadServers([], [], []),
    );
  }

  late final AcpHost host;
  final input = StreamController<List<int>>();
  final lines = Lines();
  final said = <String>[];
  final exits = <LeaveExit>[];
  final signals = <ProcessSignal, StreamController<ProcessSignal>>{};

  void send(Map<String, Object?> message) =>
      input.add(utf8.encode('${jsonEncode(message)}\n'));

  bool get watched => signals.values.any((c) => c.hasListener);
}

Future<Agent> _never({
  required Object command,
  Map<String, String>? env,
  required String cwd,
  required void Function(Traffic traffic) onTraffic,
  required PermissionHandler onPermission,
  ClientCapabilities? capabilities,
  ElicitationHandler? onElicitation,
  Relay? relay,
  CancellationToken? cancellationToken,
}) => Completer<Agent>().future;

void main() {
  test('the by-hand note goes to stderr only when stdin is a terminal, and '
      'before anything else', () {
    fakeAsync((async) {
      final note = _Served(terminal: true);
      expect(note.said, [
        'chord: acp serves ACP on stdin and stdout, for a client that '
            'starts it.',
        Platform.isLinux
            ? 'chord: nothing to press here. Ctrl-C leaves; `chord` opens a '
                  'window.'
            : 'chord: nothing to press here. Ctrl-D or Ctrl-C leaves; `chord` '
                  'opens a window.',
      ]);
      for (final line in note.said) {
        expect(line.length, lessThanOrEqualTo(80));
        expect(line, isNot(contains('\u001b')));
      }
      expect(note.lines.messages, isEmpty);
      final none = _Served();
      expect(none.said, isEmpty);
      for (final served in [note, none]) {
        served.input.close();
      }
      async.elapse(const Duration(seconds: 20));
    });
  });

  for (final signal in [
    ProcessSignal.sigterm,
    ProcessSignal.sigint,
    ProcessSignal.sighup,
  ]) {
    test('$signal starts the way out, which dies by it, its handlers off '
        'first', () {
      fakeAsync((async) {
        final served = _Served();
        expect(served.watched, isTrue);
        served.signals[signal]!.add(signal);
        async.elapse(const Duration(seconds: 20));
        expect(served.exits, [LeaveExit.signal(signal)]);
        // Raised again, it is not heard again.
        expect(served.watched, isFalse);
      });
    });
  }

  test('a crash of chord says its error and stack and exits 1', () {
    fakeAsync((async) {
      final served = _Served(
        launch:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              capabilities,
              onElicitation,
              relay,
              cancellationToken,
            }) {
              // Nothing awaits this: it is chord's own bug.
              scheduleMicrotask(() => throw StateError('a bug of chord'));
              return Completer<Agent>().future;
            },
      );
      served.send({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': 1},
      });
      served.send({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'session/new',
        'params': {'cwd': '/w', 'mcpServers': <Object?>[]},
      });
      async.elapse(const Duration(seconds: 20));
      expect(served.said.first, 'Bad state: a bug of chord');
      expect(served.said[1], contains('acp_serve_test.dart'));
      expect(served.exits, [const LeaveExit.code(1)]);
      // The client heard its open refused before the connection closed.
      expect(served.lines.messages.where((m) => m['id'] == 2).single['error'], {
        'code': -32603,
        'message': 'chord is closing',
      });
    });
  });

  test('EOF exits 0', () {
    fakeAsync((async) {
      final served = _Served();
      served.input.close();
      async.elapse(const Duration(seconds: 20));
      expect(served.exits, [const LeaveExit.code(0)]);
      expect(served.lines.closed, isTrue);
    });
  });

  group('the process\'s end', () {
    test('a code waits for stderr\'s flush no longer than the drain bound', () {
      fakeAsync((async) {
        final exits = <int>[];
        exitAcp(
          const LeaveExit.code(1),
          flush: () => Completer<void>().future,
          exit: exits.add,
          raise: (_) => fail('raised'),
        );
        async.elapse(const Duration(milliseconds: 499));
        expect(exits, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(exits, [1]);
      });
    });

    test('a flush done, or failed, exits at once', () {
      fakeAsync((async) {
        final exits = <int>[];
        exitAcp(
          const LeaveExit.code(0),
          flush: () async {},
          exit: exits.add,
          raise: (_) => fail('raised'),
        );
        exitAcp(
          const LeaveExit.code(1),
          flush: () => Future.error(const StdoutException('gone')),
          exit: exits.add,
          raise: (_) => fail('raised'),
        );
        async.flushMicrotasks();
        expect(exits, [0, 1]);
      });
    });

    test('a signal is raised at once, with no flush', () {
      fakeAsync((async) {
        final raised = <ProcessSignal>[];
        exitAcp(
          const LeaveExit.signal(ProcessSignal.sigterm),
          flush: () => fail('flushed'),
          exit: (_) => fail('exited'),
          raise: raised.add,
        );
        async.flushMicrotasks();
        expect(raised, [ProcessSignal.sigterm]);
      });
    });
  });
}

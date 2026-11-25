// A client of `chord acp` in real time, for tests on the original's fake
// agent: runAcp fed line by line, its answers waited for, its records in a
// state directory of the test's own.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/rpc.dart' show ElicitationHandler;
import 'package:chord/acp/schema.dart' show ClientCapabilities;
import 'package:chord/acp_agent.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/place.dart';
import 'package:test/test.dart';

import 'acp_rig.dart' show Lines;
import 'fixtures/fake_harness.dart';
import 'package:chord/server/server.dart' show ChordServer;

bool alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// `chord acp` serving the fake with [flags], torn down with the test.
final class AcpClient {
  AcpClient({
    List<String> flags = const [],
    String scenario = 'text',
    ChordServer? server,
    bool children = false,
    String? configHome,
    String? home,
  }) {
    stateDir = Directory.systemTemp.createTempSync('chord-acp-state-').path;
    cwd = Directory.systemTemp.createTempSync('chord-acp-cwd-').path;
    host = runAcp(
      input: input.stream,
      sink: lines,
      agent: 'fake',
      version: '9.9.9',
      place: (cwd) async => (
        cwd: cwd,
        start: SessionStart(command: fakeAgentCommand(scenario, flags)),
      ),
      stateDir: stateDir,
      server: server,
      configHome: configHome,
      home: home,
      // Children of the fake alone, started as main is.
      children: children
          ? (_) async => (
              runtimes: const ['fake'],
              startOf: (String name) =>
                  SessionStart(command: fakeAgentCommand(scenario, flags)),
            )
          : null,
      stderr: said.add,
      exit: (how) {
        if (!exited.isCompleted) exited.complete(how);
      },
      launch: _launch,
    );
    addTearDown(() async {
      if (!input.isClosed) await input.close();
      await exited.future.timeout(const Duration(seconds: 30));
      expect(pids.where(alive), isEmpty, reason: 'an agent is still running');
      Directory(stateDir).deleteSync(recursive: true);
      Directory(cwd).deleteSync(recursive: true);
    });
  }

  late final String stateDir;
  late final String cwd;
  late final AcpHost host;
  final input = StreamController<List<int>>();
  final lines = Lines();
  final said = <String>[];
  final exited = Completer<LeaveExit>();
  final pids = <int>[];

  /// What chord sent the agents, in order.
  final sentToAgents = <Map<String, Object?>>[];

  /// What chord sent the agents as [method], in order.
  List<Map<String, Object?>> agentMessages(String method) => [
    for (final message in sentToAgents)
      if (message['method'] == method) message,
  ];
  var _ids = 0;

  Future<Agent> _launch({
    required Object command,
    Map<String, String>? env,
    required String cwd,
    required void Function(Traffic traffic) onTraffic,
    required PermissionHandler onPermission,
    ClientCapabilities? capabilities,
    ElicitationHandler? onElicitation,
    Relay? relay,
    CancellationToken? cancellationToken,
  }) async {
    final agent = await openAgent(
      command: command,
      env: env,
      cwd: cwd,
      onTraffic: (traffic) {
        if (traffic case ChordTraffic(:final message)) {
          sentToAgents.add(message);
        }
        onTraffic(traffic);
      },
      onPermission: onPermission,
      capabilities: capabilities,
      onElicitation: onElicitation,
      relay: relay,
      cancellationToken: cancellationToken,
      stop: fakeStopBounds,
    );
    pids.add(agent.pid);
    return agent;
  }

  /// Sends [message] as the client.
  void send(Map<String, Object?> message) =>
      input.add(utf8.encode('${jsonEncode(message)}\n'));

  /// Sends the request [method]; its id.
  int ask(String method, [Map<String, Object?>? params]) {
    final id = ++_ids;
    send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return id;
  }

  /// The answer to request [id], once written.
  Future<Map<String, Object?>> answer(int id) => until(() {
    for (final message in lines.messages) {
      if (!message.containsKey('method') && message['id'] == id) {
        return message;
      }
    }
    return null;
  });

  /// [method]'s answer.
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?>? params,
  ]) => answer(ask(method, params));

  /// Initializes with [capabilities].
  Future<void> initialize([Map<String, Object?> capabilities = const {}]) =>
      request('initialize', {
        'protocolVersion': 1,
        'clientCapabilities': capabilities,
      });

  /// A new session in [cwd]'s client id.
  Future<String> newSession() async {
    final answered = await request('session/new', {
      'cwd': cwd,
      'mcpServers': <Object?>[],
    });
    return (answered['result'] as Map)['sessionId'] as String;
  }

  /// The first value [found] gives, waited for.
  Future<T> until<T>(T? Function() found) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (true) {
      if (found() case final value?) return value;
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('not seen: ${lines.messages}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// The notifications of [method].
  List<Map<String, Object?>> notified(String method) => [
    for (final message in lines.messages)
      if (message['method'] == method && !message.containsKey('id'))
        message['params'] as Map<String, Object?>,
  ];
}

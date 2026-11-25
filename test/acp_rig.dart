// `chord acp` in memory for its tests: a client writing lines into
// runAcp, every agent a MemoryAgentProcess that answers initialize and
// session/new by itself unless told to hold, under fake time.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart';
import 'package:chord/acp/rpc.dart' show ElicitationHandler;
import 'package:chord/acp/schema.dart' show ClientCapabilities;
import 'package:chord/acp/stdio.dart';
import 'package:chord/acp_agent.dart';
import 'package:chord/session/transcript/types.dart' show MessageFrom;
import 'package:chord/platform/process.dart';
import 'package:chord/platform/resources.dart' show Resources;
import 'package:chord/server/server.dart' show ChordServer;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:fake_async/fake_async.dart';

/// A sink that keeps every line chord writes, its flushes held on demand.
final class Lines implements OutputSink {
  final _bytes = <int>[];
  var closed = false;

  /// While true, flushes wait for [release].
  var hold = false;
  final _held = <Completer<void>>[];

  /// What was written, one message per line.
  List<Map<String, Object?>> get messages => [
    for (final line in const LineSplitter().convert(utf8.decode(_bytes)))
      if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
  ];

  @override
  void add(List<int> bytes) => _bytes.addAll(bytes);

  @override
  Future<void> flush() {
    if (!hold) return Future.value();
    final flush = Completer<void>();
    _held.add(flush);
    return flush.future;
  }

  /// Lets every held flush go.
  void release() {
    hold = false;
    for (final flush in [..._held]) {
      flush.complete();
    }
    _held.clear();
  }

  @override
  Future<void> close() async => closed = true;
}

/// A recording that writes nothing.
final class NoRecording implements Recording {
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
  Future<void> flushed() async {}
}

/// Groups that only count their kills.
final class CountedGroups implements ProcessGroups {
  var kills = 0;

  @override
  List<int> killAll() {
    kills++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A place every directory shares: the agent starts on `memory`.
Future<AcpPlace> anyPlace(String cwd) async =>
    (cwd: cwd, start: const SessionStart(command: 'memory'));

/// `chord acp` with its agents in memory.
final class Rig {
  Rig(
    this.async, {
    PlaceReader? place,
    Future<List<SessionRecord>> Function()? records,
    Future<List<SessionRecord>> Function(String id)? recordsWithId,
    ChordServer? server,
    Resources? resources,
    String agent = 'memory',
  }) {
    host = runAcp(
      input: input.stream,
      sink: lines,
      agent: agent,
      version: '9.9.9',
      place: place ?? anyPlace,
      stateDir: '/state',
      stderr: said.add,
      exit: exits.add,
      launch: _launch,
      records: records ?? () async => const [],
      recordsWithId: recordsWithId,
      recording: (_) => NoRecording(),
      groups: groups,
      server: server,
      resources: resources,
      // Children keep no record either, never one in a real directory.
      childRecording: (_) => NoRecording(),
    );
  }

  final FakeAsync async;
  late final AcpHost host;
  final input = StreamController<List<int>>();
  final lines = Lines();
  final said = <String>[];
  final exits = <LeaveExit>[];
  final groups = CountedGroups();

  /// Every agent started, in order, and what chord declared toward each.
  final agents = <MemoryAgentProcess>[];
  final declared = <ClientCapabilities?>[];

  /// What each agent answers initialize with.
  Map<String, Object?> init = {'protocolVersion': 1};

  /// What the n-th agent, from 0, answers initialize with, where given.
  Map<String, Object?>? Function(int n) initOf = (_) => null;

  /// The agent's id for its n-th session, from 1.
  String Function(int n) sessionId = (n) => 's$n';

  /// Whether agents exit on the stop's signals; one that does not makes
  /// its close fail once the stop's bounds have passed.
  var exitOnSignal = true;

  /// Whether agents answer session/new by themselves.
  var answerNew = true;

  /// What a session/new answer carries besides its id.
  Map<String, Object?> newAnswer = const {};

  /// Whether agents answer session/load and session/resume by themselves.
  var answerReopen = true;

  /// The updates an agent sends for the session it loads, before its
  /// answer.
  List<Map<String, Object?>> replay = const [];

  var _sessions = 0;
  final _answered = <MemoryAgentProcess, Set<Object?>>{};
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
  }) {
    late final MemoryAgentProcess process;
    process = MemoryAgentProcess(
      pid: 5000 + agents.length,
      onSignal: (signal) {
        if (!exitOnSignal) return;
        process.exit(
          signal == ProcessSignal.sigterm
              ? const Exit(143, 'SIGTERM')
              : const Exit(137, 'SIGKILL'),
        );
        process.closeStdout();
        process.closeStderr();
      },
    );
    agents.add(process);
    declared.add(capabilities);
    return connectAgent(
      process,
      onTraffic: onTraffic,
      onPermission: onPermission,
      capabilities: capabilities,
      onElicitation: onElicitation,
      relay: relay,
      cancellationToken: cancellationToken,
      stop: const StopBounds(
        exit: Duration(milliseconds: 100),
        term: Duration(milliseconds: 100),
        kill: Duration(milliseconds: 100),
      ),
    );
  }

  /// Lets what is due run, the agents answering what they answer by
  /// themselves.
  void settle() {
    for (var round = 0; round < 20; round++) {
      async.flushMicrotasks();
      for (final agent in agents) {
        if (agent.signals.isNotEmpty || agent.stdin.closed) continue;
        final answered = _answered.putIfAbsent(agent, () => {});
        for (final message in agent.stdin.messages) {
          final id = message['id'];
          if (!message.containsKey('method') || answered.contains(id)) {
            continue;
          }
          switch (message['method']) {
            case 'initialize':
              answered.add(id);
              agent.send({
                'jsonrpc': '2.0',
                'id': id,
                'result': initOf(agents.indexOf(agent)) ?? init,
              });
            case 'session/load' || 'session/resume' when answerReopen:
              answered.add(id);
              final params = message['params'] as Map<String, Object?>;
              if (message['method'] == 'session/load') {
                for (final update in replay) {
                  agent.send({
                    'jsonrpc': '2.0',
                    'method': 'session/update',
                    'params': {
                      'sessionId': params['sessionId'],
                      'update': update,
                    },
                  });
                }
              }
              agent.send({
                'jsonrpc': '2.0',
                'id': id,
                'result': <String, Object?>{},
              });
            case 'session/new' when answerNew:
              answered.add(id);
              agent.send({
                'jsonrpc': '2.0',
                'id': id,
                'result': {'sessionId': sessionId(++_sessions), ...newAnswer},
              });
          }
        }
      }
    }
  }

  /// Sends [message] as the client.
  void send(Map<String, Object?> message) {
    input.add(utf8.encode('${jsonEncode(message)}\n'));
    settle();
  }

  /// Sends the request [method] with [params]; its id.
  int request(String method, [Map<String, Object?>? params]) {
    final id = ++_ids;
    send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return id;
  }

  /// Initializes, declaring [capabilities].
  Map<String, Object?> initialize([
    Map<String, Object?> capabilities = const {},
  ]) =>
      answer(
            request('initialize', {
              'protocolVersion': 1,
              'clientCapabilities': capabilities,
            }),
          )!['result']
          as Map<String, Object?>;

  /// The answer to request [id], if written.
  Map<String, Object?>? answer(Object? id) {
    for (final message in lines.messages) {
      if (!message.containsKey('method') && message['id'] == id) {
        return message;
      }
    }
    return null;
  }

  /// Opens a session in [cwd]; the client's id for it.
  String newSession({
    String cwd = '/w',
    List<Map<String, Object?>> mcpServers = const [],
  }) {
    final answered = answer(
      request('session/new', {'cwd': cwd, 'mcpServers': mcpServers}),
    );
    return (answered!['result'] as Map)['sessionId'] as String;
  }

  /// The notifications chord sent of [method].
  List<Map<String, Object?>> notified(String method) => [
    for (final message in lines.messages)
      if (message['method'] == method && !message.containsKey('id'))
        message['params'] as Map<String, Object?>,
  ];

  /// Ends stdin and lets the way out run to its exit.
  void eof() {
    input.close();
    settle();
    async.elapse(const Duration(seconds: 20));
    settle();
  }
}

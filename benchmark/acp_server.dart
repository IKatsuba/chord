/// A hand-run benchmark of `chord acp`, the server, with no terminal and no
/// real agent or client:
///
///     dart run benchmark/acp_server.dart
///     dart compile exe benchmark/acp_server.dart -o build/acp_server_bench
///
/// It serves in-memory agents to a counting sink and reports: N sessions
/// streaming M updates each at once, relayed to the client; a prompt line
/// just under the 32 MiB cap on one session, and how late a ping on
/// another session is answered behind it; and a `session/load` of a record
/// of 10 000 updates, relayed ahead of its answer. For each, the wall time,
/// how late a 16 ms heartbeat runs (p50, p99, max), and the RSS at its end.
///
/// The client's and the agents' bytes arrive as a real pipe gives them: one
/// read event per 64 KiB at most, each its own turn of the event loop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart';
import 'package:chord/acp/rpc.dart' show ElicitationHandler;
import 'package:chord/acp/schema.dart' show ClientCapabilities;
import 'package:chord/acp/stdio.dart';
import 'package:chord/acp_agent.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/record.dart';

const frame = Duration(milliseconds: 16);
const pipeRead = 64 * 1024;

String ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(2);

String mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

List<int> line(Map<String, Object?> message) =>
    utf8.encode('${jsonEncode(message)}\n');

Map<String, Object?> chunk(int i) => {
  'sessionUpdate': 'agent_message_chunk',
  'content': {
    'type': 'text',
    'text': 'chunk $i of a reply that streams in, about eighty characters. ',
  },
};

/// [bytes] as a pipe delivers them: one event per [pipeRead] at most.
Future<void> deliver(void Function(List<int>) add, List<int> bytes) async {
  for (var start = 0; start < bytes.length; start += pipeRead) {
    final end = start + pipeRead < bytes.length
        ? start + pipeRead
        : bytes.length;
    final part = bytes.sublist(start, end);
    await Future<void>(() => add(part));
  }
}

/// How late a [frame] timer runs while something else does.
final class Heartbeat {
  Heartbeat() {
    _timer = Timer.periodic(frame, (_) {
      final now = _clock.elapsed;
      _lags.add(now - _last - frame);
      _last = now;
    });
  }

  var _last = Duration.zero;

  final _clock = Stopwatch()..start();
  final _lags = <Duration>[];
  late final Timer _timer;

  /// The lags so far, the wait since the last beat counted as one: a loop
  /// held up to the end beats no more.
  String stop() {
    _timer.cancel();
    final since = _clock.elapsed - _last;
    if (since > frame) _lags.add(since - frame);
    final lags = [for (final lag in _lags) lag.isNegative ? Duration.zero : lag]
      ..sort();
    if (lags.isEmpty) return 'no beats';
    Duration at(double q) => lags[((lags.length - 1) * q).round()];
    return 'heartbeat lag p50 ${ms(at(.5))} ms, p99 ${ms(at(.99))} ms, '
        'max ${ms(lags.last)} ms over ${lags.length} beats';
  }
}

/// The client's side of stdout: bytes and lines counted, and how many
/// times each marker has been written.
final class CountingSink implements OutputSink {
  CountingSink(this.markers);

  final List<String> markers;
  late final counts = {for (final marker in markers) marker: 0};
  var bytes = 0, lines = 0;
  final _changed = StreamController<void>.broadcast();

  @override
  void add(List<int> chunk) {
    bytes += chunk.length;
    for (final byte in chunk) {
      if (byte == 10) lines++;
    }
    final text = utf8.decode(chunk);
    for (final marker in markers) {
      counts[marker] = counts[marker]! + marker.allMatches(text).length;
    }
    _changed.add(null);
  }

  /// Once [marker] has been written [count] times.
  Future<void> until(String marker, int count) async {
    if (counts[marker]! >= count) return;
    await for (final _ in _changed.stream) {
      if (counts[marker]! >= count) return;
    }
  }

  @override
  Future<void> flush() => Future.value();

  @override
  Future<void> close() => Future.value();
}

/// What chord writes to a [BenchAgent]: nothing kept, each line split off
/// as it ends and only its head read, for the method and id, so the
/// harness does not decode a 32 MiB line the server already has.
final class LeanInput implements AgentInput {
  LeanInput(this.heard);

  final void Function(String method, Object id) heard;
  final _pending = BytesBuilder(copy: false);
  final _done = Completer<void>();
  static final _head = RegExp(
    r'^\{"jsonrpc":"2\.0","method":"([^"]+)","id":(\d+)',
  );

  @override
  void add(List<int> bytes) {
    var start = 0;
    for (
      var end = bytes.indexOf(10);
      end >= 0;
      end = bytes.indexOf(10, start)
    ) {
      // A head split across reads is joined first.
      final head = [
        ..._pending.takeBytes(),
        ...bytes.sublist(start, end < start + 256 ? end : start + 256),
      ];
      final match = _head.firstMatch(
        latin1.decode(head.length > 256 ? head.sublist(0, 256) : head),
      );
      if (match != null) heard(match[1]!, int.parse(match[2]!));
      start = end + 1;
    }
    // Only a line's head is ever read: what follows its first 256 bytes is
    // not kept.
    final room = 256 - _pending.length;
    if (start < bytes.length && room > 0) {
      final end = bytes.length - start < room ? bytes.length : start + room;
      _pending.add(bytes.sublist(start, end));
    }
  }

  @override
  Future<void> flush() => Future.value();

  @override
  void end() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

/// An agent in memory that answers as [answer] has it, reading what chord
/// writes to it as it comes.
final class BenchAgent implements AgentProcess {
  BenchAgent(this.answer);

  final Future<void> Function(BenchAgent agent, String method, Object id)
  answer;
  late final MemoryAgentProcess _memory = MemoryAgentProcess(
    onSignal: (_) {
      _memory
        ..exit(const Exit(143, 'SIGTERM'))
        ..closeStdout()
        ..closeStderr();
    },
  );

  @override
  late final AgentInput stdin = LeanInput(
    (method, id) => Future(() => answer(this, method, id)),
  );

  @override
  int get pid => _memory.pid;

  @override
  Stream<List<int>> get stdout => _memory.stdout;

  @override
  Future<Exit> get status => _memory.status;

  @override
  String stderrTail() => _memory.stderrTail();

  @override
  Tail stderrEnd() => _memory.stderrEnd();

  @override
  Future<String> lastWords() => _memory.lastWords();

  @override
  Future<void> stop([StopBounds bounds = const StopBounds()]) =>
      _memory.stop(bounds);

  void writeStdout(List<int> bytes) => _memory.writeStdout(bytes);

  void reply(Object? id, Object? result) =>
      _memory.send({'jsonrpc': '2.0', 'id': id, 'result': result});
}

/// Answers initialize, session/new and session/load; [prompt] the rest.
Future<void> Function(BenchAgent, String, Object) agentOf(
  String sessionId, {
  Future<void> Function(BenchAgent agent, Object id)? prompt,
}) => (agent, method, id) async {
  switch (method) {
    case 'initialize':
      agent.reply(id, {
        'protocolVersion': 1,
        'agentCapabilities': {'loadSession': true},
      });
    case 'session/new':
      agent.reply(id, {'sessionId': sessionId});
    case 'session/load':
      agent.reply(id, <String, Object?>{});
    case 'session/prompt':
      await prompt?.call(agent, id);
  }
};

/// `chord acp` serving [agents], one per session in order, to [sink].
({AcpHost host, StreamController<List<int>> input, List<BenchAgent> started})
serve(CountingSink sink, List<BenchAgent> agents, {required String stateDir}) {
  final input = StreamController<List<int>>();
  final started = <BenchAgent>[];
  Future<Agent> launch({
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
    final agent = agents[started.length];
    started.add(agent);
    return connectAgent(
      agent,
      onTraffic: onTraffic,
      onPermission: onPermission,
      capabilities: capabilities,
      onElicitation: onElicitation,
      relay: relay,
      cancellationToken: cancellationToken,
    );
  }

  final host = runAcp(
    input: input.stream,
    sink: sink,
    agent: 'bench',
    version: '0.0.0',
    place: (cwd) async =>
        (cwd: cwd, start: const SessionStart(command: 'bench')),
    stateDir: stateDir,
    stderr: (_) {},
    exit: (_) {},
    launch: launch,
  );
  return (host: host, input: input, started: started);
}

var _ids = 0;

Future<void> request(
  StreamController<List<int>> input,
  String method,
  Map<String, Object?> params,
) => deliver(
  input.add,
  line({'jsonrpc': '2.0', 'id': ++_ids, 'method': method, 'params': params}),
);

Future<void> flood(String stateDir, {required int n, required int m}) async {
  final sink = CountingSink(['"stopReason"', '"sessionId"']);
  final agents = [
    for (var i = 0; i < n; i++)
      BenchAgent(
        agentOf(
          'a$i',
          prompt: (agent, id) async {
            final bytes = BytesBuilder(copy: false);
            for (var j = 0; j < m; j++) {
              bytes.add(
                line({
                  'jsonrpc': '2.0',
                  'method': 'session/update',
                  'params': {'sessionId': 'a$i', 'update': chunk(j)},
                }),
              );
            }
            await deliver(agent.writeStdout, bytes.takeBytes());
            agent.reply(id, {'stopReason': 'end_turn'});
          },
        ),
      ),
  ];
  final served = serve(sink, agents, stateDir: stateDir);
  await request(served.input, 'initialize', {'protocolVersion': 1});
  for (var i = 0; i < n; i++) {
    await request(served.input, 'session/new', {
      'cwd': '/w',
      'mcpServers': <Object?>[],
    });
  }
  while (served.host.sessions.length < n) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  final heartbeat = Heartbeat();
  final clock = Stopwatch()..start();
  final linesBefore = sink.lines;
  for (final id in served.host.sessions.keys.toList()) {
    await request(served.input, 'session/prompt', {
      'sessionId': id,
      'prompt': [
        {'type': 'text', 'text': 'go'},
      ],
    });
  }
  await sink.until('"stopReason"', n);
  clock.stop();
  final relayed = sink.lines - linesBefore;
  stdout
    ..writeln(
      '$n sessions x $m updates: ${ms(clock.elapsed)} ms, '
      '$relayed lines relayed '
      '(${(relayed / clock.elapsed.inMicroseconds * 1e6).round()}/s)',
    )
    ..writeln('  ${heartbeat.stop()}')
    ..writeln('  RSS ${mib(ProcessInfo.currentRss)} MiB');
  await finish(served);
}

Future<void> bigLine(String stateDir) async {
  final sink = CountingSink(['"stopReason"', '"title":"ping"']);
  late final Stopwatch toAgent;
  final agents = [
    BenchAgent(
      agentOf(
        'big',
        prompt: (agent, id) async {
          toAgent.stop();
          agent.reply(id, {'stopReason': 'end_turn'});
        },
      ),
    ),
    BenchAgent(agentOf('small')),
  ];
  final served = serve(sink, agents, stateDir: stateDir);
  await request(served.input, 'initialize', {'protocolVersion': 1});
  for (var i = 0; i < 2; i++) {
    await request(served.input, 'session/new', {
      'cwd': '/w',
      'mcpServers': <Object?>[],
    });
  }
  while (served.host.sessions.length < 2) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  // Just under the cap, its envelope included.
  final text = 'x' * (32 * 1024 * 1024 - 4096);
  final prompt = line({
    'jsonrpc': '2.0',
    'id': ++_ids,
    'method': 'session/prompt',
    'params': {
      'sessionId': 'big',
      'prompt': [
        {'type': 'text', 'text': text},
      ],
    },
  });
  final ping = line({
    'jsonrpc': '2.0',
    'id': ++_ids,
    'method': 'session/set_title',
    'params': {'sessionId': 'small', 'title': 'ping'},
  });
  final heartbeat = Heartbeat();
  // From before the prompt's first byte: the ping, right behind it on the
  // same stdin, waits for all of it, as a client's would.
  final clock = Stopwatch()..start();
  toAgent = Stopwatch()..start();
  // Whichever of the two the server reaches first.
  Duration? pinged;
  sink.until('"title":"ping"', 1).then((_) => pinged = clock.elapsed);
  await deliver(served.input.add, prompt);
  final fed = clock.elapsed;
  // Taken before its bytes go in: its handler may run before the feed's
  // await returns.
  final pingFed = clock.elapsed;
  await deliver(served.input.add, ping);
  await sink.until('"title":"ping"', 1);
  await sink.until('"stopReason"', 1);
  clock.stop();
  stdout
    ..writeln(
      'a ${mib(prompt.length)} MiB prompt line: its last byte fed in ${ms(fed)} ms, at its agent in ${ms(toAgent.elapsed)} ms, '
      'answered in ${ms(clock.elapsed)} ms',
    )
    ..writeln(
      '  a ping on another session right behind it: answered '
      '${ms(pinged!)} ms from the prompt\'s first byte, '
      '${ms(pinged! - pingFed)} ms after its own was fed',
    )
    ..writeln('  ${heartbeat.stop()}')
    ..writeln('  RSS ${mib(ProcessInfo.currentRss)} MiB');
  await finish(served);
}

Future<void> load(String stateDir, {required int updates}) async {
  final id = '0b6f7c2e-1d3a-4c5b-9e8f-7a6b5c4d3e2f';
  final records = Directory(recordsDir(stateDir))..createSync(recursive: true);
  final record = StringBuffer()
    ..write(
      encodeRecord({
        'type': 'session',
        'version': 1,
        'sessionId': id,
        'agent': 'bench',
        'cwd': '/w',
        'at': 1,
      }),
    );
  for (var turn = 0; turn < updates / 100; turn++) {
    record.write(
      encodeRecord({
        'type': 'prompt',
        'turnId': 't$turn',
        'prompt': 'turn $turn',
        'images': 0,
        'at': 2 + turn,
      }),
    );
    for (var j = 0; j < 100; j++) {
      record.write(
        encodeRecord({
          'type': 'update',
          'turnId': 't$turn',
          'update': chunk(j),
        }),
      );
    }
    record.write(
      encodeRecord({
        'type': 'result',
        'turnId': 't$turn',
        'result': {'status': 'completed', 'stopReason': 'end_turn'},
      }),
    );
  }
  final file = File('${records.path}/$id.jsonl')
    ..writeAsStringSync(record.toString());
  final sink = CountingSink(['"configOptions"']);
  final served = serve(sink, [BenchAgent(agentOf(id))], stateDir: stateDir);
  await request(served.input, 'initialize', {'protocolVersion': 1});
  final heartbeat = Heartbeat();
  final before = sink.lines;
  final clock = Stopwatch()..start();
  await request(served.input, 'session/load', {
    'sessionId': id,
    'cwd': '/w',
    'mcpServers': <Object?>[],
  });
  await sink.until('"configOptions"', 1);
  clock.stop();
  stdout
    ..writeln(
      'a load of a ${mib(file.lengthSync())} MiB record of $updates updates: '
      'answered in ${ms(clock.elapsed)} ms, ${sink.lines - before} lines '
      'ahead of and with the answer',
    )
    ..writeln('  ${heartbeat.stop()}')
    ..writeln('  RSS ${mib(ProcessInfo.currentRss)} MiB');
  await finish(served);
}

Future<void> finish(
  ({AcpHost host, StreamController<List<int>> input, List<BenchAgent> started})
  served,
) async {
  await served.input.close();
  while (!served.host.leaving) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  await served.host.leave(const LeaveEof());
}

Future<void> main(List<String> args) async {
  final state = Directory.systemTemp.createTempSync('chord-acp-bench-');
  try {
    await flood(state.path, n: 1, m: 10000);
    await flood(state.path, n: 8, m: 10000);
    await bigLine(state.path);
    await load(state.path, updates: 10000);
  } finally {
    state.deleteSync(recursive: true);
  }
  exit(0);
}

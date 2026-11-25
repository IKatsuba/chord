/// A hand-run benchmark of the ACP client under floods of updates, with no
/// terminal and no real agent:
///
///     dart run benchmark/acp_updates.dart
///     dart compile exe benchmark/acp_updates.dart -o build/acp_updates_bench
///
/// It drives an in-memory agent process and reports, for 10 000 updates in
/// one burst and for 1 000 a second over 10 s: how late a 16 ms heartbeat
/// runs (the frame clock), how many frames a headless host draws, how long
/// a cancel takes to reach the agent's stdin, and chord's RSS. Then the
/// memory a non-reading agent costs, and how long closing it takes. Last,
/// the same measures over the Dart fake agent's `flood`, 64 MiB of
/// chunks from a real process, skipped with the reason where it cannot be
/// built.
///
/// Then the same through the session layer, folded into the window's state
/// as CTUI-15 builds it: the cost of one update folded at 10 000 entries,
/// 1 000 updates a second folded onto 10 000 entries under the heartbeat,
/// the memory those entries take, and the fake's `flood` through a
/// conversation, with how long Esc takes to draw `Interrupted by user`. The
/// budget, for `dart compile exe`: the heartbeat's p99 stays within one
/// frame.
///
/// The agent's stdout arrives as a real pipe gives it: one read event per
/// 64 KiB at most, each its own turn of the event loop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/acp/schema.dart';
import 'package:chord/platform/group_exec.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';

import '../test/fixtures/fake.dart';

const frame = Duration(milliseconds: 16);
const pipeRead = 64 * 1024;
const size = Size(120, 40);

/// One update as an agent streams a reply: a chunk of text.
List<int> updateLine(int i) => utf8.encode(
  '${jsonEncode({
    'jsonrpc': '2.0',
    'method': 'session/update',
    'params': {
      'sessionId': 's',
      'update': {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'chunk $i of a reply that streams in, about eighty characters. '},
      },
    },
  })}\n',
);

/// [bytes] as a pipe delivers them: one event per [pipeRead] at most.
Future<void> deliver(MemoryAgentProcess process, List<int> bytes) async {
  for (var start = 0; start < bytes.length; start += pipeRead) {
    final end = start + pipeRead < bytes.length
        ? start + pipeRead
        : bytes.length;
    final chunk = bytes.sublist(start, end);
    await Future<void>(() => process.writeStdout(chunk));
  }
}

String ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(2);

String mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

/// A connection over an in-memory agent, a headless host drawing how many
/// updates arrived, and a 16 ms heartbeat that draws a frame when anything
/// changed and records how late it ran.
class Bench {
  Bench._(this.process, this.agent, this.updates, this.host);

  /// The fake agent, started in [cwd], under the same heartbeat
  /// and host; [bytes] counts what its updates carried.
  static Future<Bench> fake(String cwd, ValueNotifier<int> bytes) async {
    final updates = ValueNotifier(0);
    final agent = await openAgent(
      command: fakeAgentCommand(),
      cwd: cwd,
      onTraffic: (traffic) {
        if (traffic case AgentTraffic(
          message: {
            'method': 'session/update',
            'params': {'update': {'content': {'text': final String text}}},
          },
        )) {
          updates.value++;
          bytes.value += text.length;
        }
      },
      onPermission: (_, _) => Completer<RequestPermissionResponse>().future,
    );
    return _drawing(null, agent, updates);
  }

  static Bench _drawing(
    MemoryAgentProcess? process,
    Agent agent,
    ValueNotifier<int> updates,
  ) {
    var dirty = true;
    final host = AppHost(
      ListenableBuilder(
        listenable: updates,
        builder: (context) => Text('updates: ${updates.value}'),
      ),
      onNeedsFrame: () => dirty = true,
    );
    final bench = Bench._(process, agent, updates, host);
    bench._dirty = () {
      final was = dirty;
      dirty = false;
      return was;
    };
    return bench;
  }

  static Future<Bench> open() async {
    final updates = ValueNotifier(0);
    late final MemoryAgentProcess process;
    process = MemoryAgentProcess(
      onSignal: (_) {
        process.exit(const Exit(143, 'SIGTERM'));
        process.closeStdout();
        process.closeStderr();
      },
    );
    final opening = connectAgent(
      process,
      onTraffic: (traffic) {
        if (traffic case AgentTraffic(
          :final message,
        ) when message['method'] == 'session/update') {
          updates.value++;
        }
      },
      onPermission: (_, _) => Completer<RequestPermissionResponse>().future,
    );
    await Future<void>.delayed(Duration.zero);
    process.send({
      'jsonrpc': '2.0',
      'id': 0,
      'result': {'protocolVersion': 1},
    });
    return _drawing(process, await opening, updates);
  }

  /// The in-memory agent; null for the fake.
  final MemoryAgentProcess? process;
  final Agent agent;
  final ValueNotifier<int> updates;
  final AppHost host;
  late bool Function() _dirty;

  final lateness = <Duration>[];
  var frames = 0;
  Timer? _heartbeat;

  void startHeartbeat() {
    lateness.clear();
    frames = 0;
    final clock = Stopwatch()..start();
    var ticks = 0;
    _heartbeat = Timer.periodic(frame, (_) {
      ticks++;
      lateness.add(clock.elapsed - frame * ticks);
      if (_dirty()) {
        host.drawFrame(size);
        frames++;
      }
    });
  }

  void stopHeartbeat() => _heartbeat?.cancel();

  /// When `session/cancel` reaches stdin, from the moment it was asked for.
  Future<Duration> cancelLatency(Duration after) async {
    final asked = Stopwatch();
    final done = Completer<Duration>();
    Timer(after, () {
      asked.start();
      agent.cancel('s').then((_) {
        final text = process!.stdin.text;
        if (text.contains('"session/cancel"')) done.complete(asked.elapsed);
      });
    });
    return done.future;
  }

  void report(String name, int updatesSeen) {
    final sorted = [...lateness]..sort();
    final p99 = sorted.isEmpty
        ? Duration.zero
        : sorted[((sorted.length - 1) * 0.99).round()];
    final worst = sorted.isEmpty ? Duration.zero : sorted.last;
    print(
      '$name: $updatesSeen updates, ${sorted.length} heartbeats, '
      'lateness p99 ${ms(p99)} ms, worst ${ms(worst)} ms, frames drawn $frames, '
      'RSS ${mib(ProcessInfo.currentRss)} MiB',
    );
  }
}

Future<void> burst() async {
  final bench = await Bench.open();
  final bytes = [for (var i = 0; i < 10000; i++) ...updateLine(i)];
  final rss = ProcessInfo.currentRss;
  bench.startHeartbeat();
  final cancel = bench.cancelLatency(const Duration(milliseconds: 5));
  final start = Stopwatch()..start();
  await deliver(bench.process!, bytes);
  while (bench.updates.value < 10000) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  final took = start.elapsed;
  await Future<void>.delayed(frame * 2);
  bench.stopHeartbeat();
  bench.report(
    '10 000 updates in one burst (${mib(bytes.length)} MiB)',
    bench.updates.value,
  );
  print(
    '  taken in ${ms(took)} ms; cancel reached stdin in ${ms(await cancel)} ms; '
    'RSS before ${mib(rss)} MiB',
  );
  await bench.agent.close();
}

Future<void> steady() async {
  final bench = await Bench.open();
  final rss = ProcessInfo.currentRss;
  bench.startHeartbeat();
  var sent = 0;
  final perTick = 16;
  final done = Completer<void>();
  final latencies = <Duration>[];
  final clock = Stopwatch()..start();
  final pacer = Timer.periodic(frame, (timer) {
    if (clock.elapsed >= const Duration(seconds: 10)) {
      timer.cancel();
      done.complete();
      return;
    }
    final bytes = [for (var i = 0; i < perTick; i++) ...updateLine(sent + i)];
    sent += perTick;
    bench.process!.writeStdout(bytes);
  });
  // Three cancels, three seconds apart, while the updates stream.
  for (var i = 0; i < 3; i++) {
    latencies.add(await bench.cancelLatency(const Duration(seconds: 3)));
  }
  await done.future;
  await Future<void>.delayed(frame * 2);
  bench.stopHeartbeat();
  pacer.cancel();
  bench.report('1 000 updates a second for 10 s', bench.updates.value);
  print(
    '  cancels reached stdin in ${[for (final l in latencies) ms(l)].join(', ')} ms; '
    'RSS before ${mib(rss)} MiB',
  );
  await bench.agent.close();
}

Future<void> nonReader() async {
  final bench = await Bench.open();
  bench.process!.stdin.hold = true;
  final rss = ProcessInfo.currentRss;
  final text = 'x' * (64 * 1024);
  const prompts = 256;
  for (var i = 0; i < prompts; i++) {
    bench.agent
        .prompt(
          PromptRequest(sessionId: 's', prompt: [ContentBlock.text(text)]),
          cancellationToken: CancellationToken(),
        )
        .ignore();
  }
  await Future<void>.delayed(const Duration(milliseconds: 50));
  final queued = prompts * text.length;
  final after = ProcessInfo.currentRss;
  print(
    'a non-reading agent sent $prompts prompts of 64 KiB (${mib(queued)} MiB): '
    'RSS ${mib(rss)} -> ${mib(after)} MiB (+${mib(after - rss)} MiB)',
  );
  final closing = Stopwatch()..start();
  await bench.agent.close();
  print(
    '  close() ended in ${ms(closing.elapsed)} ms, through the ladder\'s SIGTERM',
  );
}

/// The fake's `flood`: as many chunks as chord takes, from a real process,
/// cancelled once half of it has come.
Future<void> flood() async {
  final reason = fakeAgent.reason;
  if (reason != null) {
    print('the fake agent\'s flood: skipped, $reason');
    return;
  }
  final cwd = Directory.systemTemp.createTempSync('chord-bench-');
  try {
    final bytes = ValueNotifier(0);
    final bench = await Bench.fake(cwd.path, bytes);
    try {
      final session = await bench.agent.newSession(
        NewSessionRequest(cwd: cwd.path, mcpServers: const []),
      );
      bench.updates.value = 0;
      final rss = ProcessInfo.currentRss;
      final start = Stopwatch()..start();
      final asked = Stopwatch();
      void half() {
        if (asked.isRunning || bytes.value < 32 * 1024 * 1024) return;
        asked.start();
        bench.agent.cancel(session.sessionId).catchError((Object error) {
          print('  the cancel failed: $error');
        });
      }

      final PromptResponse answer;
      final Duration cancelled;
      final Duration took;
      bench.startHeartbeat();
      bytes.addListener(half);
      try {
        answer = await bench.agent.prompt(
          PromptRequest(
            sessionId: session.sessionId,
            prompt: [ContentBlock.text('flood')],
          ),
        );
        cancelled = asked.elapsed;
        took = start.elapsed;
        await Future<void>.delayed(frame * 2);
      } finally {
        bytes.removeListener(half);
        bench.stopHeartbeat();
      }
      bench.report(
        "the fake agent's flood (${mib(bytes.value)} MiB of 64 MiB)",
        bench.updates.value,
      );
      print(
        '  taken in ${ms(took)} ms; cancelled at 32 MiB, answered '
        '${answer.stopReason} ${ms(cancelled)} ms later; RSS before '
        '${mib(rss)} MiB',
      );
    } finally {
      final closing = Stopwatch()..start();
      await bench.agent.close();
      print('  close() ended in ${ms(closing.elapsed)} ms');
    }
  } finally {
    cwd.deleteSync(recursive: true);
  }
}

/// The window's state as the conversation folds it, drawn by a headless
/// host on a 16 ms heartbeat that records how late it runs.
class Folding {
  Folding(AppState start) : state = ValueNotifier(start) {
    host = AppHost(
      ListenableBuilder(
        listenable: state,
        builder: (context) => Text(
          'entries: ${state.value.transcript.entries.length}, '
          'turn: ${state.value.transcript.turn.runtimeType}',
        ),
      ),
      onNeedsFrame: () => _dirty = true,
    );
  }

  final ValueNotifier<AppState> state;
  late final AppHost host;
  final lateness = <Duration>[];
  var frames = 0;
  var _dirty = true;
  Timer? _heartbeat;

  /// Folds [event] into the state, as the window does.
  void hear(ConversationEvent event) =>
      state.value = reduceApp(state.value, event);

  void startHeartbeat() {
    final clock = Stopwatch()..start();
    var ticks = 0;
    _heartbeat = Timer.periodic(frame, (_) {
      ticks++;
      lateness.add(clock.elapsed - frame * ticks);
      if (_dirty) {
        _dirty = false;
        host.drawFrame(size);
        frames++;
      }
    });
  }

  void stopHeartbeat() => _heartbeat?.cancel();

  /// Whether the heartbeat still runs.
  bool get beating => _heartbeat?.isActive ?? false;

  /// The heartbeat's p99 lateness, and whether it stays within a frame.
  (Duration, bool) report(String name) {
    final sorted = [...lateness]..sort();
    final p99 = sorted.isEmpty
        ? Duration.zero
        : sorted[((sorted.length - 1) * 0.99).round()];
    final worst = sorted.isEmpty ? Duration.zero : sorted.last;
    print(
      '$name: ${state.value.transcript.entries.length} entries, '
      '${sorted.length} heartbeats, lateness p99 ${ms(p99)} ms, worst '
      '${ms(worst)} ms, frames drawn $frames, RSS '
      '${mib(ProcessInfo.currentRss)} MiB',
    );
    return (p99, p99 < frame);
  }
}

/// A transcript of [entries] entries, a prompt and a reply a turn, idle,
/// in a session at [start].
AppState transcriptOf(
  int entries, {
  StartState start = const StartState(
    phase: StartPhase.connected,
    sessionId: 's',
  ),
}) {
  final list = <Entry>[
    for (var i = 0; i < entries ~/ 2; i++) ...[
      UserEntry('past-$i', 'prompt $i'),
      AssistantEntry(
        'past-$i',
        TextRun.empty.plus('reply $i, a line or two of text.'),
      ),
    ],
  ];
  return AppState(
    start: start,
    transcript: Transcript(entries: List.unmodifiable(list)),
  );
}

/// A conversation over an in-memory agent whose session is open, folding
/// into [folding]; settles once it is connected.
Future<(Conversation, MemoryAgentProcess)> memoryConversation(
  Folding folding,
) async {
  late final MemoryAgentProcess process;
  process = MemoryAgentProcess(
    onSignal: (_) {
      process.exit(const Exit(143, 'SIGTERM'));
      process.closeStdout();
      process.closeStderr();
    },
  );
  Object? idOf(String method) =>
      process.stdin.messages.lastWhere((m) => m['method'] == method)['id'];
  final connected = Completer<void>();
  final conversation = Conversation(
    ({required onTraffic, required cancellationToken}) => openSession(
      agent: 'memory',
      command: 'memory',
      cwd: '/',
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
          ),
      onTraffic: onTraffic,
    ),
  );
  conversation.listen((event) {
    folding.hear(event);
    if (event is Connected) connected.complete();
  });
  conversation.start();
  await Future<void>.delayed(Duration.zero);
  process.send({
    'jsonrpc': '2.0',
    'id': idOf('initialize'),
    'result': {'protocolVersion': 1},
  });
  await Future<void>.delayed(Duration.zero);
  process.send({
    'jsonrpc': '2.0',
    'id': idOf('session/new'),
    'result': {'sessionId': 's'},
  });
  await connected.future;
  return (conversation, process);
}

/// One update folded at 10 000 entries: a chunk that grows the last reply,
/// and a tool call that appends an entry, each the mean of many.
void foldPerUpdate() {
  final start = transcriptOf(10000);
  const runs = 2000;
  final chunk = Transcribed(
    UpdateAction(
      'past-4999',
      SessionUpdate.fromJson({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'more of the reply. '},
      }),
    ),
  );
  var state = start;
  final grown = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    state = reduceApp(state, chunk);
  }
  grown.stop();
  state = start;
  final appended = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    state = reduceApp(
      state,
      Transcribed(
        UpdateAction(
          'past-4999',
          SessionUpdate.fromJson({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'call-$i',
            'title': 'Read',
            'status': 'pending',
          }),
        ),
      ),
    );
  }
  appended.stop();
  print(
    'one update folded at 10 000 entries: a chunk '
    '${(grown.elapsedMicroseconds / runs).toStringAsFixed(1)} µs, a new tool '
    'call ${(appended.elapsedMicroseconds / runs).toStringAsFixed(1)} µs',
  );
}

/// What 10 000 entries take, as RSS grows to hold them.
void heapAtTenThousand() {
  final before = ProcessInfo.currentRss;
  final state = transcriptOf(10000);
  final after = ProcessInfo.currentRss;
  print(
    '10 000 entries (${state.transcript.entries.length}): RSS '
    '${mib(before)} -> ${mib(after)} MiB (+${mib(after - before)} MiB)',
  );
}

/// 1 000 updates a second for 10 s, folded onto 10 000 entries through the
/// conversation, under the heartbeat.
Future<bool> steadyFolded() async {
  final folding = Folding(transcriptOf(10000));
  final (conversation, process) = await memoryConversation(folding);
  conversation.send('stream');
  await Future<void>.delayed(Duration.zero);
  var sent = 0;
  final done = Completer<void>();
  final clock = Stopwatch()..start();
  Timer? pacer;
  try {
    folding.startHeartbeat();
    pacer = Timer.periodic(frame, (timer) {
      if (clock.elapsed >= const Duration(seconds: 10)) {
        timer.cancel();
        done.complete();
        return;
      }
      process.writeStdout([
        for (var i = 0; i < 16; i++) ...updateLine(sent + i),
      ]);
      sent += 16;
    });
    await done.future;
    await Future<void>.delayed(frame * 2);
  } finally {
    // However the run ends, nothing of it keeps the benchmark alive.
    pacer?.cancel();
    folding.stopHeartbeat();
    await conversation.close();
  }
  final (_, met) = folding.report(
    '1 000 updates a second for 10 s, folded onto 10 000 entries',
  );
  return met;
}

/// The fake's `flood` through a conversation, folded onto 10 000 entries
/// under the heartbeat; Esc once half has come, and how long until
/// `Interrupted by user` is in the state. [folding], [scenario] and
/// [within] are a probe's, to make it fail and see it end.
Future<bool?> floodFolded({
  Folding? folding,
  String? scenario,
  Duration within = const Duration(seconds: 60),
}) async {
  final reason = fakeAgent.reason;
  if (reason != null) {
    print('the fake agent\'s flood, folded: skipped, $reason');
    return null;
  }
  final cwd = Directory.systemTemp.createTempSync('chord-bench-');
  var bytes = 0;
  final folded =
      folding ??
      Folding(
        transcriptOf(
          10000,
          start: const StartState(phase: StartPhase.starting),
        ),
      );
  final connected = Completer<void>();
  final cancelled = Completer<Duration>();
  final esc = Stopwatch();
  final conversation = Conversation(
    ({required onTraffic, required cancellationToken}) => openSession(
      agent: 'fake',
      command: fakeAgentCommand(scenario),
      cwd: cwd.path,
      onTraffic: (traffic) {
        onTraffic(traffic);
        if (traffic case AgentTraffic(
          message: {
            'method': 'session/update',
            'params': {'update': {'content': {'text': final String text}}},
          },
        )) {
          bytes += text.length;
        }
      },
      cancellationToken: cancellationToken,
    ),
  );
  conversation.listen((event) {
    folded.hear(event);
    if (event is Connected) connected.complete();
    if (!esc.isRunning && bytes >= 32 * 1024 * 1024) {
      esc.start();
      conversation.interrupt();
    }
    if (esc.isRunning &&
        !cancelled.isCompleted &&
        folded.state.value.transcript.entries.lastOrNull is CancelledEntry) {
      cancelled.complete(esc.elapsed);
    }
  });
  try {
    conversation.start();
    await connected.future;
    final rss = ProcessInfo.currentRss;
    final start = Stopwatch()..start();
    folded.startHeartbeat();
    conversation.send('flood');
    final took = await cancelled.future.timeout(within);
    final all = start.elapsed;
    await Future<void>.delayed(frame * 2);
    folded.stopHeartbeat();
    final (_, met) = folded.report(
      "the fake agent's flood, folded (${mib(bytes)} MiB of 64 MiB)",
    );
    print(
      '  taken in ${ms(all)} ms; Esc at 32 MiB drew Interrupted by user '
      '${ms(took)} ms later; RSS before ${mib(rss)} MiB',
    );
    return met;
  } finally {
    // However the run ends, nothing of it keeps the benchmark alive.
    folded.stopHeartbeat();
    await conversation.close();
    cwd.deleteSync(recursive: true);
  }
}

Future<void> main(List<String> args) async {
  // A binary from `dart compile exe` starts each agent through a copy of
  // itself, as chord's own binary does.
  if (args.isNotEmpty && args.first == groupExecFlag) groupExec(args);

  print('RSS at start ${mib(ProcessInfo.currentRss)} MiB');
  // First, while the heap holds nothing freed that would hide its growth.
  heapAtTenThousand();
  await nonReader();
  await burst();
  await steady();
  await flood();
  foldPerUpdate();
  final steadyMet = await steadyFolded();
  final floodMet = await floodFolded();
  print(
    'budget, heartbeat p99 within ${frame.inMilliseconds} ms: steady '
    '${steadyMet ? 'met' : 'missed'}, flood '
    '${floodMet == null
        ? 'not run'
        : floodMet
        ? 'met'
        : 'missed'}',
  );
}

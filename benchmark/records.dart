/// Owned summary/preparation/replay/layout and stalled-recording measurements.
/// Run in JIT or compile this entrypoint; no terminal, model or agent is used.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/transcript.dart' as view;
import 'package:chord/ui/pickers/pickers.dart' as pickers;
import 'package:chord/ui/pickers/state.dart' as picker_state;
import 'package:chord_tui/chord_tui.dart';
import 'package:path/path.dart' as p;

const _frame = Duration(milliseconds: 16);

double _ms(Duration value) => value.inMicroseconds / 1000;
Map<String, Object?> _distribution(List<double> values) {
  final sorted = [...values]..sort();
  double? at(double q) =>
      sorted.isEmpty ? null : sorted[((sorted.length - 1) * q).round()];
  return {
    'samples': sorted.length,
    'p50Ms': at(.5),
    'p99Ms': at(.99),
    'maxMs': at(1),
  };
}

/// A scheduled key really traverses Actions/Focus on the measured isolate.
class Pulse {
  Pulse() {
    host = AppHost(
      Actions(
        bindings: [Binding('x', 'Measure input delivery', () => accepted++)],
        child: Focus(autofocus: true, child: Text('record probe')),
      ),
    );
    host.drawFrame(const Size(80, 24));
  }
  late final AppHost host;
  int accepted = 0;
  final heartbeat = <double>[], input = <double>[];
  Future<Map<String, Object?>> measure(FutureOr<void> Function() body) async {
    heartbeat.clear();
    input.clear();
    final startAccepted = accepted;
    final clock = Stopwatch()..start();
    var expected = _frame.inMicroseconds;
    final timer = Timer.periodic(_frame, (_) {
      final late = math.max(0, clock.elapsedMicroseconds - expected);
      heartbeat.add(late / 1000);
      final before = accepted;
      host.handleKey(KeyCombo.parse('x').toEvent());
      if (accepted == before + 1) {
        input.add(math.max(0, clock.elapsedMicroseconds - expected) / 1000);
      }
      // A missed tick does not poison every later sample cumulatively.
      expected = clock.elapsedMicroseconds + _frame.inMicroseconds;
    });
    try {
      await body();
      final wall = clock.elapsed;
      // Let a timer delayed by synchronous work run before stopping sampling.
      await Future<void>.delayed(Duration.zero);
      return {
        'wallMs': _ms(wall),
        'rssBytes': ProcessInfo.currentRss,
        'cumulativePeakRssBytes': ProcessInfo.maxRss,
        'heartbeat': _distribution(heartbeat),
        'dispatchedInput': _distribution(input),
        'acceptedKeys': accepted - startAccepted,
      };
    } finally {
      timer.cancel();
    }
  }

  void close() => host.dispose();
}

Future<Map<String, Object?>> _ownedHandleSnapshot(String root) async {
  if (!File('/usr/sbin/lsof').existsSync()) {
    return {'count': null, 'available': false};
  }
  final result = await Process.run('/usr/sbin/lsof', [
    '-a',
    '-p',
    '$pid',
    '-Fftn',
  ]);
  if (result.exitCode != 0) return {'count': null, 'available': false};
  final descriptors = <Map<String, String>>[];
  var descriptor = '', type = '';
  for (final line in result.stdout.toString().split('\n')) {
    if (line.startsWith('f')) descriptor = line.substring(1);
    if (line.startsWith('t')) type = line.substring(1);
    if (line.startsWith('n$root')) {
      descriptors.add({
        'descriptor': descriptor,
        'type': type,
        'path': line.substring(root.length + 1),
      });
    }
  }
  return {
    'available': true,
    'count': descriptors.length,
    'descriptors': descriptors,
  };
}

Future<Map<String, Object?>> _cancelOperation(
  Pulse pulse,
  Future<Object?> Function(CancellationToken) body,
) async {
  final token = CancellationToken(), cancellation = Stopwatch();
  var requested = false, outcome = 'completed before cancel';
  final measured = await pulse.measure(() async {
    final pending = body(token);
    final timer = Timer(const Duration(milliseconds: 1), () {
      requested = true;
      cancellation.start();
      token.cancel();
    });
    try {
      await pending;
    } on CancelledException {
      outcome = 'cancelled';
    } finally {
      timer.cancel();
      cancellation.stop();
    }
  });
  return {
    ...measured,
    'outcome': outcome,
    'requestToFutureMs': requested ? _ms(cancellation.elapsed) : null,
  };
}

Future<void> _pickerProbe(List<String> args) async {
  final count = args.contains('--small') ? 20 : 2000;
  final allocated = await Directory.systemTemp.createTemp(
    'chord-picker-scale-',
  );
  final root = Directory(await allocated.resolveSymbolicLinks());
  final sessions = earlierSessions([
    for (var i = 0; i < count; i++)
      SessionRecord(
        path: p.join(root.path, '$i.jsonl'),
        sessionId: 'session-$i',
        agent: 'fake',
        cwd: '.',
        lastUsedAt: i + .25,
        prompt: 'Saved request $i 界😀',
      ),
  ], agent: 'fake');
  final snapshot = picker_state.ResumePickerState(
    sessions: sessions,
    cwd: '.',
    opening: Object(),
    openedAt: count,
  );
  String? selected;
  var steps = 0;
  final host = AppHost(
    pickers.ResumePicker(
      picker: snapshot,
      agent: 'fake',
      rows: 10,
      room: 40,
      onToggleScope: () {},
      onCanceled: () {},
      onSelected: (choice) => selected = choice.resume.sessionId,
    ),
  );
  late Buffer shown;
  final report = <String, Object?>{
    'runtimeLabel': 'aot-picker',
    'dartVersion': Platform.version.split(' on ').first,
    'pathMatching':
        'Canonical fixture root resolved before IO; relative lsof names.',
    'workload': {
      'choices': count,
      'rowLimit': 10,
      'steadyFrames': 50,
      'terminalSizes': ['120x40', '80x24'],
      'navigationScheduleMs': 16,
    },
    'limits':
        'Actual ResumePicker with in-memory summary fixtures. No scan, agent, reopen, disk or PTY timing. One separately labelled run; not substituted for transcript costs. Keys traverse the picker host and acceptance callback.',
  };
  Future<Map<String, Object?>> measure(Size size, void Function() body) async {
    final delivered = Completer<Map<String, Object?>>();
    final watch = Stopwatch()..start();
    final trigger = Timer(_frame, () {
      try {
        final dispatch = Stopwatch()..start();
        final handled = host.handleKey(KeyCombo.parse('down').toEvent());
        final dispatchMs = _ms(dispatch.elapsed);
        final drawing = Stopwatch()..start();
        shown = host.drawFrame(size);
        final drawMs = _ms(drawing.elapsed);
        final accept = Stopwatch()..start();
        final accepted = host.handleKey(KeyCombo.parse('enter').toEvent());
        steps++;
        if (!handled ||
            !accepted ||
            selected != 'session-${count - 1 - steps}') {
          throw StateError(
            'Picker navigation/acceptance did not reach the expected row',
          );
        }
        delivered.complete({
          'scheduledToAcceptanceMs': math.max(0, _ms(watch.elapsed) - 16),
          'downDispatchMs': dispatchMs,
          'navigationDrawMs': drawMs,
          'enterDispatchMs': _ms(accept.elapsed),
          'selectedId': selected,
        });
      } catch (error, stack) {
        delivered.completeError(error, stack);
      }
    });
    try {
      body();
      final wall = _ms(watch.elapsed);
      if (!shown.toString().contains('Resume a session') ||
          !shown.toString().contains('Saved request')) {
        throw StateError('Picker measured an absent/fallback surface');
      }
      final navigation = await delivered.future;
      return {
        'wallMs': wall,
        'rssBytes': ProcessInfo.currentRss,
        'cumulativePeakRssBytes': ProcessInfo.maxRss,
        'actualNavigation': navigation,
      };
    } finally {
      trigger.cancel();
    }
  }

  try {
    report['pickerFirstLayout120x40'] = await measure(const Size(120, 40), () {
      shown = host.drawFrame(const Size(120, 40));
    });
    report['pickerResize80x24'] = await measure(const Size(80, 24), () {
      shown = host.drawFrame(const Size(80, 24));
    });
    report['pickerResizeBack120x40'] = await measure(const Size(120, 40), () {
      shown = host.drawFrame(const Size(120, 40));
    });
    final frames = <double>[], diffs = <double>[];
    var bytes = 0;
    report['pickerSteady120x40'] = await measure(const Size(120, 40), () {
      for (var i = 0; i < 50; i++) {
        final watch = Stopwatch()..start();
        final next = host.drawFrame(const Size(120, 40));
        frames.add(_ms(watch.elapsed));
        watch.reset();
        bytes += utf8.encode(diffBuffers(shown, next)).length;
        diffs.add(_ms(watch.elapsed));
        shown = next;
      }
    });
    report['steadyFrameCosts'] = _distribution(frames);
    report['steadyCellDiffAndUtf8Costs'] = _distribution(diffs);
    report['steadyDiffBytes'] = bytes;
  } finally {
    host.dispose();
    await root.delete(recursive: true);
    report['ownedRootRemoved'] = !await root.exists();
    report['ownedHandlesAfterCleanup'] = await _ownedHandleSnapshot(root.path);
  }
  print(const JsonEncoder.withIndent('  ').convert(report));
}

Future<void> main(List<String> args) async {
  if (args.contains('--picker-only')) {
    await _pickerProbe(args);
    return;
  }
  final small = args.contains('--small');
  final records = small ? 16 : 2000;
  final turns = small ? 20 : 4000;
  final flood = small ? 32 : 10000;
  final irrelevantBytes = small ? 1024 : 65536;
  final enormousLineBytes = small ? 4096 : 8 * 1024 * 1024;
  final allocated = await Directory.systemTemp.createTemp(
    'chord-record-scale-',
  );
  final root = Directory(await allocated.resolveSymbolicLinks());
  final pulse = Pulse();
  final report = <String, Object?>{
    'runtimeLabel':
        args
            .where((a) => a.startsWith('--runtime='))
            .firstOrNull
            ?.substring(10) ??
        'unspecified',
    'dartVersion': Platform.version.split(' on ').first,
    'pathMatching':
        'Canonical fixture root resolved before IO; relative lsof names.',
    'workload': {
      'records': records,
      'irrelevantBytesPerRecord': irrelevantBytes,
      'additionalIrrelevantLineBytes': enormousLineBytes,
      'historyTurns': turns,
      'stalledUpdates': flood,
      'updateTextBytes': 512,
      'steadyFrames': 50,
      'terminalSizes': ['120x40', '80x24'],
      'frameIntervalMs': 16,
    },
    'limits':
        'Headless build/layout/paint and synthetic Actions keys; no PTY/display/write latency. Peak RSS is cumulative. No cross-runtime speed ratio, queue cap, deadline or durability claim.',
  };
  final snapshots = <String, Object?>{};
  report['handleSnapshots'] = snapshots;
  report['handleSnapshotScope'] =
      'One immediate lsof snapshot per named stage; external command adds inter-stage time. Relative owned paths only. No polling or physical-isolate-exit inference.';
  Future<int?> handles(String stage) async {
    final snapshot = await _ownedHandleSnapshot(root.path);
    snapshots[stage] = snapshot;
    return snapshot['count'] as int?;
  }

  var pendingOperations = 0, peakOperations = 0;
  Future<T> operation<T>(Future<T> Function() body) async {
    pendingOperations++;
    peakOperations = math.max(peakOperations, pendingOperations);
    try {
      return await body();
    } finally {
      pendingOperations--;
    }
  }

  try {
    final control = await pulse.measure(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    report['measurementControl'] = control;
    if ((control['acceptedKeys'] as int) == 0) {
      throw StateError('Synthetic key did not traverse Actions');
    }
    final directory = await Directory(recordsDir(root.path)).create();
    final irrelevant = encodeRecord({
      'type': 'update',
      'ignored': 'x' * irrelevantBytes,
    });
    final setup = Stopwatch()..start();
    var scanBytes = 0;
    for (var i = 0; i < records; i++) {
      final text = [
        encodeRecord({
          'type': 'session',
          'version': 1,
          'sessionId': 'session-$i',
          'agent': 'fake',
          'cwd': '.',
          'at': i,
        }),
        irrelevant,
        if (i == 0)
          encodeRecord({'type': 'update', 'ignored': 'x' * enormousLineBytes}),
        encodeRecord({
          'type': 'prompt',
          'turnId': 't',
          'prompt': 'Saved request $i 界😀',
          'images': 0,
          'at': i + .25,
        }),
      ].join();
      scanBytes += utf8.encode(text).length;
      await File(p.join(directory.path, '$i.jsonl')).writeAsString(text);
    }
    report['setup'] = {'wallMs': _ms(setup.elapsed), 'scanBytes': scanBytes};
    final handlesBefore = await handles('beforeScan');
    var summaries = <SessionRecord>[];
    report['scan'] = await pulse.measure(() async {
      summaries = await operation(() => readRecords(root.path));
    });
    await handles('afterScan');
    if (summaries.length != records) throw StateError('Lost scan summaries');
    report['sort'] = await pulse.measure(() {
      earlierSessions(summaries, agent: 'fake');
    });
    report['cancelScan'] = await _cancelOperation(
      pulse,
      (token) =>
          operation(() => readRecords(root.path, cancellationToken: token)),
    );
    await handles('afterCancelScan');
    var active = 0, peak = 0;
    Stream<String> counted(String path) async* {
      active++;
      peak = math.max(peak, active);
      try {
        yield* recordLines(path);
      } finally {
        active--;
      }
    }

    // The same scanner seam counts actual workers/streams, separately from
    // the production isolate's wall/input measurement above.
    report['instrumentedScanner'] = await pulse.measure(() async {
      await scanRecords(root.path, lines: counted);
    });
    await handles('afterInstrumentedScanner');
    report['streamCounts'] = {
      'peak': peak,
      'retained': active,
      'workerLimit': 8,
      'scope':
          'instrumented scanner seam; physical production isolate count is unmeasured',
    };
    if (active != 0 || peak > 8) throw StateError('Retained scan streams');
    final history = File(p.join(root.path, 'long.jsonl'));
    final sink = history.openWrite();
    for (var i = 0; i < turns; i++) {
      sink.write(
        encodeRecord({
          'type': 'prompt',
          'turnId': 'turn-$i',
          'prompt': 'History request $i 界😀',
          'images': 0,
          'at': i + .5,
        }),
      );
      sink.write(
        encodeRecord({
          'type': 'update',
          'turnId': 'turn-$i',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {
              'type': 'text',
              'text': 'Reply $i with **saved text**.',
            },
          },
        }),
      );
      sink.write(
        encodeRecord({
          'type': 'result',
          'turnId': 'turn-$i',
          'result': {'status': 'completed', 'stopReason': 'end_turn'},
        }),
      );
    }
    await sink.flush();
    await sink.close();
    report['historyBytes'] = await history.length();
    var prepared = PreparedHistory.empty;
    report['prepare'] = await pulse.measure(() async {
      prepared = await operation(() => readRecordedHistory(history.path));
    });
    await handles('afterPrepare');
    if (prepared.omitted ||
        prepared.actions.whereType<model.PromptAction>().length != turns) {
      throw StateError('Lost selected history prompts');
    }
    report['cancelPrepare'] = await _cancelOperation(
      pulse,
      (token) => operation(
        () => readRecordedHistory(history.path, cancellationToken: token),
      ),
    );
    await handles('afterCancelPrepare');
    final work = ReplayWork();
    var transcript = model.Transcript.empty;
    report['fold'] = await pulse.measure(() {
      transcript = replayTranscript(prepared.actions, work: work);
    });
    report['replayWork'] = {
      'actions': prepared.actions.length,
      'entries': transcript.entries.length,
      'appended': work.appendedEntries,
      'replaced': work.replacedEntries,
      'copied': work.copiedEntries,
    };
    if (transcript.entries.length != turns * 2 ||
        work.copiedEntries != transcript.entries.length) {
      throw StateError('Replay copy mismatch');
    }
    prepared = PreparedHistory.empty;
    final scroll = ScrollController(follow: Follow.bottom);
    final host = AppHost(
      view.Transcript(
        transcript: transcript,
        controller: scroll,
        bindKeys: false,
      ),
    );
    try {
      late Buffer shown;
      report['firstLayout120x40'] = await pulse.measure(() {
        shown = host.drawFrame(const Size(120, 40));
        if (!shown.toString().contains('Reply ${turns - 1}')) {
          throw StateError(
            'The measured transcript did not draw its final reply',
          );
        }
      });
      report['firstCellDiff'] = await pulse.measure(() {
        diffBuffers(null, shown);
      });
      report['resize80x24'] = await pulse.measure(() {
        host.drawFrame(const Size(80, 24));
      });
      report['resizeBack120x40'] = await pulse.measure(() {
        shown = host.drawFrame(const Size(120, 40));
      });
      final frames = <double>[], diffs = <double>[];
      var diffBytes = 0;
      report['steady120x40'] = await pulse.measure(() {
        for (var i = 0; i < 50; i++) {
          final watch = Stopwatch()..start();
          final next = host.drawFrame(const Size(120, 40));
          frames.add(_ms(watch.elapsed));
          watch.reset();
          diffBytes += utf8.encode(diffBuffers(shown, next)).length;
          diffs.add(_ms(watch.elapsed));
          shown = next;
        }
      });
      report['steadyFrameCosts'] = _distribution(frames);
      report['steadyCellDiffAndUtf8Costs'] = _distribution(diffs);
      report['steadyDiffBytes'] = diffBytes;
    } finally {
      host.dispose();
      scroll.dispose();
    }
    await handles('afterLayout');
    final gate = Completer<void>(), began = Completer<void>();
    var appendedBytes = 0, appends = 0;
    final writer = FileRecording(
      root.path,
      failed: (message) => throw StateError(message),
      append: (path, text) async {
        appends++;
        if (!began.isCompleted) began.complete();
        await gate.future;
        appendedBytes += utf8.encode(text).length;
      },
    );
    writer.opened(
      RecordingSession(sessionId: 'stalled', agent: 'fake', cwd: '.'),
    );
    writer.sent('flood', 'stalled recording', 0, [], 1.25);
    await began.future;
    final update = acp.SessionUpdate.fromJson({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'x' * 512},
    });
    report['stalledFlood'] = await pulse.measure(() async {
      for (var i = 0; i < flood; i++) {
        writer.heard(
          Transcribed(model.UpdateAction('flood', update, at: i + .25)),
        );
        if (i % 64 == 63) await Future<void>(() {});
      }
    });
    if (writer.queuedBytes < flood * 512) {
      throw StateError('Stalled updates were lost or capped');
    }
    report['stalledAppendScope'] =
        'Injected append gate models stalled IO; drain is serialization/queue work, not a filesystem flush/durability measurement';
    report['queuedByteScope'] =
        'Serialized pending UTF-8 bytes, excluding active append and held opening';
    report['queuedByteHighWater'] = writer.queuedBytesHighWater;
    report['queuedBytesBeforeRelease'] = writer.queuedBytes;
    writer.heard(const Closing());
    gate.complete();
    report['drain'] = await pulse.measure(writer.flushed);
    report['recordingAfterDrain'] = {
      'queuedBytes': writer.queuedBytes,
      'heldBytes': writer.heldBytes,
      'appendCalls': appends,
      'appendedBytes': appendedBytes,
    };
    if (writer.queuedBytes != 0 || writer.heldBytes != 0) {
      throw StateError('Retained recorder bytes');
    }
    await handles('afterDrain');
    report['operationFutures'] = {
      'peak': peakOperations,
      'pending': pendingOperations,
    };
    report['physicalIsolateCount'] = null;
    report['physicalIsolateExitLatencyMs'] = null;
    report['cancellationLatencyScope'] =
        'request to Future settlement, not physical isolate exit';
    report['ownedHandlesBefore'] = handlesBefore;
    report['ownedHandlesAfter'] = await handles('beforeCleanup');
  } finally {
    pulse.close();
    await root.delete(recursive: true);
    report['ownedRootRemoved'] = !await root.exists();
    report['ownedHandlesAfterCleanup'] = await handles('afterCleanup');
  }
  print(const JsonEncoder.withIndent('  ').convert(report));
}

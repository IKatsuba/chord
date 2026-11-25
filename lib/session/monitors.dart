/// Monitors: a command an agent started through chord's `monitor` tool,
/// whose stdout lines reach that agent later as messages. Here are the
/// numbers the original settled, a line as an event carries it, an event's
/// caps, the flood watch, the words of an end, and what a resumed session
/// says of its monitors. From the original's `session/monitors.ts`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart' show stripAnsi;
import 'package:clock/clock.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../kept.dart';
import '../shell.dart';
import 'elapsed.dart';
import 'transcript/types.dart';

/// How long lines gather from a batch's first, fixed: never pushed back.
const batchMs = 200;

/// An event's lines at most; past them lines are counted, not sent.
const eventLinesMax = 100;

/// An event's bytes at most, so 100 long lines are not one huge turn.
const eventBytes = 16 * 1024;

/// A line's characters at most, so one minified line takes no whole event.
const lineChars = 1000;

/// A monitor printing more than these within [floodMs] is stopped.
const floodLines = 1000;
const floodBytes = 256 * 1024;
const floodMs = 10000;

/// Monitors running in a session at most, its agents' counted together.
const maxMonitors = 8;
const defaultTimeoutMs = 600000;
const minTimeoutMs = 1000;
const maxTimeoutMs = 3600000;

/// A description's characters at most: it is on every event.
const descriptionChars = 60;

/// What `monitor` was asked.
typedef MonitorArgs = ({String command, String description, num? timeoutMs});

/// A monitor started: its id in the session, and what it runs.
final class MonitorInfo {
  const MonitorInfo({
    required this.id,
    required this.description,
    required this.command,
    required this.startedAt,
    required this.timeoutMs,
  });

  /// `m1`, `m2`, … in the session's start order, across `--resume`.
  final String id;
  final String description;
  final String command;

  /// When it started, epoch milliseconds.
  final int startedAt;
  final int timeoutMs;
}

/// A batch a monitor handed on, as its background detail says it.
typedef MonitorEvent = ({List<String> lines, int at});

/// A monitor still running, as the screen's list reads it.
final class RunningMonitor {
  const RunningMonitor(this.info, {this.events = 0, this.lastEvent});

  final MonitorInfo info;

  /// The batches it has handed on so far.
  final int events;

  /// The last of them, kept as it went, the lines its end carried too; none
  /// before the first.
  final MonitorEvent? lastEvent;

  /// As `_chord/monitors/changed` carries it, the original's shape.
  Map<String, Object?> toJson() => {
    'id': info.id,
    'description': info.description,
    'command': info.command,
    'startedAt': info.startedAt,
    'timeoutMs': info.timeoutMs,
    'events': events,
    if (lastEvent case (:final lines, :final at))
      'lastEvent': {'lines': lines, 'at': at},
  };
}

/// A monitor that has ended in the session, as the background view reads
/// it: how, when, and the batches it handed on by then. The agent's own
/// `stop_monitor` and the person's `x` both end it stopped.
final class EndedMonitor extends RunningMonitor {
  const EndedMonitor(
    super.info, {
    super.events,
    super.lastEvent,
    required this.end,
    required this.endedAt,
  });

  final MonitorEnd end;

  /// When it ended, epoch milliseconds; a stop's is when it was asked.
  final int endedAt;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'end': end.toJson(),
    'endedAt': endedAt,
  };
}

/// Why `monitor` refuses what it was asked, with [running] monitors already
/// in the session; null when it may start. Refused, never clamped, so the
/// agent never thinks it has what it does not.
String? monitorRefusal(MonitorArgs args, int running) {
  if (running >= maxMonitors) {
    return 'This session has $maxMonitors monitors running; '
        'stop_monitor one first';
  }
  final description = args.description.trim();
  if (description.isEmpty ||
      description.contains(RegExp(r'[\r\n]')) ||
      description.runes.length > descriptionChars) {
    return 'description is at most $descriptionChars characters on one '
        'line; it is shown on every event';
  }
  final timeout = args.timeoutMs;
  if (timeout != null &&
      (timeout != timeout.truncate() ||
          timeout < minTimeoutMs ||
          timeout > maxTimeoutMs)) {
    return 'timeout_ms is between $minTimeoutMs and $maxTimeoutMs '
        '(${timeoutWords(maxTimeoutMs)})';
  }
  return args.command.trim().isEmpty ? 'command is empty' : null;
}

/// `10m`, `1h`, `1m 30s`: a timeout as the agent and the person read it.
String timeoutWords(int ms) =>
    formatElapsed(ms).replaceFirst(RegExp(r' 0[sm]$'), '');

/// A line as an event carries it: escapes stripped, cut past the limit.
String eventLine(String raw) {
  final characters = stripAnsi(raw).runes.toList();
  if (characters.length <= lineChars) return String.fromCharCodes(characters);
  return '${String.fromCharCodes(characters.take(lineChars))}… '
      '(+${characters.length - lineChars} characters)';
}

/// The lines of one message, and how many more there were.
final class EventLines {
  const EventLines(this.lines, this.bytes, this.dropped);

  final List<String> lines;

  /// The lines' UTF-8 bytes, a newline each.
  final int bytes;

  /// Lines past the caps, counted and not sent.
  final int dropped;
}

/// No lines yet.
const noLines = EventLines([], 0, 0);

/// [event] with [lines] after it, as many as the caps let in; the rest, and
/// [dropped] more, are counted. Once one is left out, every later one is, so
/// what is sent is the first lines, unbroken: a batch's first line is
/// usually the error, the rest its trace.
EventLines withLines(
  EventLines event,
  Iterable<String> lines, [
  int dropped = 0,
]) {
  final kept = [...event.lines];
  var bytes = event.bytes;
  var left = event.dropped;
  for (final line in lines) {
    final size = utf8.encode(line).length + 1;
    if (left > 0 || kept.length >= eventLinesMax || bytes + size > eventBytes) {
      left += 1;
    } else {
      kept.add(line);
      bytes += size;
    }
  }
  return EventLines(kept, bytes, left + dropped);
}

/// A message's text: its lines, what was not sent, then chord's sentence.
String eventText(EventLines event, [String? sentence]) => [
  ...event.lines,
  if (event.dropped != 0)
    '… ${_count(event.dropped)} more '
        '${event.dropped == 1 ? 'line' : 'lines'} not delivered '
        '(an event carries at most $eventLinesMax)',
  ?sentence,
].join('\n');

/// [value] with en-US thousands separators, as `toLocaleString` writes it.
String _count(int value) => _grouped.format(value);
final _grouped = NumberFormat.decimalPattern('en_US');

/// The lines a monitor printed within the last [floodMs], sliding, and
/// whether they are more than a monitor may print.
final class FloodWatch {
  final _seen = <({int at, int bytes})>[];
  var _start = 0;
  var _bytes = 0;

  /// A line of [bytes] came at [at]; what it floods by, if anything.
  FloodBy? add(int at, int bytes) {
    _seen.add((at: at, bytes: bytes));
    _bytes += bytes;
    while (_start < _seen.length && _seen[_start].at <= at - floodMs) {
      _bytes -= _seen[_start].bytes;
      _start += 1;
    }
    // Drop what slid out now and then, not on every line.
    if (_start > 1024 && _start * 2 > _seen.length) {
      _seen.removeRange(0, _start);
      _start = 0;
    }
    return _seen.length - _start > floodLines
        ? FloodBy.lines
        : _bytes > floodBytes
        ? FloodBy.bytes
        : null;
  }
}

/// An end as its message's header and the wrapper's `from` say it.
String endWord(MonitorEnd end) => switch (end) {
  MonitorExited(:final code) => 'exit code $code',
  MonitorKilled(:final signal) => 'killed by $signal',
  MonitorTimedOut() => 'timed out',
  MonitorStopped() => 'stopped',
  MonitorFlooded() => 'flooded',
};

/// chord's sentence for an end, last in its message, after [ranMs].
String endSentence(MonitorEnd end, int ranMs) {
  final after = formatElapsed(ranMs);
  return switch (end) {
    MonitorExited(:final code) =>
      'Exited with code $code${switch (code) {
        127 => ' (command not found)',
        126 => ' (not executable)',
        _ => '',
      }} after $after.',
    MonitorKilled(:final signal) => 'Killed by $signal after $after.',
    MonitorTimedOut(:final timeoutMs) =>
      'Timed out after ${timeoutWords(timeoutMs)} '
          '(timeout_ms $timeoutMs); chord stopped it.',
    MonitorStopped() => 'The person stopped it after $after.',
    MonitorFlooded(:final by) =>
      'chord stopped it: ${by == FloodBy.lines ? '${_count(floodLines)} lines' : '${floodBytes ~/ 1024} KiB'} '
          'in ${floodMs ~/ 1000}s is more than a monitor may print. Filter '
          'its output (grep --line-buffered) and start it again.',
  };
}

/// [names] joined as en-GB's conjunction list writes them: `a, b and c`.
String _andList(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// The note after a resumed past that names the monitors it left running.
String leftRunningLine(List<PastMonitor> monitors) {
  final one = monitors.length == 1;
  return '${_andList([for (final m in monitors) m.description])} '
      '${one ? 'was' : 'were'} running when this session was left and '
      '${one ? 'is' : 'are'} not restarted';
}

/// What chord tells a resumed session's agent of the monitors it left
/// running, which stopped with it and which nothing restarts, so that it can
/// start them again.
String leftStoppedNote(List<PastMonitor> monitors) {
  final one = monitors.length == 1;
  final them = one ? 'it' : 'them';
  final names = _andList([
    for (final m in monitors) '${m.id} (${m.description})',
  ]);
  return 'Your monitor${one ? '' : 's'} $names ${one ? 'was' : 'were'} '
      'running when this session was left. chord stopped $them then, and '
      'nothing restarts $them; start $them again with monitor if you still '
      'need $them.';
}

/// What a session's past says of its monitors.
final class MonitorsPast {
  const MonitorsPast({
    this.last = 0,
    this.ended = const {},
    this.left = const [],
  });

  /// A past with no monitors.
  static const none = MonitorsPast();

  /// The highest id's number, which the next one goes on from.
  final int last;

  /// How each that ended did, by id, as its end's word says it.
  final Map<String, String> ended;

  /// Those running when it was left, in start order, which nothing
  /// restarts.
  final List<PastMonitor> left;
}

/// The monitors a session's past started, from the `monitor` calls chord
/// served, and how each ended: an end message, or the agent's own
/// `stop_monitor`. One with neither was running when the session was left,
/// as a close or a quit stops monitors without a word.
MonitorsPast monitorsPast(List<TranscriptAction> actions) {
  final started = <PastMonitor>[];
  final ended = <String, String>{};
  for (final action in actions) {
    switch (action) {
      case ServedAction(
        call: ChordCall(
          error: null,
          :final tool,
          answer: {'id': final String id} && final answer,
        ),
      ):
        if (tool == ChordTool.monitor && answer['description'] is String) {
          started.add((id: id, description: answer['description'] as String));
        } else if (tool == ChordTool.stopMonitor) {
          ended[id] = 'stopped';
        }
      case PromptAction(
        from: MessageFrom(monitor: (:final id, end: final end?)),
      ):
        ended[id] = endWord(end);
      default:
    }
  }
  return MonitorsPast(
    last: started.fold(
      0,
      (last, monitor) =>
          math.max(last, int.tryParse(monitor.id.substring(1)) ?? 0),
    ),
    ended: ended,
    left: [
      for (final monitor in started)
        if (!ended.containsKey(monitor.id)) monitor,
    ],
  );
}

/// Starts a monitor's command, handing on each stdout line.
typedef RunCommand =
    ShellProcess Function(
      String command,
      String cwd,
      void Function(String line) onLine,
    );

/// Through the person's shell, stderr dropped, as `lib/shell.dart` runs it,
/// and whatever it started gone when it ends.
ShellProcess runMonitorCommand(
  String command,
  String cwd,
  void Function(String line) onLine,
) => runShell(command, ShellOptions(cwd: cwd, onLine: onLine, reap: true));

/// Where a running monitor's batches and its end go.
abstract interface class MonitorHooks {
  /// A batch, gathered over [batchMs], ready to go to the agent.
  void event(EventLines lines);

  /// It ended on its own, by its timeout, a flood or the person's stop,
  /// with the lines not handed on yet; never after a silent stop.
  void ended(MonitorEnd end, EventLines rest);
}

/// Who stops a monitor: the person says so; the agent and a close do not.
enum StoppedBy { person, agent, close }

/// Why chord stopped a run: an end the agent is told of, or none.
sealed class _Stopping {
  const _Stopping();
}

final class _Told extends _Stopping {
  const _Told(this.end);
  final MonitorEnd end;
}

final class _Silent extends _Stopping {
  const _Silent();
}

/// One monitor's command, running: its lines batched over a fixed window,
/// the flood watched, its timeout kept, and its end told once.
final class MonitorRun {
  MonitorRun._(this.info, this._hooks, String cwd, RunCommand run) {
    _process = run(info.command, cwd, _line);
    _timeout = Timer(
      Duration(milliseconds: info.timeoutMs),
      () => _stop(_Told(MonitorTimedOut(info.timeoutMs))),
    );
    // Its end is heard only once whether it started is known: a shell that
    // did not start is the call's refusal, and no end follows it.
    unawaited(_known.future.then((_) => _process.exited).then(_exited));
    _end = Kept(_known.future.then((_) => _process.ended).then(_ended));
  }

  final _known = Completer<void>();

  /// Starts [info]'s command: the run, or `({String error})` when its shell
  /// does not start, which is the call's refusal.
  ///
  /// Dart starts a process asynchronously, so the answer waits for the
  /// shell to start or fail, as the original's spawn knows at once.
  /// [spawned] has the run at once, so a close can stop it while it starts.
  static Future<Object> start(
    MonitorInfo info,
    MonitorHooks hooks,
    String cwd, {
    RunCommand run = runMonitorCommand,
    void Function(MonitorRun run)? spawned,
  }) async {
    final monitor = MonitorRun._(info, hooks, cwd, run);
    spawned?.call(monitor);
    final failed = await monitor._process.failed;
    if (failed != null) {
      monitor._stopping = const _Silent();
      monitor._timeout.cancel();
      monitor._flush?.cancel();
    }
    monitor._known.complete();
    return failed == null
        ? monitor
        : (error: 'Could not start the command: $failed');
  }

  final MonitorInfo info;
  final MonitorHooks _hooks;
  final _flood = FloodWatch();
  late final ShellProcess _process;
  late final Timer _timeout;
  var _events = 0;
  MonitorEvent? _last;
  EventLines? _batch;
  Timer? _flush;

  /// Why chord stopped it.
  _Stopping? _stopping;

  /// How its shell ended, while what that shell started is being reaped.
  MonitorEnd? _exit;

  // Kept: a close in another error zone may wait for it (CTUI-114).
  late final Kept<void> _end;

  /// Settles once its command and all it started are gone.
  Future<void> get ended => _end.future;

  /// It as the screen's list reads it.
  RunningMonitor get running =>
      RunningMonitor(info, events: _events, lastEvent: _last);

  /// Stops it and all it started; the person's stop is told to the agent.
  void stop(StoppedBy by) => _stop(
    by == StoppedBy.person ? const _Told(MonitorStopped()) : const _Silent(),
  );

  void _stop(_Stopping why) {
    // Its shell's end is told already; only a silent stop takes its place.
    if (_stopping != null || (_exit != null && why is! _Silent)) return;
    _stopping = why;
    _timeout.cancel();
    _flush?.cancel();
    _process.stop();
  }

  void _line(String raw) {
    if (_stopping != null) return;
    final flooded = _flood.add(_now(), utf8.encode(raw).length + 1);
    // The line that flooded goes in the sample, which shows what to filter.
    _batch = withLines(_batch ?? noLines, [eventLine(raw)]);
    if (flooded != null) {
      _stop(_Told(MonitorFlooded(flooded)));
      return;
    }
    _flush ??= Timer(const Duration(milliseconds: batchMs), () {
      final batch = _batch;
      _flush = null;
      _batch = null;
      if (batch != null && _stopping == null) {
        _events += 1;
        _last = (lines: batch.lines, at: _now());
        _hooks.event(batch);
      }
    });
  }

  /// Its shell has ended, by itself unless chord stopped it: that is the
  /// end the agent hears, whatever its leftovers take to go, so no timeout
  /// or flood while they are reaped replaces it. Lines still in the pipe
  /// are batched as before.
  void _exited(ShellEnd end) {
    if (_stopping != null || _exit != null) return;
    _timeout.cancel();
    _exit = _endOfShell(end);
  }

  void _ended(ShellEnd end) {
    _timeout.cancel();
    _flush?.cancel();
    final why = _stopping;
    final rest = _batch ?? noLines;
    _stopping = const _Silent();
    _batch = null;
    if (why is _Silent) return;
    // What its end carries is the last it said.
    if (rest.lines.isNotEmpty) _last = (lines: rest.lines, at: _now());
    _hooks.ended(switch (why) {
      _Told(:final end) => end,
      _ => _exit ?? _endOfShell(end),
    }, rest);
  }
}

int _now() => clock.now().millisecondsSinceEpoch;

MonitorEnd _endOfShell(ShellEnd end) => switch (end.signal) {
  // A status that could not be read has no code; it ended all the same.
  null => MonitorExited(end.code ?? 1),
  final signal => MonitorKilled(signal),
};

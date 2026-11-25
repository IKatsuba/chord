import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:cancellation_token/cancellation_token.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'agent_state.dart';
import 'config.dart';
import 'context.dart';
import 'conversation.dart';
import 'models.dart';
import 'modes.dart';
import 'questions.dart' show withoutSecrets;
import 'sign_in.dart' show recordedSignIn;
import 'transcript/subagents.dart' show taskMetaKey;
import 'transcript/types.dart';

/// The directory of version-1 session records; legacy windows stay untouched.
String recordsDir(String stateDir) => p.join(stateDir, 'records');

/// chord's own id for the record at [path]: its file name without .jsonl.
String recordId(String path) => p.basenameWithoutExtension(path);

/// A fresh filename independent of the agent's literal session id.
String newRecordPath(String stateDir, {String Function()? uuid}) =>
    p.join(recordsDir(stateDir), '${(uuid ?? const Uuid().v4)()}.jsonl');

/// The original parser accepts any valid JSON, including an unterminated line.
/// Keeping raw values separate makes parsed presence independent of projection.
List<Object?> parseRecord(String text) => [
  for (final line in text.split('\n'))
    if (_parseLine(line) case (true, final value)) value,
];

(bool, Object?) _parseLine(String line) {
  try {
    return (true, jsonDecode(line));
  } on FormatException {
    return (false, null);
  }
}

/// Reads with Node's replacement UTF-8 policy, including a final partial line.
Stream<String> recordLines(String path) => File(path)
    .openRead()
    .transform(const Utf8Decoder(allowMalformed: true))
    .transform(const LineSplitter());

/// Reads a selected past off the UI isolate; cancellation kills its worker.
Future<List<Object?>> readPast(
  String path, {
  CancellationToken? cancellationToken,
}) => CancellableIsolate.run(() async {
  try {
    return parseRecord(
      await File(
        path,
      ).readAsString(encoding: const Utf8Codec(allowMalformed: true)),
    );
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode == 2) return <Object?>[];
    rethrow;
  }
}, cancellationToken);

/// A detached immutable raw view; unknown keys and nested metadata survive.
final class RecordEntry {
  RecordEntry(Map<String, Object?> json)
    : json = _freeze(json) as Map<String, Object?>;

  final Map<String, Object?> json;
  String get type => json['type'] as String;

  /// Supported shapes are checked individually, never trusted casts from disk.
  static RecordEntry? view(Object? value) {
    if (value is! Map<String, Object?> || value['type'] is! String) return null;
    bool string(String key) => value[key] is String;
    bool number(String key) =>
        value[key] is num && (value[key] as num).isFinite;
    final valid = switch (value['type']) {
      'session' =>
        value['version'] == 1 &&
            string('sessionId') &&
            string('agent') &&
            string('cwd') &&
            number('at'),
      'prompt' =>
        string('turnId') &&
            string('prompt') &&
            number('at') &&
            number('images') &&
            (value['into'] == null || string('into')),
      'update' =>
        string('turnId') &&
            value['update'] is Map<String, Object?> &&
            (value['at'] == null || number('at')),
      'result' =>
        string('turnId') && RecordedResult.view(value['result']) != null,
      'served' || 'ran' =>
        string('turnId') &&
            ChordCall.fromJson(value['call']) != null &&
            (value['subagentId'] == null || string('subagentId')),
      'closed' => string('agent'),
      'cancel' => string('turnId') && number('at'),
      'stopping' => string('subagentId') && value['stopping'] is bool,
      'self_started' => string('turnId'),
      'forked' => string('turnId') && string('from') && number('at'),
      'opened' || 'disconnected' => number('at'),
      'state' => value['options'] is Map<String, Object?>,
      'renamed' => string('title') && number('at'),
      'usage' => string('turnId') && value['usage'] is Map<String, Object?>,
      'asked' => string('turnId') && elicitationWaitFrom(value['wait']) != null,
      'answered' =>
        string('turnId') &&
            string('id') &&
            elicitationAnswerFrom(value['answer']) != null,
      'plan_asked' =>
        string('turnId') && PlanWait.fromJson(value['wait']) != null,
      'plan_answered' =>
        string('turnId') &&
            string('id') &&
            PlanAnswer.fromJson(value['answer']) != null,
      _ => true,
    };
    return valid ? RecordEntry(value) : null;
  }
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry(key, _freeze(value))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};

/// Compact, type-first JSONL required by the original streaming summary reader.
String encodeRecord(Map<String, Object?> entry) {
  final type = entry['type'];
  if (type is! String) throw ArgumentError('A record line needs a type.');
  return '${jsonEncode({'type': type, for (final item in entry.entries)
    if (item.key != 'type') item.key: item.value})}\n';
}

/// A saved result keeps status independently of reason and error code as text.
final class RecordedResult {
  const RecordedResult._(
    this.status, {
    this.stopReason,
    this.message,
    this.code,
    this.signIn,
  });
  final String status;
  final String? stopReason, message, code;

  /// A failed turn's sign-in as written, without its account.
  final Map<String, Object?>? signIn;

  bool get omittedDetail => code != null && int.tryParse(code!) == null;

  static RecordedResult? view(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final status = value['status'];
    if ((status == 'completed' || status == 'cancelled') &&
        value['stopReason'] is String) {
      return RecordedResult._(
        status as String,
        stopReason: value['stopReason'] as String,
      );
    }
    if (value['error'] case final Map<String, Object?> error
        when status == 'failed') {
      if (error['message'] is! String ||
          (error['code'] != null && error['code'] is! String)) {
        return null;
      }
      return RecordedResult._(
        'failed',
        message: error['message'] as String,
        code: error['code'] as String?,
        signIn: switch (error['signIn']) {
          final Map<String, Object?> signIn => signIn,
          _ => null,
        },
      );
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'status': status,
    if (status == 'failed')
      'error': {
        'message': message,
        if (code != null) 'code': code,
        'signIn': ?signIn,
      }
    else
      'stopReason': stopReason,
  };
}

/// Live turn results use the original nested error representation on disk.
Map<String, Object?> recordResult(TurnResult result) => switch (result) {
  TurnAnswered() => {
    'status': result.cancelled ? 'cancelled' : 'completed',
    'stopReason': result.stopReason,
  },
  TurnFailed() => {
    'status': 'failed',
    'error': {
      'message': result.message,
      if (result.recordedCode != null || result.code != null)
        'code': result.recordedCode ?? '${result.code}',
      if (result.signIn case final signIn?) 'signIn': recordedSignIn(signIn),
    },
  },
};

final _space = RegExp(r'\s+', unicode: true);
final _teamLabel = RegExp(
  r'^<team name="([^"]*)" role="(?:lead|member)"(?: member="([^"]*)")?>\n([\s\S]*?)\n</team>\n(?=<message )',
);
final _messageLabel = RegExp(
  r'^<message from="([^"]*)"(?: monitor="([^"]*)")?>\n([\s\S]*)\n</message>$',
);
final _aheadLabel = RegExp(
  r'^<message from="([^"]*)"(?: monitor="[^"]*")?>\n[\s\S]*?\n</message>\n\n',
);
final _onlyAsideLabel = RegExp(
  r'^<message from="chord">\n[\s\S]*?\n</message>',
);

/// Removes chord-only preambles without treating another sender as the person.
String withoutChordAsides(String prompt) {
  final kept = StringBuffer();
  var rest = prompt;
  while (true) {
    final ahead = _aheadLabel.firstMatch(rest);
    if (ahead == null) break;
    if (ahead[1] != 'chord') kept.write(ahead[0]);
    rest = rest.substring(ahead.end);
  }
  return '$kept$rest';
}

/// The typed text, or first shell command for a context-only prompt, on one line.
String promptLine(String prompt) {
  // Discovery reads child labels, but restores none of their runtime state.
  final withoutAsides = withoutChordAsides(prompt);
  final message = wrappedPromptText(prompt);
  if (message != null) return message.replaceAll(_space, ' ').trim();
  final split = splitContext(withoutAsides);
  final typed = split.text.trim().isEmpty && split.runs.isNotEmpty
      ? '!${split.runs.first.command}'
      : split.text;
  return typed.replaceAll(_space, ' ').trim();
}

/// The facts captured when an owned session successfully opens.
final class RecordingSession {
  const RecordingSession({
    required this.sessionId,
    required this.agent,
    required this.cwd,
    this.state = AgentState.empty,
    this.record,
    this.history = const [],
  });
  final String sessionId, agent, cwd;
  final AgentState state;
  final String? record;
  final List<Map<String, Object?>> history;
}

/// Ordered admitted conversation history; disk writes never delay agent IO.
abstract interface class Recording {
  void opened(RecordingSession session);
  void sent(
    String turnId,
    String prompt,
    num images,
    List<Map<String, Object?>> links,
    num at, {
    List<Map<String, Object?>> resources = const [],
    String? into,
    MessageFrom? from,
  });
  void heard(ConversationEvent event);
  Future<void> flushed();
}

/// A recording that can hand out a writer bound to the record open now,
/// for a receipt that comes after the session moved on.
abstract interface class ServedCapture {
  /// A writer of `served` lines to the record genuinely open now, never a
  /// replacement's; none before one is. The record is kept from now, as an
  /// admitted attempt is history even when no prompt was sent.
  void Function(String turnId, ChordCall call)? captureServed();
}

/// Appends a rename the agent has not taken yet to the record at [path],
/// for a session `chord acp` renamed while it was not loaded: the next load
/// or resume sends it.
Future<void> recordPendingRename(
  String path,
  String title,
  num at, {
  RecordAppend append = _appendRecord,
}) => append(
  path,
  encodeRecord({'type': 'renamed', 'title': title, 'at': at, 'pending': true}),
);

/// One append operation; the default creates the destination's directory first.
typedef RecordAppend = Future<void> Function(String path, String text);

Future<void> _appendRecord(String path, String text) async {
  await Directory(p.dirname(path)).create(recursive: true);
  await File(path).writeAsString(text, mode: FileMode.append);
}

Map<String, Object?> _recordState(AgentState state) => {
  'type': 'state',
  'model': ?modelsFrom(state.configOptions, state.models)?.current,
  'mode': ?modesFrom(state.configOptions, state.modes)?.current,
  'options': {
    for (final option in optionsFromConfigOptions(state.configOptions))
      option.id: option.current,
  },
};

/// An agent another started, as its record's header names it: the session
/// that started it, by the agent's id, read as the record opens; its name;
/// and chord's id for it, a task's or a long-lived agent's.
final class RecordChild {
  const RecordChild({
    required this.parent,
    required this.name,
    this.task,
    this.id,
    this.team,
  });

  /// The agent's id for the session that started it, once that is open.
  final String? Function() parent;

  /// A long-lived agent's name, or a task's, which `/resume` says it by.
  final String name;

  /// A task agent's: chord's id for it, which its parent's record keeps its
  /// block under, so the parent resumed draws the task's work from here.
  final String? task;

  /// A long-lived agent's: chord's id for it, as `open_agent` answered it,
  /// which its parent's record names it by.
  final String? id;

  /// A team's lead's: the team it runs, by its file's name, so its parent
  /// resumed counts its run from here.
  final String? team;
}

/// A process-owned drain shared by all successive main sessions.
/// Held openings disappear on clear; queued lines always keep their own path.
final class FileRecording implements Recording, ServedCapture {
  FileRecording(
    this.stateDir, {
    required this._failed,
    num Function()? now,
    this._uuid,
    RecordAppend? append,
    this.child,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _append = append ?? _appendRecord;

  final String stateDir;

  /// The agent another started whose record this is; none for main's.
  final RecordChild? child;
  final void Function(String message) _failed;
  final num Function() _now;
  final String Function()? _uuid;
  final RecordAppend _append;
  String? _path;
  List<String> _held = [];
  final List<({String path, String line})> _queue = [];
  final Set<String> _admitted = {};

  /// The last turn prompted in the opened session.
  String? _lastTurn;

  /// The records of sessions let go, by their last turn: what they still
  /// say they cost goes there.
  final _retiredPaths = <String, String>{};
  var _prompted = false, _closed = false, _reported = false, _flushing = false;

  /// Whether the opened session's record existed before this opening.
  var _reopened = false;
  String _state = '';
  var _queuedBytes = 0, _queuedBytesHighWater = 0;

  /// Largest pending byte count observed, excluding the active append.
  int get queuedBytesHighWater => _queuedBytesHighWater;
  Future<void> _writing = Future.value();

  /// The currently opened destination, independent of queued retired writes.
  String? get path => _path;

  /// Bytes awaiting disk, excluding an append already in progress.
  int get queuedBytes => _queuedBytes;

  /// Bytes held until the first submitted prompt in the current opening.
  int get heldBytes =>
      _held.fold(0, (sum, line) => sum + utf8.encode(line).length);

  @override
  void opened(RecordingSession session) {
    if (_closed) return;
    _path = session.record ?? newRecordPath(stateDir, uuid: _uuid);
    _reopened = session.record != null;
    _held = [];
    _prompted = false;
    _admitted.clear();
    // A form asked in the session let go is never answered into the next.
    _asking.clear();
    final state = _recordState(session.state);
    _state = encodeRecord(state);
    // Snapshot now: a caller may mutate raw maps before the prompt releases IO.
    if (session.record == null) {
      final child = this.child;
      _add({
        'type': 'session',
        'version': 1,
        'sessionId': session.sessionId,
        'agent': session.agent,
        'cwd': session.cwd,
        'at': _now(),
        'parent': ?child?.parent(),
        'name': ?child?.name,
        'task': ?child?.task,
        'id': ?child?.id,
        'team': ?child?.team,
      });
      for (final entry in session.history) {
        _add(entry);
      }
    }
    _add({'type': 'opened', 'at': _now()});
    _add(state);
  }

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
  }) {
    if (_closed || _path == null) return;
    // Encode before releasing the held prefix so admission snapshots are atomic.
    final line = encodeRecord({
      'type': 'prompt',
      'turnId': turnId,
      'at': at,
      'prompt': prompt,
      'images': images,
      'into': ?into,
      'from': ?from?.toJson(),
      if (links.isNotEmpty) 'links': links,
      if (resources.isNotEmpty)
        'resources': [
          for (final resource in resources)
            {'uri': resource['uri'], 'mimeType': ?resource['mimeType']},
        ],
    });
    if (into == null) _admitted.add(turnId);
    if (into == null) _lastTurn = turnId;
    _begun();
    _enqueue(_path!, line);
    _flush();
  }

  @override
  void heard(ConversationEvent event) {
    if (event is RetiredUpdate || event is RetiredUsage) {
      _retiredLine(event);
      return;
    }
    if (_closed) return;
    if (event is Closing) {
      _closed = true;
      _retire();
      return;
    }
    if (event is Cleared) {
      _retire();
      return;
    }
    if (_path == null) return;
    if (event case RanTyped(:final turnId, :final call)) {
      _add({'type': 'ran', 'turnId': turnId, 'call': call.toJson()});
    } else if (event case AgentClosed(:final id)) {
      _add({'type': 'closed', 'agent': id});
    } else if (event is Renamed) {
      // A rename is work on a record that exists, not a mere look: it keeps
      // what was held for it, in order, as a prompt does; a new session's
      // rename alone keeps none.
      if (_reopened) _begun();
      _add({'type': 'renamed', 'title': event.title, 'at': event.at});
    } else if (event is AgentStateChanged) {
      final state = _recordState(event.state);
      final line = encodeRecord(state);
      if (_state != line) {
        _state = line;
        _addEncoded(line);
      }
    } else if (event is Transcribed) {
      // The agent's own cycle is work the session spent on, as a prompt's
      // turn is, though nobody sent one; it writes no line of its own.
      if (event.action case CycleStartedAction(:final turnId)) {
        _admitted.add(turnId);
        _lastTurn = turnId;
        _begun();
      }
      final entry = switch (event.action) {
        ForkedAction(:final turnId, :final from, :final at) => {
          'type': 'forked',
          'turnId': turnId,
          'from': from,
          'at': at,
        },
        SelfStartedAction(:final turnId, :final from) => {
          'type': 'self_started',
          'turnId': turnId,
          'from': ?from?.toJson(),
        },
        ServedAction(:final turnId, :final call, :final subagentId) => {
          'type': 'served',
          'turnId': turnId,
          'call': call.toJson(),
          'subagentId': ?subagentId,
        },
        UpdateAction(
          :final turnId,
          :final update,
          :final at,
          :final unasked,
          :final subagentId,
        ) =>
          {
            'type': 'update',
            'turnId': turnId,
            'update': update.toJson(),
            'subagentId': ?subagentId,
            'at': ?at,
            if (unasked) 'unasked': true,
          },
        CancelAction(:final turnId, :final at)
            when _admitted.contains(turnId) =>
          {'type': 'cancel', 'turnId': turnId, 'at': at},
        SubagentStoppingAction(:final subagentId, :final stopping) => {
          'type': 'stopping',
          'subagentId': subagentId,
          'stopping': stopping,
        },
        DisconnectedAction(:final at) when at != null => {
          'type': 'disconnected',
          'at': at,
        },
        ResultAction(:final turnId, :final result)
            when _admitted.remove(turnId) =>
          {'type': 'result', 'turnId': turnId, 'result': recordResult(result)},
        UsageAction(:final figures) => {'type': 'usage', ...figures.toJson()},
        ElicitationRequestedAction(:final turnId, :final elicitation) => _asked(
          turnId,
          elicitation,
        ),
        ElicitationSettledAction(:final turnId, :final id, :final answer) =>
          _answered(turnId, id, answer),
        PlanRequestedAction(:final turnId, :final plan) => {
          'type': 'plan_asked',
          'turnId': turnId,
          'wait': plan.toJson(),
        },
        PlanSettledAction(:final turnId, :final id, :final answer) => {
          'type': 'plan_answered',
          'turnId': turnId,
          'id': id,
          'answer': answer.toJson(),
        },
        _ => null,
      };
      if (entry != null) _add(entry);
    }
    _flush();
  }

  /// The forms and links whose ask line was written, by id.
  final _asking = <String, ElicitationWait>{};

  Map<String, Object?> _asked(String turnId, ElicitationWait wait) {
    _asking[wait.id] = wait;
    return {
      'type': 'asked',
      'turnId': turnId,
      'wait': elicitationWaitJson(wait),
    };
  }

  /// An answer's line, once its ask's line was written. A form no
  /// adapter's marks read can ask for anything, a token among it, with
  /// nothing to say which value is one: none of its values reaches the
  /// file. Of a form whose questions chord read, what was given for a
  /// secret question is left out.
  Map<String, Object?>? _answered(
    String turnId,
    String id,
    ElicitationAnswer answer,
  ) {
    final wait = _asking.remove(id);
    if (wait == null) return null;
    return {
      'type': 'answered',
      'turnId': turnId,
      'id': id,
      'answer': elicitationAnswerJson(switch ((answer, wait)) {
        (ElicitationAccepted(:final content?), FormWait(:final questions)) =>
          ElicitationAccepted(
            questions == null ? null : withoutSecrets(questions, content),
          ),
        _ => answer,
      }),
    };
  }

  /// A line of a session let go, into its own record only.
  void _retiredLine(ConversationEvent event) {
    final (turnId, entry) = switch (event) {
      RetiredUpdate(:final turnId, :final update) => (
        turnId,
        {'type': 'update', 'turnId': turnId, 'update': update.toJson()},
      ),
      RetiredUsage(:final figures) => (
        figures.turnId,
        {'type': 'usage', ...figures.toJson()},
      ),
      _ => (null, null),
    };
    final path = turnId == null ? null : _retiredPaths[turnId];
    if (path == null || entry == null) return;
    _enqueue(path, encodeRecord(entry));
    _flush();
  }

  void _retire() {
    // Its last turn may still say what it cost, into this record.
    final path = _path, last = _lastTurn;
    if (path != null && last != null && _prompted) _retiredPaths[last] = path;
    _lastTurn = null;
    _path = null;
    _held = [];
    _admitted.clear();
    // A form asked in the session let go is never answered into the next.
    _asking.clear();
    _prompted = false;
  }

  /// Work began in the session: what was held for it is kept from now.
  @override
  void Function(String turnId, ChordCall call)? captureServed() {
    final path = _path;
    if (path == null) return null;
    _begun();
    _flush();
    return (turnId, call) {
      _enqueue(
        path,
        encodeRecord({
          'type': 'served',
          'turnId': turnId,
          'call': call.toJson(),
        }),
      );
      _flush();
    };
  }

  void _begun() {
    if (_prompted) return;
    _prompted = true;
    for (final held in _held) {
      _enqueue(_path!, held);
    }
    _held = [];
  }

  void _add(Map<String, Object?> entry) => _addEncoded(encodeRecord(entry));

  void _addEncoded(String line) {
    if (_path == null) return;
    if (_prompted) {
      _enqueue(_path!, line);
    } else {
      _held.add(line);
    }
  }

  void _enqueue(String path, String line) {
    _queue.add((path: path, line: line));
    _queuedBytes += utf8.encode(line).length;
    if (_queuedBytes > _queuedBytesHighWater) {
      _queuedBytesHighWater = _queuedBytes;
    }
  }

  void _flush() {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    _writing = _writing.then((_) async {
      try {
        while (_queue.isNotEmpty) {
          final batch = List.of(_queue);
          _queue.clear();
          _queuedBytes = 0;
          final paths = <String, StringBuffer>{};
          for (final item in batch) {
            (paths[item.path] ??= StringBuffer()).write(item.line);
          }
          for (final entry in paths.entries) {
            await _append(entry.key, entry.value.toString());
          }
        }
      } catch (error) {
        // A partial append is uncertain; neither its batch nor pending lines retry.
        _queue.clear();
        _queuedBytes = 0;
        if (!_reported) {
          _reported = true;
          try {
            _failed("Could not keep this session's record: $error");
          } catch (_) {
            // A warning observer cannot break transport admission or the drain.
          }
        }
      } finally {
        _flushing = false;
        // A warning callback can synchronously admit a fresh retry.
        _flush();
      }
    });
  }

  @override
  Future<void> flushed() async {
    while (true) {
      final writing = _writing;
      await writing;
      if (identical(writing, _writing) && !_flushing) return;
    }
  }
}

/// A legacy message wrapper's text, for discovery and deferred-history detection.
String? wrappedPromptText(String prompt) => _wrapped(prompt)?.group(3);

/// Who a wrapped message is from, as the original's `unwrapMessage` reads
/// the wrapper: a monitor's by its id, else the sender's name with its
/// runtime and a task's note; null for a prompt that is no message.
Map<String, Object?>? wrappedPromptFrom(String prompt) {
  final match = _wrapped(prompt);
  if (match == null) return null;
  final [name, runtime, note, ...] = [
    ...match.group(1)!.replaceAll('&quot;', '"').split(' · '),
    null,
    null,
  ];
  return switch (match.group(2)) {
    final monitor? => {
      'name': name,
      'monitor': {'id': monitor},
    },
    null => {
      'name': name,
      'runtime': ?runtime,
      if (note == 'report' || note == 'failed') 'note': note,
    },
  };
}

/// The team part that went ahead of a wrapped message, which a team's lead
/// or member got first; none for any other prompt.
TeamPart? wrappedPromptTeam(String prompt) {
  if (_wrapped(prompt) == null) return null;
  final team = _teamLabel.firstMatch(_candidate(prompt));
  return team == null
      ? null
      : (team: team.group(1)!, member: team.group(2), text: team.group(3)!);
}

String _candidate(String prompt) => withoutChordAsides(prompt).isEmpty
    ? (_onlyAsideLabel.firstMatch(prompt)?.group(0) ?? prompt)
    : prompt;

RegExpMatch? _wrapped(String prompt) {
  final candidate = _candidate(prompt);
  final team = _teamLabel.firstMatch(candidate);
  return _messageLabel.firstMatch(
    team == null ? candidate : candidate.substring(team.end),
  );
}

/// The pasts of the task agents among a session's [children], as
/// [childPasts] read them, by chord's id for each task.
Map<String, List<Object?>> taskPasts(List<List<Object?>> children) => {
  for (final entries in children)
    if (entries.firstOrNull case {'type': 'session', 'task': final String task})
      task: entries,
};

/// The pasts of the team runs among a session's [children], as
/// [childPasts] read them: their leads' records, by chord's id for each
/// lead.
Map<String, List<Object?>> runPasts(List<List<Object?>> children) => {
  for (final entries in children)
    if (entries.firstOrNull case {
      'type': 'session',
      'team': String _,
      'id': final String id,
    })
      id: entries,
};

/// How much of a record is read at a time for its header: most fit in one,
/// and a longer one, a task's long description in its name, is read on to
/// its end.
const _headerChunk = 4 * 1024;

/// The records in [dir] of the agents session [parentId] started, by the
/// agent's id for it. Only each record's first line is read to know whose
/// it is, and only a child's is read whole, as the directory holds every
/// session's records, some of them large. A record that has gone, or whose
/// first line is cut short, is not among them.
Future<List<List<Object?>>> childPasts(String dir, String parentId) async {
  final List<FileSystemEntity> files;
  try {
    files = await Directory(dir).list(followLinks: false).toList();
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode == 2) return [];
    rethrow;
  }
  final children = <List<Object?>>[];
  for (final file in files) {
    if (file is! File || !file.path.endsWith('.jsonl')) continue;
    final header = await _readHeader(file);
    if (header is! Map<String, Object?> ||
        header['type'] != 'session' ||
        header['parent'] != parentId) {
      continue;
    }
    final String text;
    try {
      text = await file.readAsString(
        encoding: const Utf8Codec(allowMalformed: true),
      );
    } on FileSystemException catch (error) {
      // Gone between its header and its whole read.
      if (error.osError?.errorCode == 2) continue;
      rethrow;
    }
    final entries = parseRecord(text);
    if (entries.isNotEmpty) children.add(entries);
  }
  return children;
}

/// [file]'s first line, read alone however long; none when the file has
/// gone or that line is no JSON.
Future<Object?> _readHeader(File file) async {
  final RandomAccessFile handle;
  try {
    handle = await file.open();
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode == 2) return null;
    rethrow;
  }
  try {
    final bytes = BytesBuilder(copy: false);
    while (true) {
      final chunk = await handle.read(_headerChunk);
      final newline = chunk.indexOf(0x0a);
      bytes.add(newline < 0 ? chunk : chunk.sublist(0, newline));
      // A file that ends with no newline is its first line whole.
      if (newline >= 0 || chunk.isEmpty) break;
    }
    final line = const Utf8Decoder(
      allowMalformed: true,
    ).convert(bytes.takeBytes());
    return switch (parseRecord(line)) {
      [final header] => header,
      _ => null,
    };
  } finally {
    await handle.close();
  }
}

/// [entries], a parent's record, with each task's work put back from the
/// task's own record in [tasks], after the line that started its block, as
/// the parent's record keeps only the block's start and end: the task's
/// updates and the calls chord served it go under the task's id, its own
/// subagents' under theirs, as they were relayed live. A task whose record
/// has gone keeps the bare block, marked so its ending does not count work
/// it no longer has.
List<Object?> withTaskWork(
  List<Object?> entries,
  Map<String, List<Object?>> tasks,
) {
  final placed = <String>{};
  final out = <Object?>[];
  for (final entry in entries) {
    final id = _taskStarted(entry);
    if (id == null || !placed.add(id)) {
      out.add(entry);
      continue;
    }
    entry as Map<String, Object?>;
    final own = tasks[id];
    if (own == null) {
      final update = entry['update'] as Map<String, Object?>;
      final meta = update['_meta'] as Map<String, Object?>;
      out.add({
        ...entry,
        'update': {
          ...update,
          '_meta': {
            ...meta,
            taskMetaKey: {...meta[taskMetaKey] as Map, 'workLost': true},
          },
        },
      });
      continue;
    }
    out.add(entry);
    for (final each in own) {
      if (each case {
        'type': 'update' || 'served',
      } when each is Map<String, Object?>) {
        out.add({
          ...each,
          'turnId': entry['turnId'],
          'subagentId': each['subagentId'] ?? id,
        });
      }
    }
  }
  return out;
}

/// The task whose block [entry] starts or goes on, when it is the session's
/// own update for one chord started: its id.
String? _taskStarted(Object? entry) {
  if (entry case {
    'type': 'update',
    'update': {
      'sessionUpdate': 'subagent_update',
      'sessionId': final String id,
      '_meta': final Map<String, Object?> meta,
    },
  } when entry is Map<String, Object?> && entry['subagentId'] == null) {
    return meta[taskMetaKey] is Map ? id : null;
  }
  return null;
}

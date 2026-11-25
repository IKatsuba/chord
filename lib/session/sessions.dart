import 'dart:convert' show Utf8Decoder;
import 'dart:io';
import 'dart:typed_data';

import 'package:byte_search/byte_search.dart';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:path/path.dart' as p;

import 'record.dart';
import 'record_worker.dart';
import 'team_selection.dart' show recordedSelection;
import 'transcript/types.dart' show ChordCall;

/// An agent session to reopen, optionally backed by a local record.
final class Resume {
  const Resume({
    required this.sessionId,
    required this.cwd,
    this.record,
    this.lastUsedAt,
    this.prompt,
    this.name,
    this.title,
    this.task = false,
  });
  final String sessionId, cwd;
  final String? record, prompt, name, title;
  final num? lastUsedAt;
  final bool task;
}

/// A record's small discovery view, without retaining its updates.
final class SessionRecord {
  const SessionRecord({
    required this.path,
    required this.sessionId,
    required this.agent,
    required this.cwd,
    required this.lastUsedAt,
    required this.prompt,
    this.parent,
    this.name,
    this.title,
    this.task = false,
  });
  final String path, sessionId, agent, cwd, prompt;
  final num lastUsedAt;
  final String? parent, name, title;
  final bool task;

  Resume get resume => Resume(
    sessionId: sessionId,
    cwd: cwd,
    record: path,
    lastUsedAt: lastUsedAt,
    prompt: prompt,
    name: name,
    title: title,
    task: task,
  );

  Map<String, Object?> toJson() => {
    'path': path,
    'sessionId': sessionId,
    'agent': agent,
    'cwd': cwd,
    'lastUsedAt': lastUsedAt,
    'prompt': prompt,
    'parent': parent,
    'name': name,
    'title': title,
    'task': task,
  };

  factory SessionRecord.fromJson(Map<String, Object?> json) => SessionRecord(
    path: json['path'] as String,
    sessionId: json['sessionId'] as String,
    agent: json['agent'] as String,
    cwd: json['cwd'] as String,
    lastUsedAt: json['lastUsedAt'] as num,
    prompt: json['prompt'] as String,
    parent: json['parent'] as String?,
    name: json['name'] as String?,
    title: json['title'] as String?,
    task: json['task'] == true,
  );
}

/// A user-facing discovery or ownership refusal.
final class ResumeError implements Exception {
  const ResumeError(this.message, {this.cause});
  final String message;

  /// The opening error under the selected-session context, when present.
  final Object? cause;
  @override
  String toString() => message;
}

/// A fresh bounded scan; cancellation joins owned IO cleanup and worker exit.
Future<List<SessionRecord>> readRecords(
  String stateDir, {
  CancellationToken? cancellationToken,
}) async {
  final List json;
  try {
    json =
        await runRecordWorker(
              _scanWorker,
              'scan',
              stateDir,
              cancellationToken: cancellationToken,
            )
            as List;
  } catch (error, stack) {
    Error.throwWithStackTrace(
      recordWorkerPublicationError(error, cancellationToken),
      stack,
    );
  }
  if (cancellationToken?.exception case final exception?) throw exception;
  return List.unmodifiable(
    json.map((value) => SessionRecord.fromJson(value as Map<String, Object?>)),
  );
}

void _scanWorker(List<Object?> initial) =>
    serveRecordWorker(initial, 'scan', (io, path) async {
      final records = await _scanRecords(path, null, io);
      final json = <Map<String, Object?>>[];
      for (final (index, record) in records.indexed) {
        io.throwIfCancelled();
        json.add(record.toJson());
        if (index % 64 == 63) await io.checkpoint(stage: 'scan-projection');
      }
      return json;
    });

/// Stream seam for deterministic scanner tests; production uses [readRecords].
Future<List<SessionRecord>> scanRecords(
  String stateDir, {
  Stream<String> Function(String) lines = recordLines,
}) async {
  final io = RecordWorkerIO();
  try {
    return await _scanRecords(stateDir, lines, io);
  } finally {
    await io.close();
  }
}

Future<List<SessionRecord>> _scanRecords(
  String stateDir,
  Stream<String> Function(String)? lines,
  RecordWorkerIO io,
) async {
  final paths = await _recordPaths(stateDir, io);
  final summaries = List<SessionRecord?>.filled(paths.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < paths.length) {
      io.throwIfCancelled();
      final index = next++, summary = _Summary(paths[index]);
      try {
        if (lines == null) {
          await _scanBytes(paths[index], summary, io);
        } else {
          var count = 0;
          await io.forEach(
            lines(paths[index]),
            (line) async {
              io.throwIfCancelled();
              summary.line(line);
              io.throwIfCancelled();
              if (++count % 64 == 0) await io.checkpoint(stage: 'scan');
            },
            stage: 'file',
            path: paths[index],
          );
        }
        io.throwIfCancelled();
        summaries[index] = summary.done();
      } catch (_) {
        if (io.cancelled) io.throwIfCancelled();
        // An unreadable or vanished individual record is not offered.
      }
    }
  }

  await Future.wait([for (var i = 0; i < 8 && i < paths.length; i++) worker()]);
  io.throwIfCancelled();
  return List.unmodifiable(summaries.whereType<SessionRecord>());
}

// The records directory's .jsonl files, in listing order: every read
// keeps this order, which breaks ties between equal times.
Future<List<String>> _recordPaths(String stateDir, RecordWorkerIO io) async {
  final entries = <FileSystemEntity>[];
  final directory = recordsDir(stateDir);
  try {
    await io.forEach(
      Directory(directory).list(followLinks: false),
      (entry) async {
        entries.add(entry);
        if (entries.length % 64 == 0) await io.checkpoint(stage: 'scan');
      },
      stage: 'directory',
      path: directory,
    );
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode == 2) return const [];
    rethrow;
  }
  io.throwIfCancelled();
  return [
    for (final entry in entries)
      if (entry is File && p.extension(entry.path) == '.jsonl') entry.path,
  ];
}

// A record's lines are found and tested as bytes: only the header and the
// few lines a summary reads are decoded, as [recordLines] would decode them.
Future<void> _scanBytes(
  String path,
  _Summary summary,
  RecordWorkerIO io,
) async {
  final lines = RecordByteLines(summary.bytes);
  await io.forEach(
    File(path).openRead(),
    (List<int> chunk) async {
      io.throwIfCancelled();
      lines.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
      await io.checkpoint(stage: 'scan');
    },
    stage: 'file',
    path: path,
  );
  lines.close();
}

/// Splits byte chunks into lines as [recordLines] does, at `\n`, `\r` or
/// `\r\n`, a last line without a newline included, handing each line's
/// bytes on without decoding them.
final class RecordByteLines {
  RecordByteLines(this.line);

  /// Receives one line as `bytes[start, end)`, valid only during the call.
  final void Function(Uint8List bytes, int start, int end) line;
  var _carry = Uint8List(0);
  var _carried = 0;
  var _skipNewline = false;

  /// Hands on every line [chunk] completes.
  void add(Uint8List chunk) {
    var start = 0, i = 0;
    final length = chunk.length;
    if (_skipNewline && length > 0) {
      _skipNewline = false;
      if (chunk[0] == 0x0A) start = i = 1;
    }
    while (i < length) {
      i = chunk.indexOfAnyByte(_newlines, start: i);
      if (i < 0) break;
      final byte = chunk[i];
      if (_carried > 0) {
        _keep(chunk, start, i);
        line(_carry, 0, _carried);
        _carried = 0;
      } else {
        line(chunk, start, i);
      }
      i++;
      if (byte == 0x0D) {
        if (i == length) {
          _skipNewline = true;
        } else if (chunk[i] == 0x0A) {
          i++;
        }
      }
      start = i;
    }
    _keep(chunk, start, length);
  }

  /// Hands on a last line that has no newline after it.
  void close() {
    if (_carried > 0) line(_carry, 0, _carried);
    _carried = 0;
  }

  void _keep(Uint8List chunk, int start, int end) {
    final count = end - start;
    if (count == 0) return;
    if (_carried + count > _carry.length) {
      final grown = Uint8List(
        (_carried + count) * 2 < 4096 ? 4096 : (_carried + count) * 2,
      )..setRange(0, _carried, _carry);
      _carry = grown;
    }
    _carry.setRange(_carried, _carried + count, chunk, start);
    _carried += count;
  }
}

Uint8List _ascii(String text) => Uint8List.fromList(text.codeUnits);
final _served = _ascii('{"type":"served"'),
    _opened = _ascii('{"type":"opened"'),
    _prompt = _ascii('{"type":"prompt"'),
    _renamed = _ascii('{"type":"renamed"'),
    _update = _ascii('{"type":"update"');
final _runTeam = BytePattern.fromAscii(needle: '"run_team"'),
    _sessionInfo = BytePattern.fromAscii(needle: '"session_info_update"'),
    _newlines = ByteSet.fromAsciiChars('\r\n');
const _decoder = Utf8Decoder(allowMalformed: true);

/// The records whose first line names [id], summarised as [readRecords]
/// summarises them, in its order: [sessionById] and [recordedAgent] give
/// on them what they give on the full scan, without reading every record.
Future<List<SessionRecord>> readRecordsWithId(
  String stateDir,
  String id, {
  CancellationToken? cancellationToken,
}) => _targeted(
  (initial) => serveRecordWorker(
    initial,
    'with-id',
    (io, path) async => _project(await _withId(path, id, io), io),
  ),
  'with-id',
  stateDir,
  cancellationToken,
);

// Only a plain file name names a record: nothing outside records/.
bool _recordName(String id) =>
    id.isNotEmpty &&
    !id.contains('/') &&
    !id.contains('\\') &&
    !id.contains('..') &&
    !id.contains('\u0000');

/// The record named [id] among [records], as [readNamedRecord] finds it.
List<SessionRecord> namedRecordOf(List<SessionRecord> records, String id) =>
    _recordName(id)
    ? records.where((r) => recordId(r.path) == id).take(1).toList()
    : const [];

/// The session the record chord printed [id] for resumes: the record's
/// own, refused as [sessionById] refuses one of another agent.
Resume namedSession(SessionRecord record, String id, {required String agent}) {
  if (record.agent != agent) {
    throw ResumeError(
      'Session $id belongs to another agent (${record.agent}).',
    );
  }
  return record.resume;
}

/// The record chord printed [id] for, its file name without .jsonl, alone;
/// none when [id] is not a plain file name (empty, a separator or `..`),
/// or names no readable record with a session header, so the
/// caller looks [id] up as an agent's session id instead.
Future<List<SessionRecord>> readNamedRecord(
  String stateDir,
  String id, {
  CancellationToken? cancellationToken,
}) => _targeted(
  (initial) => serveRecordWorker(
    initial,
    'named',
    (io, path) async => _project(await _named(path, id, io), io),
  ),
  'named',
  stateDir,
  cancellationToken,
);

Future<List<SessionRecord>> _named(
  String stateDir,
  String id,
  RecordWorkerIO io,
) async {
  if (!_recordName(id)) return const [];
  final path = p.join(recordsDir(stateDir), '$id.jsonl');
  try {
    // A regular file only, as the scan lists them: a link is not followed.
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return const [];
    }
    // A session header is enough: a record named by chord resumes even
    // before its first prompt (the lead's ruling).
    if (await _summarise(path, io, anyWork: false) case final record?) {
      return [record];
    }
  } catch (_) {
    if (io.cancelled) io.throwIfCancelled();
    // Unreadable: looked up as an agent's id instead.
  }
  return const [];
}

/// The record [latestSession] picks for [agent] in [cwd] on the full scan,
/// alone, or none: only first lines are read, then each candidate's tail
/// back to its last prompt, and the newest candidate whole.
Future<List<SessionRecord>> readLatestRecord(
  String stateDir, {
  required String agent,
  required String cwd,
  CancellationToken? cancellationToken,
}) => _targeted(
  (initial) => serveRecordWorker(
    initial,
    'latest',
    (io, path) async => _project(await _latest(path, agent, cwd, io), io),
  ),
  'latest',
  stateDir,
  cancellationToken,
);

Future<List<SessionRecord>> _targeted(
  RecordWorkerEntry entry,
  String kind,
  String stateDir,
  CancellationToken? cancellationToken,
) async {
  final List json;
  try {
    json =
        await runRecordWorker(
              entry,
              kind,
              stateDir,
              cancellationToken: cancellationToken,
            )
            as List;
  } catch (error, stack) {
    Error.throwWithStackTrace(
      recordWorkerPublicationError(error, cancellationToken),
      stack,
    );
  }
  if (cancellationToken?.exception case final exception?) throw exception;
  return List.unmodifiable(
    json.map((value) => SessionRecord.fromJson(value as Map<String, Object?>)),
  );
}

Future<List<Map<String, Object?>>> _project(
  List<SessionRecord> records,
  RecordWorkerIO io,
) async {
  io.throwIfCancelled();
  return [for (final record in records) record.toJson()];
}

// Runs [each] over [paths] eight at a time, as the full scan reads them.
Future<List<T?>> _eachPath<T>(
  List<String> paths,
  RecordWorkerIO io,
  Future<T?> Function(String path) each,
) async {
  final results = List<T?>.filled(paths.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < paths.length) {
      io.throwIfCancelled();
      final index = next++;
      try {
        results[index] = await each(paths[index]);
      } catch (_) {
        if (io.cancelled) io.throwIfCancelled();
        // Unreadable or vanished: not offered, as the full scan drops it.
      }
    }
  }

  await Future.wait([for (var i = 0; i < 8 && i < paths.length; i++) worker()]);
  io.throwIfCancelled();
  return results;
}

Future<SessionRecord?> _summarise(
  String path,
  RecordWorkerIO io, {
  bool anyWork = true,
}) async {
  final summary = _Summary(path);
  await _scanBytes(path, summary, io);
  io.throwIfCancelled();
  return summary.done(anyWork: anyWork);
}

// The header as _Summary reads it: the first line, up to \n or \r. Null
// when it is not a session header, as done() then offers nothing.
Future<Map<String, Object?>?> _header(String path, RecordWorkerIO io) async {
  final file = await File(path).open();
  try {
    // Tests hold a read here, its file open, to cancel it.
    await io.testGate('header', path);
    final bytes = BytesBuilder(copy: false);
    while (true) {
      io.throwIfCancelled();
      final chunk = await file.read(4096);
      final end = chunk.indexOfAnyByte(_newlines);
      bytes.add(end < 0 ? chunk : Uint8List.sublistView(chunk, 0, end));
      if (end >= 0 || chunk.isEmpty) break;
    }
    final values = parseRecord(_decoder.convert(bytes.takeBytes()));
    final header = values.isEmpty ? null : RecordEntry.view(values.first);
    return header?.type == 'session' ? header!.json : null;
  } finally {
    await file.close();
  }
}

Future<List<SessionRecord>> _withId(
  String stateDir,
  String id,
  RecordWorkerIO io,
) async {
  final paths = await _recordPaths(stateDir, io);
  final headers = await _eachPath(paths, io, (path) => _header(path, io));
  final named = [
    for (final (index, path) in paths.indexed)
      if (headers[index]?['sessionId'] == id) path,
  ];
  final summaries = await _eachPath(named, io, (path) => _summarise(path, io));
  return summaries.whereType<SessionRecord>().toList();
}

Future<List<SessionRecord>> _latest(
  String stateDir,
  String agent,
  String cwd,
  RecordWorkerIO io,
) async {
  final paths = await _recordPaths(stateDir, io);
  final headers = await _eachPath(paths, io, (path) => _header(path, io));
  // latestSession's filter, on what the header alone says.
  final candidates = [
    for (final (index, path) in paths.indexed)
      if (headers[index] case final header?
          when header['agent'] == agent &&
              header['cwd'] == cwd &&
              header['parent'] is! String)
        path,
  ];
  // A record with a valid prompt is offered, its time that prompt's; one
  // without is summarised whole, as its time and its offer depend on more.
  final times = await _eachPath(candidates, io, (path) async {
    final at = await _lastPromptAt(path, io);
    if (at != null) return (at: at, whole: null);
    final whole = await _summarise(path, io);
    return whole == null ? null : (at: whole.lastUsedAt, whole: whole);
  });
  final order = [
    for (final (index, time) in times.indexed)
      if (time != null) (index, time),
  ];
  // _newest's order: later first, then the earlier listed.
  order.sort((a, b) {
    final time = b.$2.at.compareTo(a.$2.at);
    return time == 0 ? a.$1.compareTo(b.$1) : time;
  });
  for (final (index, time) in order) {
    io.throwIfCancelled();
    SessionRecord? record;
    try {
      record = time.whole ?? await _summarise(candidates[index], io);
    } catch (_) {
      if (io.cancelled) io.throwIfCancelled();
    }
    // Gone since its tail was read: the next one is what a scan now finds.
    if (record != null) return [record];
  }
  return const [];
}

/// The `at` of the last line of the record at [path] that _Summary takes
/// as a prompt, read backward from the end; null when there is none.
Future<num?> _lastPromptAt(String path, RecordWorkerIO io) async {
  final file = await File(path).open();
  try {
    await io.testGate('tail', path);
    var position = await file.length();
    // The line being gathered, nearest the start first: its later pieces
    // were read before its earlier ones.
    final pieces = <Uint8List>[];
    num? prompt(List<Uint8List> line) {
      var length = 0;
      for (final piece in line) {
        length += piece.length;
      }
      if (length < _prompt.length) return null;
      final head = BytesBuilder(copy: false);
      for (final piece in line) {
        head.add(piece);
        if (head.length >= _prompt.length) break;
      }
      if (!head.toBytes().startsWithBytes(_prompt)) return null;
      final bytes = BytesBuilder(copy: false);
      line.forEach(bytes.add);
      final values = parseRecord(_decoder.convert(bytes.takeBytes()));
      final entry = values.isEmpty ? null : RecordEntry.view(values.first);
      return entry?.type == 'prompt' ? entry!.json['at'] as num : null;
    }

    while (position > 0) {
      io.throwIfCancelled();
      final start = position > 65536 ? position - 65536 : 0;
      await file.setPosition(start);
      final chunk = await file.read(position - start);
      var end = chunk.length;
      for (var i = end - 1; i >= 0; i--) {
        final byte = chunk[i];
        if (byte != 0x0A && byte != 0x0D) continue;
        // An empty piece between \r and \n is no line, as in the forward
        // split, which reads \r\n as one end.
        final at = prompt([
          Uint8List.sublistView(chunk, i + 1, end),
          ...pieces,
        ]);
        if (at != null) return at;
        pieces.clear();
        end = i;
      }
      if (end > 0) pieces.insert(0, Uint8List.sublistView(chunk, 0, end));
      position = start;
      await io.checkpoint(stage: 'scan');
    }
    return prompt(pieces);
  } finally {
    await file.close();
  }
}

/// chord's record id for the quit line: only when [path] is a regular file
/// (a link is not followed) whose first line is the session header of
/// [session], as `--resume` reads it; else none, and the agent's id is
/// printed.
Future<String?> quitRecordId(
  String? path,
  ({String agent, String sessionId})? session,
) async {
  if (path == null || session == null) return null;
  final io = RecordWorkerIO();
  try {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final header = await _header(path, io);
    return header?['sessionId'] == session.sessionId &&
            header?['agent'] == session.agent
        ? recordId(path)
        : null;
  } catch (_) {
    return null;
  } finally {
    await io.close();
  }
}

/// One launch shares one scan, including a failed result.
Future<List<SessionRecord>> Function() recordsOnce(
  Future<List<SessionRecord>> Function() read,
) {
  Future<List<SessionRecord>>? records;
  return () => records ??= Future.sync(read);
}

/// Summarizes a fixture or a small record without building a transcript.
SessionRecord? summaryOf(String path, String text) {
  final summary = _Summary(path);
  for (final line in text.split('\n')) {
    summary.line(line);
  }
  return summary.done();
}

final class _Summary {
  _Summary(this.path);
  final String path;
  var read = false;
  RecordEntry? header;
  Map<String, Object?>? first, last, opened;
  String? title;

  /// The last selected run's receipt the record kept, which names a record
  /// with no prompt: an attempt admitted and refused before any.
  Map<String, Object?>? receipt;

  /// The byte form of [line]: a line [line] would only skip is not decoded.
  void bytes(Uint8List bytes, int start, int end) {
    if (read &&
        !(bytes.startsWithBytes(_prompt, start: start, end: end) ||
            bytes.startsWithBytes(_opened, start: start, end: end) ||
            bytes.startsWithBytes(_renamed, start: start, end: end) ||
            (bytes.startsWithBytes(_update, start: start, end: end) &&
                _sessionInfo.hasMatch(
                  haystack: bytes,
                  start: start,
                  end: end,
                )) ||
            (bytes.startsWithBytes(_served, start: start, end: end) &&
                _runTeam.hasMatch(haystack: bytes, start: start, end: end)))) {
      return;
    }
    line(_decoder.convert(bytes, start, end));
  }

  void line(String line) {
    if (!read) {
      read = true;
      final values = parseRecord(line);
      header = values.isEmpty ? null : RecordEntry.view(values.first);
    }
    // Irrelevant updates are never decoded or held during discovery.
    if (line.startsWith('{"type":"served"') && line.contains('"run_team"')) {
      final values = parseRecord(line);
      final call = values.isEmpty
          ? null
          : ChordCall.fromJson((values.first as Map)['call']);
      if (call != null) receipt = recordedSelection(call) ?? receipt;
      return;
    }
    if (line.startsWith('{"type":"opened"')) {
      final values = parseRecord(line);
      if (values.firstOrNull case final Map<String, Object?> entry) {
        opened = entry;
      }
      return;
    }
    if (!(line.startsWith('{"type":"prompt"') ||
        line.startsWith('{"type":"renamed"') ||
        (line.startsWith('{"type":"update"') &&
            line.contains('"session_info_update"')))) {
      return;
    }
    final values = parseRecord(line);
    final entry = values.isEmpty ? null : RecordEntry.view(values.first);
    if (entry == null) return;
    final json = entry.json;
    if (entry.type == 'prompt') {
      first ??= json;
      last = json;
    } else if (entry.type == 'renamed') {
      final value = json['title'] as String;
      if (value.trim().isNotEmpty) title = titleLine(value);
    } else if (entry.type == 'update' && !json.containsKey('subagentId')) {
      final update = json['update'] as Map<String, Object?>;
      if (update['sessionUpdate'] != 'session_info_update') return;
      final value = update['title'];
      if (update.containsKey('title') && value == null) {
        title = null;
      } else if (value is String && value.trim().isNotEmpty) {
        title = titleLine(value);
      }
    }
  }

  /// The record as discovery offers it: none without a prompt or receipt,
  /// unless [anyWork] is false, as for a record named by its id, whose
  /// prompt is then empty.
  SessionRecord? done({bool anyWork = true}) {
    if (header?.type != 'session' ||
        (anyWork && first == null && receipt == null)) {
      return null;
    }
    final json = header!.json;
    final task = json['task'] is String;
    return SessionRecord(
      path: path,
      sessionId: json['sessionId'] as String,
      agent: json['agent'] as String,
      cwd: json['cwd'] as String,
      lastUsedAt: (last?['at'] ?? opened?['at'] ?? json['at']) as num,
      prompt: first != null
          ? promptLine(first!['prompt'] as String)
          : receipt != null
          ? 'Team attempt: ${(receipt!['saved'] as Map)['name']}'
          : '',
      parent: json['parent'] is String ? json['parent'] as String : null,
      name: json['name'] is String ? json['name'] as String : null,
      task: task,
      title: task ? null : title,
    );
  }
}

/// Fold whitespace before removing controls, matching the original title policy.
String titleLine(String title) => title
    .replaceAll(RegExp(r'\s+', unicode: true), ' ')
    .replaceAll(RegExp(r'\p{Cc}', unicode: true), '')
    .trim();

List<SessionRecord> _newest(Iterable<SessionRecord> records) {
  final indexed = records.indexed.toList();
  indexed.sort((a, b) {
    final time = b.$2.lastUsedAt.compareTo(a.$2.lastUsedAt);
    return time == 0 ? a.$1.compareTo(b.$1) : time;
  });
  return [for (final item in indexed) item.$2];
}

/// Continue only a person's latest session for this exact agent and directory.
Resume latestSession(
  List<SessionRecord> records, {
  required String agent,
  required String cwd,
}) {
  final found = latestRecordOf(records, agent: agent, cwd: cwd);
  if (found.isEmpty) {
    throw ResumeError('No earlier $agent session in $cwd to continue.');
  }
  return found.first.resume;
}

/// The one record [latestSession] picks among [records], or none: what
/// [readLatestRecord] reads, from records already read.
List<SessionRecord> latestRecordOf(
  List<SessionRecord> records, {
  required String agent,
  required String cwd,
}) => _newest(
  records.where((r) => r.agent == agent && r.cwd == cwd && r.parent == null),
).take(1).toList();

/// The records with [id] among [records], in their order: what
/// [readRecordsWithId] reads, from records already read.
List<SessionRecord> recordsWithIdOf(List<SessionRecord> records, String id) =>
    records.where((r) => r.sessionId == id).toList();

/// One picker row, with an ISO time and the original session label.
final class EarlierSession {
  const EarlierSession({
    required this.resume,
    required this.lastUsedAt,
    required this.prompt,
  });
  final Resume resume;
  final String lastUsedAt, prompt;
}

/// Newest unique ids for an agent, optionally restricted to one directory.
List<EarlierSession> earlierSessions(
  List<SessionRecord> records, {
  required String agent,
  String? cwd,
  String? except,
}) {
  final seen = <String>{};
  return List.unmodifiable([
    for (final record in _newest(
      records.where(
        (r) =>
            r.agent == agent &&
            (cwd == null || r.cwd == cwd) &&
            r.sessionId != except,
      ),
    ))
      if (seen.add(record.sessionId))
        EarlierSession(
          resume: record.resume,
          lastUsedAt: DateTime.fromMillisecondsSinceEpoch(
            record.lastUsedAt.toInt(),
            isUtc: true,
          ).toIso8601String(),
          prompt: sessionLabel(
            prompt: record.prompt,
            name: record.name,
            title: record.title,
          ),
        ),
  ]);
}

/// Label uses the latest title, falling back to the first prompt.
String sessionLabel({required String prompt, String? name, String? title}) =>
    name == null ? title ?? prompt : '$name · ${title ?? prompt}';

/// Before a first prompt there is no open-session label.
String? openSessionLabel(String? firstPrompt) {
  final prompt = firstPrompt == null ? '' : promptLine(firstPrompt);
  return prompt.isEmpty ? null : sessionLabel(prompt: prompt);
}

/// Restricts a stable picker snapshot without changing its order.
List<EarlierSession> sessionsIn(List<EarlierSession> sessions, String cwd) =>
    List.unmodifiable(sessions.where((s) => s.resume.cwd == cwd));

/// Agent of the latest matching record, before CLI default resolution.
String? recordedAgent(List<SessionRecord> records, String id) {
  final found = _newest(records.where((r) => r.sessionId == id));
  return found.isEmpty ? null : found.first.agent;
}

/// Unknown ids go unchanged to ACP; known ids must belong to the chosen agent.
Resume sessionById(
  List<SessionRecord> records,
  String id, {
  required String agent,
  required String cwd,
}) {
  final named = _newest(records.where((r) => r.sessionId == id));
  final matching = named.where((r) => r.agent == agent);
  if (matching.isNotEmpty) return matching.first.resume;
  if (named.isNotEmpty) {
    throw ResumeError(
      'Session $id belongs to another agent (${named.first.agent}).',
    );
  }
  return Resume(sessionId: id, cwd: cwd);
}

String _shellQuote(String text) => RegExp(r'^[\w@%+=:,./-]+$').hasMatch(text)
    ? text
    : "'${text.replaceAll("'", "'\\''")}'";

/// Safe reopen command; only an explicitly supplied command override is repeated.
String resumeCommand(
  String agent,
  String sessionId, [
  String? agentCommand,
  // A typed `--no-mcp-servers` is said again, as the command is.
  bool noMcpServers = false,
]) => [
  'chord',
  _shellQuote(agent),
  if (agentCommand != null) ...['--agent-command', _shellQuote(agentCommand)],
  if (noMcpServers) '--no-mcp-servers',
  if (sessionId.startsWith('-'))
    '--resume=${_shellQuote(sessionId)}'
  else ...[
    '--resume',
    _shellQuote(sessionId),
  ],
].join(' ');

/// Refusal leaves a cross-directory selection to a new invocation.
String elsewhereRefusal(
  Resume chosen, {
  required String agent,
  String? agentCommand,
  bool noMcpServers = false,
  required String shownCwd,
}) =>
    'That session is in $shownCwd. Quit and open it there with:\n${resumeCommand(agent, chosen.record == null ? chosen.sessionId : recordId(chosen.record!), agentCommand, noMcpServers)}';

/// Printed only for a prompted or successfully resumed main session, with
/// chord's own [record] id where it has one, else the agent's session id.
String? resumeMessage(
  ({String agent, String sessionId})? session, {
  String? record,
  String? overrideAgent,
  String? agentCommand,
  bool noMcpServers = false,
}) => session == null
    ? null
    : 'Resume this session with:\n${resumeCommand(session.agent, record ?? session.sessionId, session.agent == overrideAgent ? agentCommand : null, session.agent == overrideAgent && noMcpServers)}';

/// Original fixed English relative ages, frozen by the caller's opening time.
String lastUsed(String at, num now) {
  final date = DateTime.tryParse(at);
  if (date == null) return at;
  final seconds = ((now - date.millisecondsSinceEpoch) / 1000).floor();
  for (final (unit, size, special) in const [
    ('year', 31536000, 'last year'),
    ('month', 2592000, 'last month'),
    ('week', 604800, 'last week'),
    ('day', 86400, 'yesterday'),
    ('hour', 3600, null),
    ('minute', 60, null),
  ]) {
    if (seconds < size) continue;
    final count = seconds ~/ size;
    if (count == 1 && special != null) return special;
    return '$count $unit${count == 1 ? '' : 's'} ago';
  }
  return 'just now';
}

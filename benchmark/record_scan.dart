/// Times the full record scan ([readRecords]) over a generated state shaped
/// like a person's: thousands of records, most small, a few of hundreds of MB.
/// Never reads a person's state. AOT:
/// `dart compile exe benchmark/record_scan.dart -o build/record_scan`.
///
/// Flags: --files=N (default 2000), --big-count=N (3), --big-mb=N (200),
/// --runs=N (3), --dir=PATH (an empty or missing dir to generate into, or
/// one this benchmark completed with the same flags; kept; any other
/// directory is refused unread),
/// --keep (keep the generated temp dir).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  String? flag(String name) {
    for (final arg in args) {
      if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
    }
    return null;
  }

  int number(String name, int fallback, {int least = 0}) {
    final value = int.tryParse(flag(name) ?? '$fallback');
    if (value == null || value < least) {
      stderr.writeln('--$name must be a whole number of at least $least');
      exit(64);
    }
    return value;
  }

  final set = RecordScanSet(
    files: number('files', 2000),
    bigCount: number('big-count', 3),
    bigMb: number('big-mb', 200),
  );
  final runs = number('runs', 3, least: 1);
  final keep = args.contains('--keep'), given = flag('dir');
  final state = given == null
      ? Directory.systemTemp.createTempSync('record_scan_').path
      : p.absolute(given);
  final records = Directory(p.join(state, 'records'));
  try {
    final clock = Stopwatch()..start();
    switch (prepareRecordScan(state, set)) {
      case RecordScanRefused(:final reason):
        stderr.writeln(reason);
        exitCode = 64;
        return;
      case RecordScanGenerated():
        stderr.writeln('generated in ${clock.elapsedMilliseconds} ms');
      case RecordScanReused():
        stderr.writeln('reusing the generated set in $state');
    }
    var bytes = 0, count = 0;
    for (final entry in records.listSync()) {
      if (entry is File) {
        bytes += entry.lengthSync();
        count++;
      }
    }
    final times = <double>[];
    var found = 0;
    for (var run = 0; run < runs; run++) {
      final clock = Stopwatch()..start();
      found = (await readRecords(state)).length;
      times.add(clock.elapsedMicroseconds / 1000);
    }
    final result = <String, Object?>{
      'files': count,
      'bytes': bytes,
      'runs': runs,
      'port': {'records': found, ..._stats(times)},
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  } finally {
    if (given == null && !keep) {
      Directory(state).deleteSync(recursive: true);
    } else {
      stderr.writeln('kept: $state');
    }
  }
}

/// The shape of a generated set, as its marker records it.
final class RecordScanSet {
  const RecordScanSet({
    required this.files,
    required this.bigCount,
    required this.bigMb,
  });
  final int files, bigCount, bigMb;
  Map<String, Object?> toJson() => {
    'generator': 'benchmark/record_scan.dart',
    'files': files,
    'bigCount': bigCount,
    'bigMb': bigMb,
  };
}

/// What [prepareRecordScan] did with a state directory.
sealed class RecordScanPrepared {}

/// A set was generated there and marked complete.
final class RecordScanGenerated extends RecordScanPrepared {}

/// A complete set of the same shape was already there.
final class RecordScanReused extends RecordScanPrepared {}

/// The directory is not this benchmark's, or holds another set: nothing
/// in it was read or changed.
final class RecordScanRefused extends RecordScanPrepared {
  RecordScanRefused(this.reason);
  final String reason;
}

/// The file that marks [prepareRecordScan]'s complete sets; written last,
/// so an interrupted generation leaves a directory that is refused.
const recordScanMarker = 'record_scan.json';

/// Generates [set] into an empty or missing [state], or reuses one this
/// benchmark completed with the same shape; any other directory, such as a
/// person's state, is refused before anything in it is read.
RecordScanPrepared prepareRecordScan(String state, RecordScanSet set) {
  final directory = Directory(state);
  final marker = File(p.join(state, recordScanMarker));
  final wanted = jsonEncode(set.toJson());
  if (marker.existsSync()) {
    final found = marker.readAsStringSync();
    return found == wanted
        ? RecordScanReused()
        : RecordScanRefused(
            '$state holds another generated set ($found); '
            'use another --dir or the same flags.',
          );
  }
  if (directory.existsSync() && directory.listSync().isNotEmpty) {
    return RecordScanRefused(
      '$state is not empty and has no $recordScanMarker: it is not a '
      'complete set this benchmark generated, so it is not read.',
    );
  }
  final records = Directory(p.join(state, 'records'))
    ..createSync(recursive: true);
  generateRecordScan(records.path, set);
  marker.writeAsStringSync(wanted);
  return RecordScanGenerated();
}

Map<String, Object?> _stats(List<double> times) {
  final sorted = [...times]..sort();
  return {
    'medianMs': sorted[sorted.length ~/ 2],
    'maxMs': sorted.last,
    'timesMs': times,
  };
}

/// Lines as a recorder writes them, with `type` first; payloads carry
/// multi-byte text so decoding costs what it does on real records.
final class _Lines {
  _Lines(this.random);
  final math.Random random;
  var _turn = 0, _at = 1700000000000;

  String _text(int length) {
    const words = [
      'the',
      'record',
      'scan',
      'résumé',
      'naïve',
      'κόσμε',
      'файл',
      '日本語',
      'tool',
      'output',
      '🙂',
      'function',
      'return',
      '{',
      '}',
      '\\n',
      '"x"',
    ];
    final buffer = StringBuffer();
    while (buffer.length < length) {
      buffer
        ..write(words[random.nextInt(words.length)])
        ..write(' ');
    }
    return buffer.toString();
  }

  String header(String id, String agent, String cwd, {String? task}) =>
      jsonEncode({
        'type': 'session',
        'version': 1,
        'sessionId': id,
        'agent': agent,
        'cwd': cwd,
        'at': _at,
        'task': ?task,
      });
  String opened() => jsonEncode({'type': 'opened', 'at': _at += 1000});
  String state() => jsonEncode({
    'type': 'state',
    'options': {'mode': 'default', 'model': 'fake-model'},
  });
  String prompt() => jsonEncode({
    'type': 'prompt',
    'turnId': 't${++_turn}',
    'at': _at += 60000,
    'prompt': _text(20 + random.nextInt(400)),
    'images': 0,
  });
  String chunk(int size) => jsonEncode({
    'type': 'update',
    'turnId': 't$_turn',
    'update': {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': _text(size)},
    },
    'at': _at += 10,
  });
  String tool(int size) => jsonEncode({
    'type': 'update',
    'turnId': 't$_turn',
    'update': {
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 'call${random.nextInt(1 << 30)}',
      'status': 'completed',
      'rawOutput': {'output': _text(size)},
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': _text(size ~/ 4)},
        },
      ],
    },
  });
  String served(int size) => jsonEncode({
    'type': 'served',
    'turnId': 't$_turn',
    'call': {
      'tool': 'send_message',
      'input': {'to': 'designer', 'text': _text(size)},
      'output': 'sent',
    },
  });
  String renamed() =>
      jsonEncode({'type': 'renamed', 'title': _text(30), 'at': _at += 5});
  String info() => jsonEncode({
    'type': 'update',
    'turnId': 't$_turn',
    'update': {'sessionUpdate': 'session_info_update', 'title': _text(25)},
  });
  String usage() => jsonEncode({
    'type': 'usage',
    'turnId': 't$_turn',
    'usage': {'inputTokens': random.nextInt(9000), 'outputTokens': 300},
  });
}

/// Writes [set]'s records into [dir], the same bytes for the same set.
void generateRecordScan(String dir, RecordScanSet set) {
  final RecordScanSet(:files, :bigCount, :bigMb) = set;
  final random = math.Random(176);
  final lines = _Lines(random);
  // A pool of bodies reused across files keeps generation fast; their order
  // and sizes vary per file.
  final pool = [
    for (var i = 0; i < 64; i++)
      switch (i % 4) {
        0 => lines.chunk(40 + random.nextInt(400)),
        1 => lines.tool(500 + random.nextInt(20000)),
        2 => lines.tool(50000 + random.nextInt(200000)),
        _ => lines.served(100 + random.nextInt(2000)),
      },
  ];
  const agents = ['claude', 'codex', 'gemini'];
  void write(int index, int targetBytes) {
    final sink = File(
      p.join(dir, '${index.toString().padLeft(8, '0')}-record.jsonl'),
    ).openSync(mode: FileMode.write);
    final buffer = StringBuffer();
    var written = 0;
    void add(String line) {
      buffer
        ..write(line)
        ..write('\n');
      if (buffer.length > 1 << 20) {
        final bytes = utf8.encode(buffer.toString());
        written += bytes.length;
        sink.writeFromSync(bytes);
        buffer.clear();
      }
    }

    add(
      lines.header(
        'session-${random.nextInt(files ~/ 2 + 1)}',
        agents[random.nextInt(agents.length)],
        '/work/project-${random.nextInt(20)}',
        task: random.nextInt(10) == 0 ? 'a task' : null,
      ),
    );
    add(lines.opened());
    add(lines.state());
    // A few records are looked-only, with no prompt.
    final prompts = random.nextInt(15) != 0;
    while (written + buffer.length < targetBytes) {
      if (prompts) add(lines.prompt());
      for (var i = 0, n = 5 + random.nextInt(40); i < n; i++) {
        add(pool[random.nextInt(pool.length)]);
      }
      add(lines.usage());
      if (random.nextInt(8) == 0) add(lines.info());
      if (random.nextInt(20) == 0) add(lines.renamed());
      if (random.nextInt(6) == 0) add(lines.opened());
    }
    sink.writeFromSync(utf8.encode(buffer.toString()));
    sink.closeSync();
  }

  for (var i = 0; i < files; i++) {
    // Most are small; about one in twenty is a few MB.
    final size = random.nextInt(20) == 0
        ? 1000000 + random.nextInt(6000000)
        : 5000 + random.nextInt(400000);
    write(i, size);
  }
  for (var i = 0; i < bigCount; i++) {
    write(files + i, bigMb * 1000000);
  }
}

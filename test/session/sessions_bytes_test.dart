import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _line(Map<String, Object?> json) => encodeRecord(json).trimRight();

String _header(String id, {String agent = 'fake', String? task}) => _line({
  'type': 'session',
  'version': 1,
  'sessionId': id,
  'agent': agent,
  'cwd': 'project',
  'at': 1,
  'task': ?task,
});

/// Lines a summary reads, and lines it skips, with multi-byte text.
List<String> _body(int turns, {int pad = 0}) => [
  _line({'type': 'opened', 'at': 2}),
  for (var turn = 0; turn < turns; turn++) ...[
    _line({
      'type': 'prompt',
      'turnId': 't$turn',
      'prompt': 'prompt $turn κόσμε 🙂 日本語',
      'at': 10 + turn,
      'images': 0,
    }),
    _line({
      'type': 'update',
      'turnId': 't$turn',
      'update': {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'é🙂' * pad},
      },
    }),
    _line({
      'type': 'update',
      'turnId': 't$turn',
      'update': {
        'sessionUpdate': 'session_info_update',
        'title': 'Titre $turn é',
      },
    }),
    _line({
      'type': 'served',
      'turnId': 't$turn',
      'call': {'tool': 'run_team', 'input': {}},
    }),
    if (turn.isOdd) _line({'type': 'renamed', 'title': 'Renamed 界', 'at': 3}),
    if (turn % 3 == 2)
      _line({
        'type': 'update',
        'turnId': 't$turn',
        'update': {'sessionUpdate': 'session_info_update', 'title': null},
      }),
  ],
];

void main() {
  group('RecordByteLines', () {
    List<String> split(List<int> bytes, List<int> cuts) {
      final out = <String>[];
      final lines = RecordByteLines(
        (b, s, e) =>
            out.add(const Utf8Decoder(allowMalformed: true).convert(b, s, e)),
      );
      var from = 0;
      for (final cut in [...cuts, bytes.length]) {
        lines.add(Uint8List.fromList(bytes.sublist(from, cut)));
        from = cut;
      }
      lines.close();
      return out;
    }

    List<String> expected(List<int> bytes) => const LineSplitter().convert(
      const Utf8Decoder(allowMalformed: true).convert(bytes),
    );

    for (final (name, text) in [
      ('LF', 'a\nbé\n\nc'),
      ('CRLF and a lone CR', 'a\r\nb🙂\r\rc\r\n'),
      ('a leading newline', '\nx\n'),
      ('a trailing CR', 'x\r'),
      ('one line without newline', '日本語'),
      ('empty', ''),
    ]) {
      test('splits $name as LineSplitter does at every cut', () {
        final bytes = utf8.encode(text);
        for (var a = 0; a <= bytes.length; a++) {
          for (var b = a; b <= bytes.length; b++) {
            expect(split(bytes, [a, b]), expected(bytes), reason: '$a $b');
          }
        }
      });
    }

    test('malformed UTF-8 decodes as the stream decoder does', () {
      final bytes = [0x61, 0xE2, 0x0A, 0xF0, 0x9F, 0x0D, 0x0A, 0xFF, 0x62];
      for (var a = 0; a <= bytes.length; a++) {
        expect(split(bytes, [a]), expected(bytes), reason: '$a');
      }
    });
  });

  group('byte scan', () {
    late Directory state;
    late Directory records;
    setUp(() async {
      state = await Directory.systemTemp.createTemp('chord-scan-bytes-');
      records = await Directory(recordsDir(state.path)).create();
    });
    tearDown(() => state.delete(recursive: true));

    test('summaries equal the line scan for every record shape', () async {
      final texts = <String, String>{
        'empty': '',
        'header_only': _header('h'),
        'header_newline': '${_header('hn')}\n',
        'no_prompt': [
          _header('np'),
          _line({'type': 'opened', 'at': 5}),
        ].join('\n'),
        'lf': [_header('lf'), ..._body(4)].join('\n'),
        'lf_trailing': '${[_header('lt'), ..._body(3)].join('\n')}\n',
        'crlf': [_header('crlf'), ..._body(5)].join('\r\n'),
        'cr': [_header('cr'), ..._body(2)].join('\r'),
        'task': [_header('task', task: 'a task'), ..._body(3)].join('\n'),
        'other_agent': [_header('oa', agent: 'other'), ..._body(1)].join('\n'),
        'torn_tail':
            '${[_header('tt'), ..._body(2)].join('\n')}\n'
            '{"type":"prompt",',
        // Lines of tens of KB put multi-byte text and CRLF pairs across
        // the reader's chunk boundaries.
        'big_crlf': [_header('big'), ..._body(40, pad: 9000)].join('\r\n'),
        'big_lf': [_header('big2'), ..._body(40, pad: 7001)].join('\n'),
      };
      for (final MapEntry(:key, :value) in texts.entries) {
        await File(p.join(records.path, '$key.jsonl')).writeAsString(value);
      }
      // Every chunk boundary is somewhere else for a one-byte shift.
      final shifted = '\n${texts['big_crlf']!}';
      await File(p.join(records.path, 'shifted.jsonl')).writeAsString(shifted);
      texts['shifted'] = shifted;

      final scanned = {
        for (final record in await readRecords(state.path))
          p.basenameWithoutExtension(record.path): record.toJson(),
      };
      // The line path, as the scan read records before bytes.
      final expected = {
        for (final record in await scanRecords(state.path))
          p.basenameWithoutExtension(record.path): record.toJson(),
      };
      expect(scanned, expected);
      expect(scanned.keys, containsAll(['lf', 'crlf', 'cr', 'big_crlf']));
      expect(scanned['big_crlf']!['title'], 'Renamed 界');
      expect(scanned, isNot(contains('shifted')));
      expect(
        scanned['lf'],
        summaryOf(p.join(records.path, 'lf.jsonl'), texts['lf']!)!.toJson(),
      );
    });
  });
}

// A record's usage lines cross the record worker whole: the window's resume
// of a session that kept a turn's figures, and chord acp's load of it.
import 'dart:io';
import 'dart:convert';

import 'package:chord/session/record.dart';

import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

void main() {
  for (final past in [false, true]) {
    test('a turn\'s figures are read back unchanged'
        '${past ? ', the raw past kept too' : ''}', () async {
      final dir = Directory.systemTemp.createTempSync('chord-usage-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/r.jsonl';
      File(path).writeAsStringSync(
        [
          '{"type":"session","version":1,"sessionId":"s","agent":"fake",'
              '"cwd":"/w","at":1}',
          '{"type":"opened","at":2}',
          '{"type":"prompt","turnId":"t","at":3,"prompt":"text","images":0}',
          '{"type":"result","turnId":"t","result":{"status":"completed",'
              '"stopReason":"end_turn"}}',
          '{"type":"usage","turnId":"t","usage":{"inputTokens":1000,'
              '"outputTokens":200,"totalTokens":2000},"model":"fake-large",'
              '"cost":{"amount":0.0125,"currency":"USD"},"estimated":true}',
          '',
        ].join('\n'),
      );
      final history = await readRecordedHistory(path, past: past);
      final figures = [
        for (final action in history.actions)
          if (action is UsageAction)
            {'turnId': action.turnId, 'figures': action.figures.toJson()},
      ];
      expect(figures, [
        {
          'turnId': 'history-t',
          'figures': {
            'turnId': 'history-t',
            'usage': {
              'inputTokens': 1000,
              'outputTokens': 200,
              'totalTokens': 2000,
            },
            'model': 'fake-large',
            'cost': {'amount': 0.0125, 'currency': 'USD'},
            'estimated': true,
          },
        },
      ]);
    });
  }

  group('tester usage worker boundaries', () {
    for (final past in [false, true]) {
      test(
        'all figures and sparse later usage cross worker and JSON with past=$past',
        () async {
          final dir = Directory.systemTemp.createTempSync(
            'chord-usage-fields-',
          );
          addTearDown(() => dir.deleteSync(recursive: true));
          final rows = [
            {
              'type': 'prompt',
              'turnId': 'history/already',
              'prompt': 'text',
              'images': 0,
              'at': 1.25,
            },
            {
              'type': 'usage',
              'turnId': 'history/already',
              'usage': {
                'inputTokens': 1.5,
                'outputTokens': 2,
                'cachedReadTokens': 3,
                'cachedWriteTokens': 4,
                'thoughtTokens': 5,
                'totalTokens': 15.5,
              },
              'total': true,
              'model': 'model 界',
              'cost': {'amount': 0.0, 'currency': 'credits'},
              'estimated': true,
              'uncounted': true,
              'before': {'until': 4.75},
            },
            {
              'type': 'prompt',
              'turnId': 'sparse',
              'prompt': 'second',
              'images': 0,
              'at': 2,
            },
            {
              'type': 'usage',
              'turnId': 'sparse',
              'usage': {'outputTokens': 0},
            },
          ];
          final path = '${dir.path}/r.jsonl';
          File(path).writeAsStringSync(rows.map(encodeRecord).join());
          final history = await readRecordedHistory(path, past: past);
          final crossed = PreparedHistory.fromJson(
            jsonDecode(jsonEncode(history.toJson())) as Map<String, Object?>,
          );
          for (final projection in [history, crossed]) {
            final usage = projection.actions.whereType<UsageAction>().toList();
            expect(usage.map((a) => a.turnId), [
              'history-history/already',
              'history-sparse',
            ]);
            expect(usage.first.figures.toJson(), {
              for (final entry in rows[1].entries)
                if (entry.key != 'type') entry.key: entry.value,
              'turnId': 'history-history/already',
            });
            expect(usage.last.figures.toJson(), {
              'turnId': 'history-sparse',
              'usage': {'outputTokens': 0},
            });
            expect(projection.past != null, past);
          }
        },
      );
    }
  });
}

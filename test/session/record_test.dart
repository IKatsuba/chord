import 'dart:convert';
import 'dart:io';

import 'package:chord/session/record.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('retained original parser oracle matches raw values exactly', () async {
    final text = await File(
      'test/fixtures/records/original.jsonl',
    ).readAsString();
    final oracle =
        jsonDecode(
              await File(
                'test/fixtures/records/original_oracle.json',
              ).readAsString(),
            )
            as Map;
    expect(parseRecord(text), oracle['parsed']);
  });

  test(
    'raw parser matches original valid JSON presence across broken lines',
    () {
      expect(parseRecord('\nnot json\nnull\n[]\n{"type":"future"}\n{"torn"'), [
        null,
        [],
        {'type': 'future'},
      ]);
      expect(parseRecord('{"type":"opened","at":4}'), [
        {'type': 'opened', 'at': 4},
      ]);
      expect(
        parseRecord('{"type":"opened","at":1}\r{"type":"opened","at":2}'),
        isEmpty,
      );
      expect(RecordEntry.view(null), isNull);
      expect(RecordEntry.view({'type': 'session', 'version': 2}), isNull);
      expect(RecordEntry.view({'type': 'prompt', 'prompt': 'bad'}), isNull);
    },
  );

  test(
    'type-first codec retains opaque nested metadata and snapshots deeply',
    () {
      final nested = <String, Object?>{
        'values': <Object?>[1, 2.5],
      };
      final raw = <String, Object?>{
        'extra': nested,
        'type': 'future',
        '_meta': {'private': 'kept'},
      };
      final view = RecordEntry(raw);
      (nested['values'] as List).add(3);
      expect(view.json['extra'], {
        'values': [1, 2.5],
      });
      expect(
        () => (view.json['extra'] as Map)['new'] = true,
        throwsUnsupportedError,
      );
      final encoded = encodeRecord(view.json);
      expect(encoded, startsWith('{"type":"future",'));
      expect(encoded, endsWith('\n'));
      expect(jsonDecode(encoded), view.json);
    },
  );

  test(
    'result codec preserves historical status, nested messages and raw codes',
    () {
      for (final status in ['completed', 'cancelled']) {
        final raw = {
          'status': status,
          'stopReason': status == 'completed' ? 'cancelled' : 'end_turn',
        };
        final result = RecordedResult.view(raw)!;
        expect(result.status, status);
        expect(result.toJson(), raw);
      }
      for (final code in ['-32000', 'permission/refused']) {
        final raw = {
          'status': 'failed',
          'error': {'message': 'refused', 'code': code},
        };
        final result = RecordedResult.view(raw)!;
        expect(result.toJson(), raw);
        expect(result.omittedDetail, code == 'permission/refused');
      }
      expect(recordResult(const TurnFailed('no', code: -32000)), {
        'status': 'failed',
        'error': {'message': 'no', 'code': '-32000'},
      });
      expect(recordResult(const TurnAnswered('cancelled')), {
        'status': 'cancelled',
        'stopReason': 'cancelled',
      });
      expect(
        RecordedResult.view({'status': 'failed', 'message': 'flat'}),
        isNull,
      );
    },
  );

  test(
    'selected history replaces malformed UTF-8 and accepts final JSON',
    () async {
      final dir = await Directory.systemTemp.createTemp('chord-record-test-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'past.jsonl'));
      await file.writeAsBytes([
        ...utf8.encode('{"type":"future","text":"'),
        255,
        ...utf8.encode('"}\n{"type":"opened","at":3}'),
      ]);
      expect(await readPast(file.path), [
        {'type': 'future', 'text': '\uFFFD'},
        {'type': 'opened', 'at': 3},
      ]);
      expect(await recordLines(file.path).toList(), hasLength(2));
      expect(await readPast(p.join(dir.path, 'missing')), isEmpty);
    },
  );

  test('UUID basenames never use ACP ids and state uses records only', () {
    expect(
      newRecordPath('state', uuid: () => 'fixture'),
      p.join('state', 'records', 'fixture.jsonl'),
    );
    final names = {for (var i = 0; i < 100; i++) newRecordPath('state')};
    expect(names, hasLength(100));
    expect(
      names.every(
        (name) => RegExp(r'^[0-9a-f-]{36}\.jsonl$').hasMatch(p.basename(name)),
      ),
      isTrue,
    );
  });
}

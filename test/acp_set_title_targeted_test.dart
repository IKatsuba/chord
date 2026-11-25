// chord acp's session/set_title on a listed session that is not loaded
// reads only the records naming its id, not the full scan (CTUI-181).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp_agent.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

void main() {
  test('a listed, unloaded session is renamed from its own records', () async {
    final dir = Directory.systemTemp.createTempSync('chord-title-targeted-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final mine = '${dir.path}/mine.jsonl';
    final other = '${dir.path}/other.jsonl';
    File(mine).writeAsStringSync('');
    File(other).writeAsStringSync('');
    SessionRecord record(String path, String id, String agent) => SessionRecord(
      path: path,
      sessionId: id,
      agent: agent,
      cwd: '/w',
      prompt: 'Old',
      lastUsedAt: 0,
    );
    final named = {
      // Another agent's newer record with the same id is not this one's.
      'one': [record(mine, 'one', 'memory'), record(other, 'one', 'other')],
      'theirs': [record(other, 'theirs', 'other')],
    };
    var scans = 0;
    final asked = <String>[];
    final input = StreamController<List<int>>();
    final lines = Lines();
    runAcp(
      input: input.stream,
      sink: lines,
      agent: 'memory',
      version: '9.9.9',
      place: anyPlace,
      stateDir: dir.path,
      stderr: (_) {},
      exit: (_) {},
      records: () async {
        scans++;
        throw StateError('the full scan is not read for a rename');
      },
      recordsWithId: (id) async {
        asked.add(id);
        return named[id] ?? const [];
      },
      recording: (_) => NoRecording(),
    );
    var next = 0;
    int send(String method, Map<String, Object?> params) {
      final id = ++next;
      input.add(
        utf8.encode(
          '${jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params})}\n',
        ),
      );
      return id;
    }

    Future<Map<String, Object?>?> answer(int id) async {
      Map<String, Object?>? found() =>
          lines.messages.where((m) => m['id'] == id).firstOrNull;
      for (var i = 0; i < 200 && found() == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return found();
    }

    await answer(send('initialize', {'protocolVersion': 1}));
    final renamed = await answer(
      send('session/set_title', {'sessionId': 'one', 'title': 'Later'}),
    );
    expect(renamed?['result'], {'title': 'Later'});
    for (final id in ['theirs', 'nobody']) {
      final refused = await answer(
        send('session/set_title', {'sessionId': id, 'title': 'x'}),
      );
      expect((refused?['error'] as Map?)?['code'], -32002, reason: id);
    }
    await input.close();
    expect(scans, 0);
    expect(asked, ['one', 'theirs', 'nobody']);
    final line = jsonDecode(File(mine).readAsLinesSync().single) as Map;
    expect(line['type'], 'renamed');
    expect(
      recordActions([line.cast<String, Object?>()]).pendingRename,
      'Later',
    );
    expect(File(other).readAsStringSync(), isEmpty);
  });
}

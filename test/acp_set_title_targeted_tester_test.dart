import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp_agent.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

void main() {
  group('tester CTUI-181: targeted rename on real isolated records', () {
    test(
      'concurrent ids choose their newest own record and normalize titles',
      () async {
        final state = Directory.systemTemp.createTempSync(
          'targeted-title-tester-',
        );
        addTearDown(() => state.deleteSync(recursive: true));
        final dir = Directory(recordsDir(state.path))..createSync();
        File record(String name, String id, String agent, int at) {
          final file = File('${dir.path}/$name.jsonl');
          file.writeAsStringSync(
            encodeRecord({
                  'type': 'session',
                  'version': 1,
                  'sessionId': id,
                  'agent': agent,
                  'cwd': 'project',
                  'at': 1,
                }) +
                encodeRecord({
                  'type': 'prompt',
                  'turnId': 't',
                  'prompt': 'before',
                  'images': 0,
                  'at': at,
                }),
          );
          return file;
        }

        final old = record('old', 'one', 'memory', 2);
        final newest = record('newest', 'one', 'memory', 20);
        final other = record('other-agent', 'one', 'other', 200);
        final second = record('second', 'two', 'memory', 3);
        final unchanged = {
          for (final f in [old, other]) f.path: f.readAsStringSync(),
        };
        final input = StreamController<List<int>>();
        final output = Lines();
        var scans = 0;
        final ids = <String>[];
        runAcp(
          input: input.stream,
          sink: output,
          agent: 'memory',
          version: 'test',
          place: anyPlace,
          stateDir: state.path,
          stderr: (_) {},
          exit: (_) {},
          recording: (_) => NoRecording(),
          records: () async {
            scans++;
            throw StateError('full scan forbidden');
          },
          recordsWithId: (id) async {
            ids.add(id);
            return readRecordsWithId(state.path, id);
          },
        );
        var next = 0;
        Future<Map<String, Object?>> request(
          String method,
          Map<String, Object?> params,
        ) async {
          final id = ++next;
          input.add(
            utf8.encode(
              '${jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params})}\n',
            ),
          );
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (!output.messages.any((m) => m['id'] == id)) {
            if (DateTime.now().isAfter(deadline)) {
              fail('missing ACP answer $id');
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          return output.messages.singleWhere((m) => m['id'] == id);
        }

        await request('initialize', {'protocolVersion': 1});
        final answers = await Future.wait([
          request('session/set_title', {
            'sessionId': 'one',
            'title': '  界🙂e\u0301\n  first  ',
          }),
          request('session/set_title', {
            'sessionId': 'two',
            'title': ' second\t title ',
          }),
        ]);
        expect(answers.map((a) => a['result']), [
          {'title': '界🙂e\u0301 first'},
          {'title': 'second title'},
        ]);
        final beforeInvalid = ids.length;
        final refused = await request('session/set_title', {
          'sessionId': 'one',
          'title': ' \n\t ',
        });
        expect((refused['error'] as Map)['code'], -32602);
        expect(ids.length, beforeInvalid);
        await input.close();
        expect(scans, 0);
        expect(ids, ['one', 'two']);
        for (final f in [old, other]) {
          expect(f.readAsStringSync(), unchanged[f.path]);
        }
        for (final (f, title) in [
          (newest, '界🙂e\u0301 first'),
          (second, 'second title'),
        ]) {
          final last = jsonDecode(f.readAsLinesSync().last) as Map;
          expect(last['type'], 'renamed');
          expect(last['title'], title);
          expect(last['pending'], isTrue);
        }
      },
    );
  });
}

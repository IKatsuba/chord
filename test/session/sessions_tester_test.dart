import 'dart:async';
import 'dart:io';

import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _header(String id) => encodeRecord({
  'type': 'session',
  'version': 1,
  'sessionId': id,
  'agent': 'fake',
  'cwd': 'fixture-project',
  'at': 0,
});

String _prompt(String text, num at) => encodeRecord({
  'type': 'prompt',
  'turnId': 'turn',
  'prompt': text,
  'at': at,
  'images': 0,
});

SessionRecord _record(String id, num at, {String cwd = 'fixture-project'}) =>
    SessionRecord(
      path: '$id.jsonl',
      sessionId: id,
      agent: 'fake',
      cwd: cwd,
      lastUsedAt: at,
      prompt: id,
    );

void main() {
  group('tester: CTUI-34 resume flag boundaries', () {
    test('option-like Unicode ids remain one quoted value after the flag', () {
      expect(
        resumeCommand('my agent', '-界🙂e\u0301 id', 'exec --x', true),
        "chord 'my agent' --agent-command 'exec --x' --no-mcp-servers --resume='-界🙂e\u0301 id'",
      );
    });

    test(
      'an absent session and another agent inherit no typed launch flags',
      () {
        expect(
          resumeMessage(
            null,
            overrideAgent: 'fake',
            agentCommand: 'exec --x',
            noMcpServers: true,
          ),
          isNull,
        );
        expect(
          resumeMessage(
            (agent: 'other', sessionId: '-id'),
            overrideAgent: 'fake',
            agentCommand: 'exec --x',
            noMcpServers: true,
          ),
          'Resume this session with:\nchord other --resume=-id',
        );
        expect(
          resumeMessage((agent: 'fake', sessionId: 'id'), noMcpServers: true),
          'Resume this session with:\nchord fake --resume id',
        );
      },
    );
  });

  group('CTUI-26 U1 tester: discovery ownership and stream boundaries', () {
    late Directory state;
    setUp(() async {
      state = await Directory.systemTemp.createTemp('chord-u1-tester-');
    });
    tearDown(() async {
      await state.delete(recursive: true);
    });

    test(
      'startup shares an unfinished scan and freezes its resolved snapshot',
      () async {
        final pending = Completer<List<SessionRecord>>();
        var reads = 0;
        final once = recordsOnce(() {
          reads++;
          return pending.future;
        });
        final first = once(), second = once();
        expect(second, same(first));
        expect(reads, 1);
        final snapshot = [_record('first', 1)];
        pending.complete(snapshot);
        expect(await first, same(snapshot));
        expect(await once(), same(snapshot));
        expect(reads, 1);
      },
    );

    test('a failed scan stays shared while a new startup may retry', () async {
      final failure = StateError('fixture scan unavailable');
      var reads = 0;
      Future<List<SessionRecord>> read() async {
        reads++;
        if (reads == 1) throw failure;
        return [_record('fresh', 2)];
      }

      final once = recordsOnce(read);
      await expectLater(once(), throwsA(same(failure)));
      await expectLater(once(), throwsA(same(failure)));
      expect(reads, 1);
      expect((await recordsOnce(read)()).single.sessionId, 'fresh');
      expect(reads, 2);
    });

    test('a synchronous scanner failure also settles once', () async {
      var reads = 0;
      final failure = StateError('fixture synchronous failure');
      final once = recordsOnce(() {
        reads++;
        throw failure;
      });
      await expectLater(once(), throwsA(same(failure)));
      await expectLater(once(), throwsA(same(failure)));
      expect(reads, 1);
    });

    test(
      'long Unicode, CRLF and final unterminated prompt survive real IO',
      () async {
        await Directory(recordsDir(state.path)).create();
        final file = File(p.join(recordsDir(state.path), 'boundary.jsonl'));
        final text = [
          _header('boundary'),
          _prompt('first 界👩‍💻é', 1.25),
          encodeRecord({
            'type': 'update',
            'turnId': 'turn',
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': '界🙂' * 30000},
            },
          }),
          encodeRecord({
            'type': 'update',
            'turnId': 'turn',
            'update': {
              'sessionUpdate': 'session_info_update',
              'title': 'Résumé 界🙂',
            },
          }),
          _prompt('last', 9.75),
        ].join().trimRight().replaceAll('\n', '\r\n');
        await file.writeAsString(text);
        final before = await file.readAsBytes();
        final result = (await readRecords(state.path)).single;
        expect(result.toJson(), summaryOf(file.path, text)!.toJson());
        expect(result.prompt, 'first 界👩‍💻é');
        expect(result.title, 'Résumé 界🙂');
        expect(result.lastUsedAt, 9.75);
        expect(await file.readAsBytes(), before);
      },
    );

    test(
      'failed streams discard partial summaries and release later slots',
      () async {
        final dir = await Directory(recordsDir(state.path)).create();
        for (var i = 0; i < 24; i++) {
          await File(p.join(dir.path, '$i.jsonl')).writeAsString('');
        }
        var active = 0, completed = 0;
        Stream<String> lines(String path) async* {
          active++;
          final id = p.basenameWithoutExtension(path);
          try {
            yield _header(id).trimRight();
            yield _prompt(id, 2).trimRight();
            if (id == '0' || id == '9') {
              throw const FileSystemException('fixture partial read failure');
            }
            completed++;
          } finally {
            active--;
          }
        }

        final result = await scanRecords(state.path, lines: lines);
        expect(result.map((r) => r.sessionId).toSet(), {
          for (var i = 0; i < 24; i++)
            if (i != 0 && i != 9) '$i',
        });
        expect(completed, 22);
        expect(active, 0);
      },
    );

    test(
      'directory entries, legacy windows and a torn tail leave valid records readable',
      () async {
        final dir = await Directory(recordsDir(state.path)).create();
        await Directory(p.join(dir.path, 'directory.jsonl')).create();
        final legacy = await Directory(p.join(state.path, 'windows')).create();
        final old = File(p.join(legacy.path, 'legacy.jsonl'));
        await old.writeAsString('legacy bytes');
        await File(p.join(dir.path, 'valid.jsonl')).writeAsString(
          '${_header('valid')}${_prompt('valid', 3)}{"type":"prompt",',
        );
        expect((await readRecords(state.path)).single.sessionId, 'valid');
        expect(await old.readAsString(), 'legacy bytes');
      },
    );

    test(
      'records directory errors propagate instead of looking like an empty store',
      () async {
        await File(recordsDir(state.path)).writeAsString('not a directory');
        await expectLater(
          readRecords(state.path),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test(
      'scope filtering precedes duplicate elimination and keeps fractional time',
      () {
        final local = _record('duplicate', 1.5);
        final remote = _record('duplicate', 2.5, cwd: 'fixture-other');
        final records = [local, remote, _record('tie', 1.5)];
        final here = earlierSessions(
          records,
          agent: 'fake',
          cwd: 'fixture-project',
        );
        expect(here.map((r) => r.resume.sessionId), ['duplicate', 'tie']);
        expect(here.first.resume.lastUsedAt, 1.5);
        expect(
          earlierSessions(records, agent: 'fake').first.resume.cwd,
          'fixture-other',
        );
        expect(
          sessionsIn(
            earlierSessions(records, agent: 'fake'),
            'fixture-project',
          ).map((r) => r.resume.sessionId),
          ['tie'],
        );
        expect(records, [local, remote, records.last]);
      },
    );
  });
}

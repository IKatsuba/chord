// `chord acp` on the original's fake agent: sessions opened, listed and
// closed, starts that fail, and the way out.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/session/leaving.dart';
import 'package:chord/session/record.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'acp_client.dart';
import 'fixtures/fake_harness.dart';

void main() {
  final skip = fakeAgentSkip;

  test('a session opens on the fake, is listed once recorded, and closes '
      'with its agent', () async {
    final client = AcpClient();
    await client.initialize();
    final sessionId = await client.newSession();
    expect(client.host.sessions.keys, [sessionId]);
    expect(client.pids, hasLength(1));
    final closed = await client.request('session/close', {
      'sessionId': sessionId,
    });
    expect(closed['result'], <String, Object?>{});
    expect(client.pids.where(alive), isEmpty);
    await client.input.close();
    expect(await client.exited.future, const LeaveExit.code(0));
  }, skip: skip);

  test(
    'session/list reads the records in chord\'s state, this agent\'s',
    () async {
      final client = AcpClient();
      final records = Directory(recordsDir(client.stateDir))
        ..createSync(recursive: true);
      File(p.join(records.path, 'one.jsonl')).writeAsStringSync(
        [
          {
            'type': 'session',
            'version': 1,
            'sessionId': 'one',
            'agent': 'fake',
            'cwd': client.cwd,
            'at': 1000,
          },
          {
            'type': 'prompt',
            'turnId': 't',
            'prompt': 'Fix the parser',
            'images': 0,
            'at': 2000,
          },
        ].map(encodeRecord).join(),
      );
      await client.initialize();
      final listed = await client.request('session/list', {'cwd': client.cwd});
      expect((listed['result'] as Map)['sessions'], [
        {
          'sessionId': 'one',
          'cwd': client.cwd,
          'title': 'Fix the parser',
          'updatedAt': '1970-01-01T00:00:02.000Z',
        },
      ]);
    },
    skip: skip,
  );

  test('an agent nobody signed in to is -32000 with its ways in, and no '
      'agent is left', () async {
    final client = AcpClient(flags: ['--auth-required', 'methods']);
    await client.initialize();
    final failed = await client.request('session/new', {
      'cwd': client.cwd,
      'mcpServers': <Object?>[],
    });
    final error = failed['error'] as Map;
    expect(error['code'], -32000);
    expect((error['data'] as Map)['lines'], isNotEmpty);
    expect(client.pids.where(alive), isEmpty);
    expect(client.host.sessions, isEmpty);
  }, skip: skip);

  test('a start that hangs is given up by a cancel of its request: '
      '-32800', () async {
    final client = AcpClient(flags: ['--hang', 'start']);
    await client.initialize();
    final id = client.ask('session/new', {
      'cwd': client.cwd,
      'mcpServers': <Object?>[],
    });
    // The fake hangs before it answers initialize: the start is under way.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    client.send({
      'jsonrpc': '2.0',
      'method': r'$/cancel_request',
      'params': {'requestId': id},
    });
    final answered = await client.answer(id);
    expect((answered['error'] as Map)['code'], -32800);
    expect(client.host.sessions, isEmpty);
  }, skip: skip);

  test('EOF closes every session and exits 0', () async {
    final client = AcpClient();
    await client.initialize();
    await client.newSession();
    await client.newSession();
    expect(client.pids, hasLength(2));
    await client.input.close();
    expect(await client.exited.future, const LeaveExit.code(0));
    expect(client.pids.where(alive), isEmpty);
    expect(client.lines.closed, isTrue);
  }, skip: skip);
}

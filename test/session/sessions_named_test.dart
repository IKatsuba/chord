import 'dart:async';
// The owner's departure (CTUI-176): chord prints its own record id to
// resume with, and --resume <id> finds that record by its file name first.
import 'dart:io';

import 'package:chord/session/launch_connection.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'recording_start_test.dart' show connected, idle, launch;
import 'reopen_session_test.dart' as memory;

String _record(String id, String agent, {num at = 5}) => [
  encodeRecord({
    'type': 'session',
    'version': 1,
    'sessionId': id,
    'agent': agent,
    'cwd': '/w',
    'at': 1,
  }),
  encodeRecord({
    'type': 'prompt',
    'turnId': 't',
    'prompt': 'hello',
    'at': at,
    'images': 0,
  }),
].join();

void main() {
  late Directory state;
  late String records;
  setUp(() async {
    state = await Directory.systemTemp.createTemp('chord-named-');
    records = (await Directory(recordsDir(state.path)).create()).path;
  });
  tearDown(() => state.delete(recursive: true));

  Future<void> write(String name, String text) =>
      File(p.join(records, '$name.jsonl')).writeAsString(text);

  test('a printed record id names its record directly', () async {
    await write('rec-1', _record('agent-1', 'claude'));
    final found = await readNamedRecord(state.path, 'rec-1');
    expect(found.single.sessionId, 'agent-1');
    final resume = namedSession(found.single, 'rec-1', agent: 'claude');
    expect(
      (resume.sessionId, resume.cwd, resume.record),
      ('agent-1', '/w', p.join(records, 'rec-1.jsonl')),
    );
    expect(
      () => namedSession(found.single, 'rec-1', agent: 'codex'),
      throwsA(
        isA<ResumeError>().having(
          (e) => e.message,
          'message',
          'Session rec-1 belongs to another agent (claude).',
        ),
      ),
    );
  });

  test('a header-only record resumes by its record id', () async {
    await write('looked', _record('y', 'claude').split('\n').first);
    final found = await readNamedRecord(state.path, 'looked');
    expect(found.single.prompt, '');
    final resume = namedSession(found.single, 'looked', agent: 'claude');
    expect(
      (resume.sessionId, resume.cwd, resume.record, resume.lastUsedAt),
      ('y', '/w', p.join(records, 'looked.jsonl'), 1),
    );
    // The scan still offers it nowhere.
    expect(await readRecords(state.path), isEmpty);
  });

  test('an agent id, a missing name, a bad header or an unreadable file '
      'name no record', () async {
    await write('rec-1', _record('agent-1', 'claude'));
    await write('bad', 'not a header\n${_record('x', 'claude')}');
    await write('locked', _record('z', 'claude'));
    await Process.run('chmod', ['000', p.join(records, 'locked.jsonl')]);
    addTearDown(
      () => Process.run('chmod', ['600', p.join(records, 'locked.jsonl')]),
    );
    for (final id in ['agent-1', 'missing', 'bad', 'locked']) {
      expect(await readNamedRecord(state.path, id), isEmpty, reason: id);
    }
  });

  test('path-like ids never read a file outside records/', () async {
    // Records that such ids would reach if joined as paths.
    await File(
      p.join(state.path, 'escape.jsonl'),
    ).writeAsString(_record('e', 'claude'));
    await Directory(p.join(records, 'sub')).create();
    await write('sub/inner', _record('i', 'claude'));
    await write('..', _record('dots', 'claude'));
    for (final id in ['../escape', 'sub/inner', r'sub\inner', '', '..', '.']) {
      expect(await readNamedRecord(state.path, id), isEmpty, reason: id);
    }
    final all = await readRecords(state.path);
    for (final id in ['../escape', 'sub/inner', '', '..']) {
      expect(namedRecordOf(all, id), isEmpty, reason: id);
    }
    expect(namedRecordOf(all, 'missing'), isEmpty);
  });

  test('the quit line and the elsewhere refusal print the record id', () {
    expect(
      resumeMessage((agent: 'fake', sessionId: 'agent-id'), record: 'rec-1'),
      'Resume this session with:\nchord fake --resume rec-1',
    );
    expect(
      resumeMessage((agent: 'fake', sessionId: 'agent-id')),
      'Resume this session with:\nchord fake --resume agent-id',
    );
    expect(
      elsewhereRefusal(
        const Resume(
          sessionId: 'agent-id',
          cwd: '/w',
          record: '/s/rec-1.jsonl',
        ),
        agent: 'fake',
        shownCwd: '/w',
      ),
      endsWith('chord fake --resume rec-1'),
    );
    expect(
      elsewhereRefusal(
        const Resume(sessionId: 'agent-id', cwd: '/w'),
        agent: 'fake',
        shownCwd: '/w',
      ),
      endsWith('chord fake --resume agent-id'),
    );
  });

  test('a session that becomes resumable keeps its record id, a new one '
      'and a reopened one, after it closes', () async {
    final dir = await memory.directory();
    final transport = memory.Memory();
    final connection = startLaunchConnection(
      launch,
      cwd: dir.path,
      open: transport.open,
      stateDirectory: () => dir.path,
    );
    addTearDown(connection.close);
    await connected(connection);
    connection.conversation.send('actual prompt');
    await idle(connection);
    final path = (connection.recording as FileRecording).path!;
    await connection.close();
    expect(
      await quitRecordId(
        connection.conversation.resumableRecord,
        connection.conversation.resumable,
      ),
      recordId(path),
    );

    final again = startLaunchConnection(
      launch,
      cwd: dir.path,
      open: memory.Memory().open,
      stateDirectory: () => dir.path,
      resume: Resume(sessionId: 'literal/id', cwd: dir.path, record: path),
    );
    addTearDown(again.close);
    await connected(again);
    await again.close();
    expect(again.conversation.resumable?.sessionId, 'literal/id');
    expect(
      await quitRecordId(
        again.conversation.resumableRecord,
        again.conversation.resumable,
      ),
      recordId(path),
    );
  });

  test('a bare resume that did no work, and a record whose first append '
      'failed, leave the agent id on the quit line', () async {
    final dir = await memory.directory();
    final bare = startLaunchConnection(
      launch,
      cwd: dir.path,
      open: memory.Memory().open,
      stateDirectory: () => dir.path,
      resume: Resume(sessionId: 'agent-only', cwd: dir.path),
    );
    addTearDown(bare.close);
    await connected(bare);
    await bare.close();
    expect(bare.conversation.resumable?.sessionId, 'agent-only');
    expect(
      await quitRecordId(
        bare.conversation.resumableRecord,
        bare.conversation.resumable,
      ),
      isNull,
    );
    expect(await Directory(recordsDir(dir.path)).exists(), isFalse);

    final failed = startLaunchConnection(
      launch,
      cwd: dir.path,
      open: memory.Memory().open,
      recording: FileRecording(
        dir.path,
        failed: (_) {},
        append: (path, text) async => throw const FileSystemException('full'),
      ),
    );
    addTearDown(failed.close);
    await connected(failed);
    failed.conversation.send('actual prompt');
    await idle(failed);
    await failed.close();
    expect(failed.conversation.resumable, isNotNull);
    expect(
      await quitRecordId(
        failed.conversation.resumableRecord,
        failed.conversation.resumable,
      ),
      isNull,
    );
  });

  test('a link in records/ is not followed: the id is looked up as an '
      'agent id', () async {
    final outside = File(p.join(state.path, 'outside.jsonl'));
    await outside.writeAsString(_record('linked', 'claude'));
    await Link(p.join(records, 'link.jsonl')).create(outside.path);
    expect(await readNamedRecord(state.path, 'link'), isEmpty);
  });

  test('the quit line names only a regular file whose first line is this '
      'session header', () async {
    const session = (agent: 'claude', sessionId: 'agent-1');
    Future<String?> named(String name) =>
        quitRecordId(p.join(records, '$name.jsonl'), session);
    await write('good', _record('agent-1', 'claude'));
    expect(await named('good'), 'good');
    // A record whose first lines were lost while later ones landed (an
    // earlier append failed, then the session's prompt was written).
    await write('headless', _record('agent-1', 'claude').split('\n')[1]);
    expect(await named('headless'), isNull);
    await write('other', _record('agent-2', 'claude'));
    expect(await named('other'), isNull);
    await write('agent', _record('agent-1', 'codex'));
    expect(await named('agent'), isNull);
    expect(await named('missing'), isNull);
    await Link(
      p.join(records, 'link.jsonl'),
    ).create(p.join(records, 'good.jsonl'));
    expect(await named('link'), isNull);
    expect(await quitRecordId(null, session), isNull);
  });

  test('an earlier record failing while the next one opens and prompts: '
      'the next one is not named once its later lines land', () async {
    final gate = Completer<void>();
    var ids = 0;
    final recording = FileRecording(
      state.path,
      failed: (_) {},
      uuid: () => 'rec-${ids++}',
      append: (path, text) async {
        if (p.basename(path) == 'rec-0.jsonl') {
          await gate.future;
          throw const FileSystemException('full');
        }
        await File(path).writeAsString(text, mode: FileMode.append);
      },
    );
    recording.opened(
      const RecordingSession(sessionId: 'a', agent: 'claude', cwd: '/w'),
    );
    recording.sent('t1', 'first', 0, const [], 1);
    // A's append is pending; B opens and prompts behind it.
    recording.opened(
      const RecordingSession(sessionId: 'b', agent: 'claude', cwd: '/w'),
    );
    recording.sent('t2', 'second', 0, const [], 2);
    gate.complete();
    await recording.flushed();
    recording.sent('t3', 'third', 0, const [], 3);
    await recording.flushed();
    final b = p.join(records, 'rec-1.jsonl');
    expect(await File(b).exists(), isTrue);
    // B's header went with A's failed batch; its later prompt landed.
    expect(await File(b).readAsString(), startsWith('{"type":"prompt"'));
    expect(await quitRecordId(b, (agent: 'claude', sessionId: 'b')), isNull);
  });
}

// --resume <id> and --continue read only the records their choice needs;
// the picker still reads every record.
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

SessionRecord _saved(String id, {String agent = 'claude', num at = 1}) =>
    SessionRecord(
      path: 'records/$id.jsonl',
      sessionId: id,
      agent: agent,
      cwd: 'project',
      lastUsedAt: at,
      prompt: 'saved $id',
    );

Never _fullScan() => throw StateError('the full scan was read');

void main() {
  Future<CliOutcome> run(
    List<String> args, {
    Future<List<SessionRecord>> Function()? full,
    Future<List<SessionRecord>> Function(String id)? withId,
    Future<List<SessionRecord>> Function(String id)? printed,
    Future<List<SessionRecord>> Function({
      required String agent,
      required String cwd,
    })?
    latest,
    String Function()? stateDirectory,
    StringBuffer? errors,
    bool tty = false,
  }) => runCli(
    args,
    stdout: StringBuffer(),
    stderr: errors ?? StringBuffer(),
    cwd: 'project',
    home: null,
    stdinTTY: tty,
    stdoutTTY: tty,
    lookup: (_) async => 'found',
    readSessionRecords: full,
    readSessionRecordsWithId: withId,
    readNamedSessionRecord:
        printed ?? (withId == null ? null : (_) async => const []),
    readLatestSessionRecord: latest,
    stateDirectory: stateDirectory ?? () => _fullScan(),
    pickResume:
        ({
          required sessions,
          required agent,
          required version,
          required directory,
          required cwd,
          required home,
        }) async => sessions.first,
  );

  test('--resume <id> reads the records with the id once, for the agent '
      'it names and the session, never the full scan', () async {
    final asked = <String>[];
    final outcome = await run(
      ['-r', 'known'],
      full: () async => _fullScan(),
      withId: (id) async {
        asked.add(id);
        return [
          _saved('known', agent: 'codex', at: 1),
          _saved('known', agent: 'codex', at: 5),
        ];
      },
    );
    expect(asked, ['known']);
    expect(outcome.launch?.agent?.name, 'codex');
    expect(outcome.launch?.resume?.lastUsedAt, 5);
    final errors = StringBuffer();
    final refused = await run(
      ['claude', '-r', 'known'],
      full: () async => _fullScan(),
      withId: (id) async => [_saved('known', agent: 'codex')],
      errors: errors,
    );
    expect(refused.code, 2);
    expect(
      '$errors',
      contains('Session known belongs to another agent (codex).'),
    );
  });

  test('--continue reads the latest record for the agent and directory, '
      'never the full scan', () async {
    final asked = <(String, String)>[];
    final outcome = await run(
      ['claude', '-c'],
      full: () async => _fullScan(),
      latest: ({required agent, required cwd}) async {
        asked.add((agent, cwd));
        return [_saved('latest', at: 9)];
      },
    );
    expect(asked, [('claude', 'project')]);
    expect(outcome.launch?.resume?.sessionId, 'latest');
    final errors = StringBuffer();
    final none = await run(
      ['claude', '-c'],
      full: () async => _fullScan(),
      latest: ({required agent, required cwd}) async => const [],
      errors: errors,
    );
    expect(none.code, 2);
    expect('$errors', contains('No earlier claude session in'));
  });

  test(
    'the picker reads every record, and the picked id comes from them',
    () async {
      var scans = 0;
      final outcome = await run(
        ['claude', '-r'],
        tty: true,
        full: () async {
          scans++;
          return [_saved('picked', at: 3)];
        },
        withId: (_) async => _fullScan(),
        latest: ({required agent, required cwd}) async => _fullScan(),
      );
      expect(scans, 1);
      expect(outcome.launch?.resume?.sessionId, 'picked');
    },
  );

  test('unseamed, an id and --continue read the state directory '
      'and pick what the full scan picks', () async {
    final state = await Directory.systemTemp.createTemp('chord-cli-targeted-');
    addTearDown(() => state.delete(recursive: true));
    final dir = await Directory(recordsDir(state.path)).create();
    const cwd = 'project';
    var n = 0;
    for (final (id, agent, at) in [
      ('s1', 'claude', 10),
      ('s1', 'claude', 30),
      ('s1', 'codex', 90),
      ('s2', 'claude', 20),
    ]) {
      await File(p.join(dir.path, '${n++}.jsonl')).writeAsString(
        [
          encodeRecord({
            'type': 'session',
            'version': 1,
            'sessionId': id,
            'agent': agent,
            'cwd': cwd,
            'at': 1,
          }),
          encodeRecord({
            'type': 'prompt',
            'turnId': 't',
            'prompt': 'p',
            'at': at,
            'images': 0,
          }),
        ].join(),
      );
    }
    final full = await readRecords(state.path);
    final byId = await run([
      'claude',
      '-r',
      's1',
    ], stateDirectory: () => state.path);
    expect(
      byId.launch?.resume?.record,
      sessionById(full, 's1', agent: 'claude', cwd: cwd).record,
    );
    final latest = await run([
      'claude',
      '-c',
    ], stateDirectory: () => state.path);
    expect(
      latest.launch?.resume?.record,
      latestSession(full, agent: 'claude', cwd: cwd).record,
    );
    expect(latest.launch?.resume?.sessionId, 's1');
  });

  test('--resume with a printed record id resumes that record, an agent '
      'id still resumes, another agent refuses, nothing found is bare, and '
      'a path-like id reads nothing outside records/', () async {
    final state = await Directory.systemTemp.createTemp('chord-cli-printed-');
    addTearDown(() => state.delete(recursive: true));
    final dir = await Directory(recordsDir(state.path)).create();
    String record(String id, String agent) => [
      encodeRecord({
        'type': 'session',
        'version': 1,
        'sessionId': id,
        'agent': agent,
        'cwd': 'project',
        'at': 1,
      }),
      encodeRecord({
        'type': 'prompt',
        'turnId': 't',
        'prompt': 'p',
        'at': 2,
        'images': 0,
      }),
    ].join();
    await File(
      p.join(dir.path, 'rec-1.jsonl'),
    ).writeAsString(record('agent-1', 'codex'));
    await File(
      p.join(dir.path, 'rec-2.jsonl'),
    ).writeAsString(record('agent-2', 'claude'));
    await File(
      p.join(state.path, 'escape.jsonl'),
    ).writeAsString(record('escaped', 'claude'));
    // A record with its header alone: a quit line can name one.
    await File(
      p.join(dir.path, 'rec-3.jsonl'),
    ).writeAsString(record('agent-3', 'claude').split('\n').first);
    String dirOf() => state.path;
    final headerOnly = await run(['-r', 'rec-3'], stateDirectory: dirOf);
    expect(headerOnly.launch?.agent?.name, 'claude');
    expect(headerOnly.launch?.resume?.sessionId, 'agent-3');
    expect(headerOnly.launch?.resume?.record, p.join(dir.path, 'rec-3.jsonl'));

    // The printed id, no agent named: the record's agent and session.
    final printed = await run(['-r', 'rec-1'], stateDirectory: dirOf);
    expect(printed.launch?.agent?.name, 'codex');
    expect(printed.launch?.resume?.sessionId, 'agent-1');
    expect(printed.launch?.resume?.record, p.join(dir.path, 'rec-1.jsonl'));
    // The agent's own id still resumes, by the header lookup.
    final agentId = await run(['-r', 'agent-2'], stateDirectory: dirOf);
    expect(agentId.launch?.agent?.name, 'claude');
    expect(agentId.launch?.resume?.record, p.join(dir.path, 'rec-2.jsonl'));
    // The named agent is not the record's.
    final errors = StringBuffer();
    final refused = await run(
      ['claude', '-r', 'rec-1'],
      stateDirectory: dirOf,
      errors: errors,
    );
    expect(refused.code, 2);
    expect(
      '$errors',
      contains('Session rec-1 belongs to another agent (codex).'),
    );
    // Nothing has the id: a bare resume, as before.
    for (final id in ['nothing', '../escape']) {
      final bare = await run(['claude', '-r', id], stateDirectory: dirOf);
      expect(bare.launch?.resume?.sessionId, id, reason: id);
      expect(bare.launch?.resume?.record, isNull, reason: id);
    }
  });
}

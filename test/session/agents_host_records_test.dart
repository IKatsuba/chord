// The window's agents kept in records and resumed, on the original's fake in
// a state directory of the test's own: each child's record names its parent,
// main's keeps what it served, what /new ran and what it closed, and main
// resumed draws its task's work from the task's record, names the agents it
// left open without reopening them, and close_agent still finds the task
// that ended before the resume.
@Tags(['fake_agent'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord/server/tools.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/conversation.dart' show Conversation;
import 'package:chord/session/place.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart' show Resume;
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/subagents.dart' show subagentsIn;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/agents/agents.dart' show leftOpenLine;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import '../fixtures/runtimes.dart';
import 'agents_host_test.dart' show FakeServer, until;

/// Main on the fake, kept in a record under [stateDir], with the host
/// keeping each child's beside it; resumed from [resume] when given.
final class _Rig {
  _Rig(this.runtimes, this.stateDir, {Resume? resume, String? cwd}) {
    recording = FileRecording(stateDir, failed: fail);
    connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
      resume: resume,
      recording: recording,
    );
    host = AgentsHost(
      runtimeNames: const ['fake'],
      startupOf: (runtime) => runtime == 'fake'
          ? SessionStart(command: runtimes.commandOf('fake'))
          : null,
      openChildSession: connection.openChild,
      agents: connection.agents,
      opened: (key) => connection.fold.dispatch(AgentOpened(key)),
      closed: (key, front) =>
          connection.fold.dispatch(SessionClosed(key, front)),
      server: server,
      recordingOf: (child) =>
          FileRecording(stateDir, failed: fail, child: child),
      transcriptOf: (key) => connection.fold.stateOf(key)?.transcript,
      cwd: cwd,
    );
    connection
      ..server = server
      ..window = host
      ..start();
  }

  final TestRuntimes runtimes;
  final String stateDir;
  final server = FakeServer();
  late final FileRecording recording;
  late final StartConnection connection;
  late final AgentsHost host;

  Conversation get main => connection.conversation;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);

  Transcript transcript([int key = mainKey]) =>
      connection.fold.stateOf(key)!.transcript;

  bool get idle =>
      connection.fold.stateOf(mainKey)?.transcript.turn is Idle &&
      main.queuedFrom.isEmpty;

  Future<void> connected() => until(
    () => connection.fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
}

/// Every record in [stateDir], by its header.
Future<List<List<Object?>>> _records(String stateDir) async => [
  for (final file in Directory(recordsDir(stateDir)).listSync())
    if (file is File) parseRecord(await file.readAsString()),
];

void main() {
  _testerRecordGeneration();
  test(
    "a team run left open counts its lead and the members its lead's record "
    'had open, and is said to start again with run_team',
    () async {
      final runtimes = TestRuntimes();
      addTearDown(runtimes.dispose);
      final stateDir = p.join(runtimes.home.path, 'state', 'chord');
      final cwd = p.join(runtimes.home.path, 'work');
      Directory(p.join(cwd, '.chord', 'teams')).createSync(recursive: true);
      File(p.join(cwd, '.chord', 'teams', 'bugfix.md')).writeAsStringSync(
        File(
          p.join(
            portPackageDir(),
            'test',
            'fixtures',
            'teams',
            'fake',
            'bugfix.md',
          ),
        ).readAsStringSync(),
      );
      final first = _Rig(runtimes, stateDir, cwd: cwd);
      addTearDown(first.connection.close);
      await first.connected();
      expect(first.main.send('hello'), isTrue);
      await until(() => first.idle && first.transcript().entries.length > 1);
      const args = (team: 'bugfix', job: 'text');
      final answer = await first.host.runTeam(first.person, args);
      final ran = answer as Started;
      first.host.served(
        first.person,
        ChordCall(
          tool: ChordTool.runTeam,
          input: const {'team': 'bugfix', 'job': 'text'},
          answer: ran.toJson(),
        ),
      );
      // Each has sent its first prompt, so each keeps a record.
      bool prompted(String name) {
        final child = first.connection.agents.agents.children
            .where((each) => each.name == name)
            .firstOrNull;
        return child != null &&
            first
                .transcript(child.key)
                .entries
                .whereType<UserEntry>()
                .isNotEmpty &&
            first.transcript(child.key).turn is Idle;
      }

      await until(() => prompted('bugfix'));
      final lead = Caller(
        role: Role.child,
        key: mainKey,
        agent: ran.id,
        team: TeamSide.lead,
        window: first.host,
      );
      final opened = await first.host.openMember(lead, (
        member: 'tester',
        prompt: 'text',
      ));
      final tester = opened as Started;
      first.host.served(
        lead,
        ChordCall(
          tool: ChordTool.openAgent,
          input: const {'member': 'tester', 'prompt': 'text'},
          answer: tester.toJson(),
        ),
      );
      await until(() => prompted('tester'));
      final mainId = first.main.session!.id;
      final path = first.recording.path!;
      await first.connection.close();
      final leadHeader = (await _records(stateDir))
          .map((entries) => entries.first as Map<String, Object?>)
          .singleWhere((header) => header['id'] == ran.id);
      expect(
        [leadHeader['parent'], leadHeader['name'], leadHeader['team']],
        [mainId, 'bugfix', 'bugfix'],
      );

      final second = _Rig(
        runtimes,
        stateDir,
        cwd: cwd,
        resume: Resume(
          sessionId: mainId,
          cwd: runtimes.home.path,
          record: path,
        ),
      );
      addTearDown(second.connection.close);
      await second.connected();
      expect(
        leftOpenLine(
          second.transcript().entries.whereType<LeftOpenEntry>().single.agents,
        ),
        'team bugfix (2 agents) was open when this session was left and is '
        'not reopened · /resume lists them · /team run bugfix starts the '
        'team again',
      );
      expect(
        (second.host.close(second.person, 'bugfix') as Refused).error,
        'bugfix was closed when this session was left; run_team starts the '
        'team again',
      );
    },
    skip: fakeAgentSkip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    "children keep their own records, and main resumed draws its task's "
    'work, names those left open and still closes its ended task',
    () async {
      final runtimes = TestRuntimes();
      addTearDown(runtimes.dispose);
      final stateDir = p.join(runtimes.home.path, 'state', 'chord');

      // The session as it went.
      final first = _Rig(runtimes, stateDir);
      addTearDown(first.connection.close);
      await first.connected();
      expect(first.main.send('hello'), isTrue);
      await until(() => first.idle && first.transcript().entries.length > 1);
      final task =
          await first.host.spawn(
                first.person,
                const SpawnArgs(
                  agent: 'fake',
                  prompt: 'Read the parser.',
                  name: 'reader',
                ),
              )
              as Started;
      await until(
        () => subagentsIn(first.transcript().entries).any(
          (each) => each.id == task.id && each.state != SubagentState.running,
        ),
      );
      await until(() => first.idle);
      final parser =
          await first.host.open(
                mainKey,
                const SpawnArgs(agent: 'fake', prompt: 'Read.', name: 'parser'),
                first.person,
              )
              as Started;
      final docs =
          await first.host.open(
                mainKey,
                const SpawnArgs(agent: 'fake', prompt: 'Write.', name: 'docs'),
                first.person,
              )
              as Started;
      await until(
        () => first.connection.agents.agents.children.every(
          (child) => first
              .transcript(child.key)
              .entries
              .whereType<UserEntry>()
              .isNotEmpty,
        ),
      );
      // As chord's server serves them to main, which asked.
      for (final (name, answer) in [('parser', parser), ('docs', docs)]) {
        first.host.served(
          first.person,
          ChordCall(
            tool: ChordTool.openAgent,
            input: {'agent': 'fake', 'prompt': 'Read.', 'name': name},
            answer: answer.toJson(),
          ),
        );
      }
      expect(first.host.close(first.person, 'docs'), isA<Closed>());
      final scratch =
          await first.host.newTyped('fake --name scratch', show: (_) {})
              as Started;
      const listed = ChordCall(
        tool: ChordTool.listSessions,
        input: {'n': 1},
        answer: {'sessions': <Object?>[]},
      );
      first.host.served(first.person, listed);
      final mainId = first.main.session!.id;
      final path = first.recording.path!;
      await first.connection.close();

      // Each child's record names its parent and itself.
      final records = await _records(stateDir);
      Map<String, Object?> headerOf(bool Function(Map h) test) => records
          .map((entries) => entries.first as Map<String, Object?>)
          .singleWhere(test);
      final taskHeader = headerOf((h) => h['task'] == task.id);
      expect([taskHeader['parent'], taskHeader['name']], [mainId, 'reader']);
      for (final (name, id) in [('parser', parser.id), ('docs', docs.id)]) {
        final header = headerOf((h) => h['id'] == id);
        expect([header['parent'], header['name']], [mainId, name]);
      }
      // One /new opened is only looked at until its first prompt, and
      // leaves no record, as any session only looked at.
      expect(
        records.where((entries) => (entries.first as Map)['id'] == scratch.id),
        isEmpty,
      );
      // Main's keeps what it served, what /new ran and what it closed.
      final own = parseRecord(
        await File(path).readAsString(),
      ).cast<Map<String, Object?>>();
      expect(
        own.where((line) => line['type'] == 'served').map((l) => l['call']),
        anyElement(equals(jsonDecode(jsonEncode(listed.toJson())))),
      );
      expect(
        own.singleWhere((line) => line['type'] == 'ran')['call'],
        jsonDecode(jsonEncode(newCall('fake', scratch).toJson())),
      );
      expect(own.where((line) => line['type'] == 'closed'), [
        {'type': 'closed', 'agent': docs.id},
      ]);

      // Read back: the task's work spliced, those left open named.
      final history = await readRecordedHistory(path);
      expect(
        history.actions.whereType<UpdateAction>().where(
          (action) => action.subagentId == task.id,
        ),
        isNotEmpty,
      );
      expect(history.actions.last, isA<LeftOpenAction>());

      // Resumed, on the same records.
      final second = _Rig(
        runtimes,
        stateDir,
        resume: Resume(
          sessionId: mainId,
          cwd: runtimes.home.path,
          record: path,
        ),
      );
      addTearDown(second.connection.close);
      await second.connected();
      final entries = second.transcript().entries;
      final block = subagentsIn(
        entries,
      ).singleWhere((each) => each.id == task.id);
      expect(block.task?.workLost, isFalse);
      expect(block.entries, isNotEmpty);
      expect(
        leftOpenLine(entries.whereType<LeftOpenEntry>().single.agents),
        'parser (fake) and scratch (fake) were open when this session was '
        'left and are not reopened · /resume lists them',
      );
      // Never reopened.
      expect(second.connection.agents.agents.children, isEmpty);
      final ended = second.host.close(second.person, 'reader');
      expect(ended, isA<Ended>());
      expect((ended as Ended).ended, 'reader');
      expect(
        (second.host.close(second.person, task.id) as Ended).ended,
        'reader',
      );
      expect(
        (second.host.close(second.person, 'parser') as Refused).error,
        'parser was closed when this session was left; open_agent starts '
        'another',
      );
      expect(
        (second.host.tell(second.person, 'scratch', 'hi', () {}) as Refused)
            .error,
        'scratch was closed when this session was left; open_agent starts '
        'another',
      );
      expect(
        (second.host.close(second.person, 'docs') as Refused).error,
        'No agent docs is open in this session; list_sessions names them',
      );
    },
    skip: fakeAgentSkip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

void _testerRecordGeneration() {
  group('CTUI-35 tester: child record generation', () {
    test(
      'main then child clear preserves old header and records fresh parent only in new child record',
      () async {
        final runtimes = TestRuntimes();
        addTearDown(runtimes.dispose);
        final stateDir = p.join(runtimes.home.path, 'state', 'chord');
        final rig = _Rig(runtimes, stateDir);
        addTearDown(rig.connection.close);
        await rig.connected();
        expect(rig.main.send('hello'), isTrue);
        await until(() => rig.idle && rig.transcript().entries.length > 1);
        final parentBefore = rig.main.session!.id;
        final opened =
            await rig.host.open(
                  mainKey,
                  const SpawnArgs(
                    agent: 'fake',
                    prompt: 'text',
                    name: '界🙂e\u0301',
                  ),
                  rig.person,
                )
                as Started;
        final child = rig.connection.agents.agents.children.single;
        await until(
          () =>
              rig.transcript(child.key).turn is Idle &&
              rig
                  .transcript(child.key)
                  .entries
                  .whereType<UserEntry>()
                  .isNotEmpty,
        );
        await rig.main.clear();
        await until(
          () =>
              rig.main.session != null && rig.main.session!.id != parentBefore,
        );
        final parentAfter = rig.main.session!.id;
        await rig.host.clear(rig.person, opened.id);
        await until(
          () =>
              rig.connection.fold.stateOf(child.key)?.start.phase ==
              StartPhase.connected,
        );
        expect(child.conversation.send('text'), isTrue);
        await until(
          () =>
              rig.transcript(child.key).turn is Idle &&
              rig
                  .transcript(child.key)
                  .entries
                  .whereType<UserEntry>()
                  .isNotEmpty,
        );
        await rig.connection.close();
        final records = await _records(stateDir);
        final children = records
            .map((lines) => lines.first as Map<String, Object?>)
            .where((header) => header['id'] == opened.id)
            .toList();
        expect(children, hasLength(2));
        expect(children.map((header) => header['parent']).toSet(), {
          parentBefore,
          parentAfter,
        });
        expect(children.map((header) => header['name']).toSet(), {
          '界🙂e\u0301',
        });
        expect(
          children.map((header) => header['sessionId']).toSet(),
          hasLength(2),
        );
      },
      skip: fakeAgentSkip,
    );
  });
}

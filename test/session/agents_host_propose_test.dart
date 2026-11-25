// propose_team on the original's fake through chord's own server over
// HTTP: `propose` saved for this project from the box, `proposeagain`
// after the person's "no" and words, and `proposeefforts` then its change
// replacing the saved file.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/server/server.dart' show serveChord;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/teams.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import '../fixtures/runtimes.dart';
import 'agents_host_test.dart' show until;

/// Main on the fake with chord's own server, in a project of its own.
Future<({StartConnection connection, String cwd})> _served() async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final cwd = p.join(runtimes.home.path, 'work');
  Directory(cwd).createSync(recursive: true);
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  final host = AgentsHost(
    // The fake proposes teams on claude and codex, which it never starts.
    runtimeNames: const ['fake', 'claude', 'codex'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: connection.openChild,
    agents: connection.agents,
    opened: (key) => connection.fold.dispatch(AgentOpened(key)),
    closed: (key, front) => connection.fold.dispatch(SessionClosed(key, front)),
    server: server,
    cwd: cwd,
  );
  connection
    ..server = server
    ..window = host
    ..start();
  addTearDown(() async {
    await connection.close();
    await server.close();
    runtimes.dispose();
  });
  await until(
    () => connection.fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return (connection: connection, cwd: cwd);
}

/// Waits for the save box, checks its title and question, and picks
/// [option]; the box's question back.
Future<String?> _answer(StartConnection connection, String option) async {
  Transcript transcript() => connection.fold.stateOf(mainKey)!.transcript;
  await until(() => transcript().turn is AwaitingPermission);
  final wait = (transcript().turn as AwaitingPermission).permissions.single;
  expect(wait.title, 'Team(bugfix)');
  connection.conversation.choose(wait.id, option);
  return wait.save?.question;
}

Future<void> _idle(StartConnection connection) => until(
  () =>
      connection.fold.stateOf(mainKey)!.transcript.turn is Idle &&
      connection.conversation.queuedFrom.isEmpty,
);

Team _saved(String cwd) {
  final read = parseTeam(
    'bugfix',
    File(p.join(cwd, '.chord', 'teams', 'bugfix.md')).readAsStringSync(),
    const ['claude', 'codex'],
  );
  expect(read.problem, isNull);
  return read.team!;
}

void main() {
  group('CTUI-37 tester: cancelled fake proposals', () {
    test(
      'interrupt withdraws a save and a late choice cannot write it',
      () async {
        final (:connection, :cwd) = await _served();
        connection.conversation.send('propose');
        await until(
          () =>
              connection.fold.stateOf(mainKey)!.transcript.turn
                  is AwaitingPermission,
        );
        final wait =
            (connection.fold.stateOf(mainKey)!.transcript.turn
                    as AwaitingPermission)
                .permissions
                .single;
        connection.conversation.interrupt();
        await _idle(connection);
        connection.conversation.choose(wait.id, 'project');
        await Future<void>.delayed(Duration.zero);
        expect(
          File(p.join(cwd, '.chord', 'teams', 'bugfix.md')).existsSync(),
          isFalse,
        );
        expect(connection.conversation.send('propose'), isTrue);
        await _answer(connection, 'project');
        await _idle(connection);
        expect(_saved(cwd).members, hasLength(3));
      },
      skip: fakeAgentSkip,
    );
  });

  final skip = fakeAgentSkip;

  test("propose: the person's yes saves bugfix for this project, chord "
      'writing it', () async {
    final (:connection, :cwd) = await _served();
    expect(connection.conversation.send('propose'), isTrue);
    expect(await _answer(connection, 'project'), 'Save team bugfix?');
    await _idle(connection);
    final team = _saved(cwd);
    expect(team.members.map((m) => m.name), ['tester', 'coder', 'reviewer']);
    final said = [
      for (final entry in connection.fold.stateOf(mainKey)!.transcript.entries)
        if (entry is AssistantEntry) entry.text.text,
    ];
    expect(said.last, startsWith('bugfix is saved for this project.'));
  }, skip: skip);

  test("proposeagain: after the person's no, their words get the changed "
      'team proposed, nothing written until then', () async {
    final (:connection, :cwd) = await _served();
    connection.conversation.send('propose');
    await _answer(connection, 'change');
    await _idle(connection);
    expect(
      File(p.join(cwd, '.chord', 'teams', 'bugfix.md')).existsSync(),
      isFalse,
    );
    connection.conversation.send('the reviewer on codex, please');
    await _answer(connection, 'project');
    await _idle(connection);
    final tester = _saved(cwd).members.firstWhere((m) => m.name == 'tester');
    expect(tester.mode, 'bypassPermissions');
  }, skip: skip);

  test('proposeefforts: saved with efforts, then a change replaces the '
      'saved file, the box asking to replace it', () async {
    final (:connection, :cwd) = await _served();
    connection.conversation.send('proposeefforts');
    await _answer(connection, 'project');
    await _idle(connection);
    expect(_saved(cwd).lead.effort, 'high');
    connection.conversation.send('tester on high');
    expect(await _answer(connection, 'replace'), 'Replace team bugfix?');
    await _idle(connection);
    final coder = _saved(cwd).members.firstWhere((m) => m.name == 'coder');
    expect(coder.effort, 'xhigh');
    final served = [
      for (final entry in connection.fold.stateOf(mainKey)!.transcript.entries)
        if (entry is ToolEntry && entry.call.chord != null) entry.call.chord!,
    ].where((call) => call.tool == ChordTool.proposeTeam).toList();
    expect(
      [for (final call in served) (call.answer as Map)['proposal']],
      ['new', 'change'],
    );
  }, skip: skip);
}

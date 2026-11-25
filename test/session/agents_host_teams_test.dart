// The host's team runs: run_team opening a lead with its team part, runs
// named apart and never renumbered, a lead's open_agent of its file's
// members, the frozen team, messages between a team's agents, closing a
// lead with its members, and the refusals. Main is the original's fake;
// the team's agents are scripted, so each first prompt is read whole.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/server/server.dart' show serveChord;
import 'package:chord/server/tools.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/conversation.dart' show Conversation;
import 'package:chord/session/open_agents.dart' show CloseFailures;
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import '../fixtures/runtimes.dart';
import 'agents_host_test.dart' show FakeServer, until;
import 'conversation_fake.dart' show ScriptedSession;
import 'settings_test.dart' show select, value;

final _bugfix = File(
  p.join(portPackageDir(), 'test', 'fixtures', 'teams', 'fake', 'bugfix.md'),
).readAsStringSync();

/// Main on the fake, its children scripted, in a project holding team
/// `bugfix`.
final class TeamRig {
  TeamRig() {
    final teams = Directory(
      p.join(runtimes.home.path, 'work', '.chord', 'teams'),
    )..createSync(recursive: true);
    File(p.join(teams.path, 'bugfix.md')).writeAsStringSync(_bugfix);
    cwd = p.dirname(p.dirname(teams.path));
    connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
    );
    host = AgentsHost(
      runtimeNames: const ['fake', 'codex'],
      startupOf: (runtime) => runtime == 'fake'
          ? SessionStart(command: runtimes.commandOf('fake'))
          : null,
      openChildSession:
          (
            runtime,
            start, {
            required initial,
            chordServer,
            required onTraffic,
            required cancellationToken,
          }) async {
            // On the model and mode the team file asked for, as the fake
            // offers them.
            final session = ScriptedSession()
              ..agent = runtime
              ..state = AgentState(
                configOptions: [
                  select('model', 'model', [
                    value('fake-large'),
                    value('fake-small'),
                  ], current: initial.model ?? 'fake-large'),
                  select('mode', 'mode', [
                    value('default'),
                    value('acceptEdits'),
                    value('plan'),
                  ], current: initial.mode ?? 'default'),
                ],
              );
            sessions.add(session);
            await gate?.future;
            return session;
          },
      agents: connection.agents,
      opened: (key) => connection.fold.dispatch(AgentOpened(key)),
      closed: (key, front) =>
          connection.fold.dispatch(SessionClosed(key, front)),
      server: server,
      cwd: cwd,
    );
    connection
      ..server = server
      ..window = host
      ..start();
  }

  final runtimes = TestRuntimes();
  final server = FakeServer();
  final sessions = <ScriptedSession>[];

  /// When set, each child's session opens only once it completes.
  Completer<void>? gate;
  late final String cwd;
  late final StartConnection connection;
  late final AgentsHost host;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);

  WindowAgents<Conversation> get agents => connection.agents.agents;

  Child<Conversation> named(String name) =>
      agents.children.firstWhere((child) => child.name == name);

  /// Child [name] as chord's server knows it: a lead or a member.
  Caller callerOf(String name) {
    final child = named(name);
    return Caller(
      role: Role.child,
      key: mainKey,
      agent: child.id,
      team: isLead(child.info) ? TeamSide.lead : TeamSide.member,
      window: host,
    );
  }

  /// The scripted session of child [name] once its first prompt went.
  Future<ScriptedSession> firstPromptOf(String name) async {
    await until(() => agents.children.any((child) => child.name == name));
    final child = named(name);
    await until(
      () =>
          child.conversation.session is ScriptedSession &&
          (child.conversation.session! as ScriptedSession).turns.isNotEmpty,
    );
    return child.conversation.session! as ScriptedSession;
  }

  List<UserEntry> prompts(int key) => [
    ...?connection.fold.stateOf(key)?.transcript.entries.whereType<UserEntry>(),
  ];

  Future<void> close() async {
    await connection.close();
    runtimes.dispose();
  }
}

Future<TeamRig> _started() async {
  final rig = TeamRig();
  addTearDown(rig.close);
  await until(
    () =>
        rig.connection.fold.stateOf(mainKey)?.start.phase ==
        StartPhase.connected,
  );
  return rig;
}

Future<Started> _run(TeamRig rig, [String job = 'Fix issue 214.']) async =>
    await rig.host.runTeam(rig.person, (team: 'bugfix', job: job)) as Started;

void main() {
  wireTests();

  group('tester team host failure boundaries', () {
    test('fake team2 keeps two runs and their members separate', () async {
      final connection = await _servedTeam();
      bool idle() =>
          connection.fold.stateOf(mainKey)?.transcript.turn is Idle &&
          connection.conversation.queuedFrom.isEmpty;
      expect(connection.conversation.send('team'), isTrue);
      await until(
        () => connection.agents.agents.children.length == 3 && idle(),
      );
      expect(connection.conversation.send('team2'), isTrue);
      await until(
        () => connection.agents.agents.children.length == 6 && idle(),
      );
      final children = connection.agents.agents.children;
      final leads = children.where((child) => isLead(child.info)).toList();
      expect(leads.map((lead) => lead.name), ['bugfix', 'bugfix 2']);
      for (final lead in leads) {
        expect(
          children.where((child) => child.lead == lead.id).map((c) => c.name),
          ['tester', 'coder'],
        );
      }
    }, skip: fakeAgentSkip);

    test('fake teamtask admits a main task beside the team members', () async {
      final connection = await _servedTeam();
      expect(connection.conversation.send('teamtask'), isTrue);
      await until(
        () =>
            connection.agents.agents.children.length == 3 &&
            connection.conversation.tasks.isNotEmpty,
      );
      expect(
        connection.conversation.tasks.single.start.name,
        'Fix the tokenizer',
      );
      expect(connection.agents.agents.children.map((c) => c.name), [
        'bugfix',
        'tester',
        'coder',
      ]);
      await until(
        () => connection.fold
            .stateOf(mainKey)!
            .transcript
            .entries
            .whereType<AssistantEntry>()
            .any(
              (entry) => entry.text.text.contains(
                'The team and the task are both at work.',
              ),
            ),
      );
    }, skip: fakeAgentSkip);

    test(
      'fake savedteamplain launches the saved composition without overrides',
      () async {
        final connection = await _servedTeam();
        final host = connection.window! as AgentsHost;
        final caller = Caller(role: Role.person, key: mainKey, window: host);
        final listed = await host.teams(caller);
        File(
          p.join(p.dirname(listed.found.single.file), 'fixture.md'),
        ).writeAsStringSync(_bugfix);
        expect(connection.conversation.send('savedteamplain'), isTrue);
        await until(() => connection.agents.agents.children.isNotEmpty);
        final lead = connection.agents.agents.children.single;
        expect(
          (lead.name, lead.info.team, lead.info.model, lead.info.mode),
          ('fixture', 'fixture', 'fake-large', 'default'),
        );
        await until(
          () => connection.fold
              .stateOf(mainKey)!
              .transcript
              .entries
              .whereType<AssistantEntry>()
              .any(
                (entry) => entry.text.text.contains(
                  'Ordinary saved-composition handoff completed.',
                ),
              ),
        );
      },
      skip: fakeAgentSkip,
    );
    test('edited team affects the next run but not an existing lead', () async {
      final rig = await _started();
      await _run(rig);
      final file = File(p.join(rig.cwd, '.chord', 'teams', 'bugfix.md'));
      file.writeAsStringSync(
        _bugfix.replaceAll('name: tester', 'name: checker'),
      );
      await _run(rig);
      expect(
        await rig.host.openMember(rig.callerOf('bugfix'), (
          member: 'tester',
          prompt: 'old snapshot',
        )),
        isA<Started>(),
      );
      final next = rig.callerOf('bugfix 2');
      expect(
        (await rig.host.openMember(next, (member: 'tester', prompt: 'x'))
                as Refused)
            .error,
        contains('has no member tester'),
      );
      expect(
        await rig.host.openMember(next, (
          member: 'checker',
          prompt: 'new snapshot',
        )),
        isA<Started>(),
      );
      expect(
        (await rig.firstPromptOf('tester')).turns.first.text,
        contains('old snapshot'),
      );
      expect(
        (await rig.firstPromptOf('checker')).turns.first.text,
        contains('new snapshot'),
      );
    }, skip: fakeAgentSkip);

    test(
      'member failure and exit tell only its lead while another run survives',
      () async {
        final rig = await _started();
        await _run(rig);
        await _run(rig);
        final lead = rig.named('bugfix');
        await rig.host.openMember(rig.callerOf('bugfix'), (
          member: 'tester',
          prompt: 'x',
        ));
        final member = await rig.firstPromptOf('tester');
        (await rig.firstPromptOf('bugfix')).turns.first.answer();
        member.turns.first.answer(const TurnFailed('scripted failure'));
        await until(
          () => rig
              .prompts(lead.key)
              .any(
                (entry) =>
                    entry.from?.name == 'chord' &&
                    entry.text.contains("tester's turn failed"),
              ),
        );
        expect(rig.named('tester').conversation.session, same(member));
        (await rig.firstPromptOf('bugfix')).turns.last.answer();
        member.exit('scripted exit');
        await until(
          () => rig
              .prompts(lead.key)
              .any(
                (entry) =>
                    entry.from?.name == 'chord' &&
                    entry.text.contains("tester's agent exited"),
              ),
        );
        expect((await rig.firstPromptOf('bugfix 2')).hasExited, isFalse);
        expect(
          rig
              .prompts(mainKey)
              .where(
                (entry) =>
                    entry.from?.name == 'chord' &&
                    entry.text.contains("tester's"),
              ),
          isEmpty,
        );
      },
      skip: fakeAgentSkip,
    );

    test(
      'cancelled member answers late after team close without a new turn',
      () async {
        final rig = await _started();
        await _run(rig);
        await rig.host.openMember(rig.callerOf('bugfix'), (
          member: 'tester',
          prompt: 'hang',
        ));
        final child = rig.named('tester');
        final session = await rig.firstPromptOf('tester');
        child.conversation.interrupt();
        await until(() => session.cancels == 1);
        rig.host.close(rig.person, 'bugfix');
        await until(() => session.closes == 1);
        session.turns.first.answer();
        await Future<void>.delayed(Duration.zero);
        expect(rig.agents.children, isEmpty);
        expect(session.turns, hasLength(1));
        expect(session.closes, 1);
      },
      skip: fakeAgentSkip,
    );
  });
  final skip = fakeAgentSkip;

  test("run_team opens the team's lead, named after it, on the file's "
      'runtime, model and mode, its first prompt the team part and the '
      'job', () async {
    final rig = await _started();
    final ran = await _run(rig);
    expect(ran.toJson(), {
      'id': ran.id,
      'name': 'bugfix',
      'agent': 'fake',
      'model': 'fake-large',
      'mode': 'default',
      'team': 'bugfix',
    });
    final lead = rig.named('bugfix');
    expect(
      (lead.info.team, lead.info.lead, lead.info.mode, isLead(lead.info)),
      ('bugfix', null, 'default', true),
    );
    final session = await rig.firstPromptOf('bugfix');
    final first = session.turns.first.text;
    expect(
      first,
      startsWith(
        '<team name="bugfix" role="lead">\nYou are the lead of team bugfix: '
        'a long-lived agent chord opened for main',
      ),
    );
    expect(first, contains('You work in ${rig.cwd}'));
    expect(first, contains('No other run of a team is open in this session.'));
    expect(
      first,
      endsWith('\n</team>\n<message from="main">\nFix issue 214.\n</message>'),
    );
    final caller = rig.server.admitted.values.lastWhere(
      (each) => each.agent == ran.id,
    );
    expect(caller.team, TeamSide.lead);
  }, skip: skip);

  test('a second run is numbered, names the first, and a closed run\'s '
      'number is never given again', () async {
    final rig = await _started();
    await _run(rig);
    final second = await _run(rig, 'Fix issue 219.');
    expect(second.name, 'bugfix 2');
    final part = (await rig.firstPromptOf('bugfix 2')).turns.first.text;
    expect(
      part,
      contains(
        'You are the lead of team bugfix, running as bugfix 2: a long-lived',
      ),
    );
    expect(part, contains('by these names: bugfix.'));
    expect(rig.host.close(rig.person, 'bugfix 2'), isA<Closed>());
    expect((await _run(rig)).name, 'bugfix 3');
    expect(rig.agents.runs, ['bugfix 2']);
  }, skip: skip);

  test('a team not found or a broken file is refused, as the caller lists '
      'teams', () async {
    final rig = await _started();
    File(
      p.join(rig.cwd, '.chord', 'teams', 'triage.md'),
    ).writeAsStringSync('# no frontmatter');
    Future<String> refusal(String team) async =>
        (await rig.host.runTeam(rig.person, (team: team, job: 'x')) as Refused)
            .error;
    expect(await refusal('nope'), 'No team named nope · list_teams lists them');
    expect(
      await refusal('triage'),
      '.chord/teams/triage.md is not a team chord can run: no frontmatter '
      'between --- lines',
    );
    expect(rig.agents.children, isEmpty);
  }, skip: skip);

  test("list_teams reads the files now, and each open run's lead", () async {
    final rig = await _started();
    final ran = await _run(rig);
    final found = await rig.host.teams(rig.person);
    expect([for (final team in found.found) team.name], ['bugfix']);
    expect(found.runs, [(team: 'bugfix', name: 'bugfix', id: ran.id)]);
    expect(teamsAnswer(found)['runs'], [
      {'team': 'bugfix', 'name': 'bugfix', 'id': ran.id},
    ]);
  }, skip: skip);

  test("a lead opens its file's members, after it in the list, on their "
      'runtime, model and mode, each first prompt its part and the lead\'s '
      'words', () async {
    final rig = await _started();
    final ran = await _run(rig);
    final lead = rig.callerOf('bugfix');
    final tester =
        await rig.host.openMember(lead, (
              member: 'tester',
              prompt: 'Write the test.',
            ))
            as Started;
    expect(tester.toJson(), {
      'id': tester.id,
      'name': 'tester',
      'agent': 'fake',
      'model': 'fake-small',
      'mode': 'acceptEdits',
    });
    await rig.host.openMember(lead, (member: 'coder', prompt: 'Read it.'));
    expect(
      [for (final child in rig.agents.children) child.name],
      ['bugfix', 'tester', 'coder'],
    );
    final member = rig.named('tester').info;
    expect(
      (member.team, member.lead, member.mode),
      ('bugfix', ran.id, 'acceptEdits'),
    );
    final first = (await rig.firstPromptOf('tester')).turns.first.text;
    expect(
      first,
      startsWith(
        '<team name="bugfix" role="member" member="tester">\nYou are tester, '
        'a member of team bugfix, opened by its lead, bugfix.',
      ),
    );
    expect(
      first,
      endsWith('<message from="bugfix">\nWrite the test.\n</message>'),
    );
    // Members count none of main's eight.
    expect(ownChildren(rig.agents).map((child) => child.name), ['bugfix']);
  }, skip: skip);

  test("a lead's open_agent refusals: a member open, one the team lacks, a "
      'lead closed', () async {
    final rig = await _started();
    await _run(rig);
    final lead = rig.callerOf('bugfix');
    Future<String> refusal(String member) async =>
        (await rig.host.openMember(lead, (member: member, prompt: 'x'))
                as Refused)
            .error;
    await rig.host.openMember(lead, (member: 'tester', prompt: 'x'));
    expect(await refusal('tester'), 'tester is open; send_message reaches it');
    expect(
      await refusal('reviewer'),
      'Team bugfix has no member reviewer; its members are tester and coder',
    );
    rig.host.close(rig.person, 'bugfix');
    expect(await refusal('coder'), 'You are closed; you open no members');
  }, skip: skip);

  test('two open_agent calls for one member at once start one', () async {
    final rig = await _started();
    await _run(rig);
    final lead = rig.callerOf('bugfix');
    final both = await Future.wait([
      rig.host.openMember(lead, (member: 'tester', prompt: 'x')),
      rig.host.openMember(lead, (member: 'tester', prompt: 'x')),
    ]);
    expect(both.whereType<Started>(), hasLength(1));
    expect(
      both.whereType<Refused>().single.error,
      'tester is open; send_message reaches it',
    );
  }, skip: skip);

  test('a run keeps the team its file had when it started', () async {
    final rig = await _started();
    await _run(rig);
    File(p.join(rig.cwd, '.chord', 'teams', 'bugfix.md')).deleteSync();
    expect(
      await rig.host.openMember(rig.callerOf('bugfix'), (
        member: 'tester',
        prompt: 'x',
      )),
      isA<Started>(),
    );
  }, skip: skip);

  test("messages: a lead reaches main, its members and other runs' leads; a "
      'member its lead and the other members, straight', () async {
    final rig = await _started();
    await _run(rig);
    await _run(rig, 'Another.');
    final lead = rig.callerOf('bugfix');
    await rig.host.openMember(lead, (member: 'tester', prompt: 'x'));
    await rig.host.openMember(lead, (member: 'coder', prompt: 'x'));
    Map<String, Object?> tell(Caller from, String to) =>
        rig.host.tell(from, to, 'hello', () {}).toJson();
    final tester = rig.callerOf('tester');
    expect(tell(lead, 'main')['to'], 'main');
    expect(tell(lead, 'tester')['delivered'], isNotNull);
    expect(tell(lead, 'bugfix 2')['delivered'], isNotNull);
    expect(tell(tester, 'coder')['delivered'], isNotNull);
    expect(tell(tester, 'bugfix')['delivered'], isNotNull);
    expect(tell(tester, 'main'), {
      'error': 'No agent main is open for you; you reach bugfix and coder',
    });
    expect(tell(lead, 'nope'), {
      'error':
          'No agent nope is open for you; you reach main, tester, coder, and '
          'bugfix 2',
    });
    await until(
      () => rig.prompts(mainKey).any((prompt) => prompt.from?.name == 'bugfix'),
    );
    rig.host.close(lead, 'coder');
    expect(tell(tester, 'coder'), {
      'error': 'coder is closed; bugfix can open it again',
    });
    expect(tell(lead, 'coder'), {
      'error': 'coder is closed; open_agent opens it again',
    });
  }, skip: skip);

  test('close_agent: a lead closes its members, a member only its tasks, '
      'main a lead with its members', () async {
    final rig = await _started();
    await _run(rig);
    final lead = rig.callerOf('bugfix');
    await rig.host.openMember(lead, (member: 'tester', prompt: 'x'));
    await rig.host.openMember(lead, (member: 'coder', prompt: 'x'));
    expect(
      (rig.host.close(rig.callerOf('tester'), 'coder') as Refused).error,
      "No task coder of yours; spawn_task's answer names them",
    );
    expect((rig.host.close(lead, 'coder') as Closed).closed, 'coder');
    expect(
      (rig.host.close(lead, 'coder') as Refused).error,
      'No member coder of yours is open',
    );
    expect((rig.host.close(rig.person, 'bugfix') as Closed).closed, 'bugfix');
    expect(rig.agents.children, isEmpty);
    expect(rig.agents.runs, ['bugfix']);
  }, skip: skip);

  test("the person's x on a lead closes the team and tells main its "
      'members', () async {
    final rig = await _started();
    final ran = await _run(rig);
    await rig.host.openMember(rig.callerOf('bugfix'), (
      member: 'tester',
      prompt: 'x',
    ));
    expect(rig.host.closeByPerson(rig.named('bugfix').key), ['tester']);
    expect(rig.agents.children, isEmpty);
    await until(
      () => rig.prompts(mainKey).any((prompt) => prompt.from?.name == 'chord'),
    );
    expect(
      rig.prompts(mainKey).lastWhere((p) => p.from?.name == 'chord').text,
      'The person closed team bugfix: its lead (fake · fake-large, id '
      '${ran.id}) and its members tester. It takes no more messages; '
      'run_team starts it again.',
    );
  }, skip: skip);

  test("a lead's exit closes its members and tells main", () async {
    final rig = await _started();
    await _run(rig);
    await rig.host.openMember(rig.callerOf('bugfix'), (
      member: 'tester',
      prompt: 'x',
    ));
    (await rig.firstPromptOf('bugfix')).exit('out of memory');
    await until(() => rig.agents.children.length < 2);
    await until(
      () => rig.prompts(mainKey).any((prompt) => prompt.from?.name == 'chord'),
    );
    expect(
      rig.prompts(mainKey).lastWhere((p) => p.from?.name == 'chord').text,
      "bugfix's lead exited: out of memory. Its members are closed; "
      'run_team starts the team again.',
    );
    expect(rig.agents.children.map((child) => child.name), ['bugfix']);
  }, skip: skip);

  test('two run_team calls at once are named apart', () async {
    final rig = await _started();
    final both = await Future.wait([
      rig.host.runTeam(rig.person, (team: 'bugfix', job: 'one')),
      rig.host.runTeam(rig.person, (team: 'bugfix', job: 'two')),
    ]);
    expect(
      [for (final ran in both.cast<Started>()) ran.name],
      // Whichever read its file first is the first run.
      unorderedEquals(['bugfix', 'bugfix 2']),
    );
  }, skip: skip);

  test("a lead closed while its open_agent waits opens no member", () async {
    final rig = await _started();
    await _run(rig);
    await rig.firstPromptOf('bugfix');
    final lead = rig.callerOf('bugfix');
    final opening = rig.host.openMember(lead, (member: 'tester', prompt: 'x'));
    // Closed while the open waits on what the runtime offers.
    rig.host.close(rig.person, 'bugfix');
    expect(
      ((await opening) as Refused).error,
      'You are closed; you open no members',
    );
    expect(rig.agents.children, isEmpty);
  }, skip: skip);

  test("main's clear while a lead starts lets its launch go: the lead gets "
      'no first job and closes', () async {
    final rig = await _started();
    rig.gate = Completer();
    // Answered at once, as the lead is placed; its first job waits on it.
    final ran = await _run(rig);
    await until(() => rig.sessions.isNotEmpty);
    await rig.connection.conversation.clear();
    rig.gate!.complete();
    await until(() => !rig.agents.children.any((c) => c.id == ran.id));
    expect(rig.sessions.single.turns, isEmpty);
  }, skip: skip);

  test("closing a lead starts every member's close and the lead's at once, "
      'and closeAll reports every failure', () async {
    final rig = await _started();
    await _run(rig);
    final leadSession = await rig.firstPromptOf('bugfix');
    await rig.host.openMember(rig.callerOf('bugfix'), (
      member: 'tester',
      prompt: 'x',
    ));
    final memberSession = await rig.firstPromptOf('tester');
    // Each close hangs until released, then fails.
    final leadGone = Completer<void>(), memberGone = Completer<void>();
    leadSession.closing = () async {
      await leadGone.future;
      throw StateError('lead stuck');
    };
    memberSession.closing = () async {
      await memberGone.future;
      throw StateError('tester stuck');
    };
    rig.host.closeByPerson(rig.named('bugfix').key);
    // The lead's close has started while the member's still hangs.
    await until(() => leadSession.closes == 1 && memberSession.closes == 1);
    expect((leadGone.isCompleted, memberGone.isCompleted), (false, false));
    memberGone.complete();
    leadGone.complete();
    await expectLater(
      rig.connection.agents.closeAll(),
      throwsA(
        isA<CloseFailures>().having(
          (failures) => [for (final e in failures.errors) '$e'],
          'errors',
          unorderedEquals(['Bad state: lead stuck', 'Bad state: tester stuck']),
        ),
      ),
    );
  }, skip: skip);

  test('a ninth run is refused; members never count', () async {
    final rig = await _started();
    for (var i = 0; i < 8; i++) {
      await _run(rig);
    }
    expect(
      (await rig.host.runTeam(rig.person, (team: 'bugfix', job: 'x'))
              as Refused)
          .error,
      'This session has 8 agents open; close_agent one first',
    );
    expect(
      await rig.host.openMember(rig.callerOf('bugfix'), (
        member: 'tester',
        prompt: 'x',
      )),
      isA<Started>(),
    );
  }, skip: skip);
}

/// Main on the fake with chord's own server, its children on the fake too,
/// in a project holding the fake's team `bugfix`.
Future<StartConnection> _servedTeam() async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final teams = Directory(p.join(runtimes.home.path, 'work', '.chord', 'teams'))
    ..createSync(recursive: true);
  File(p.join(teams.path, 'bugfix.md')).writeAsStringSync(_bugfix);
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  final host = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: connection.openChild,
    agents: connection.agents,
    opened: (key) => connection.fold.dispatch(AgentOpened(key)),
    closed: (key, front) => connection.fold.dispatch(SessionClosed(key, front)),
    server: server,
    cwd: p.dirname(p.dirname(teams.path)),
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
  return connection;
}

void wireTests() {
  test("the fake's team hands bugfix a job; its lead opens tester and coder "
      'and reports to main, over HTTP', () async {
    final connection = await _servedTeam();
    expect(connection.conversation.send('team'), isTrue);
    List<String> names() => [
      for (final child in connection.agents.agents.children) child.name,
    ];
    await until(() => names().length == 3);
    expect(names(), ['bugfix', 'tester', 'coder']);
    final lead = connection.agents.agents.children.first;
    expect(isLead(lead.info), isTrue);
    for (final member in connection.agents.agents.children.skip(1)) {
      expect((member.info.team, member.info.lead), ('bugfix', lead.id));
    }
    await until(
      () => [
        ...?connection.fold
            .stateOf(mainKey)
            ?.transcript
            .entries
            .whereType<UserEntry>(),
      ].any((entry) => entry.from?.name == 'bugfix'),
    );
  }, skip: fakeAgentSkip);
}

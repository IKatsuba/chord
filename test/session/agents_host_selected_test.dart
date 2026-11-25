// Selected team runs on the original's fake: the fake's `selectedteam`
// over chord's own server, the refusals before anything opens, a lead the
// runtime does not confirm, and the receipt's later updates appended to the
// record captured when the launch was admitted, after a /clear too, an
// attempt refused before any prompt kept for /resume. Records live in a
// state directory of the test's own.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/server/server.dart' show ChordServer, serveChord;
import 'package:chord/server/tools.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart' show recordActions;
import 'package:chord/session/sessions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/team_selection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord/ui/transcript/tools/selection_lines.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import '../fixtures/runtimes.dart';
import 'agents_host_test.dart' show until;

const _team = '''
---
description: Frozen selection fixture
lead:
  agent: fake
members:
  - name: reviewer
    role: Review only
    agent: fake
    instructions: Preserve this exact review instruction.
---
Preserve the exact team body and permissions.
''';

const _reason = 'Keep every instruction and permission; capacity is unknown.';

typedef _Policy = Future<({Map<String, Object?>? policy, String? error})>;

/// Main on the fake with chord's own server, every child on the fake as
/// `fake`, `codex` or `claude`, in a project holding team `fixture`, each
/// session's record under [stateDir].
final class _Rig {
  _Rig._(this.server, this.policy) {
    final teams = Directory(p.join(cwd, '.chord', 'teams'))
      ..createSync(recursive: true);
    File(p.join(teams.path, 'fixture.md')).writeAsStringSync(_team);
    recording = FileRecording(stateDir, failed: fail);
    connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
      recording: recording,
    );
    host = AgentsHost(
      runtimeNames: const ['fake', 'codex', 'claude'],
      startupOf: (runtime) =>
          SessionStart(command: runtimes.commandOf(runtime)),
      // A child's session opens once [gate], when set, lets it.
      openChildSession:
          (
            runtime,
            start, {
            required initial,
            chordServer,
            required onTraffic,
            required cancellationToken,
          }) async {
            await gate?.future;
            return connection.openChild(
              runtime,
              start,
              initial: initial,
              chordServer: chordServer,
              onTraffic: onTraffic,
              cancellationToken: cancellationToken,
            );
          },
      agents: connection.agents,
      opened: (key) => connection.fold.dispatch(AgentOpened(key)),
      closed: (key, front) =>
          connection.fold.dispatch(SessionClosed(key, front)),
      server: server,
      recordingOf: (child) =>
          FileRecording(stateDir, failed: fail, child: child),
      transcriptOf: (key) => connection.fold.stateOf(key)?.transcript,
      cwd: cwd,
      selectionPolicy: () => policy(),
    );
    connection
      ..server = server
      ..window = host
      ..start();
  }

  static Future<_Rig> started({_Policy Function()? policy}) async {
    final rig = _Rig._(
      await serveChord(),
      policy ?? () async => (policy: const <String, Object?>{}, error: null),
    );
    addTearDown(() async {
      await rig.connection.close();
      await rig.server.close();
      rig.runtimes.dispose();
    });
    await until(
      () =>
          rig.connection.fold.stateOf(mainKey)?.start.phase ==
          StartPhase.connected,
    );
    return rig;
  }

  final ChordServer server;
  _Policy Function() policy;

  /// When set, holds every child's session open until it completes.
  Completer<void>? gate;
  final runtimes = TestRuntimes(
    fakes: const {
      'fake': (scenario: null, flags: []),
      'codex': (scenario: null, flags: []),
      'claude': (scenario: null, flags: []),
    },
  );
  late final cwd = p.join(runtimes.home.path, 'work');
  late final stateDir = p.join(runtimes.home.path, 'state', 'chord');
  late final FileRecording recording;
  late final StartConnection connection;
  late final AgentsHost host;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);

  WindowAgents get agents => connection.agents.agents;

  Transcript transcript([int key = mainKey]) =>
      connection.fold.stateOf(key)!.transcript;

  /// The `run_team` calls the transcript of [key] ties to its rows.
  List<ChordCall> runCalls([int key = mainKey]) => [
    for (final entry in transcript(key).entries)
      if (entry is ToolEntry && entry.call.chord?.tool == ChordTool.runTeam)
        entry.call.chord!,
    ...transcript(key).served.where((call) => call.tool == ChordTool.runTeam),
  ];

  Future<RunTeamAnswer> run(Object selection) => host.runTeam(person, (
    team: 'fixture',
    job: 'selectedidle',
  ), selection: selection);
}

/// The `served` `run_team` lines of the record at [path], in order.
/// None while the record is not written yet.
List<Map<String, Object?>> _servedRuns(String path) => [
  if (File(path).existsSync())
    for (final line in parseRecord(File(path).readAsStringSync()))
      if (line case {
        'type': 'served',
        'call': {'tool': 'run_team'} && final Map<String, Object?> call,
      })
        call,
];

Map _role(Map<String, Object?> receipt, String name) =>
    (receipt['roles'] as List).cast<Map>().firstWhere(
      (role) => role['name'] == name,
    );

/// The `run_team` receipt replay of the record at [path] draws last for
/// run [id].
SelectionReceipt? _replayed(String path, String id) {
  final history = recordActions(parseRecord(File(path).readAsStringSync()));
  return [
    for (final action in history.actions)
      if (action is ServedAction)
        if (recordedSelection(action.call) case final receipt?
            when receipt['runId'] == id)
          receipt,
  ].lastOrNull;
}

void main() {
  final skip = fakeAgentSkip;

  test("a selected lead's late refusal after main was resumed into another "
      'record lands in the record its launch was admitted to', () async {
    final rig = await _Rig.started();
    // The session to resume later: a record of its own.
    expect(rig.connection.conversation.send('hello'), isTrue);
    await until(
      () =>
          rig.transcript().entries.whereType<UserEntry>().isNotEmpty &&
          rig.transcript().turn is Idle,
    );
    final earlier = rig.connection.conversation.session!.id;
    final replacement = rig.recording.path!;
    await rig.connection.conversation.clear();
    await until(
      () =>
          rig.connection.fold.stateOf(mainKey)?.start.phase ==
          StartPhase.connected,
    );
    expect(rig.connection.conversation.send('hello'), isTrue);
    await until(() => rig.recording.path != replacement);
    final admitted = rig.recording.path!;
    expect(admitted, isNot(replacement));
    // The lead admitted, its start held.
    rig.gate = Completer();
    final run = rig.run({'reason': _reason});
    await until(() => _servedRuns(admitted).isNotEmpty);
    final id = _servedRuns(admitted).single['asked'] as String;
    final replacementBefore = _servedRuns(replacement).length;
    // Main replaced by the earlier session, a record of its own.
    await rig.connection.conversation.resume(
      Resume(
        sessionId: earlier,
        cwd: rig.runtimes.home.path,
        record: replacement,
      ),
    );
    await until(() => rig.recording.path == replacement);
    rig.gate!.complete();
    expect(await run, isA<RunRefused>());
    await rig.recording.flushed();
    await until(
      () =>
          _servedRuns(admitted).length > 1 &&
          _role(
                (_servedRuns(admitted).last['answer'] as Map)['receipt']
                    as Map<String, Object?>,
                'lead',
              )['state'] ==
              'refused',
    );
    expect(_servedRuns(replacement), hasLength(replacementBefore));
    expect(_role(_replayed(admitted, id)!, 'lead')['state'], 'refused');
  }, skip: skip);

  test('a selected lead\'s late refusal after main closed lands in the '
      'admitted record, and an attempt with no prompt keeps it for '
      '/resume', () async {
    final rig = await _Rig.started();
    rig.gate = Completer();
    final run = rig.run({'reason': _reason});
    await until(() => rig.recording.path != null);
    final admitted = rig.recording.path!;
    await until(() => _servedRuns(admitted).isNotEmpty);
    final id = _servedRuns(admitted).single['asked'] as String;
    // Main closed, as the window closes it, the lead still held.
    await rig.connection.conversation.close();
    rig.gate!.complete();
    expect(await run, isA<RunRefused>());
    await rig.recording.flushed();
    await until(
      () =>
          _servedRuns(admitted).length > 1 &&
          _role(
                (_servedRuns(admitted).last['answer'] as Map)['receipt']
                    as Map<String, Object?>,
                'lead',
              )['state'] ==
              'refused',
    );
    expect(_role(_replayed(admitted, id)!, 'lead')['state'], 'refused');
    final listed = await readRecords(rig.stateDir);
    expect(
      [
        for (final record in listed)
          if (record.path == admitted) record.prompt,
      ],
      ['Team attempt: fixture'],
    );
  }, skip: skip);

  test("the fake's selectedteam opens the lead on the frozen choice over "
      'chord\'s server and its row draws the confirmed receipt', () async {
    final rig = await _Rig.started();
    expect(rig.connection.conversation.send('selectedteam'), isTrue);
    await until(
      () => rig.agents.children.any((child) => child.name == 'fixture'),
    );
    final lead = rig.agents.children.firstWhere((c) => c.name == 'fixture');
    expect(
      (lead.runtime, lead.info.model, lead.info.mode),
      ('codex', 'fake-small', 'plan'),
    );
    await until(
      () => rig.runCalls().any(
        (call) =>
            recordedSelection(call) != null &&
            _role(recordedSelection(call)!, 'lead')['state'] == 'confirmed',
      ),
    );
    final call = rig.runCalls().lastWhere(
      (call) => recordedSelection(call) != null,
    );
    final receipt = recordedSelection(call)!;
    expect(call.asked, receipt['runId']);
    expect(_role(receipt, 'lead')['actual'], {
      'agent': 'codex',
      'model': 'fake-small',
      'mode': 'plan',
      'effort': 'medium',
    });
    expect(_role(receipt, 'reviewer')['state'], 'planned');
    expect(
      selectionLines(receipt),
      containsAllInOrder([
        'Selection: agent-selected · this run',
        'Reason: Preserve all instructions and exact permission requirements; '
            'capacity is unknown.',
        'Billing: unknown · advisory',
        'Planned for this run:',
        'lead (lead): codex · model fake-small · effort agent default '
            '(unconfirmed) · mode plan',
        'Actual: confirmed · session runtime codex · model fake-small · '
            'effort medium · mode plan',
        'reviewer: fake · model fake-small · effort agent default '
            '(unconfirmed) · mode plan',
        'Actual: not opened · configuration unconfirmed',
        'ctrl+o for saved definition and changes',
      ]),
    );
  }, skip: skip);

  test("the fake's budgetawareteam reads the teams, agents and budgets, "
      'then selects the lead for this run only', () async {
    final rig = await _Rig.started();
    expect(rig.connection.conversation.send('budgetawareteam'), isTrue);
    await until(
      () => rig.runCalls().any(
        (call) =>
            recordedSelection(call) != null &&
            _role(recordedSelection(call)!, 'lead')['state'] == 'confirmed',
      ),
    );
    final lead = rig.agents.children.firstWhere((c) => c.name == 'fixture');
    expect(
      (lead.runtime, lead.info.model, lead.info.mode),
      ('fake', 'fake-small', 'plan'),
    );
    final receipt = recordedSelection(
      rig.runCalls().lastWhere((call) => recordedSelection(call) != null),
    )!;
    expect(_role(receipt, 'lead')['saved'], {'agent': 'fake'});
    expect(_role(receipt, 'lead')['planned'], {
      'agent': 'fake',
      'model': 'fake-small',
      'mode': 'plan',
    });
    // The saved file is the same as before the run.
    expect(
      File(p.join(rig.cwd, '.chord', 'teams', 'fixture.md')).readAsStringSync(),
      _team,
    );
  }, skip: skip);

  test('refusals before anything opens: the policy, its settings, the '
      'saved file', () async {
    final rig = await _Rig.started();
    rig.policy = () async => (
      policy: const <String, Object?>{
        'constraints': {
          'agents': ['claude'],
        },
      },
      error: null,
    );
    Future<String> refusal(Object selection) async =>
        (await rig.run(selection) as Refused).error;
    expect(
      await refusal({'reason': _reason}),
      'lead.agent: the choice is outside the configured allowlist. No run '
      'started. Choose a supported configuration.',
    );
    rig.policy = () => throw StateError('unreadable');
    expect(
      await refusal({'reason': _reason}),
      'Team selection settings could not be validated. Correct the settings '
      'before selecting a team.',
    );
    rig.policy = () async => (policy: const <String, Object?>{}, error: null);
    expect(
      await refusal({'reason': ' '}),
      'Invalid run selection. No run started.',
    );
    expect(
      await refusal({
        'reason': _reason,
        'members': {'ghost': <String, Object?>{}},
      }),
      'Unknown selected member ghost. No run started.',
    );
    File(
      p.join(rig.cwd, '.chord', 'teams', 'fixture.md'),
    ).writeAsStringSync('# no frontmatter');
    expect(
      await refusal({'reason': _reason}),
      'The saved team is invalid. No run started.',
    );
    expect(rig.agents.children, isEmpty);
  }, skip: skip);

  test('a lead its runtime does not confirm is refused before its first '
      'job, the attempt kept in the record though main sent no prompt, and '
      '/resume lists it as a team attempt', () async {
    final rig = await _Rig.started();
    final answer = await rig.run({
      'reason': _reason,
      'lead': {'agent': 'claude', 'model': 'no-such-model', 'mode': 'plan'},
    });
    expect(answer, isA<RunRefused>());
    final refused = answer as RunRefused;
    expect(
      refused.error,
      'Team launch ${refused.id} was refused before its first job; the '
      'attempted lead is closing.',
    );
    expect(_role(refused.receipt!, 'lead')['state'], 'refused');
    await until(() => rig.agents.children.isEmpty);
    // The attempt's record is main's, though main never prompted.
    final path = rig.recording.path!;
    await rig.recording.flushed();
    await until(() => _servedRuns(path).isNotEmpty);
    final last = _servedRuns(path).last;
    expect(last['asked'], refused.id);
    expect(last['error'], startsWith('Team launch ${refused.id}: '));
    final listed = await readRecords(rig.stateDir);
    expect(
      listed.where((record) => record.prompt == 'Team attempt: fixture'),
      hasLength(1),
    );
  }, skip: skip);

  test("a receipt's later update after main's /clear is appended to the "
      'record the launch was admitted to, never the fresh one', () async {
    final rig = await _Rig.started();
    expect(rig.connection.conversation.send('hello'), isTrue);
    await until(
      () => rig.transcript().entries.whereType<UserEntry>().isNotEmpty,
    );
    final ran = await rig.run({'reason': _reason}) as Started;
    final before = rig.recording.path!;
    final lead = rig.agents.children.firstWhere((c) => c.name == 'fixture');
    await until(
      () => _servedRuns(before).any(
        (call) =>
            _role(
              (call['answer'] as Map)['receipt'] as Map<String, Object?>,
              'lead',
            )['state'] ==
            'confirmed',
      ),
    );
    await rig.connection.conversation.clear();
    // The member's admission now refused by the policy as it reads now.
    rig.policy = () async => (
      policy: const <String, Object?>{
        'constraints': {
          'agents': ['claude'],
        },
      },
      error: null,
    );
    final member = await rig.host.openMember(
      Caller(
        role: Role.child,
        key: mainKey,
        agent: lead.id,
        team: TeamSide.lead,
        window: rig.host,
      ),
      (member: 'reviewer', prompt: 'selectedidle'),
    );
    expect(
      (member as Refused).error,
      'reviewer.agent: the choice is outside the configured allowlist. This '
      'member was not started.',
    );
    await rig.recording.flushed();
    await until(
      () =>
          _servedRuns(before).isNotEmpty &&
          _role(
                (_servedRuns(before).last['answer'] as Map)['receipt']
                    as Map<String, Object?>,
                'reviewer',
              )['state'] ==
              'refused',
    );
    expect(_servedRuns(before).last['asked'], ran.id);
    final after = rig.recording.path;
    if (after != null && after != before && File(after).existsSync()) {
      expect(_servedRuns(after), isEmpty);
    }
    // Replayed, the record draws the latest receipt once, at the run's row.
    final history = recordActions(parseRecord(File(before).readAsStringSync()));
    final served = [
      for (final action in history.actions)
        if (action is ServedAction && action.call.tool == ChordTool.runTeam)
          action.call,
    ];
    expect(served, isNotEmpty);
    expect(
      _role(recordedSelection(served.last)!, 'reviewer')['state'],
      'refused',
    );
    expect(
      jsonEncode(served.last.input['selection']),
      jsonEncode({'reason': _reason}),
    );
  }, skip: skip);
}

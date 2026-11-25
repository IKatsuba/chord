// A window the tools read, with three runtimes, one read, one failing,
// one never read, that records what it was served.
import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/server/runtimes.dart';
import 'package:chord/session/budgets.dart';
import 'package:chord/server/tools.dart';
import 'package:chord/session/monitors.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/settings.dart';
import 'package:chord/settings_tool.dart';

const readOffer = Offer(
  models: [(id: 'fake-large', name: 'Fake Large', efforts: null, effort: null)],
  current: 'fake-large',
  modes: [(id: 'default', name: 'Default'), (id: 'plan', name: 'Plan')],
  currentMode: 'default',
);

/// A window of three runtimes, one read, one failing, one never read, that
/// records what it was served and answers each call as [answers] says.
class FakeWindow implements WindowView {
  FakeWindow({List<OpenSessionView>? sessions})
    : _sessions =
          sessions ??
          [
            (
              key: 0,
              runtime: 'fake',
              id: 'one',
              model: 'fake-large',
              children: const [],
            ),
          ];

  final List<OpenSessionView> _sessions;
  final probed = <String>[];
  final calls = <ChordCall>[];
  final later = <ChordCall>[];
  void Function()? queue;
  SpawnAnswer spawned = const Refused('no tasks here');
  OpenAnswer opened = const Refused('no agents here');
  MessageAnswer told = const Refused('no children here');
  CloseAnswer closed = const Refused('no children here');
  ClearAnswer cleared = const Refused('no children here');
  MonitorAnswer monitored = const Refused('no monitors here');
  StopMonitorAnswer stopped = const Refused('no monitors here');
  List<RunningMonitor> running = const [];
  final asked = <MonitorArgs>[];

  /// Where settings are read and written; none until a test places them.
  SettingsWhere where = const SettingsWhere(
    configHome: null,
    cwd: '.',
    home: null,
  );

  /// What the person picks in the settings box, by option id; null
  /// withdraws it; [signal] is the call's own, cancelled with it. Each
  /// question asked, as its title and box.
  Future<String?> Function(String title, SaveBox save, CancellationToken signal)
  picks = (_, _, _) async => null;
  final questions = <(String, String, List<acp.PermissionOption>, SaveBox)>[];
  final saved = <(List<String>, SettingChange)>[];
  final claim = settingsBoxClaim();

  @override
  Future<String?> askPerson(
    Caller caller, {
    required String title,
    required String detail,
    required List<acp.PermissionOption> options,
    required SaveBox save,
    required CancellationToken signal,
  }) {
    questions.add((title, detail, options, save));
    return picks(title, save, signal);
  }

  @override
  ({SettingsWhere where, String agent}) settingsWhere(Caller caller) =>
      (where: where, agent: 'fake');

  @override
  void Function()? claimSettingsBox() => claim();

  @override
  void settingSaved(List<String> path, SettingChange change) =>
      saved.add((path, change));

  @override
  List<OpenSessionView> sessions() => _sessions;

  @override
  Future<MonitorAnswer> monitor(Caller caller, MonitorArgs args) async {
    asked.add(args);
    return monitored;
  }

  @override
  StopMonitorAnswer stopMonitor(Caller caller, String id) => stopped;

  @override
  List<RunningMonitor> monitors(Caller caller) => running;

  @override
  List<String> runtimes() => ['fake', 'broken', 'claude'];

  @override
  Future<RuntimeOffer?> offer(
    String runtime, {
    required bool probe,
    int? key,
  }) async {
    if (probe) probed.add(runtime);
    return switch (runtime) {
      'fake' => readOffer,
      'broken' => const OfferError('Unknown agent "broken".'),
      _ => probe ? readOffer : null,
    };
  }

  @override
  Future<SpawnAnswer> spawn(Caller caller, SpawnArgs args) async => spawned;

  @override
  Future<OpenAnswer> open(int key, SpawnArgs args, Caller caller) async =>
      opened;

  @override
  MessageAnswer message(Caller caller, String text, void Function() queued) {
    queue = queued;
    return told;
  }

  @override
  MessageAnswer tell(
    Caller caller,
    String to,
    String text,
    void Function() queued,
  ) {
    queue = queued;
    return told;
  }

  @override
  CloseAnswer close(Caller caller, String to) => closed;

  /// When set, clear_agent waits on it, as a fresh session starting.
  Completer<ClearAnswer>? clearing;

  @override
  Future<ClearAnswer> clear(Caller caller, String to) async =>
      clearing == null ? cleared : clearing!.future;

  @override
  void served(Caller caller, ChordCall call) => calls.add(call);

  @override
  void Function(ChordCall call) servedLater(Caller caller) => later.add;

  TeamsFound teamsFound = (found: const [], runs: const []);
  RunTeamAnswer ran = const Refused('no teams here');
  OpenAnswer member = const Refused('no members here');
  final runArgs = <RunTeamArgs>[];

  /// Where a proposal goes; none saved, both places, until a test says.
  TeamPlaces places = (
    agent: 'fake',
    project: (
      file: '/w/.chord/teams/bugfix.md',
      shown: '.chord/teams/bugfix.md',
    ),
    user: (
      file: '/c/chord/teams/bugfix.md',
      shown: '~/.config/chord/teams/bugfix.md',
    ),
    saved: null,
  );

  @override
  Future<TeamPlaces> teamPlaces(Caller caller, String name) async => places;
  final memberArgs = <MemberArgs>[];

  /// What get_budgets reads; null reads none.
  Budgets? budgetsRead;
  final budgetsAsked = <List<String>?>[];

  @override
  Future<Budgets>? budgets(
    Caller caller,
    List<String>? agents,
    CancellationToken cancelled,
  ) {
    budgetsAsked.add(agents);
    final read = budgetsRead;
    return read == null ? null : Future.value(read);
  }

  @override
  Future<TeamsFound> teams(Caller caller) async => teamsFound;

  @override
  Future<RunTeamAnswer> runTeam(
    Caller caller,
    RunTeamArgs args, {
    Object? selection,
  }) async {
    runArgs.add(args);
    selections.add(selection);
    return ran;
  }

  /// The selection each run_team carried, null for none.
  final selections = <Object?>[];

  @override
  Future<OpenAnswer> openMember(Caller caller, MemberArgs args) async {
    memberArgs.add(args);
    return member;
  }
}

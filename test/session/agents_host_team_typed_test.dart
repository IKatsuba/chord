// The person's /team in the host: the listing the picker reads, a run
// /team run starts with its call drawn and main told ahead of its next
// turn, /team stop closing a run with its members, and /team show of a
// saved team and of one running. Main is the original's fake; the team's
// agents are scripted.
@Tags(['fake_agent'])
library;

import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord/ui/teams/teams.dart' show teamWords;
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import 'agents_host_teams_test.dart' show TeamRig;
import 'agents_host_test.dart' show until;
import 'package:chord/ui/start_state.dart';

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

void main() {
  final skip = fakeAgentSkip;

  test("the picker's listing: the teams read now, the runs open and the two "
      'places as shown', () async {
    final rig = await _started();
    final empty = (await rig.host.listTeams())!;
    expect(
      [for (final team in empty.teams) team.shown],
      ['.chord/teams/bugfix.md'],
    );
    expect(empty.runs, isEmpty);
    expect(empty.dirs, (project: '.chord/teams', user: null));
    final ran = await rig.host.runTyped('bugfix', 'Fix it.');
    final listing = (await rig.host.listTeams())!;
    expect(
      [for (final run in listing.runs) (run.team, run.name)],
      [('bugfix', 'bugfix')],
    );
    expect(ran.ran!.answer, isA<Map<String, Object?>>());
  }, skip: skip);

  test('/team run starts the run as run_team does, its call to draw', () async {
    final rig = await _started();
    final answer = await rig.host.runTyped('bugfix', 'Fix issue 214.');
    final call = answer.ran!;
    expect(call.tool, ChordTool.runTeam);
    expect(call.input, {'team': 'bugfix', 'job': 'Fix issue 214.'});
    expect((call.answer! as Map)['name'], 'bugfix');
    expect(rig.named('bugfix').info.team, 'bugfix');
    expect(
      (await rig.host.runTyped('nope', 'x')).refused,
      'No team named nope · /team lists them',
    );
  }, skip: skip);

  test('/team stop closes the run and its members, said first; a run not '
      'open is refused', () async {
    final rig = await _started();
    await rig.host.runTyped('bugfix', 'Fix it.');
    await rig.firstPromptOf('bugfix');
    await rig.host.openMember(rig.callerOf('bugfix'), (
      member: 'tester',
      prompt: 'x',
    ));
    final said = <(String, bool)>[];
    rig.host.stopTyped(
      'bugfix',
      teamWords,
      (text, {required failed}) => said.add((text, failed)),
    );
    expect(said, [
      (
        'Stopped bugfix: its lead and tester are closed · /resume lists them',
        false,
      ),
    ]);
    expect(rig.agents.children, isEmpty);
    rig.host.stopTyped(
      'bugfix',
      teamWords,
      (text, {required failed}) => said.add((text, failed)),
    );
    expect(said.last, (
      'No run named bugfix is open · the list under the prompt names them',
      true,
    ));
  }, skip: skip);

  test('/team show: a saved team as its file has it; one running filled '
      'from what its agents do', () async {
    final rig = await _started();
    final saved = await rig.host.showTyped(
      'bugfix',
      (file, lead, team, job, members) => throw StateError('not running'),
    );
    expect((saved.shown! as ShownTeam).running, isNull);
    expect((saved.shown! as ShownTeam).file, '.chord/teams/bugfix.md');
    expect(
      (await rig.host.showTyped('nope', (a, b, c, d, e) => throw '')).refused,
      'No team named nope · /team lists them',
    );
    await rig.host.runTyped('bugfix', 'Fix it.');
    final running = await rig.host.showTyped(
      'bugfix',
      (file, lead, team, job, members) => ShownTeam(
        name: 'bugfix',
        file: file,
        team: team,
        running: TeamRunShown(
          name: lead.name,
          since: 0,
          at: 0,
          job: job,
          agents: const [],
        ),
      ),
    );
    expect((running.shown! as ShownTeam).running!.job, 'Fix it.');
    expect((running.shown! as ShownTeam).running!.name, 'bugfix');
  }, skip: skip);
}

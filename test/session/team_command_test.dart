import 'package:chord/session/team_command.dart';
import 'package:chord/teams.dart';
import 'package:test/test.dart';

const TeamWords _words = (
  whichRun: 'which run, host?',
  closedLead: 'the host has it',
  closedRun: 'the host has them',
  noRun: 'the host names them',
);

ListedTeam _found({Team? team, String? problem}) => (
  found: FoundTeam(
    name: 'triage',
    file: '/w/.chord/teams/triage.md',
    place: TeamPlace.project,
    hides: false,
    team: team,
    problem: problem,
  ),
  shown: 'triage.md',
);

void main() {
  group('tester team command boundaries', () {
    test(
      'JavaScript whitespace separates commands and collapses run names',
      () {
        expect(teamCommand('\uFEFF\u00A0list\u2028', _words), isA<TeamList>());
        expect(
          teamCommand('stop\u00A0bugfix\u2028\t2', _words),
          isA<TeamStop>().having((c) => c.name, 'name', 'bugfix 2'),
        );
        expect(
          teamCommand('run\u00A0bugfix\t界😀é\nnext\uFEFF', _words),
          isA<TeamRunJob>()
              .having((c) => c.name, 'name', 'bugfix')
              .having((c) => c.job, 'job', '界😀é\nnext'),
        );
      },
    );
  });

  test('/team reads its form, then a name, then the rest', () {
    expect(teamCommand('', _words), isA<TeamList>());
    expect(teamCommand('list', _words), isA<TeamList>());
    expect(
      teamCommand('new fixes bugs', _words),
      isA<TeamNew>().having((c) => c.words, 'words', 'fixes bugs'),
    );
    expect(
      teamCommand('show bugfix', _words),
      isA<TeamShow>().having((c) => c.name, 'name', 'bugfix'),
    );
    expect(
      teamCommand('run bugfix issue 214', _words),
      isA<TeamRunJob>()
          .having((c) => c.name, 'name', 'bugfix')
          .having((c) => c.job, 'job', 'issue 214'),
    );
    expect(
      teamCommand('stop bugfix  2', _words),
      isA<TeamStop>().having((c) => c.name, 'name', 'bugfix 2'),
    );
    expect(
      teamCommand('  run bugfix\n line one\nline two ', _words),
      isA<TeamRunJob>().having((c) => c.job, 'job', 'line one\nline two'),
    );
  });

  test("/team stop with no run answers in the host's words, the rest in "
      "/team's", () {
    String? refused(String args) => switch (teamCommand(args, _words)) {
      TeamRefused(:final problem) => problem,
      _ => null,
    };
    expect(refused('stop'), 'which run, host?');
    expect(refused('show'), 'Which team? /team lists them');
    expect(refused('run'), 'Which team? /team lists them');
    expect(
      refused('run bugfix'),
      '/team run bugfix takes the job after the name',
    );
    expect(
      refused('new'),
      '/team new takes a few words about the work the team does',
    );
    expect(
      refused('nope'),
      '/team has no nope; it takes list, new, show, run or stop',
    );
  });

  test("what /team stop says ends in the host's words", () {
    expect(
      stoppedLine('bugfix', [], _words),
      'Stopped bugfix: its lead is closed · the host has it',
    );
    expect(
      stoppedLine('bugfix', ['tester', 'coder'], _words),
      'Stopped bugfix: its lead, tester, and coder are closed · the host has '
      'them',
    );
  });

  test('a team not found, or broken, is refused; a good one is not', () {
    expect(teamRefusal('nope', null), 'No team named nope · /team lists them');
    expect(
      teamRefusal('triage', _found(problem: 'no lead')),
      'triage.md is not a team chord can run:\nno lead',
    );
    expect(
      teamRefusal(
        'triage',
        _found(
          team: const Team(
            description: 'd',
            lead: TeamLead(agent: 'claude'),
            members: [],
            body: 'b',
          ),
        ),
      ),
      isNull,
    );
  });

  test('the note to main names the job, the lead and how to reach it', () {
    expect(
      ranNote('bugfix', 'bugfix 2', 'issue 214'),
      'The person handed team bugfix this job: "issue 214". Its lead is '
      '@bugfix 2 and reports to you; send_message reaches it.',
    );
  });

  test('where teams are saved, and the words around a team', () {
    expect(
      teamsSaved((project: '/w/.chord/teams', user: null)),
      'Saved for this project in /w/.chord/teams.',
    );
    expect(
      teamsSaved((project: '/w/.chord/teams', user: '~/.config/chord/teams')),
      'Saved for this project in /w/.chord/teams, and for every project in '
      '~/.config/chord/teams.',
    );
    expect(
      noTeams,
      'No teams yet. /team new and a few words about the work makes one.',
    );
    expect(
      leadRole,
      'Splits the job, says who edits which files, reports to main',
    );
    expect(newTeamPrompt('fix bugs'), endsWith('modes).\n\nfix bugs'));
    expect(briefly(41000), '41s');
    expect(briefly(6 * 60000 + 5000), '6m');
  });
}

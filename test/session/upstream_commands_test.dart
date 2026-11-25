// What chord's commands say under `chord acp`: the original's
// tests/session/upstream_commands_test.ts.
import 'package:chord/session/team_command.dart';
import 'package:chord/session/upstream_commands.dart';
import 'package:chord/teams.dart' hide teamText;
import 'package:test/test.dart';

const _team = Team(
  description: 'Fixes a reported bug',
  lead: TeamLead(agent: 'claude', model: 'opus', effort: 'high', mode: 'auto'),
  members: [
    TeamMember(
      name: 'developer',
      role: 'Builds the fix',
      agent: 'claude',
      model: 'opus',
      mode: 'auto',
      instructions: 'x',
    ),
    TeamMember(
      name: 'tester',
      role: 'Tests the fix',
      agent: 'codex',
      mode: 'agent',
      instructions: 'x',
    ),
  ],
  body: '',
);

ListedTeam _found({
  String name = 'bugfix',
  TeamPlace place = TeamPlace.project,
  bool hides = false,
  Team? team = _team,
  String? problem,
}) => (
  found: FoundTeam(
    name: name,
    file: '/a/$name.md',
    place: place,
    hides: hides,
    team: problem == null ? team : null,
    problem: problem,
  ),
  shown: '.chord/teams/$name.md',
);

const _dirs = (project: '.chord/teams', user: '~/.config/chord/teams');
const _now = 360000;

TeamListing _listing({
  List<ListedTeam> teams = const [],
  List<TeamRun> runs = const [],
  ({String project, String? user}) dirs = _dirs,
}) => (teams: teams, runs: runs, dirs: dirs);

void main() {
  group('/team list', () {
    test('a team a line, its parts joined; then no run, where they go, '
        'what to type', () {
      expect(
        teamsText(
          _listing(
            teams: [
              _found(),
              _found(name: 'wide', place: TeamPlace.user),
              _found(name: 'near', hides: true),
              _found(name: 'broken', problem: 'description is required'),
            ],
          ),
          _now,
        ),
        [
          'Teams:',
          '',
          '- bugfix · 3 agents · claude, codex · this project · Fixes a '
              'reported bug',
          '- wide · 3 agents · claude, codex · every project · Fixes a '
              'reported bug',
          "- near · 3 agents · claude, codex · this project · hides every "
              "project's · Fixes a reported bug",
          '- broken · not read: description is required',
          '',
          'No run is open.',
          '',
          'Saved for this project in .chord/teams, and for every project in '
              '~/.config/chord/teams.',
          '',
          '/team show and a name shows a team; /team run, a name and a job '
              'starts one.',
        ].join('\n'),
      );
    });

    test('a run says how long, several say how many', () {
      const TeamRun one = (id: null, team: 'bugfix', name: 'bugfix', since: 0);
      const TeamRun two = (
        id: null,
        team: 'bugfix',
        name: 'bugfix 2',
        since: 0,
      );
      expect(
        teamsText(_listing(teams: [_found()], runs: [one]), _now),
        contains(
          '- bugfix · 3 agents · claude, codex · this project · working 6m · '
          'Fixes',
        ),
      );
      expect(
        teamsText(_listing(teams: [_found()], runs: [one]), _now),
        contains('Runs open:\n\n- bugfix · team bugfix · working 6m'),
      );
      expect(
        teamsText(_listing(teams: [_found()], runs: [one, two]), _now),
        contains('this project · 2 runs · Fixes'),
      );
    });

    test('no team: the window line in its place, and no line about what to '
        'type', () {
      expect(
        teamsText(_listing(dirs: (project: '.chord/teams', user: null)), _now),
        [
          'No teams yet. /team new and a few words about the work makes one.',
          '',
          'No run is open.',
          '',
          'Saved for this project in .chord/teams.',
        ].join('\n'),
      );
    });

    test('nothing in it a renderer could take for a tag', () {
      expect(
        teamsText(_listing(teams: [_found()]), _now),
        isNot(matches(RegExp('[<>]'))),
      );
    });
  });

  group('/team show', () {
    test('a team not running: an unset value is left out', () {
      expect(
        teamText('bugfix', '.chord/teams/bugfix.md', _team),
        [
          'bugfix · .chord/teams/bugfix.md',
          '',
          'Fixes a reported bug',
          '',
          'Agents:',
          '',
          '- lead · claude · opus · high · auto · Splits the job, says who '
              'edits which files, reports to main',
          '- developer · claude · opus · auto · Builds the fix',
          '- tester · codex · agent · Tests the fix',
        ].join('\n'),
      );
    });

    test('a running one: its header on one line, and which are open', () {
      expect(
        runText(
          name: 'bugfix 2',
          file: '.chord/teams/bugfix.md',
          team: _team,
          job: 'the login\ntest fails',
          since: 0,
          open: const ['developer'],
          now: _now,
        ),
        [
          'bugfix 2 · .chord/teams/bugfix.md · working 6m on "the login test '
              'fails"',
          '',
          'Fixes a reported bug',
          '',
          'Agents:',
          '',
          '- lead (bugfix 2) · open · claude · opus · high · auto · Splits the '
              'job, says who edits which files, reports to main',
          '- developer · open · claude · opus · auto · Builds the fix',
          '- tester · not open · codex · agent · Tests the fix',
        ].join('\n'),
      );
    });

    test('a selected run is refused, naming its run id', () {
      expect(
        selectedRunRefusal('bugfix', '7f3a9c21'),
        "bugfix is a selected run, and only chord's window shows its "
        "receipt: chord -r with this session's id, then /team show 7f3a9c21 "
        'there',
      );
    });
  });

  group('a file that tries to make rows of its own', () {
    const hostile = Team(
      description: 'Fixes bugs\n\n- fake · row\r\nAgents:',
      lead: TeamLead(
        agent: 'claude',
        model: 'opus',
        effort: 'high',
        mode: 'auto',
      ),
      members: [
        TeamMember(
          name: 'tester',
          role: 'Tests\n- another · fake row',
          agent: 'codex',
          instructions: 'x',
        ),
      ],
      body: '',
    );
    List<String> rows(String text) => [
      for (final line in text.split('\n'))
        if (line.startsWith('- ')) line,
    ];

    test('stays one row each in /team show, not running and running', () {
      expect(rows(teamText('bugfix', 'a.md', hostile)), hasLength(2));
      final running = runText(
        name: 'bugfix',
        file: 'a.md',
        team: hostile,
        job: 'a job',
        since: 0,
        open: const [],
        now: _now,
      );
      expect(rows(running), hasLength(2));
      expect(running, contains('Fixes bugs - fake · row Agents:\n\nAgents:'));
      expect(running, contains('Tests - another · fake row'));
    });

    for (final separator in ['\v', '\f', '\u0085', '\u2028', '\u2029']) {
      test('any line separator goes too: ${separator.codeUnitAt(0)}', () {
        final text = teamText(
          'bugfix',
          'a.md',
          Team(
            description: 'Fixes$separator- fake · row',
            lead: _team.lead,
            members: _team.members,
            body: '',
          ),
        );
        expect(text, contains('\n\nFixes - fake · row\n\n'));
      });
    }

    test('stays one row in /team list, a broken file too', () {
      final text = teamsText(
        _listing(
          teams: [
            _found(team: hostile),
            _found(name: 'broken', problem: 'bad\n- fake · row'),
          ],
        ),
        _now,
      );
      expect(rows(text), hasLength(2));
      expect(text, contains('- broken · not read: bad - fake · row'));
    });
  });

  group('the other replies', () {
    test('/team run names the lead by its run, bare', () {
      expect(
        startedText('bugfix', 'bugfix 2'),
        'Team bugfix started. Its lead is bugfix 2; /team stop bugfix 2 ends '
        'it.',
      );
      expect(
        startedText('bugfix', 'bugfix', 'A note.'),
        'Team bugfix started. Its lead is bugfix; /team stop bugfix ends it.'
        '\n\nA note.',
      );
    });

    test('/new says it is idle and what starts it', () {
      expect(
        openedText('codex 2', 'codex'),
        "Opened codex 2 (codex). It is idle, with no prompt yet; main's "
        'send_message starts it, so ask main to send it the work.',
      );
    });

    test('a command beside other blocks ran nothing', () {
      expect(
        notAloneRefusal('team'),
        '/team takes text alone, and this prompt had other blocks beside it. '
        'Nothing ran; send the command by itself.',
      );
    });
  });

  test("chord acp's /team words say where runs are named", () {
    expect(acpTeamWords.whichRun, 'Which run? /team lists them');
    expect(acpTeamWords.noRun, '/team lists them');
    expect(
      acpTeamWords.closedLead,
      "chord with its agent's name and -r lists it",
    );
    expect(
      acpTeamWords.closedRun,
      "chord with each agent's name and -r lists them",
    );
  });
}

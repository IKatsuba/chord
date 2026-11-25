/// `/team`'s words read, and what chord says of a run, whoever hosts it.
/// Nothing here reads a file or a session; the host gathers what each
/// needs. From the original's `src/session/team_command.ts`.
library;

import '../js_trim.dart';
import '../teams.dart';
import 'elapsed.dart';

export '../teams.dart' show andList;

/// What only the host can say, as it names where the host shows things.
typedef TeamWords = ({
  /// Answers `/team stop` with no run, which has to say where runs are named.
  String whichRun,

  /// Ends what `/team stop` says of a lead closed alone: where to find it.
  String closedLead,

  /// Ends what `/team stop` says of a lead and members: where to find them.
  String closedRun,

  /// Ends what `/team stop` says of no such run: where runs are named.
  String noRun,
});

/// A team file as the picker lists it, its path as the window shows it.
typedef ListedTeam = ({FoundTeam found, String shown});

/// A team's run open in the window, as the picker and `/team show` read it.
typedef TeamRun = ({
  String? id,

  /// The team's file name.
  String team,

  /// The run's name, its lead's: `bugfix`, `bugfix 2`.
  String name,

  /// When its lead opened, on chord's clock, in milliseconds.
  int since,
});

/// What `/team`'s picker and names read: the teams, the runs, the two
/// places.
typedef TeamListing = ({
  List<ListedTeam> teams,
  List<TeamRun> runs,
  ({String project, String? user}) dirs,
});

/// What `/team` was asked, by the words after it.
sealed class TeamCommand {
  const TeamCommand();
}

/// `/team` or `/team list`.
final class TeamList extends TeamCommand {
  const TeamList();
}

/// `/team new <words>`.
final class TeamNew extends TeamCommand {
  const TeamNew(this.words);

  final String words;
}

/// `/team show <name>`.
final class TeamShow extends TeamCommand {
  const TeamShow(this.name);

  final String name;
}

/// `/team run <name> <job>`.
final class TeamRunJob extends TeamCommand {
  const TeamRunJob(this.name, this.job);

  final String name;
  final String job;
}

/// `/team stop <run>`.
final class TeamStop extends TeamCommand {
  const TeamStop(this.name);

  final String name;
}

/// Words `/team` cannot read, and what it says of them.
final class TeamRefused extends TeamCommand {
  const TeamRefused(this.problem);

  final String problem;
}

final _split = RegExp(r'^(\S*)\s*([\s\S]*)$');

/// `/team`'s words read: the form, then a team's name, then the rest, which
/// is a new team's description or a job. `stop` takes a run's name whole,
/// as a second run is `bugfix 2`.
TeamCommand teamCommand(String args, TeamWords words) {
  final first = _split.firstMatch(jsTrim(args));
  final form = first?[1] ?? '';
  final rest = first?[2] ?? '';
  final second = _split.firstMatch(rest);
  final name = second?[1] ?? '';
  final job = second?[2] ?? '';
  const which = 'Which team? /team lists them';
  switch (form) {
    case '':
    case 'list':
      return const TeamList();
    case 'new':
      return rest.isEmpty
          ? const TeamRefused(
              '/team new takes a few words about the work the team does',
            )
          : TeamNew(rest);
    case 'show':
      return name.isEmpty ? const TeamRefused(which) : TeamShow(name);
    case 'run':
      return name.isEmpty
          ? const TeamRefused(which)
          : job.isEmpty
          ? TeamRefused('/team run $name takes the job after the name')
          : TeamRunJob(name, job);
    case 'stop':
      return rest.isEmpty
          ? TeamRefused(words.whichRun)
          : TeamStop(rest.replaceAll(RegExp(r'\s+'), ' '));
    default:
      return TeamRefused(
        '/team has no $form; it takes list, new, show, run or stop',
      );
  }
}

/// What chord tells main, ahead of its next turn, of a run the person
/// started with `/team run`, which main took no part in.
String ranNote(String team, String lead, String job) =>
    'The person handed team $team this job: "$job". Its lead is '
    '@$lead and reports to you; send_message reaches it.';

/// Why `/team run` or `/team show` found no team by [name], or a file that
/// is not one; null for a team it can run.
String? teamRefusal(String name, ListedTeam? found) {
  if (found == null) return 'No team named $name · /team lists them';
  final problem = found.found.problem;
  return problem == null
      ? null
      : '${found.shown} is not a team chord can run:\n$problem';
}

/// What `/team stop` says of the run it closed: its lead, and the members
/// open with it.
String stoppedLine(String run, List<String> members, TeamWords words) =>
    members.isEmpty
    ? 'Stopped $run: its lead is closed · ${words.closedLead}'
    : 'Stopped $run: ${andList(['its lead', ...members])} are closed · '
          '${words.closedRun}';

/// What chord says with no team saved.
const noTeams =
    'No teams yet. /team new and a few words about the work makes one.';

/// The lead's role, which the file has no line for.
const leadRole = 'Splits the job, says who edits which files, reports to main';

/// What main gets for `/team new <words>`: the words, after one line that
/// names the tool which makes a team, so the agent proposes one rather than
/// answers in prose.
String newTeamPrompt(String words) =>
    'The person asks for a team of agents through /team new: work '
    "out the team for what they describe below, then call chord's "
    "propose_team with it (list_agents gives each runtime's models and "
    'modes).\n\n$words';

/// Where teams are saved, whole.
String teamsSaved(({String project, String? user}) dirs) => dirs.user == null
    ? 'Saved for this project in ${dirs.project}.'
    : 'Saved for this project in ${dirs.project}, and for every project in '
          '${dirs.user}.';

/// The first unit of an elapsed time: `41s`, `6m`.
String briefly(num ms) => formatElapsed(ms).split(' ').first;

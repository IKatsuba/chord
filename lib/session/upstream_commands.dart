/// What chord's commands say under `chord acp`, from the original's
/// `session/upstream_commands.ts`: plain text for a client's own interface,
/// which may render it as markdown and in a proportional font, so one thing
/// a line, no columns and no angle brackets.
library;

import '../teams.dart';
import 'team_command.dart';

/// `/team`'s words where no window shows a list under a prompt.
const TeamWords acpTeamWords = (
  whichRun: 'Which run? /team lists them',
  closedLead: "chord with its agent's name and -r lists it",
  closedRun: "chord with each agent's name and -r lists them",
  noRun: '/team lists them',
);

/// What a command came to, and whether it was refused.
typedef CommandSaid = ({String text, bool failed});

/// A command's one chunk under [sessionId], marked as chord's.
Map<String, Object?> commandChunk(
  String sessionId,
  String name,
  String text,
  bool failed,
) => {
  'sessionId': sessionId,
  'update': {
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
    '_meta': {
      'chord/command': {'name': name, 'failed': failed},
    },
  },
};

final _breaks = RegExp('\\s*[\\n\\v\\f\\r\\u0085\\u2028\\u2029]+\\s*');

/// What a file says, on one line: a repo's file must not make rows or
/// blocks of its own in what chord says. A client treats it as untrusted,
/// as an agent's.
String _oneLine(String text) => text.replaceAll(_breaks, ' ').trim();

String _joined(List<String?> parts) => [
  for (final part in parts) ?(part == null ? null : _oneLine(part)),
].join(' · ');

String _teamRow(ListedTeam listed, List<TeamRun> runs, num now) {
  final found = listed.found;
  final team = found.team;
  if (team == null) {
    return '- ${_joined([found.name, 'not read: ${found.problem}'])}';
  }
  final own = [
    for (final run in runs)
      if (run.team == found.name) run,
  ];
  final runtimes = {
    team.lead.agent,
    for (final member in team.members) member.agent,
  };
  return '- ${_joined([found.name, '${team.members.length + 1} agents', runtimes.join(', '), found.place == TeamPlace.user
      ? 'every project'
      : found.hides
      ? "this project · hides every project's"
      : 'this project', own.isEmpty
      ? null
      : own.length == 1
      ? 'working ${briefly(now - own.single.since)}'
      : '${own.length} runs', team.description])}';
}

/// `/team list`: the teams, the runs, where they are saved, what to type.
String teamsText(TeamListing listing, num now) => [
  listing.teams.isEmpty
      ? noTeams
      : 'Teams:\n\n${[for (final found in listing.teams) _teamRow(found, listing.runs, now)].join('\n')}',
  listing.runs.isEmpty
      ? 'No run is open.'
      : 'Runs open:\n\n${[for (final run in listing.runs) '- ${run.name} · team ${run.team} · working ${briefly(now - run.since)}'].join('\n')}',
  teamsSaved(listing.dirs),
  if (listing.teams.isNotEmpty)
    '/team show and a name shows a team; /team run, a name and a job starts '
        'one.',
].join('\n\n');

List<String?> _agentParts(
  String agent,
  String? model,
  String? effort,
  String? mode,
) => [agent, model, effort, mode];

/// `/team show` of a team not running.
String teamText(String name, String file, Team team) => [
  _joined([name, file]),
  _oneLine(team.description),
  'Agents:\n\n${[
    '- ${_joined(['lead', ..._agentParts(team.lead.agent, team.lead.model, team.lead.effort, team.lead.mode), leadRole])}',
    for (final member in team.members) '- ${_joined([member.name, ..._agentParts(member.agent, member.model, member.effort, member.mode), member.role])}',
  ].join('\n')}',
].join('\n\n');

/// `/team show` of a run: its header, whole, and which of its agents are
/// open; [open] its members open now, by name.
String runText({
  required String name,
  required String file,
  required Team team,
  required String job,
  required num since,
  required List<String> open,
  required num now,
}) => [
  '$name · $file · working ${briefly(now - since)} on '
      '"${job.replaceAll(RegExp(r'\s+'), ' ').trim()}"',
  _oneLine(team.description),
  'Agents:\n\n${[
    '- ${_joined(['lead ($name)', 'open', ..._agentParts(team.lead.agent, team.lead.model, team.lead.effort, team.lead.mode), leadRole])}',
    for (final member in team.members) '- ${_joined([member.name, open.contains(member.name) ? 'open' : 'not open', ..._agentParts(member.agent, member.model, member.effort, member.mode), member.role])}',
  ].join('\n')}',
].join('\n\n');

/// Why `/team show` shows no selected run: only a window draws its
/// receipt.
String selectedRunRefusal(String typed, String runId) =>
    "$typed is a selected run, and only chord's window shows its receipt: "
    "chord -r with this session's id, then /team show $runId there";

/// `/team run`, started: the run's lead is [lead].
String startedText(String team, String lead, [String? note]) => _withNote(
  'Team $team started. Its lead is $lead; /team stop $lead ends it.',
  note,
);

String _withNote(String words, String? note) =>
    note == null ? words : '$words\n\n$note';

/// `/new`, opened: [name] of [runtime], idle until main sends it work.
String openedText(String name, String runtime, [String? note]) => _withNote(
  'Opened $name ($runtime). It is idle, with no prompt yet; main\'s '
  'send_message starts it, so ask main to send it the work.',
  note,
);

/// A command with other blocks beside it.
String notAloneRefusal(String name) =>
    '/$name takes text alone, and this prompt had other blocks beside it. '
    'Nothing ran; send the command by itself.';

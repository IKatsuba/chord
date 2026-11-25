/// Team files: a team's agents in YAML frontmatter, how the team works in the
/// markdown body after it. They live in `.chord/teams/` for the project and in
/// `teams/` beside the user's settings file for every project, and are read
/// whenever they are needed, never at start, so a file saved elsewhere counts
/// at once. From the original's `src/teams.ts`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'agent_name.dart';
import 'js_trim.dart';
import 'settings.dart' show userSettingsFile;
import 'yaml_stringify.dart';

/// A team's name, which is also its lead's name in the list and messages.
final _teamName = RegExp(r'^[a-z][a-z0-9-]{0,23}$');

/// A member's name, short enough for the list's name column.
final _memberName = RegExp(r'^[a-z][a-z0-9-]{0,15}$');

/// Names that already mean an agent of the session.
const _taken = ['main', 'chord'];

/// The most members one lead holds, as it is one of main's 8 children.
const maxMembers = 8;

const _equality = DeepCollectionEquality();

/// A team's lead as its file says it. Model, effort and mode ids are not
/// checked here: only an agent's runtime knows them.
final class TeamLead {
  /// A lead on [agent]'s runtime, with what the file gives besides.
  const TeamLead({
    required this.agent,
    this.model,
    this.effort,
    this.mode,
    this.instructions,
  });

  final String agent;
  final String? model;
  final String? effort;
  final String? mode;
  final String? instructions;

  /// The lead as the frontmatter holds it, in the file's key order, with
  /// what is not given left out.
  Map<String, String> toMap() => {
    'agent': agent,
    'model': ?model,
    'effort': ?effort,
    'mode': ?mode,
    'instructions': ?instructions,
  };

  @override
  bool operator ==(Object other) =>
      other is TeamLead && _equality.equals(toMap(), other.toMap());

  @override
  int get hashCode => _equality.hash(toMap());
}

/// A team's member as its file says it.
final class TeamMember {
  /// A member named [name] on [agent]'s runtime.
  const TeamMember({
    required this.name,
    required this.role,
    required this.agent,
    this.model,
    this.effort,
    this.mode,
    required this.instructions,
  });

  final String name;
  final String role;
  final String agent;
  final String? model;
  final String? effort;
  final String? mode;
  final String instructions;

  /// The member as the frontmatter holds it, in the file's key order.
  Map<String, String> toMap() => {
    'name': name,
    'role': role,
    'agent': agent,
    'model': ?model,
    'effort': ?effort,
    'mode': ?mode,
    'instructions': instructions,
  };

  @override
  bool operator ==(Object other) =>
      other is TeamMember && _equality.equals(toMap(), other.toMap());

  @override
  int get hashCode => _equality.hash(toMap());
}

/// A team as its file says it, checked.
final class Team {
  /// A checked team.
  const Team({
    required this.description,
    required this.lead,
    required this.members,
    required this.body,
  });

  final String description;
  final TeamLead lead;
  final List<TeamMember> members;

  /// How the team works, in markdown, without the blank lines around it.
  final String body;

  /// The frontmatter as it is written, the body left out.
  Map<String, Object> frontmatter() => {
    'description': description,
    'lead': lead.toMap(),
    'members': [for (final member in members) member.toMap()],
  };

  /// The team as JSON, its body after its frontmatter, as a call's answer
  /// holds it.
  Map<String, Object> toJson() => {...frontmatter(), 'body': body};

  @override
  bool operator ==(Object other) =>
      other is Team &&
      body == other.body &&
      _equality.equals(frontmatter(), other.frontmatter());

  @override
  int get hashCode => Object.hash(body, _equality.hash(frontmatter()));
}

/// [json] read back as the team it was written as, by [Team.toJson] or as
/// `propose_team`'s input that passed the check; null for anything that is
/// not one.
Team? teamFromJson(Object? json) {
  if (json is! Map) return null;
  String? text(Map<Object?, Object?> map, String key) =>
      map[key] is String ? map[key] as String : null;
  final lead = json['lead'];
  final members = json['members'];
  final description = text(json, 'description');
  final body = text(json, 'body');
  if (lead is! Map ||
      members is! List ||
      description == null ||
      body == null ||
      text(lead, 'agent') == null) {
    return null;
  }
  final read = <TeamMember>[];
  for (final member in members) {
    if (member is! Map) return null;
    final (name, role, agent, instructions) = (
      text(member, 'name'),
      text(member, 'role'),
      text(member, 'agent'),
      text(member, 'instructions'),
    );
    if (name == null || role == null || agent == null || instructions == null) {
      return null;
    }
    read.add(
      TeamMember(
        name: name,
        role: role,
        agent: agent,
        model: text(member, 'model'),
        effort: text(member, 'effort'),
        mode: text(member, 'mode'),
        instructions: instructions,
      ),
    );
  }
  return Team(
    description: description,
    lead: TeamLead(
      agent: text(lead, 'agent')!,
      model: text(lead, 'model'),
      effort: text(lead, 'effort'),
      mode: text(lead, 'mode'),
      instructions: text(lead, 'instructions'),
    ),
    members: read,
    body: body,
  );
}

/// A team checked, or the first problem with it.
typedef TeamRead = ({Team? team, String? problem});

/// Where a team is saved.
enum TeamPlace { project, user }

/// A team file found, read and checked, or the first problem with it.
final class FoundTeam {
  /// A file found at [file], with [team] or [problem].
  const FoundTeam({
    required this.name,
    required this.file,
    required this.place,
    required this.hides,
    this.team,
    this.problem,
  });

  final String name;
  final String file;
  final TeamPlace place;

  /// A project's team that hides the user's file of the same name.
  final bool hides;
  final Team? team;
  final String? problem;
}

/// The two directories teams are saved in; none for the user without a
/// config home.
({String project, String? user}) teamDirs({
  required String? configHome,
  required String cwd,
}) {
  final settings = userSettingsFile(configHome);
  return (
    project: p.join(cwd, '.chord', 'teams'),
    user: settings == null ? null : p.join(p.dirname(settings), 'teams'),
  );
}

/// The file a team of [name] is saved to in [dir].
String teamFile(String dir, String name) => p.join(dir, '$name.md');

/// Why [name] cannot name a team, or null when it can.
String? teamNameProblem(String name) =>
    agentNameProblem(name) ??
    (!_teamName.hasMatch(name)
        ? 'the name $name must be a lowercase letter, then up to 23 of a-z, '
              '0-9 and -'
        : _taken.contains(name)
        ? 'the name $name is taken'
        : null);

/// The first problem the check met, as zod's first issue.
final class _Issue implements Exception {
  _Issue(this.path, this.message, {this.code = 'custom', this.key});

  final List<Object> path;
  final String message;
  final String code;

  /// The first unknown key, for an `unrecognized_keys` issue.
  final String? key;
}

const _missing = 'missing';

/// zod's issue in its path's words, as the settings files' problems are:
/// `members.1.agent is missing`.
String _problemOf(_Issue issue) {
  final path = issue.path.join('.');
  if (path.isEmpty) {
    return issue.code == 'invalid_type'
        ? 'the frontmatter is not a YAML mapping'
        : issue.message.toLowerCase();
  }
  if (issue.message == _missing) return '$path is missing';
  if (issue.code == 'unrecognized_keys') {
    return '$path.${issue.key} is not a key a team has';
  }
  final message = issue.message;
  return '$path: ${message.substring(0, 1).toLowerCase()}'
      '${message.substring(1)}';
}

/// What zod calls a value's type; a number that is not finite by its
/// JavaScript name.
String _received(Object? value) => switch (value) {
  null => 'null',
  double(isNaN: true) => 'NaN',
  double(isInfinite: true) => value > 0 ? 'Infinity' : '-Infinity',
  num() => 'number',
  String() => 'string',
  bool() => 'boolean',
  List() => 'array',
  _ => 'object',
};

_Issue _type(List<Object> path, String expected, Object? value) => _Issue(
  path,
  'Invalid input: expected $expected, received ${_received(value)}',
  code: 'invalid_type',
);

/// The schema's checks, in zod's order, throwing the first [_Issue].
final class _Check {
  _Check(this.name, this.runtimes);

  final String name;
  final List<String> runtimes;

  Map<String, Object?> object(List<Object> path, Object? value) {
    if (value is! Map) throw _type(path, 'object', value);
    return value.cast<String, Object?>();
  }

  void strict(
    List<Object> path,
    Map<String, Object?> value,
    List<String> keys,
  ) {
    final unknown = [
      for (final key in value.keys)
        if (!keys.contains(key)) key,
    ];
    if (unknown.isEmpty) return;
    final listed = unknown.map((key) => '"$key"').join(', ');
    throw _Issue(
      path,
      'Unrecognized key${unknown.length > 1 ? 's' : ''}: $listed',
      code: 'unrecognized_keys',
      key: unknown.first,
    );
  }

  String? string(
    List<Object> path,
    Map<String, Object?> parent,
    String key, {
    bool optional = false,
    int min = 1,
    int? max,
    List<String? Function(String)> refine = const [],
  }) {
    final at = [...path, key];
    if (!parent.containsKey(key)) {
      if (optional) return null;
      throw _Issue(at, _missing, code: 'invalid_type');
    }
    final value = parent[key];
    if (value is! String) throw _type(at, 'string', value);
    if (value.length < min) {
      throw _Issue(
        at,
        'Too small: expected string to have >=$min characters',
        code: 'too_small',
      );
    }
    if (max != null && value.length > max) {
      throw _Issue(
        at,
        'Too big: expected string to have <=$max characters',
        code: 'too_big',
      );
    }
    for (final check in refine) {
      final message = check(value);
      if (message != null) throw _Issue(at, message);
    }
    return value;
  }

  String? _oneLine(String text) =>
      RegExp(r'[\r\n]').hasMatch(text) ? 'must be one line' : null;

  String? _runtime(String id) =>
      runtimes.contains(id) ? null : 'chord knows no runtime named $id';

  String _agent(List<Object> path, Map<String, Object?> parent) =>
      string(path, parent, 'agent', refine: [_runtime])!;

  TeamLead lead(Object? value) {
    const path = ['lead'];
    final map = object(path, value);
    final lead = TeamLead(
      agent: _agent(path, map),
      model: string(path, map, 'model', optional: true),
      effort: string(path, map, 'effort', optional: true),
      mode: string(path, map, 'mode', optional: true),
      instructions: string(path, map, 'instructions', optional: true),
    );
    strict(path, map, const [
      'agent',
      'model',
      'effort',
      'mode',
      'instructions',
    ]);
    return lead;
  }

  TeamMember member(int index, Object? value) {
    final path = <Object>['members', index];
    final map = object(path, value);
    final member = TeamMember(
      name: string(
        path,
        map,
        'name',
        min: 0,
        refine: [
          agentNameProblem,
          (id) => _memberName.hasMatch(id)
              ? null
              : 'must be a lowercase letter, then up to 15 of a-z, 0-9 and -',
          (id) => !_taken.contains(id) && id != name ? null : '$id is taken',
        ],
      )!,
      role: string(path, map, 'role', max: 80, refine: [_oneLine])!,
      agent: _agent(path, map),
      model: string(path, map, 'model', optional: true),
      effort: string(path, map, 'effort', optional: true),
      mode: string(path, map, 'mode', optional: true),
      instructions: string(path, map, 'instructions')!,
    );
    strict(path, map, const [
      'name',
      'role',
      'agent',
      'model',
      'effort',
      'mode',
      'instructions',
    ]);
    return member;
  }

  List<TeamMember> members(Map<String, Object?> parent) {
    const path = ['members'];
    if (!parent.containsKey('members')) {
      throw _Issue(path, _missing, code: 'invalid_type');
    }
    final value = parent['members'];
    if (value is! List) throw _type(path, 'array', value);
    if (value.isEmpty) {
      throw _Issue(
        path,
        'Too small: expected array to have >=1 items',
        code: 'too_small',
      );
    }
    if (value.length > maxMembers) {
      throw _Issue(
        path,
        'Too big: expected array to have <=$maxMembers items',
        code: 'too_big',
      );
    }
    final members = [
      for (final (index, item) in value.indexed) member(index, item),
    ];
    for (final (index, one) in members.indexed) {
      if (members.indexWhere((other) => other.name == one.name) < index) {
        throw _Issue(['members', index, 'name'], '${one.name} is named twice');
      }
    }
    return members;
  }

  ({String description, TeamLead lead, List<TeamMember> members}) root(
    Object? value,
  ) {
    final map = object(const [], value);
    final description = string(
      const [],
      map,
      'description',
      max: 200,
      refine: [_oneLine],
    )!;
    if (!map.containsKey('lead')) {
      throw _Issue(const ['lead'], _missing, code: 'invalid_type');
    }
    final lead = this.lead(map['lead']);
    final members = this.members(map);
    strict(const [], map, const ['description', 'lead', 'members']);
    return (description: description, lead: lead, members: members);
  }
}

/// Checks a team's parts: its name, the frontmatter's structure and
/// runtimes against [runtimes], and a body that is not empty. The answer is
/// the team or its first problem.
TeamRead checkTeam(
  String name,
  Object? frontmatter,
  String body,
  List<String> runtimes,
) {
  final named = teamNameProblem(name);
  if (named != null) return (team: null, problem: named);
  final ({String description, TeamLead lead, List<TeamMember> members}) read;
  try {
    read = _Check(name, runtimes).root(frontmatter);
  } on _Issue catch (issue) {
    return (team: null, problem: _problemOf(issue));
  }
  final trimmed = jsTrim(body);
  return trimmed.isEmpty
      ? (team: null, problem: 'the body is empty')
      : (
          team: Team(
            description: read.description,
            lead: read.lead,
            members: read.members,
            body: trimmed,
          ),
          problem: null,
        );
}

/// A proposed team checked as its file would be, from `propose_team`'s
/// arguments: its name and the team, or the first problem.
({String? name, Team? team, String? problem}) checkProposal(
  Object? input,
  List<String> runtimes,
) {
  final fields = input is Map
      ? input.cast<String, Object?>()
      : const <String, Object?>{};
  final name = fields['name'];
  if (name is! String) {
    return (name: null, team: null, problem: 'name is missing');
  }
  final body = fields['body'];
  final frontmatter = {
    for (final MapEntry(:key, :value) in fields.entries)
      if (key != 'name' && key != 'body') key: value,
  };
  final checked = checkTeam(
    name,
    frontmatter,
    body is String ? body : '',
    runtimes,
  );
  return checked.team == null
      ? (name: null, team: null, problem: checked.problem)
      : (name: name, team: checked.team, problem: null);
}

/// How one of a team's agents changed against the team saved before.
enum RowChange { added, changed, removed }

/// Each agent's change from [before] to [after]: the lead's apart, since a
/// member may be named `lead` too, and each member's by its name, new, gone
/// or set otherwise; none where it is the same.
({RowChange? lead, Map<String, RowChange> members}) teamChanges(
  Team before,
  Team after,
) {
  final members = <String, RowChange>{};
  for (final member in after.members) {
    final old = before.members.firstWhereOrNull(
      (each) => each.name == member.name,
    );
    if (old == null) {
      members[member.name] = RowChange.added;
    } else if (old != member) {
      members[member.name] = RowChange.changed;
    }
  }
  for (final member in before.members) {
    if (!after.members.any((each) => each.name == member.name)) {
      members[member.name] = RowChange.removed;
    }
  }
  return (
    lead: before.lead == after.lead ? null : RowChange.changed,
    members: members,
  );
}

// vfile-matter's frontmatter, verbatim.
final _matter = RegExp(
  r'^---(?:\r?\n|\r)(?:([\s\S]*?)(?:\r?\n|\r))?---(?:\r?\n|\r|$)',
);

/// [yaml] as plain maps, lists and scalars, a map's keys as strings.
Object? _plain(Object? yaml) => switch (yaml) {
  YamlMap() => {
    for (final MapEntry(:key, :value) in yaml.nodes.entries)
      '${(key as YamlNode).value}': _plain(value.value),
  },
  YamlList() => [for (final item in yaml.nodes) _plain(item.value)],
  _ => yaml,
};

/// Whether JavaScript reads [value] as false, which vfile-matter takes for
/// an empty mapping.
bool _falsy(Object? value) =>
    value == null ||
    value == false ||
    value == '' ||
    (value is num && (value == 0 || value.isNaN));

/// Reads a team file's text, as [checkTeam] checks it. A leading BOM is
/// dropped, as vfile's UTF-8 decoder drops it.
TeamRead parseTeam(String name, String text, List<String> runtimes) {
  final read = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final match = _matter.firstMatch(read);
  if (match == null) {
    return (team: null, problem: 'no frontmatter between --- lines');
  }
  Object? frontmatter;
  try {
    frontmatter = _plain(loadYaml(match[1] ?? ''));
  } on YamlException catch (error) {
    return (
      team: null,
      problem:
          'the frontmatter is not valid YAML '
          '(${error.message.split('\n').first})',
    );
  }
  return checkTeam(
    name,
    _falsy(frontmatter) ? const <String, Object?>{} : frontmatter,
    read.substring(match.end),
    runtimes,
  );
}

/// A team as its file holds it: the frontmatter between `---` lines, then
/// the body.
String teamText(Team team) =>
    '---\n${yamlStringify(team.frontmatter())}---\n\n${team.body}\n';

/// The teams saved in [dir], by name; none for a directory that is not
/// there.
Future<List<({String name, String file})>> _teamsIn(String? dir) async {
  if (dir == null) return const [];
  final found = <({String name, String file})>[];
  try {
    await for (final entry in Directory(dir).list(followLinks: false)) {
      final base = p.basename(entry.path);
      if (entry is! Directory && p.extension(base) == '.md') {
        found.add((
          name: p.basenameWithoutExtension(base),
          file: p.join(dir, base),
        ));
      }
    }
  } on PathNotFoundException {
    return const [];
  }
  return found;
}

String _reason(FileSystemException error) {
  final os = error.osError?.message;
  return os == null || os.isEmpty ? error.message : os;
}

/// Every team file, by name: the project's and the user's, the project's
/// winning a name both have, as the project's settings sit on top of the
/// user's. A file that fails the check is listed with its first problem,
/// so the person sees it and can fix it.
Future<List<FoundTeam>> findTeams({
  required String? configHome,
  required String cwd,
  required List<String> runtimes,
}) async {
  final dirs = teamDirs(configHome: configHome, cwd: cwd);
  final project = await _teamsIn(dirs.project);
  final user = await _teamsIn(dirs.user);
  final shadowed = {for (final found in project) found.name};
  final files = [
    for (final found in project)
      (
        name: found.name,
        file: found.file,
        place: TeamPlace.project,
        hides: user.any((other) => other.name == found.name),
      ),
    for (final found in user)
      if (!shadowed.contains(found.name))
        (
          name: found.name,
          file: found.file,
          place: TeamPlace.user,
          hides: false,
        ),
  ]..sort((a, b) => a.name.compareTo(b.name));
  return Future.wait([
    for (final found in files)
      () async {
        FoundTeam with_(TeamRead read) => FoundTeam(
          name: found.name,
          file: found.file,
          place: found.place,
          hides: found.hides,
          team: read.team,
          problem: read.problem,
        );
        try {
          final bytes = await File(found.file).readAsBytes();
          final text = utf8.decode(bytes, allowMalformed: true);
          return with_(parseTeam(found.name, text, runtimes));
        } on FileSystemException catch (error) {
          return with_((
            team: null,
            problem: 'cannot be read (${_reason(error)})',
          ));
        }
      }(),
  ]);
}

/// Writes [team] to [file] as a settings file is saved: to a file beside it
/// that is renamed over the old, so a failed write leaves nothing
/// half-written. A missing directory is made.
Future<void> saveTeam(String file, Team team) async {
  await Directory(p.dirname(file)).create(recursive: true);
  final temporary = '$file.${const Uuid().v4()}.tmp';
  try {
    await File(temporary).writeAsString(teamText(team));
    await File(temporary).rename(file);
  } catch (_) {
    try {
      await File(temporary).delete();
    } on FileSystemException {
      // Nothing was left to remove.
    }
    rethrow;
  }
}

/// `a`, `a and b`, `a, b, and c`, as `Intl.ListFormat` in English gives
/// them; Dart's `intl` has no list format.
String andList(List<String> names) => switch (names.length) {
  0 => '',
  1 => names.single,
  2 => '${names[0]} and ${names[1]}',
  _ => '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}',
};

/// A member as the team part lists it: name, role, runtime · model · effort
/// · mode.
String _memberLine(TeamMember member) =>
    '- ${member.name}: ${member.role} (${[member.agent, ?member.model, ?member.effort, ?member.mode].join(' · ')})';

/// Who a team part is for: a run's lead, or one of its members.
sealed class TeamRole {
  const TeamRole();
}

/// A run's lead, by the name chord gave it (`bugfix`, `bugfix 2`), with the
/// leads of the other runs open in the session.
final class LeadRole extends TeamRole {
  /// The lead named [lead], beside [others].
  const LeadRole({required this.lead, required this.others});

  final String lead;
  final List<String> others;
}

/// One of a run's members, opened by [lead].
final class MemberRole extends TeamRole {
  /// [member] of the run whose lead is [lead].
  const MemberRole({required this.member, required this.lead});

  final TeamMember member;
  final String lead;
}

/// The team part of a lead's or member's first message: the team, the
/// member it is for (none for a lead), and the text.
typedef TeamPart = ({String team, String? member, String text});

/// The team part a lead or member gets ahead of its first message: chord's
/// standing words, which say only the mechanics (its tools, the names it
/// reaches, the directory), then the file's words: its instructions, the
/// members and how the team works.
TeamPart teamPart(String name, Team team, TeamRole role, String cwd) {
  final members = team.members.map(_memberLine).join('\n');
  final how = 'How the team works:\n${team.body}';
  switch (role) {
    case MemberRole(:final member, :final lead):
      final others = [
        for (final each in team.members)
          if (!identical(each, member)) each.name,
      ];
      return (
        team: name,
        member: member.name,
        text: [
          'You are ${member.name}, a member of team $name, opened by its '
              "lead, $lead. You work in $cwd, beside the team's other "
              'members: there are no worktrees.',
          "Your tools on chord's server: send_message {to, text} reaches "
              'your lead, $lead, and '
              '${others.isEmpty ? '' : '${andList(others)}, '}'
              "the team's other members while they are open, by name and "
              'directly: the lead does not see those. spawn_task and '
              'list_agents start task agents for one-off jobs. You open no '
              'long-lived agents.',
          'Your role: ${member.role}',
          'Your instructions:\n${jsTrim(member.instructions)}',
          'The members:\n$members',
          how,
        ].join('\n\n'),
      );
    case LeadRole(:final lead, :final others):
      final runs = others.isEmpty
          ? 'No other run of a team is open in this session.'
          : 'Other runs open in this session, whose leads send_message '
                'reaches by these names: ${andList(others)}.';
      return (
        team: name,
        member: null,
        text: [
          'You are the lead of team $name'
              '${lead == name ? '' : ', running as $lead'}: a long-lived '
              'agent chord opened for main, the session the person talks '
              'to. You work in $cwd, and so does every member you open: '
              'there are no worktrees.',
          "Your tools on chord's server: open_agent {member, prompt} opens "
              'one of the members below on the runtime, model, effort and '
              'mode the team gives it, with your prompt as its first '
              'message. send_message {to, text} reaches main, your open '
              'members by name, and the leads of the other runs. '
              'close_agent {to} closes a member; close each when its part '
              'is done. spawn_task and list_agents start task agents for '
              'one-off jobs. Each message of yours to main goes into the '
              "turn main is in, where its runtime takes that, or else starts "
              "a turn of main's.",
          runs,
          if (team.lead.instructions != null)
            'Your instructions:\n${jsTrim(team.lead.instructions!)}',
          'The members:\n$members',
          how,
        ].join('\n\n'),
      );
  }
}

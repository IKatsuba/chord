/// chord's `settings` tool, without the server or the window: which keys it
/// writes and what a write of each means, the refusals in their order, a
/// read of the checked settings with secrets masked, and the plan of a
/// change before the person is asked. From the original's
/// `src/settings_tool.ts`.
library;

import 'dart:io';

import 'mcp.dart' show checkedServerEntry;
import 'settings.dart';

/// What a path holds when it holds nothing, null being a value; a read's
/// answer leaves it out, as JSON leaves out the original's `undefined`.
const Object absent = _Absent();

final class _Absent {
  const _Absent();

  @override
  String toString() => 'absent';
}

/// When a saved setting reaches the window it was saved from.
enum TakesEffect {
  now('now'),
  nextStart('next start');

  const TakesEffect(this.words);

  /// As an answer says it.
  final String words;
}

/// What a settings path names, for the tool.
sealed class SettingClass {
  const SettingClass();
}

/// A key the tool may write, and what a write of it means.
final class WritableSetting extends SettingClass {
  const WritableSetting({
    required this.userOnly,
    required this.takesEffect,
    required this.check,
    this.agentsIn,
  });

  /// Only the user's file holds it, so no project's file can shadow it.
  final bool userOnly;
  final TakesEffect takesEffect;

  /// What is wrong with a value of it, in its schema's words; null when
  /// nothing is. [absent] is a value left out.
  final String? Function(Object? value) check;

  /// The agent names a value gives, which chord has to know.
  final List<String> Function(Object? value)? agentsIn;
}

/// Read, but a person edits it by hand.
final class HandSetting extends SettingClass {
  const HandSetting();
}

/// A parent of writable leaves, with the leaves it could have named.
final class ParentSetting extends SettingClass {
  const ParentSetting(this.leaves);
  final List<String> leaves;
}

/// No setting at all.
final class UnknownSetting extends SettingClass {
  const UnknownSetting();
}

const _unknown = UnknownSetting();
const _hand = HandSetting();

/// The type zod names a value by, as its messages say it.
String _type(Object? value) => switch (value) {
  _Absent() => 'undefined',
  null => 'null',
  num() => 'number',
  String() => 'string',
  bool() => 'boolean',
  List() => 'array',
  _ => 'object',
};

String? Function(Object?) _oneOf(List<String> values) =>
    (value) => values.contains(value)
    ? null
    : 'Invalid option: expected one of ${values.map((v) => '"$v"').join('|')}';

String? _boolean(Object? value) => value is bool
    ? null
    : 'Invalid input: expected boolean, received ${_type(value)}';

/// A string of at least one character, and of at most [max] when given.
String? Function(Object?) _text([int? max]) =>
    (value) => value is! String
    ? 'Invalid input: expected string, received ${_type(value)}'
    : value.isEmpty
    ? 'Too small: expected string to have >=1 characters'
    : max != null && value.length > max
    ? 'Too big: expected string to have <=$max characters'
    : null;

String? _offered(Object? value) =>
    value is List &&
        value.isNotEmpty &&
        value.every((name) => name is String && name.isNotEmpty)
    ? null
    : 'expected a list of one or more agent names';

List<String> _oneAgent(Object? value) => [value as String];

/// The top-level leaves: the design's allowlist, closed to any other key.
final Map<String, WritableSetting> _topLevel = {
  'theme': WritableSetting(
    userOnly: true,
    takesEffect: TakesEffect.now,
    check: _oneOf(themeSettings),
  ),
  'editorMode': WritableSetting(
    userOnly: true,
    takesEffect: TakesEffect.now,
    check: _oneOf(editorModes),
  ),
  'mouse': const WritableSetting(
    userOnly: true,
    takesEffect: TakesEffect.nextStart,
    check: _boolean,
  ),
  'copyOnSelect': const WritableSetting(
    userOnly: true,
    takesEffect: TakesEffect.nextStart,
    check: _boolean,
  ),
  'offeredAgents': WritableSetting(
    userOnly: true,
    takesEffect: TakesEffect.now,
    check: _offered,
    agentsIn: (value) => (value as List).cast<String>(),
  ),
  'preferredNotifChannel': WritableSetting(
    userOnly: false,
    takesEffect: TakesEffect.nextStart,
    check: _oneOf(notifChannels),
  ),
  'agent': WritableSetting(
    userOnly: false,
    takesEffect: TakesEffect.nextStart,
    check: _text(),
    agentsIn: _oneAgent,
  ),
};

final Map<String, WritableSetting> _agentKeys = {
  'model': WritableSetting(
    userOnly: false,
    takesEffect: TakesEffect.nextStart,
    check: _text(),
  ),
  'effort': WritableSetting(
    userOnly: false,
    takesEffect: TakesEffect.nextStart,
    check: _text(),
  ),
};

final _intent = WritableSetting(
  userOnly: false,
  takesEffect: TakesEffect.now,
  check: _oneOf(teamIntents),
);

final Map<String, WritableSetting> _preferKeys = {
  'agent': WritableSetting(
    userOnly: false,
    takesEffect: TakesEffect.now,
    check: _text(128),
    agentsIn: _oneAgent,
  ),
  'model': WritableSetting(
    userOnly: false,
    takesEffect: TakesEffect.now,
    check: (value) => value == null ? null : _text(128)(value),
  ),
};

SettingClass _agentClass(List<String> rest, String name) {
  if (rest.isEmpty) {
    final shown = shownSettingPath(['agents', name]);
    return ParentSetting(['$shown.model', '$shown.effort']);
  }
  final [key, ...deeper] = rest;
  if (key == 'command' || key == 'permissionMode' || key == 'mcpServers') {
    return _hand;
  }
  return deeper.isEmpty ? _agentKeys[key] ?? _unknown : _unknown;
}

SettingClass _teamSelectionClass(List<String> rest) {
  if (rest.isEmpty) {
    return const ParentSetting([
      'teamSelection.intent',
      'teamSelection.prefer.agent',
      'teamSelection.prefer.model',
    ]);
  }
  final [key, ...after] = rest;
  if (key == 'constraints') return _hand;
  if (key == 'intent') return after.isEmpty ? _intent : _unknown;
  if (key != 'prefer') return _unknown;
  if (after.isEmpty) {
    return const ParentSetting([
      'teamSelection.prefer.agent',
      'teamSelection.prefer.model',
    ]);
  }
  final [leaf, ...deeper] = after;
  return deeper.isEmpty ? _preferKeys[leaf] ?? _unknown : _unknown;
}

/// What [path] names. A new key is closed until it is named above.
SettingClass classifySetting(List<String> path) {
  if (!canBeSettingPath(path)) return _unknown;
  final [first, ...rest] = path;
  if (first == 'mcpServers') return _hand;
  if (first == 'teamSelection') return _teamSelectionClass(rest);
  if (first == 'agents') {
    return rest.isEmpty
        ? const ParentSetting(['agents.<name>.model', 'agents.<name>.effort'])
        : _agentClass(rest.sublist(1), rest.first);
  }
  return rest.isEmpty ? _topLevel[first] ?? _unknown : _unknown;
}

/// `a`, `a or b`, `a, b or c`.
String _either(List<String> words) => words.length < 2
    ? words.join()
    : '${words.sublist(0, words.length - 1).join(', ')} or ${words.last}';

/// Why a path alone is not one the tool writes, as the refusal says it.
String? _pathRefusal(List<String> path, SettingClass named) {
  final shown = shownSettingPath(path);
  return switch (named) {
    UnknownSetting() => 'No setting $shown'.trimRight(),
    HandSetting() =>
      'chord does not write $shown; edit the settings file by hand',
    ParentSetting(:final leaves) =>
      '$shown is not one setting; name ${_either(leaves)}',
    WritableSetting() => null,
  };
}

/// The first thing wrong with a write that reading no file can tell: the
/// allowlist, the key's own schema, then the names chord knows. A remove
/// has no value to check, and defines nothing, so a stale agent's key can
/// leave. A set of [absent] is a value left out.
String? settingRefusal(
  List<String> path,
  SettingChange change,
  List<String> knownAgents,
) {
  final named = classifySetting(path);
  final refused = _pathRefusal(path, named);
  if (refused != null || named is! WritableSetting) return refused;
  if (change is! SetSetting) return null;
  final value = change.value;
  if (named.check(value) case final issue?) {
    final given = identical(value, absent) ? 'left out' : shownValue(value);
    return '${shownSettingPath(path)} cannot be $given: $issue';
  }
  final agents = [
    if (path.first == 'agents') path[1],
    ...?named.agentsIn?.call(value),
  ];
  for (final name in agents) {
    if (!knownAgents.contains(name)) {
      return 'chord knows no agent named ${shownValue(name)}; '
          'list_agents names every one';
    }
  }
  return null;
}

/// A refusal about the file, its name as shown and why in the writer's
/// words.
String notSavedLine(String shownFile, String why) =>
    '$shownFile was not saved: $why';

/// Where a window's settings files are, and how it shows them.
final class SettingsWhere {
  const SettingsWhere({
    required this.configHome,
    required this.cwd,
    required this.home,
  });

  final String? configHome;
  final String cwd;
  final String? home;
}

const _mask = '***';

/// The keys whose values may carry a secret, whatever holds them.
const _secretKeys = {'env', 'headers', 'command', 'args', 'url'};

/// Every leaf hidden, a list's or an object's shape kept.
Object? _maskedLeaves(Object? value) => switch (value) {
  List() => [for (final item in value) _maskedLeaves(item)],
  Map() => {
    for (final MapEntry(:key, value: held) in value.entries)
      '$key': _maskedLeaves(held),
  },
  _ => _mask,
};

/// Every value under a secret key's name hidden, at any depth.
Object? _maskedByName(Object? value) => switch (value) {
  List() => [for (final item in value) _maskedByName(item)],
  Map() => {
    for (final MapEntry(:key, value: held) in value.entries)
      '$key': _secretKeys.contains(key)
          ? _maskedLeaves(held)
          : _maskedByName(held),
  },
  _ => value,
};

/// [settings] as their file holds them once checked.
Map<String, Object?> _settingsJson(Settings settings) => {
  'agent': ?settings.agent,
  if (settings.agents case final agents?)
    'agents': {
      for (final MapEntry(key: name, value: agent) in agents.entries)
        name: {
          if (agent.command case final command?)
            'command': switch (command) {
              CommandLine(:final line) => line,
              CommandArgv(:final argv) => argv,
            },
          'model': ?agent.model,
          'effort': ?agent.effort,
          'permissionMode': ?agent.permissionMode,
          'mcpServers': ?agent.mcpServers,
        },
    },
  'teamSelection': ?settings.teamSelection,
  'mcpServers': ?settings.mcpServers,
  'preferredNotifChannel': ?settings.preferredNotifChannel,
  'theme': ?settings.theme,
  'editorMode': ?settings.editorMode,
  'mouse': ?settings.mouse,
  'copyOnSelect': ?settings.copyOnSelect,
  'offeredAgents': ?settings.offeredAgents,
};

/// Checked settings as a read shows them. The settings check does not look
/// inside a server, so each goes through its transport's shape here: a
/// field of no known name, `token` or `Env`, is gone with its value, and a
/// server that fails is left out. Masked before any path is walked: a path
/// below a leaf is not set.
Object? _shownSettings(Settings settings) {
  final json = _settingsJson(settings);
  // The servers go last, after every other key in the settings' order, as
  // the original spreads them.
  if (json.remove('mcpServers') case final Map<String, Object?> servers) {
    json['mcpServers'] = {
      for (final MapEntry(key: name, value: entry) in servers.entries)
        name: ?checkedServerEntry(entry),
    };
  }
  return _maskedByName(json);
}

/// The value at [path] in [value], or [absent], by the object's own keys.
Object? _at(Object? value, List<String> path) {
  var held = value;
  for (final key in path) {
    if (held is! Map || !held.containsKey(key)) return absent;
    held = held[key];
  }
  return held;
}

/// The home an answer's paths are shown from `~`: none where `HOME` is
/// unset or empty, as the settings file is then found through
/// `XDG_CONFIG_HOME` and shown as it is.
String? shownHome(SettingsWhere where) =>
    where.home == null || where.home!.isEmpty ? null : where.home;

/// `1 key`, `3 keys`.
String _keysWord(int count) => '$count ${count == 1 ? 'key' : 'keys'}';

/// The kind of parse problem a file has, in the words a read says it by.
String _parseWords(SettingsProblem problem) =>
    problem.message.startsWith('not valid JSON')
    ? 'not valid JSON'
    : problem.message.startsWith('not a JSON object')
    ? 'not a JSON object'
    : 'cannot be used';

/// What a read says of one file's problems, by kind and count alone: a
/// problem's message and key quote the file's own names and the parser's
/// words, and a read carries nothing of a file the check did not pass.
List<String> _problemWords(List<SettingsProblem> problems) {
  int count(SettingsProblemKind kind) =>
      problems.where((problem) => problem.kind == kind).length;
  final parse = problems
      .where((problem) => problem.kind == SettingsProblemKind.parse)
      .firstOrNull;
  final invalid = count(SettingsProblemKind.validation);
  final scoped = count(SettingsProblemKind.scope);
  return [
    if (count(SettingsProblemKind.read) > 0) 'cannot be read; ignored',
    if (parse != null) '${_parseWords(parse)}; ignored',
    if (invalid > 0) '${_keysWord(invalid)} ignored',
    if (scoped > 0)
      "${_keysWord(scoped)} only the user's file may set; ignored",
  ];
}

/// What a file's row says of it, from what the load left.
String _fileState(SettingsLayer? layer, List<SettingsProblem> problems) {
  if (problems.any((problem) => problem.kind == SettingsProblemKind.read)) {
    return 'cannot be read';
  }
  if (layer == null) return 'not there';
  final parse = problems
      .where((problem) => problem.kind == SettingsProblemKind.parse)
      .firstOrNull;
  return parse == null
      ? _keysWord(_settingsJson(layer.settings).length)
      : _parseWords(parse);
}

/// A `settings` read: the answer the agent gets. A layer is [absent]
/// where the path names nothing in it, and null where the file could not
/// be used.
final class SettingsRead {
  const SettingsRead({
    required this.user,
    required this.project,
    required this.effective,
    required this.problems,
  });

  /// The file's checked settings, masked.
  final Object? user, project;

  /// The merged, checked settings, masked.
  final Object? effective;

  /// Per file, by kind and count, with no name from the file.
  final List<({String file, String message})> problems;

  /// As the agent is answered.
  Map<String, Object?> toJson() => {
    if (!identical(user, absent)) 'user': user,
    if (!identical(project, absent)) 'project': project,
    if (!identical(effective, absent)) 'effective': effective,
    'problems': [
      for (final (:file, :message) in problems)
        {'file': file, 'message': message},
    ],
  };
}

/// A read's answer, and what its row says of each file.
final class SettingsReadAnswer {
  const SettingsReadAnswer(
    this.answer, {
    required this.user,
    required this.project,
  });

  final SettingsRead answer;

  /// Each file as shown, then what it held: `~/.config/chord/settings.json
  /// · 3 keys`.
  final String user, project;
}

/// A `settings` call refused before anything was asked or written.
final class SettingsToolRefused {
  const SettingsToolRefused(this.error);
  final String error;
}

/// The `settings` tool's read, of every key or of the one at [path], and
/// what the row says of each file: a [SettingsReadAnswer], or a
/// [SettingsToolRefused]. It loads as a start does, following links, and
/// answers only from what the check passed: no raw file is parsed for it.
Future<Object> readSettingsTool(
  SettingsWhere where, [
  List<String> path = const [],
]) async {
  if (path.isNotEmpty && !canBeSettingPath(path)) {
    return SettingsToolRefused('No setting ${shownSettingPath(path)}');
  }
  final home = shownHome(where);
  String shown(String file) => shownPath(file, cwd: where.cwd, home: home);
  final userFile = userSettingsFile(where.configHome);
  final projectFile = settingsFiles(
    configHome: where.configHome,
    cwd: where.cwd,
  ).last;
  final loaded = await loadSettings(
    configHome: where.configHome,
    cwd: where.cwd,
    home: home,
  );
  SettingsLayer? layerOf(String? file) =>
      loaded.layers.where((layer) => layer.file == file).firstOrNull;
  List<SettingsProblem> problemsOf(String? file) =>
      loaded.problems.where((problem) => problem.file == file).toList();
  // A file the load could not use is none, not one that is fine and empty.
  Object? shownLayer(String? file) {
    final layer = layerOf(file);
    return layer == null ||
            problemsOf(
              file,
            ).any((problem) => problem.kind == SettingsProblemKind.parse)
        ? null
        : _shownSettings(layer.settings);
  }

  return SettingsReadAnswer(
    SettingsRead(
      user: _at(shownLayer(userFile), path),
      project: _at(shownLayer(projectFile), path),
      effective: _at(_shownSettings(loaded.settings), path),
      problems: [
        for (final file in [?userFile, projectFile])
          for (final message in _problemWords(problemsOf(file)))
            (file: shown(file), message: message),
      ],
    ),
    user: userFile == null
        ? 'no home directory'
        : '${shown(userFile)} · ${_fileState(layerOf(userFile), problemsOf(userFile))}',
    project:
        '${shown(projectFile)} · ${_fileState(layerOf(projectFile), problemsOf(projectFile))}',
  );
}

/// What a `set` or `remove` answers, while the box is open and once
/// answered.
final class SettingsChanged {
  const SettingsChanged({
    required this.path,
    this.before = absent,
    this.after = absent,
    required this.file,
    this.saved,
    this.unchanged = false,
    required this.takesEffect,
    this.shadowedBy,
  });

  final List<String> path;

  /// The value the check passed in the file, [absent] where it holds none.
  final Object? before;
  final Object? after;

  /// The user's file, as the window shows it.
  final String file;

  /// Not there yet while the person is asked.
  final bool? saved;

  /// Nothing to do: nothing was asked or written.
  final bool unchanged;
  final TakesEffect takesEffect;

  /// The project's file, as shown, where its checked settings hold this
  /// key.
  final String? shadowedBy;

  /// This answer once the person said [saved].
  SettingsChanged answered({required bool saved}) => SettingsChanged(
    path: path,
    before: before,
    after: after,
    file: file,
    saved: saved,
    unchanged: unchanged,
    takesEffect: takesEffect,
    shadowedBy: shadowedBy,
  );

  /// As the agent is answered.
  Map<String, Object?> toJson() => {
    'path': path,
    if (!identical(before, absent)) 'before': before,
    if (!identical(after, absent)) 'after': after,
    'file': file,
    'saved': ?saved,
    if (unchanged) 'unchanged': true,
    'takesEffect': takesEffect.words,
    'shadowedBy': ?shadowedBy,
  };
}

/// What a system error says, without the person's home: the model is told
/// paths as the window shows them.
String _withoutHome(Object error, String? home) {
  final message = switch (error) {
    SettingRefused(:final message) => message,
    FileSystemException(:final message, :final osError, :final path) => [
      osError?.message ?? message,
      ?path,
    ].where((part) => part.isNotEmpty).join(', '),
    _ => '$error',
  };
  return home == null ? message : message.replaceAll(home, '~');
}

/// A write that failed, as a refusal says it.
String saveFailure(String shownFile, Object error, String? home) =>
    notSavedLine(shownFile, _withoutHome(error, home));

/// A change that passed its checks: what it answers and the file it writes.
final class PlannedSetting {
  const PlannedSetting(this.answer, this.file);
  final SettingsChanged answer;
  final String file;
}

/// Whether [a] and [b] are the same JSON value, [absent] included.
bool _same(Object? a, Object? b) => switch ((a, b)) {
  (final List a, final List b) =>
    a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => _same(a[i], b[i])),
  (final Map a, final Map b) =>
    a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key])),
  _ => identical(a, b) || a == b,
};

/// The checks a `set` or `remove` passes before the person is asked, in
/// the design's order, and what it would do: a [SettingsToolRefused], or
/// the [PlannedSetting].
Future<Object> plannedSetting(
  SettingsWhere where,
  List<String> path,
  SettingChange change,
  List<String> knownAgents,
) async {
  final refused = settingRefusal(path, change, knownAgents);
  if (refused != null) return SettingsToolRefused(refused);
  final file = userSettingsFile(where.configHome);
  if (file == null) return const SettingsToolRefused(noSettingsHome);
  final named = classifySetting(path) as WritableSetting;
  final home = shownHome(where);
  String shown(String file) => shownPath(file, cwd: where.cwd, home: home);
  final shownFile = shown(file);
  final Map<String, Object?> settings;
  try {
    settings = await readSettingsObject(file);
  } on Object catch (error) {
    return SettingsToolRefused(saveFailure(shownFile, error, home));
  }
  if (settingParentProblem(settings, path) case final parent?) {
    return SettingsToolRefused(notSavedLine(shownFile, parent));
  }
  final after = change is SetSetting ? change.value : absent;
  final projectFile = settingsFiles(
    configHome: where.configHome,
    cwd: where.cwd,
  ).last;
  final loaded = await loadSettings(
    configHome: where.configHome,
    cwd: where.cwd,
    home: home,
  );
  Settings? layerAt(String file) =>
      loaded.layers.where((layer) => layer.file == file).firstOrNull?.settings;
  // From the checked layer, so a bad value reads as not set and no raw
  // value goes in an answer; a set replaces it, and a remove has nothing to
  // remove.
  final userLayer = layerAt(file);
  final held = userLayer == null ? absent : _at(_settingsJson(userLayer), path);
  final before = userLayer == null
      ? absent
      : _at(_shownSettings(userLayer), path);
  final projectLayer = layerAt(projectFile);
  final shadowed =
      !named.userOnly &&
      projectLayer != null &&
      !identical(_at(_settingsJson(projectLayer), path), absent);
  final unchanged = _same(held, after);
  return PlannedSetting(
    SettingsChanged(
      path: path,
      before: before,
      after: after,
      file: shownFile,
      saved: unchanged ? false : null,
      unchanged: unchanged,
      takesEffect: named.takesEffect,
      shadowedBy: shadowed ? shown(projectFile) : null,
    ),
    file,
  );
}

/// The note a planned change goes by: on the row and, capitalised, the
/// box.
String changeWord(SettingsChanged answer) => identical(answer.after, absent)
    ? 'remove'
    : identical(answer.before, absent)
    ? 'set'
    : 'change';

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ui/shortcuts/bindings.dart';

/// The command a settings file starts an agent with instead of chord's own,
/// as `--agent-command` does: a line the shell splits, or the program and
/// its arguments.
sealed class SettingsCommand {
  const SettingsCommand();
}

/// A command line the shell splits.
final class CommandLine extends SettingsCommand {
  const CommandLine(this.line);

  final String line;

  @override
  bool operator ==(Object other) => other is CommandLine && other.line == line;

  @override
  int get hashCode => line.hashCode;

  @override
  String toString() => 'CommandLine($line)';
}

/// The program, then its arguments as written, an empty one too.
final class CommandArgv extends SettingsCommand {
  CommandArgv(List<String> argv) : argv = List.unmodifiable(argv);

  final List<String> argv;

  @override
  bool operator ==(Object other) =>
      other is CommandArgv && _sameList(other.argv, argv);

  @override
  int get hashCode => Object.hashAll(argv);

  @override
  String toString() => 'CommandArgv($argv)';
}

/// What one agent starts with. Model, effort and mode ids are the agent's
/// own, so they are set per agent.
class AgentSettings {
  const AgentSettings({
    this.command,
    this.model,
    this.effort,
    this.permissionMode,
    this.mcpServers,
  });

  final SettingsCommand? command;
  final String? model;
  final String? effort;
  final String? permissionMode;

  /// Read and checked; no effect in the port yet.
  final bool? mcpServers;

  /// These keys over [earlier]'s.
  AgentSettings over(AgentSettings? earlier) => AgentSettings(
    command: command ?? earlier?.command,
    model: model ?? earlier?.model,
    effort: effort ?? earlier?.effort,
    permissionMode: permissionMode ?? earlier?.permissionMode,
    mcpServers: mcpServers ?? earlier?.mcpServers,
  );

  @override
  bool operator ==(Object other) =>
      other is AgentSettings &&
      other.command == command &&
      other.model == model &&
      other.effort == effort &&
      other.permissionMode == permissionMode &&
      other.mcpServers == mcpServers;

  @override
  int get hashCode =>
      Object.hash(command, model, effort, permissionMode, mcpServers);

  @override
  String toString() =>
      'AgentSettings(command: $command, model: $model, effort: $effort, '
      'permissionMode: $permissionMode, mcpServers: $mcpServers)';
}

/// The themes a settings file may name, by Claude Code's ids.
const themeSettings = [
  'auto',
  'dark',
  'light',
  'dark-daltonized',
  'light-daltonized',
  'dark-ansi',
  'light-ansi',
];

/// How the prompt box edits.
const editorModes = ['normal', 'vim'];

/// How the terminal is told chord waits on the person.
const notifChannels = ['auto', 'bell', 'osc9', 'osc777', 'off'];

/// The keys read only from the user's file.
const _userOnly = [
  'theme',
  'editorMode',
  'mouse',
  'copyOnSelect',
  'offeredAgents',
];

/// One settings file, or several merged, as written. Keys the port reads
/// but does not act on yet are kept so that they are checked and merged as
/// the original does.
class Settings {
  const Settings({
    this.agent,
    this.agents,
    this.teamSelection,
    this.mcpServers,
    this.preferredNotifChannel,
    this.theme,
    this.editorMode,
    this.mouse,
    this.copyOnSelect,
    this.offeredAgents,
  });

  /// The agent `chord` starts when none is named.
  final String? agent;
  final Map<String, AgentSettings>? agents;

  /// Team selection preferences and constraints, checked as the
  /// original's `TeamSelection` is and holding only what passed.
  final Map<String, Object?>? teamSelection;
  final Map<String, Object?>? mcpServers;
  final String? preferredNotifChannel;
  final String? theme;
  final String? editorMode;
  final bool? mouse;

  /// `false` keeps a drag's selection until ctrl+c copies it.
  final bool? copyOnSelect;

  /// The agents the start screen and `/new` offer, in their order.
  final List<String>? offeredAgents;

  /// These settings without the user-only key [key].
  Settings _without(String key) => Settings(
    agent: agent,
    agents: agents,
    teamSelection: teamSelection,
    mcpServers: mcpServers,
    preferredNotifChannel: preferredNotifChannel,
    theme: key == 'theme' ? null : theme,
    editorMode: key == 'editorMode' ? null : editorMode,
    mouse: key == 'mouse' ? null : mouse,
    copyOnSelect: key == 'copyOnSelect' ? null : copyOnSelect,
    offeredAgents: key == 'offeredAgents' ? null : offeredAgents,
  );

  Object? _userOnlyValue(String key) => switch (key) {
    'theme' => theme,
    'editorMode' => editorMode,
    'mouse' => mouse,
    'copyOnSelect' => copyOnSelect,
    _ => offeredAgents,
  };
}

/// What a problem left out of a list: an item, or the list's last.
enum SettingsLeftOut { item, list }

/// What kind of thing a settings problem is.
enum SettingsProblemKind { read, parse, validation, scope }

/// Something wrong in a settings file, said in a line of its own.
class SettingsProblem {
  const SettingsProblem(
    this.file,
    this.message, {
    this.kind,
    this.key,
    this.leftOut,
  });

  final String file;
  final String message;
  final SettingsProblemKind? kind;
  final List<String>? key;

  /// Set when the problem only left an item out of the list at [key], or
  /// says the list has none left: the list still counts without its bad
  /// items (the original's Q346).
  final SettingsLeftOut? leftOut;

  @override
  bool operator ==(Object other) =>
      other is SettingsProblem &&
      other.file == file &&
      other.message == message &&
      other.kind == kind &&
      _sameList(other.key, key);

  @override
  int get hashCode => Object.hash(
    file,
    message,
    kind,
    key == null ? null : Object.hashAll(key!),
  );

  @override
  String toString() => 'SettingsProblem($file, $message)';
}

/// The directory chord's configuration lives under: `XDG_CONFIG_HOME`,
/// else `~/.config`; none without either.
String? configHome(Map<String, String> environment) {
  final xdg = environment['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) return xdg;
  final home = environment['HOME'];
  return home == null || home.isEmpty ? null : p.join(home, '.config');
}

/// The user's own settings file; none without a config home.
String? userSettingsFile(String? configHome) =>
    configHome == null ? null : p.join(configHome, 'chord', 'settings.json');

/// The keybindings file: the user's only, as keys are about a person's
/// hands, not a project; none without a config home.
String? keybindingsFile(String? configHome) =>
    configHome == null ? null : p.join(configHome, 'chord', 'keybindings.json');

/// Reads the keybindings file over the defaults. A file that is not there
/// is no problem, and one that cannot be read leaves the defaults.
Future<({Keybindings keymap, List<SettingsProblem> problems})> loadKeybindings(
  String? file,
) async {
  if (file == null) {
    return (keymap: defaultKeymap, problems: const <SettingsProblem>[]);
  }
  final String text;
  try {
    text = utf8.decode(await File(file).readAsBytes(), allowMalformed: true);
  } on PathNotFoundException {
    return (keymap: defaultKeymap, problems: const <SettingsProblem>[]);
  } on FileSystemException catch (error) {
    return (
      keymap: defaultKeymap,
      problems: [
        SettingsProblem(
          file,
          'cannot be read (${_reason(error)}); the file is ignored',
          kind: SettingsProblemKind.read,
        ),
      ],
    );
  }
  final read = readKeybindings(text);
  return (
    keymap: read.keymap,
    problems: [
      for (final message in read.problems) SettingsProblem(file, message),
    ],
  );
}

/// Each settings file chord reads, lowest precedence first.
List<String> settingsFiles({
  required String? configHome,
  required String cwd,
}) => [?userSettingsFile(configHome), p.join(cwd, '.chord', 'settings.json')];

/// One file's settings as [parseSettings] reads them.
class ParsedSettings {
  const ParsedSettings(this.settings, this.problems, [this.refused = const {}]);

  final Settings settings;
  final List<SettingsProblem> problems;

  /// The agents whose `command` this file gives chord refused, each with
  /// why: such an agent is not started at all.
  final Map<String, String> refused;
}

/// What zod calls a JSON value's type.
String _received(Object? value) => switch (value) {
  null => 'null',
  num() => 'number',
  String() => 'string',
  bool() => 'boolean',
  List() => 'array',
  _ => 'object',
};

/// What chord was given in place of a command, as a refusal says it.
String _given(Object? value) {
  if (value is List) {
    return value.isEmpty
        ? 'an empty list'
        : value.every((item) => item is String)
        ? 'a list whose program is empty'
        : 'a list with something not a string';
  }
  if (value == '') return 'an empty string';
  if (value == null) return 'null';
  final type = _received(value);
  return '${RegExp('^[aeiou]').hasMatch(type) ? 'an' : 'a'} $type';
}

String _options(List<String> values) => values.map((v) => '"$v"').join('|');

/// Reads one file's text. A key that is unknown or holds the wrong kind of
/// value is a problem and is left out, and the rest still counts; text that
/// is not a JSON object counts for nothing.
ParsedSettings parseSettings(String file, String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    return ParsedSettings(const Settings(), [
      SettingsProblem(
        file,
        'not valid JSON (${error.message}); the file is ignored',
        kind: SettingsProblemKind.parse,
      ),
    ]);
  }
  if (decoded is! Map<String, Object?>) {
    return ParsedSettings(const Settings(), [
      SettingsProblem(
        file,
        'not a JSON object; the file is ignored',
        kind: SettingsProblemKind.parse,
      ),
    ]);
  }
  final input = decoded;

  final problems = <SettingsProblem>[];
  final refused = <String, String>{};
  void bad(List<String> path, String issue) => problems.add(
    SettingsProblem(
      file,
      '"${path.join('.')}": $issue, ignored',
      kind: SettingsProblemKind.validation,
      key: path,
    ),
  );
  void unknown(List<String> path) => problems.add(
    SettingsProblem(
      file,
      'unknown key "${path.join('.')}", ignored',
      kind: SettingsProblemKind.validation,
      key: path,
    ),
  );

  String? string(List<String> path, Object? value) {
    if (value is! String) {
      bad(path, 'invalid input: expected string, received ${_received(value)}');
      return null;
    }
    if (value.isEmpty) {
      bad(path, 'too small: expected string to have >=1 characters');
      return null;
    }
    return value;
  }

  bool? boolean(List<String> path, Object? value) {
    if (value is bool) return value;
    bad(path, 'invalid input: expected boolean, received ${_received(value)}');
    return null;
  }

  String? choice(List<String> path, Object? value, List<String> values) {
    if (values.contains(value)) return value as String;
    bad(path, 'invalid option: expected one of ${_options(values)}');
    return null;
  }

  Map<String, Object?>? record(
    List<String> path,
    Object? value,
    String expected,
  ) {
    if (value is Map<String, Object?>) return value;
    bad(
      path,
      'invalid input: expected $expected, received ${_received(value)}',
    );
    return null;
  }

  AgentSettings? agentOf(String name, Object? value) {
    final path = ['agents', name];
    final fields = record(path, value, 'object');
    if (fields == null) return null;
    SettingsCommand? command;
    String? model, effort, permissionMode;
    bool? mcpServers;
    if (fields.containsKey('command')) {
      final raw = fields['command'];
      if (raw is String && raw.isNotEmpty) {
        command = CommandLine(raw);
      } else if (raw is List &&
          raw.isNotEmpty &&
          raw.every((item) => item is String) &&
          (raw.first as String).isNotEmpty) {
        command = CommandArgv(raw.cast<String>());
      } else {
        refused[name] = 'expected a string, got ${_given(raw)}';
        problems.add(
          SettingsProblem(
            file,
            '"agents.$name.command": ${refused[name]} · $name will not start',
            kind: SettingsProblemKind.validation,
            key: [...path, 'command'],
          ),
        );
      }
    }
    String? text(String key) =>
        fields.containsKey(key) ? string([...path, key], fields[key]) : null;
    model = text('model');
    effort = text('effort');
    permissionMode = text('permissionMode');
    if (fields.containsKey('mcpServers')) {
      mcpServers = boolean([...path, 'mcpServers'], fields['mcpServers']);
    }
    for (final key in fields.keys) {
      if (!_agentKeys.contains(key)) unknown([...path, key]);
    }
    return AgentSettings(
      command: command,
      model: model,
      effort: effort,
      permissionMode: permissionMode,
      mcpServers: mcpServers,
    );
  }

  bool has(String key) => input.containsKey(key);
  final agent = has('agent') ? string(['agent'], input['agent']) : null;
  Map<String, AgentSettings>? agents;
  if (has('agents')) {
    final entries = record(['agents'], input['agents'], 'record');
    if (entries != null) {
      agents = {
        for (final MapEntry(:key, :value) in entries.entries)
          key: ?agentOf(key, value),
      };
    }
  }
  // A bad item of a constraint's list leaves the list, not the key, as the
  // original's parse leaves it (its Q346).
  List<String>? ids(List<String> path, Object? value, String allows) {
    if (value is! List) {
      bad(path, 'invalid input: expected array, received ${_received(value)}');
      return null;
    }
    if (value.length > _idsMax) {
      bad(path, 'too big: expected array to have <=$_idsMax items');
      return null;
    }
    final kept = <String>[];
    for (final (index, item) in value.indexed) {
      final issue = _refIssue(item);
      if (issue == null) {
        kept.add(item as String);
        continue;
      }
      problems.add(
        SettingsProblem(
          file,
          '"${path.join('.')}": item ${index + 1} (${_shownItem(item)}), '
          '$issue, left out',
          kind: SettingsProblemKind.validation,
          key: path,
          leftOut: SettingsLeftOut.item,
        ),
      );
    }
    if (value.isNotEmpty && kept.isEmpty) {
      problems.add(
        SettingsProblem(
          file,
          '"${path.join('.')}": no item left; the list now allows no $allows',
          kind: SettingsProblemKind.validation,
          key: path,
          leftOut: SettingsLeftOut.list,
        ),
      );
    }
    return kept;
  }

  // A record of runtime to its ids: a bad runtime name or list costs only
  // its own entry.
  Map<String, Object?>? byRuntime(List<String> path, Object? value) {
    final entries = record(path, value, 'record');
    if (entries == null) return null;
    final kind = path.last.substring(0, path.last.length - 1);
    final checked = <String, Object?>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      if (_refIssue(key) case final issue?) {
        bad([...path, key], issue);
      } else if (ids([...path, key], value, '$kind for $key')
          case final kept?) {
        checked[key] = kept;
      }
    }
    return checked;
  }

  // Each object strict, its own keys checked in the schema's order and
  // anything else unknown.
  Map<String, Object?>? strict(
    List<String> path,
    Object? value,
    Map<String, Object? Function(List<String> path, Object? value)> keys,
  ) {
    final fields = record(path, value, 'object');
    if (fields == null) return null;
    final checked = <String, Object?>{};
    for (final MapEntry(:key, value: check) in keys.entries) {
      if (!fields.containsKey(key)) continue;
      final at = [...path, key];
      final before = problems.length;
      final kept = check(at, fields[key]);
      // A value that cost a problem of its own is gone; a list that only
      // lost items stays.
      if (kept != null || fields[key] == null && problems.length == before) {
        checked[key] = kept;
      }
    }
    for (final key in fields.keys) {
      if (!keys.containsKey(key)) unknown([...path, key]);
    }
    return checked;
  }

  String? ref(List<String> path, Object? value) {
    final issue = _refIssue(value);
    if (issue != null) bad(path, issue);
    return issue == null ? value as String : null;
  }

  final teamSelection = has('teamSelection')
      ? strict(
          ['teamSelection'],
          input['teamSelection'],
          {
            'intent': (path, value) => choice(path, value, teamIntents),
            'prefer': (path, value) => strict(path, value, {
              'agent': ref,
              'model': (path, value) => value == null ? null : ref(path, value),
            }),
            'constraints': (path, value) => strict(path, value, {
              'agents': (path, value) => ids(path, value, 'agent'),
              'models': byRuntime,
              'modes': byRuntime,
            }),
          },
        )
      : null;
  final mcpServers = has('mcpServers')
      ? record(['mcpServers'], input['mcpServers'], 'record')
      : null;
  final channel = has('preferredNotifChannel')
      ? choice(
          ['preferredNotifChannel'],
          input['preferredNotifChannel'],
          notifChannels,
        )
      : null;
  final theme = has('theme')
      ? choice(['theme'], input['theme'], themeSettings)
      : null;
  final editorMode = has('editorMode')
      ? choice(['editorMode'], input['editorMode'], editorModes)
      : null;
  final mouse = has('mouse') ? boolean(['mouse'], input['mouse']) : null;
  final copyOnSelect = has('copyOnSelect')
      ? boolean(['copyOnSelect'], input['copyOnSelect'])
      : null;
  List<String>? offeredAgents;
  if (has('offeredAgents')) {
    final value = input['offeredAgents'];
    if (value is List &&
        value.isNotEmpty &&
        value.every((name) => name is String && name.isNotEmpty)) {
      offeredAgents = List.unmodifiable(value.cast<String>());
    } else {
      bad(['offeredAgents'], 'expected a list of one or more agent names');
    }
  }
  for (final key in input.keys) {
    if (!_fileKeys.contains(key)) unknown([key]);
  }

  return ParsedSettings(
    Settings(
      agent: agent,
      agents: agents,
      teamSelection: teamSelection,
      mcpServers: mcpServers,
      preferredNotifChannel: channel,
      theme: theme,
      editorMode: editorMode,
      mouse: mouse,
      copyOnSelect: copyOnSelect,
      offeredAgents: offeredAgents,
    ),
    problems,
    refused,
  );
}

const _agentKeys = {
  'command',
  'model',
  'effort',
  'permissionMode',
  'mcpServers',
};

const _fileKeys = {
  'agent',
  'agents',
  'teamSelection',
  'mcpServers',
  'preferredNotifChannel',
  'theme',
  'editorMode',
  'mouse',
  'copyOnSelect',
  'offeredAgents',
};

/// What a team run's selection aims at, as `teamSelection.intent` says.
const teamIntents = ['balanced', 'prefer', 'economy', 'fixed'];

/// The most names a constraint's list holds, and the longest name.
const _idsMax = 128, _refMax = 128;

/// What is wrong with [value] as an agent, model or mode name, in zod's
/// words as the original's `ref` says them; null when it is one.
String? _refIssue(Object? value) => value is! String
    ? 'invalid input: expected string, received ${_received(value)}'
    : value.isEmpty
    ? 'too small: expected string to have >=1 characters'
    : value.length > _refMax
    ? 'too big: expected string to have <=$_refMax characters'
    : null;

/// An item as the person wrote it, short enough for one line.
String _shownItem(Object? value) {
  final json = jsonEncode(value);
  return json.length > 40 ? '${json.substring(0, 40)}…' : json;
}

/// [next]'s team selection over [previous]'s: its keys win, preferences
/// field by field, constraints key by key and their runtime maps runtime by
/// runtime, a list replaced whole, as the original's mergeTeamSelection.
Map<String, Object?> mergeTeamSelection(
  Map<String, Object?>? previous,
  Map<String, Object?>? next,
) {
  previous ??= const {};
  next ??= const {};
  Map<String, Object?>? mapAt(Map<String, Object?>? of, String key) =>
      of?[key] as Map<String, Object?>?;
  Map<String, Object?>? both(
    Map<String, Object?>? earlier,
    Map<String, Object?>? later,
  ) => earlier == null && later == null ? null : {...?earlier, ...?later};
  final prefer = both(mapAt(previous, 'prefer'), mapAt(next, 'prefer'));
  final was = mapAt(previous, 'constraints'), now = mapAt(next, 'constraints');
  final constraints = both(was, now);
  if (constraints != null) {
    for (final key in const ['models', 'modes']) {
      final runtimes = both(mapAt(was, key), mapAt(now, key));
      if (runtimes != null) constraints[key] = runtimes;
    }
  }
  return {...previous, ...next, 'prefer': ?prefer, 'constraints': ?constraints};
}

/// Later settings win, key by key, agent by agent within `agents` and
/// server by server within `mcpServers`.
Settings mergeSettings(Iterable<Settings> layers) {
  var merged = const Settings();
  for (final layer in layers) {
    final agents = merged.agents;
    merged = Settings(
      agent: layer.agent ?? merged.agent,
      agents: layer.agents == null
          ? agents
          : {
              ...?agents,
              for (final MapEntry(:key, :value) in layer.agents!.entries)
                key: value.over(agents?[key]),
            },
      teamSelection: layer.teamSelection == null
          ? merged.teamSelection
          : mergeTeamSelection(merged.teamSelection, layer.teamSelection),
      mcpServers: layer.mcpServers == null
          ? merged.mcpServers
          : {...?merged.mcpServers, ...layer.mcpServers!},
      preferredNotifChannel:
          layer.preferredNotifChannel ?? merged.preferredNotifChannel,
      theme: layer.theme ?? merged.theme,
      editorMode: layer.editorMode ?? merged.editorMode,
      mouse: layer.mouse ?? merged.mouse,
      copyOnSelect: layer.copyOnSelect ?? merged.copyOnSelect,
      offeredAgents: layer.offeredAgents ?? merged.offeredAgents,
    );
  }
  return merged;
}

/// One file's settings, kept apart so a value can be traced to its file.
class SettingsLayer {
  const SettingsLayer(this.file, this.settings, [this.refused = const {}]);

  final String file;
  final Settings settings;

  /// The agents whose command this file gives was refused, with why.
  final Map<String, String> refused;
}

/// Both files read, merged, and what was wrong with them.
class LoadedSettings {
  const LoadedSettings(this.settings, this.layers, this.problems);

  final Settings settings;
  final List<SettingsLayer> layers;
  final List<SettingsProblem> problems;
}

/// Reads the user's file, then the project's, which overrides it. A file
/// that is not there is no problem. A user-only key in the project's file
/// is a problem and is left out; [home] shows the user's file from `~` in
/// what it says.
Future<LoadedSettings> loadSettings({
  required String? configHome,
  required String cwd,
  String? home,
}) async {
  final layers = <SettingsLayer>[];
  final problems = <SettingsProblem>[];
  final user = userSettingsFile(configHome);

  for (final file in settingsFiles(configHome: configHome, cwd: cwd)) {
    final String text;
    try {
      // As the original reads utf8: a malformed byte is replaced, not fatal.
      text = utf8.decode(await File(file).readAsBytes(), allowMalformed: true);
    } on PathNotFoundException {
      continue;
    } on FileSystemException catch (error) {
      problems.add(
        SettingsProblem(
          file,
          'cannot be read (${_reason(error)}); the file is ignored',
          kind: SettingsProblemKind.read,
        ),
      );
      continue;
    }

    final parsed = parseSettings(file, text);
    var settings = parsed.settings;
    problems.addAll(parsed.problems);

    for (final key in file == user ? const <String>[] : _userOnly) {
      if (settings._userOnlyValue(key) == null) continue;
      settings = settings._without(key);
      problems.add(
        SettingsProblem(
          file,
          '"$key" is read only from ${user == null ? "the user's settings file" : shownPath(user, cwd: cwd, home: home)}, ignored',
          kind: SettingsProblemKind.scope,
          key: [key],
        ),
      );
    }
    layers.add(SettingsLayer(file, settings, parsed.refused));
  }

  return LoadedSettings(
    mergeSettings(layers.map((layer) => layer.settings)),
    layers,
    problems,
  );
}

String _reason(FileSystemException error) {
  final os = error.osError?.message;
  return os == null || os.isEmpty ? error.message : os;
}

/// The merged `teamSelection` policy, read now: `policy` while the files
/// read and parse and their `teamSelection` is valid, a list that only
/// lost bad items included; else `error`, as a selected run is refused
/// while the person's settings cannot be checked.
Future<({Map<String, Object?>? policy, String? error})> readTeamSelection({
  required String? configHome,
  required String cwd,
  String? home,
}) async {
  final loaded = await loadSettings(
    configHome: configHome,
    cwd: cwd,
    home: home,
  );
  final invalid = loaded.problems.any(
    (problem) =>
        problem.kind == SettingsProblemKind.read ||
        problem.kind == SettingsProblemKind.parse ||
        (problem.kind == SettingsProblemKind.validation &&
            problem.key?.firstOrNull == 'teamSelection' &&
            problem.leftOut == null),
  );
  return invalid
      ? (
          policy: null,
          error:
              'Team selection settings could not be validated. Correct the '
              'settings before selecting a team.',
        )
      : (
          policy: loaded.settings.teamSelection ?? const <String, Object?>{},
          error: null,
        );
}

/// What the command line gave; anything left out falls back to the files.
class Flags {
  const Flags({
    this.agent,
    this.agentCommand,
    this.model,
    this.effort,
    this.permissionMode,
  });

  final String? agent;
  final String? agentCommand;
  final String? model;
  final String? effort;
  final String? permissionMode;
}

/// A value and what set it: the flag's name, or the settings file's path,
/// so an agent's refusal can point at the place to change it.
class Sourced {
  const Sourced(this.id, this.from);

  final String id;
  final String from;

  @override
  bool operator ==(Object other) =>
      other is Sourced && other.id == id && other.from == from;

  @override
  int get hashCode => Object.hash(id, from);

  @override
  String toString() => 'Sourced($id, $from)';
}

/// Why an agent is not started: its command, refused in [file].
class Refusal {
  const Refusal(this.file, this.cause);

  final String file;

  /// `expected a string, got a number`.
  final String cause;

  @override
  bool operator ==(Object other) =>
      other is Refusal && other.file == file && other.cause == cause;

  @override
  int get hashCode => Object.hash(file, cause);

  @override
  String toString() => 'Refusal($file, $cause)';
}

/// What chord starts with once flags, files and its own default are weighed.
class Startup {
  const Startup({
    required this.agent,
    this.agentCommand,
    this.refused,
    this.model,
    this.effort,
    this.permissionMode,
  });

  final String agent;

  /// `--agent-command`'s line, else the files' command.
  final SettingsCommand? agentCommand;

  /// A file gave a command for the agent that chord refused: nothing starts
  /// on it, not even chord's own command, unless a flag gives one.
  final Refusal? refused;
  final Sourced? model;
  final Sourced? effort;
  final Sourced? permissionMode;

  @override
  bool operator ==(Object other) =>
      other is Startup &&
      other.agent == agent &&
      other.agentCommand == agentCommand &&
      other.refused == refused &&
      other.model == model &&
      other.effort == effort &&
      other.permissionMode == permissionMode;

  @override
  int get hashCode =>
      Object.hash(agent, agentCommand, refused, model, effort, permissionMode);

  @override
  String toString() =>
      'Startup($agent, command: $agentCommand, refused: $refused, '
      'model: $model, effort: $effort, permissionMode: $permissionMode)';
}

Sourced? _sourced(
  String name,
  String? flag,
  List<SettingsLayer> layers,
  String agent,
  String? Function(AgentSettings) key,
) {
  if (flag != null) return Sourced(flag, name);
  for (final layer in layers.reversed) {
    final settings = layer.settings.agents?[agent];
    final id = settings == null ? null : key(settings);
    if (id != null) return Sourced(id, layer.file);
  }
  return null;
}

/// The last file to give the agent a command decides: a refused one
/// refuses the agent, never falling back to chord's own, and a later good
/// one replaces it.
SettingsLayer? _commandLayer(List<SettingsLayer> layers, String agent) => layers
    .reversed
    .where(
      (layer) =>
          layer.refused.containsKey(agent) ||
          layer.settings.agents?[agent]?.command != null,
    )
    .firstOrNull;

/// The agents the files leave unstartable: their deciding command was
/// refused.
Set<String> refusedAgents(List<SettingsLayer> layers) => {
  for (final layer in layers)
    for (final agent in layer.refused.keys)
      if (_commandLayer(layers, agent)!.refused.containsKey(agent)) agent,
};

/// A flag beats the files, and a later file an earlier one. The agent's
/// other settings are looked up under the agent chosen, whichever said it.
Startup resolveStartup(
  Flags flags,
  List<SettingsLayer> layers,
  String defaultAgent,
) {
  final settings = mergeSettings(layers.map((layer) => layer.settings));
  final agent = flags.agent ?? settings.agent ?? defaultAgent;
  final agentCommand = flags.agentCommand != null
      ? CommandLine(flags.agentCommand!)
      : settings.agents?[agent]?.command;
  final last = _commandLayer(layers, agent);
  final cause = last?.refused[agent];
  final refused = flags.agentCommand == null && cause != null
      ? Refusal(last!.file, cause)
      : null;
  return Startup(
    agent: agent,
    agentCommand: refused == null ? agentCommand : null,
    refused: refused,
    model: _sourced('--model', flags.model, layers, agent, (a) => a.model),
    effort: _sourced('--effort', flags.effort, layers, agent, (a) => a.effort),
    permissionMode: _sourced(
      '--permission-mode',
      flags.permissionMode,
      layers,
      agent,
      (a) => a.permissionMode,
    ),
  );
}

/// What a session resumed from another directory starts with: the agent
/// and its command stay those that found the session; its model, effort
/// and mode come from the files where it works, and a flag still beats them.
Startup resumedStartup(Startup found, Flags flags, List<SettingsLayer> layers) {
  final here = resolveStartup(
    Flags(
      agent: found.agent,
      agentCommand: flags.agentCommand,
      model: flags.model,
      effort: flags.effort,
      permissionMode: flags.permissionMode,
    ),
    layers,
    found.agent,
  );
  return Startup(
    agent: found.agent,
    agentCommand: found.agentCommand,
    model: here.model,
    effort: here.effort,
    permissionMode: here.permissionMode,
  );
}

/// `codex not started: agents.codex.command in <file>: expected a string, …`.
String refusalLine(
  String agent,
  Refusal refusal, {
  required String cwd,
  required String? home,
}) =>
    '$agent not started: agents.$agent.command in '
    '${shownPath(refusal.file, cwd: cwd, home: home)}: ${refusal.cause}';

/// The command the settings files start each agent with, where one does.
Map<String, SettingsCommand> agentCommands(List<SettingsLayer> layers) => {
  for (final MapEntry(:key, :value)
      in (mergeSettings(layers.map((layer) => layer.settings)).agents ??
              const <String, AgentSettings>{})
          .entries)
    key: ?value.command,
};

/// Every agent a window started on [invoked] can open a session of, by
/// name: that one, those the settings files give a command, then
/// [registry]'s.
List<String> knownAgents(
  Startup invoked,
  List<SettingsLayer> layers,
  List<String> registry,
) => {invoked.agent, ...agentCommands(layers).keys, ...registry}.toList();

/// The problems in [found] not already in [seen]: both readings take in
/// the user's file, and its problems are said once.
List<SettingsProblem> unseenProblems(
  List<SettingsProblem> seen,
  List<SettingsProblem> found,
) => [
  for (final problem in found)
    if (!seen.any(
      (old) => old.file == problem.file && old.message == problem.message,
    ))
      problem,
];

/// A path as the window shows it: under the working directory relative to
/// it; under the home directory from `~`; elsewhere whole. A screen never
/// shows the person's home path.
String shownPath(String file, {required String cwd, required String? home}) {
  final path = p.relative(file, from: cwd);
  return path == '.' || path.startsWith('..') ? homePath(file, home) : path;
}

/// A path shortened against the home directory alone: `~` for the home
/// directory itself, from `~` under it, elsewhere whole.
String homePath(String file, String? home) {
  if (home == null) return file;

  final path = p.relative(file, from: home);

  return path == '.'
      ? '~'
      : path.startsWith('..') || p.isAbsolute(path)
      ? file
      : '~${p.separator}$path';
}

/// Where a starting value was set, as a refusal says it.
String setWhere(String from, {required String cwd, required String? home}) =>
    from.startsWith('-')
    ? 'set by $from'
    : 'set in ${shownPath(from, cwd: cwd, home: home)}';

/// A problem as the transcript says it, the file shown as the window shows
/// paths.
String problemNote(
  SettingsProblem problem, {
  required String cwd,
  required String? home,
}) => '${shownPath(problem.file, cwd: cwd, home: home)}: ${problem.message}';

/// What chord says of a name `offeredAgents` gives that it lacks.
String unknownOfferedMessage(String name) =>
    '"offeredAgents": no agent named $name, left out';

/// The names `offeredAgents` gives that chord lacks, one problem each.
List<SettingsProblem> unknownOffered(String file, List<String> unknown) => [
  for (final name in unknown)
    SettingsProblem(
      file,
      unknownOfferedMessage(name),
      kind: SettingsProblemKind.validation,
      key: const ['offeredAgents'],
    ),
];

/// A problem as stderr says it, naming the file.
String problemLine(SettingsProblem problem) =>
    'chord: ${problem.file}: ${problem.message}';

bool _sameList(List<String>? a, List<String>? b) => a == null || b == null
    ? a == b
    : a.length == b.length &&
          Iterable.generate(a.length).every((i) => a[i] == b[i]);

/// Sets `theme` in the user's file, as [saveSettingAt] sets a key.
Future<void> saveTheme(String file, String theme) =>
    saveSettingAt(file, const ['theme'], SetSetting(theme));

/// Sets `editorMode` in the user's file, as `/vim` leaves it.
Future<void> saveEditorMode(String file, String mode) =>
    saveSettingAt(file, const ['editorMode'], SetSetting(mode));

/// What a write does at a settings path.
sealed class SettingChange {
  const SettingChange();
}

/// Sets the leaf to [value].
final class SetSetting extends SettingChange {
  const SetSetting(this.value);
  final Object? value;
}

/// Removes the leaf, and the parents that leaves empty.
final class RemoveSetting extends SettingChange {
  const RemoveSetting();
}

/// A write the settings file refuses, in the words the refusal ends with.
final class SettingRefused implements Exception {
  const SettingRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What the writer says with no file to write.
const noSettingsHome =
    'No settings file without a home directory; nothing was saved';

/// Names that reach an object's prototype in the original, so no path may
/// hold them, whatever a file or a caller says.
const _notKeys = {'__proto__', 'constructor', 'prototype'};

/// Whether a path can name a setting at all, whichever setting it is.
bool canBeSettingPath(List<String> path) =>
    path.isNotEmpty && !path.any(_notKeys.contains);

/// A value as the person reads it: JSON, on one line, or [indent] cells a
/// level when given, with what JSON leaves raw and a terminal would act on
/// escaped too.
String shownValue(Object? value, [int? indent]) =>
    (indent == null
            ? jsonEncode(value)
            : JsonEncoder.withIndent(' ' * indent).convert(value))
        .replaceAllMapped(
          // A raw line feed is the indent's own: JSON escapes any in a string.
          RegExp(r'(?!\n)[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', unicode: true),
          (mark) => [
            for (final unit in mark[0]!.codeUnits)
              '\\u${unit.toRadixString(16).padLeft(4, '0')}',
          ].join(),
        );

/// A path's keys joined by dots, a key with anything else in it as JSON.
String shownSettingPath(List<String> path) => path
    .map(
      (key) =>
          RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key) ? key : shownValue(key),
    )
    .join('.');

/// The user's file as an object, empty when it is not there. What is wrong
/// with one that is there is thrown as a [SettingRefused].
Future<Map<String, Object?>> readSettingsObject(String file) async {
  final String text;
  try {
    text = utf8.decode(await File(file).readAsBytes(), allowMalformed: true);
  } on PathNotFoundException {
    return {};
  }
  final Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException {
    throw const SettingRefused('it is not valid JSON');
  }
  if (parsed is! Map<String, Object?>) {
    throw const SettingRefused('it is not a JSON object');
  }
  return parsed;
}

/// The value at [path], by the object's own keys alone.
Object? settingAt(Object? value, List<String> path) {
  var held = value;
  for (final key in path) {
    if (held is! Map<String, Object?> || !held.containsKey(key)) return null;
    held = held[key];
  }
  return held;
}

/// Why [path] cannot be written in [settings]: the first parent there that
/// is not an object.
String? settingParentProblem(Map<String, Object?> settings, List<String> path) {
  var held = settings;
  for (var depth = 0; depth < path.length - 1; depth++) {
    final key = path[depth];
    if (!held.containsKey(key)) return null;
    final next = held[key];
    if (next is! Map<String, Object?>) {
      return 'its ${shownSettingPath(path.sublist(0, depth + 1))} is not an object; edit it by hand';
    }
    held = next;
  }
  return null;
}

/// Sets or removes the leaf at [path] in the user's file, keeping every
/// other key: the file is read, changed, and the object written whole with
/// two-space indents to a file beside it that is renamed over the old, so a
/// crash cannot leave half a file. A missing file, and its directory, are
/// made. A file that is not a JSON object, or a parent on the path that is
/// not one, is never overwritten: the write is refused instead. Removing
/// what is not there writes nothing.
Future<void> saveSettingAt(
  String? file,
  List<String> path,
  SettingChange change,
) async {
  if (file == null) throw const SettingRefused(noSettingsHome);
  if (!canBeSettingPath(path)) {
    throw SettingRefused('No setting ${shownSettingPath(path)}');
  }
  final settings = await readSettingsObject(file);
  final problem = settingParentProblem(settings, path);
  if (problem != null) throw SettingRefused(problem);
  switch (change) {
    case SetSetting(:final value):
      var parent = settings;
      for (final key in path.sublist(0, path.length - 1)) {
        parent = (parent[key] ??= <String, Object?>{}) as Map<String, Object?>;
      }
      parent[path.last] = value;
    case RemoveSetting():
      if (!_has(settings, path)) return;
      for (var depth = path.length; depth > 0; depth--) {
        final parent =
            settingAt(settings, path.sublist(0, depth - 1))
                as Map<String, Object?>;
        parent.remove(path[depth - 1]);
        if (parent.isNotEmpty) break;
      }
  }
  await Directory(p.dirname(file)).create(recursive: true);
  final temporary = '$file.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp';
  try {
    await File(temporary).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(settings)}\n',
    );
    await File(temporary).rename(file);
  } catch (_) {
    try {
      await File(temporary).delete();
    } on FileSystemException {
      // Nothing was left to take away.
    }
    rethrow;
  }
}

/// Whether [path] holds a value, null included, in [settings].
bool _has(Map<String, Object?> settings, List<String> path) {
  final parent = settingAt(settings, path.sublist(0, path.length - 1));
  return parent is Map<String, Object?> && parent.containsKey(path.last);
}

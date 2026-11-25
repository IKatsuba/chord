import 'dart:io';
import 'dart:math';

import 'package:chord_tui/chord_tui.dart';
import 'package:process_run/which.dart';

import 'chorded.dart';
import 'clis.dart';
import 'registry.dart';
import 'settings.dart';
import 'shell_quote.dart';

/// The registry calls Claude's and Codex's adapters `claude-acp` and
/// `codex-acp`; chord has always started them as `claude` and `codex`, and
/// those names stay, in the registry's place.
const _aliases = {
  'claude': 'claude-acp',
  'codex': 'codex-acp',
  // The registry's Kimi Code, which chord ran as its own CLI `kimi` before:
  // records, settings and team files keep the name.
  'kimi': 'kimi-code',
};

/// Fallback agent and initial startup-picker preference.
const defaultAgent = 'claude';

/// What starts an agent: npx or uvx with the registry's package, `cli`, a
/// command the person installs themselves, or `settings`, the command a
/// settings file gives.
enum AgentRunner { npx, uvx, cli, settings }

/// How an agent's process is started.
class AgentStart {
  /// A start: the argv, taken whole, and the environment laid over chord's.
  const AgentStart(this.command, this.env);

  /// The command and its words.
  final List<String> command;

  /// Laid over chord's own environment for the agent alone.
  final Map<String, String> env;
}

/// An agent chord can start by name.
class KnownAgent {
  /// An agent of the catalog.
  const KnownAgent({
    required this.name,
    required this.title,
    required this.start,
    required this.runner,
    required this.install,
    this.pinned,
    this.mcpServers,
    this.fastOption,
  });

  /// What `chord <name>` calls it.
  final String name;

  /// What the registry or the agent calls it, for people.
  final String title;

  /// How its process is started.
  final AgentStart start;

  /// What starts it.
  final AgentRunner runner;

  /// Where the agent says to install it, when it says.
  final String? install;

  /// The registry's package and version, `package@version`, that npx or uvx
  /// runs.
  final String? pinned;

  /// `false` where chord's own table gives the agent no MCP servers.
  final bool? mcpServers;

  /// The adapter's recorded speed-option id when ACP has no speed category.
  final String? fastOption;
}

final _byId = {
  for (final MapEntry(:key, :value) in _aliases.entries) value: key,
};

KnownAgent _fromRegistry(RegistryAgent agent) {
  final pinned = '${agent.package}@${agent.version}';

  return KnownAgent(
    name: _byId[agent.id] ?? agent.id,
    title: agent.name,
    start: AgentStart(switch (agent.runner) {
      Runner.npx => ['npx', '-y', pinned, ...agent.args],
      Runner.uvx => ['uvx', pinned, ...agent.args],
    }, agent.env),
    runner: switch (agent.runner) {
      Runner.npx => AgentRunner.npx,
      Runner.uvx => AgentRunner.uvx,
    },
    install: agent.website ?? agent.repository,
    pinned: pinned,
    fastOption: const {
      'claude-acp': 'fast',
      'codex-acp': 'fast-mode',
    }[agent.id],
    mcpServers: agent is ChordedAgent ? agent.mcpServers : null,
  );
}

KnownAgent _fromCli(CliAgent agent) => KnownAgent(
  name: agent.name,
  title: agent.title,
  start: AgentStart(agent.argv, const {}),
  runner: AgentRunner.cli,
  install: agent.install,
  mcpServers: agent.mcpServers,
);

/// The registry's agents, then the table's. A name in both is the
/// registry's: its entry pins a version and needs nothing installed but npx
/// or uvx.
final List<KnownAgent> _agents = () {
  final registered = ([
    ...registryAgents,
    ...chordedAgents,
  ]..sort((a, b) => a.id.compareTo(b.id))).map(_fromRegistry).toList();

  return List<KnownAgent>.unmodifiable([
    ...registered,
    ...cliAgents
        .where((cli) => !registered.any((agent) => agent.name == cli.name))
        .map(_fromCli),
  ]);
}();

/// Every agent chord can start by name: the registry's, then the table's.
List<KnownAgent> listAgents() => _agents;

/// The agent a name means, or null for one chord does not know.
KnownAgent? findAgent(String name) {
  for (final agent in _agents) {
    if (agent.name == name) return agent;
  }
  return null;
}

/// What a registry agent runs through: chord fetches the agent itself, so
/// what a person lacks is the runner, and the agent's own site would not
/// give it.
const _runners = {
  AgentRunner.npx: 'npx comes with Node.js: https://nodejs.org/en/download',
  AgentRunner.uvx:
      'uvx comes with uv: https://docs.astral.sh/uv/getting-started/installation/',
};

/// Finds a command on PATH, or null; tests give one of their own.
typedef Lookup = Future<String?> Function(String command);

/// Finds [command] on the real PATH alone. process_run would otherwise lay
/// its own user env files over the environment, which the original's lookup
/// never reads.
Future<String?> onPath(String command) => which(
  command,
  environment: Platform.environment,
  includeParentEnvironment: false,
);

/// The line chord refuses [name] with when the command its start runs is
/// not on PATH, or null when it is there or chord does not know the name.
Future<String?> missingCommand(String name, [Lookup lookup = onPath]) async {
  final agent = findAgent(name);

  if (agent == null || agent.start.command.isEmpty) return null;

  final command = agent.start.command.first;

  if (await lookup(command) != null) return null;

  final line = 'chord: $name runs "$command", which is not on PATH';
  final runner = _runners[agent.runner];

  if (runner != null) return '$line; $runner';

  return agent.install == null
      ? '$line.'
      : '$line; install it from ${agent.install}';
}

/// The start as one line a person could type, for `chord agents`.
String startLine(AgentStart start) => [
  for (final MapEntry(:key, :value) in start.env.entries) '$key=$value',
  ...start.command,
].join(' ');

/// An agent as `chord agents` lists it.
class ListedAgent {
  /// A row of `chord agents`.
  const ListedAgent({
    required this.name,
    required this.title,
    required this.start,
    required this.from,
    this.found,
  });

  /// What `chord <name>` calls it.
  final String name;

  /// What the registry or the agent calls it, for people; none for an
  /// agent the settings files alone define.
  final String? title;

  /// What starts it, as a person would type it.
  final String start;

  /// Where that comes from: the registry's npx or uvx, or the agent's own
  /// CLI from the table.
  final AgentRunner from;

  /// For the agent's own CLI, whether PATH has its command.
  final bool? found;
}

/// The default start-page catalog, excluding own CLIs missing from PATH.
List<ListedAgent> offeredAgents(Iterable<ListedAgent> catalog) => [
  for (final agent in catalog)
    if (agent.found != false) agent,
];

/// What the start page offers from [catalog]: the `offeredAgents` setting's
/// names in its order, each once, or without it [catalog] as given; and the
/// names the setting gives that the catalog lacks, in the setting's order.
({List<ListedAgent> agents, List<String> unknown}) offeredFrom(
  List<ListedAgent> catalog,
  List<String>? offered,
) {
  if (offered == null) return (agents: catalog, unknown: []);
  final agents = <ListedAgent>[];
  final unknown = <String>[];
  for (final name in {...offered}) {
    final agent = catalog.where((listed) => listed.name == name).firstOrNull;
    if (agent == null) {
      unknown.add(name);
    } else {
      agents.add(agent);
    }
  }
  return (agents: agents, unknown: unknown);
}

/// A command as a line: given as one, or its words quoted as a shell would.
String commandLine(SettingsCommand command) => switch (command) {
  CommandLine(:final line) => line,
  CommandArgv(:final argv) => quote(argv),
};

/// What chord calls an agent with no title, as the settings files alone
/// define it.
const settingsOnly = 'from settings';

/// Every agent chord can start, as `chord agents` lists them: the catalog's,
/// those [commands] start their own way, then the names only [commands]
/// gives.
Future<List<ListedAgent>> listedAgents([
  Lookup lookup = onPath,
  Map<String, SettingsCommand> commands = const {},
]) async => [
  ...await Future.wait(
    _agents.map((agent) async {
      final command = agent.start.command;
      final given = commands[agent.name];

      if (given != null) {
        return ListedAgent(
          name: agent.name,
          title: agent.title,
          start: commandLine(given),
          from: AgentRunner.settings,
        );
      }

      return ListedAgent(
        name: agent.name,
        title: agent.title,
        start: startLine(agent.start),
        from: agent.runner,
        found: agent.runner == AgentRunner.cli && command.isNotEmpty
            ? await lookup(command.first) != null
            : null,
      );
    }),
  ),
  for (final MapEntry(:key, :value) in commands.entries)
    if (findAgent(key) == null)
      ListedAgent(
        name: key,
        title: null,
        start: commandLine(value),
        from: AgentRunner.settings,
      ),
];

/// What chord says of an own CLI whose command PATH lacks.
const notOnPath = 'not on PATH';

/// An agent's title and, for its own CLI when PATH lacks it, that: how
/// `/new` describes it, so it says what `chord agents` does.
String agentNote(ListedAgent agent) {
  final shown = agent.title ?? settingsOnly;
  return agent.from == AgentRunner.cli && agent.found == false
      ? '$shown · $notOnPath'
      : shown;
}

/// What `chord agents` says of where an agent's start comes from.
String mark(ListedAgent agent) => switch (agent.from) {
  AgentRunner.cli =>
    agent.found == true ? 'own CLI · found' : 'own CLI · $notOnPath',
  final from => from.name,
};

const _padding = 2;

/// Narrower than this, a start line is wrapped no further; the terminal
/// does.
const _minStart = 20;

/// [text] broken hard into lines of at most [width] cells, as the
/// original's wrap-ansi breaks it.
List<String> _wrap(String text, int width) => [
  for (final line in TextLayout.wrapAnsi(
    TextSpan(text),
    width,
    hard: true,
  ).lines)
    line.map((glyph) => glyph.text).join(),
];

/// `chord agents`' lines in columns: name, title, where the start comes
/// from, and the start last, as it is the one that runs long. On a terminal
/// [width] wide the start wraps within its column, so the names still read
/// down the left; without one, piped, each agent stays one line for grep and
/// awk.
String agentTable(List<ListedAgent> listed, [int? width]) {
  if (listed.isEmpty) return '';

  final rows = [
    for (final agent in listed)
      [agent.name, agent.title ?? settingsOnly, mark(agent)],
  ];
  final widths = [
    for (var column = 0; column < 3; column++)
      rows.map((row) => cellWidth(row[column])).reduce(max),
  ];
  final before = widths.fold(0, (sum, w) => sum + w + _padding);
  final room = width == null ? null : max(width - before, _minStart);
  final starts = [
    for (final agent in listed)
      room == null ? [agent.start] : _wrap(agent.start, room),
  ];
  final lines = <String>[];

  for (var i = 0; i < rows.length; i++) {
    for (var j = 0; j < starts[i].length; j++) {
      final cells = j == 0 ? rows[i] : ['', '', ''];
      final line = StringBuffer();

      for (var column = 0; column < 3; column++) {
        final cell = cells[column];
        line
          ..write(cell)
          ..write(' ' * (widths[column] - cellWidth(cell) + _padding));
      }
      line.write(starts[i][j]);
      lines.add(line.toString().trimRight());
    }
  }

  return lines.join('\n');
}

/// `chord agents --json`: what a client offering a choice of agent reads,
/// ready for `jsonEncode`. Its shape is promised; `version` changes when a
/// field's meaning does. The listed agents come offered first, in the start
/// screen's order, then the rest in the catalog's; a name [offered] gives
/// that the catalog lacks is a problem, as it is on the start screen. No
/// start command is given: it can hold tokens.
Map<String, Object?> agentsJson({
  required List<ListedAgent> listed,
  required List<String>? offered,
  required String preferred,
  required List<SettingsProblem> problems,
  required Set<String> refused,
}) {
  final chosen = offered == null
      ? (agents: offeredAgents(listed), unknown: const <String>[])
      : offeredFrom(listed, offered);
  final shown = [
    for (final agent in chosen.agents)
      if (!refused.contains(agent.name)) agent,
  ];
  Map<String, Object?> entry(ListedAgent agent, bool isOffered) => {
    'name': agent.name,
    'title': agent.title,
    'via': agent.from.name,
    'found': agent.from == AgentRunner.cli ? (agent.found ?? false) : null,
    'offered': isOffered,
    'startable': !refused.contains(agent.name),
  };

  return {
    'version': 1,
    'preferred': preferred,
    'agents': [
      for (final agent in shown) entry(agent, true),
      for (final agent in listed)
        if (!shown.contains(agent)) entry(agent, false),
    ],
    'problems': [
      for (final problem in problems)
        {'file': problem.file, 'message': problem.message},
      for (final name in chosen.unknown)
        {'message': unknownOfferedMessage(name)},
    ],
  };
}

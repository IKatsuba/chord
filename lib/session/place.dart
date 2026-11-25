/// What a session's directory decides for `chord acp`, from the original's
/// `session/place.ts`: how a session of the startup agent starts there.
/// The launch directory's settings are read once; any other directory's on
/// each call, and every directory's MCP servers on each call.
library;

import '../agents.dart';
import '../mcp.dart';
import '../settings.dart';
import 'conversation.dart' show Starting;
import 'servers.dart';
import 'starting.dart';

/// The private dev flag, defined only at compile time (`tool/dev.dart` with
/// `--fake`), never read from the environment, so a built chord cannot be
/// switched by where it runs: every runtime then starts as the command
/// line's `--agent-command`, the fake agent, under its own name, and
/// nothing starts without one.
const fakeRuntimesFlag = bool.fromEnvironment('CHORD_FAKE_RUNTIMES');

/// Why nothing starts on [agent] when chord was built with
/// [fakeRuntimesFlag] and the command line gave no `--agent-command`.
String fakeRuntimesRefusal(String agent) =>
    '$agent does not start: this chord starts only the fake agent, given '
    'with --agent-command';

/// How a session of the startup agent starts in a directory.
final class SessionStart {
  /// A start of [command] with [env], put on [starting]; or [refused].
  const SessionStart({
    this.command,
    this.env = const {},
    this.refused,
    this.starting = const Starting(),
    this.noMcpServers = false,
    this.noMcpServersFrom,
    this.pinned,
    this.mcpServers = const [],
    this.mcpIgnored = const [],
    this.agentCommand,
  });

  /// What starts the agent: a command line or an argv.
  final Object? command;

  /// The person's own command for the agent, from a flag or a settings
  /// file; null when chord's registry starts it. Nothing ties such a
  /// command to the provider's own authentication, so its limits are not
  /// read.
  final Object? agentCommand;

  /// What its catalog entry lays over the environment.
  final Map<String, String> env;

  /// Why nothing starts there, as said to the person: its command refused.
  final String? refused;

  /// The model, effort and mode each session starts on, with where each
  /// was set.
  final Starting starting;

  /// The agent takes no MCP servers there, as a flag, a settings file or
  /// chord's own table says.
  final bool noMcpServers;

  /// What set [noMcpServers]: the flag, or a settings file; none for
  /// chord's own table.
  final String? noMcpServersFrom;

  /// The version the registry pins, said when chord's own start fails.
  final String? pinned;

  /// The MCP servers the directory's files give each session there, with
  /// the file each came from.
  final List<DefinedServer> mcpServers;

  /// What those files defined that chord did not pass.
  final List<Ignored> mcpIgnored;
}

/// A directory and how the startup agent starts in it; none when chord
/// cannot start it there.
typedef AcpPlace = ({String cwd, SessionStart? start});

/// Reads a directory's MCP servers, as [loadMcpServers] does.
typedef McpReader =
    Future<ReadServers> Function({
      required List<SettingsLayer> layers,
      required String cwd,
    });

/// Reads a directory's place.
typedef PlaceReader = Future<AcpPlace> Function(String cwd);

/// Which runtimes a session's children may start on, and how each starts
/// where the session works.
typedef AcpChildren = ({
  List<String> runtimes,
  SessionStart? Function(String runtime) startOf,
});

/// Reads a directory's [AcpChildren].
typedef ChildrenReader = Future<AcpChildren> Function(String cwd);

/// What the children of [agent]'s sessions start on, as the window's do:
/// every runtime chord knows there, each started as [childStart] says, the
/// startup agent as it was invoked in [launchDir] with [flags]. A directory
/// other than [launchDir] is read on each call; its problems are the place
/// reader's to say.
ChildrenReader childrenReader({
  required String agent,
  required String launchDir,
  required LoadedSettings launched,
  required Flags flags,
  bool noMcpServers = false,
  required String? configHome,
  required String? home,
  KnownAgent? Function(String name) find = findAgent,
  McpReader readMcp = loadMcpServers,
  bool fakeRuntimes = fakeRuntimesFlag,
}) {
  final invoked = resolveStartup(flags, launched.layers, agent);
  return (cwd) async {
    final there = cwd == launchDir
        ? launched
        : await loadSettings(configHome: configHome, cwd: cwd, home: home);
    final layers = there.layers;
    final mcp = await readMcp(layers: layers, cwd: cwd);
    return (
      runtimes: knownAgents(invoked, layers, [
        for (final known in listAgents()) known.name,
      ]),
      startOf: (String runtime) => childStart(
        runtime,
        layers,
        cwd: cwd,
        home: home,
        invoked: invoked,
        flags: flags,
        noMcpServers: noMcpServers,
        mcp: mcp,
        find: find,
        fakeRuntimes: fakeRuntimes,
      ),
    );
  };
}

/// The places of [agent]'s sessions: [launched], the launch directory
/// [launchDir]'s settings, as they were read at start; any other directory
/// read on each call, its problems not yet said given to [report]. [flags]
/// are the command line's, and [noMcpServers] its `--no-mcp-servers`. The
/// command is the one chord was invoked with in [launchDir], as the
/// original's `resumedStartup` keeps it; a directory's files give the
/// model, effort and mode, and may refuse the command.
PlaceReader placeReader({
  required String agent,
  required String launchDir,
  required LoadedSettings launched,
  required Flags flags,
  bool noMcpServers = false,
  required String? configHome,
  required String? home,
  KnownAgent? Function(String name) find = findAgent,
  void Function(List<SettingsProblem> problems)? report,
  McpReader readMcp = loadMcpServers,
  bool fakeRuntimes = fakeRuntimesFlag,
}) {
  final said = [...launched.problems];
  // As chord was invoked in the launch directory: its command stays that
  // one wherever a session works.
  final invoked = resolveStartup(flags, launched.layers, agent);
  return (cwd) async {
    final there = cwd == launchDir
        ? launched
        : await loadSettings(configHome: configHome, cwd: cwd, home: home);
    final layers = there.layers;
    final mcp = await readMcp(layers: layers, cwd: cwd);
    final added = unseenProblems(said, [
      if (cwd != launchDir) ...there.problems,
      ...mcp.problems,
    ]);
    said.addAll(added);
    if (added.isNotEmpty) report?.call(added);
    return (
      cwd: cwd,
      start: _startOf(
        agent,
        invoked,
        flags,
        layers,
        cwd: cwd,
        home: home,
        find: find,
        noMcpServers: noMcpServers,
        mcp: mcp,
        fakeRuntimes: fakeRuntimes,
      ),
    );
  };
}

SessionStart? _startOf(
  String agent,
  Startup invoked,
  Flags flags,
  List<SettingsLayer> layers, {
  required String cwd,
  required String? home,
  required KnownAgent? Function(String) find,
  required bool noMcpServers,
  required ReadServers mcp,
  bool fakeRuntimes = false,
}) {
  if (fakeRuntimes && flags.agentCommand == null) {
    return SessionStart(refused: fakeRuntimesRefusal(agent));
  }
  // The command as invoked, the values from the directory's files; its
  // files may still refuse the command, unless a flag gave one.
  final found = resumedStartup(invoked, flags, layers);
  final refusal =
      invoked.refused ??
      (flags.agentCommand == null
          ? resolveStartup(Flags(agent: agent), layers, agent).refused
          : null);
  if (refusal case final refused?) {
    return SessionStart(
      refused: refusalLine(agent, refused, cwd: cwd, home: home),
    );
  }
  final known = find(agent);
  final (
    Object? command,
    Map<String, String> env,
  ) = switch (found.agentCommand) {
    CommandLine(:final line) => (line, const {}),
    CommandArgv(:final argv) => (argv, const {}),
    null => (known?.start.command, known?.start.env ?? const {}),
  };
  if (command == null) return null;
  final taking = mcpServersTaken(
    agent,
    layers,
    flag: noMcpServers,
    known: known,
  );
  StartingValue? starting(Sourced? value) => value == null
      ? null
      : StartingValue(
          value.id,
          from: setWhere(value.from, cwd: cwd, home: home),
        );
  return SessionStart(
    command: command,
    env: env,
    starting: Starting(
      model: starting(found.model),
      effort: starting(found.effort),
      mode: starting(found.permissionMode),
    ),
    noMcpServers: taking.none,
    noMcpServersFrom: taking.from,
    pinned: found.agentCommand == null ? known?.pinned : null,
    agentCommand: found.agentCommand == null ? null : command,
    mcpServers: mcp.servers,
    mcpIgnored: mcp.ignored,
  );
}

/// How a child of [runtime] starts where the window works: its command as
/// the directory's settings or chord's catalog give it, the settings' model,
/// effort and mode, or why it does not start there. A child of the window's
/// own agent, [invoked] with the command line's [flags] and
/// [noMcpServers], starts as that agent was invoked, `--agent-command`
/// included, as the original's `startupOf` does. Its servers are [mcp], the
/// place's, as main's are. With [fakeRuntimes], every runtime starts as
/// the invoked agent does, the fake's `--agent-command`, under its own
/// name.
SessionStart? childStart(
  String runtime,
  List<SettingsLayer> layers, {
  required String cwd,
  required String? home,
  Startup? invoked,
  Flags flags = const Flags(),
  bool noMcpServers = false,
  ReadServers mcp = const ReadServers([], [], []),
  KnownAgent? Function(String name) find = findAgent,
  bool fakeRuntimes = fakeRuntimesFlag,
}) {
  // Only the invoked agent takes the command line: a flag names that one;
  // on the fake every runtime does, so none starts a real agent.
  final own = invoked != null && (fakeRuntimes || runtime == invoked.agent);
  return _startOf(
    runtime,
    own ? invoked : resolveStartup(Flags(agent: runtime), layers, runtime),
    own ? flags : Flags(agent: runtime),
    layers,
    cwd: cwd,
    home: home,
    find: find,
    noMcpServers: own && noMcpServers,
    mcp: mcp,
    fakeRuntimes: fakeRuntimes,
  );
}

/// Whether [agent] takes no MCP servers, as [flag] (`--no-mcp-servers`),
/// else the last of [layers] to set its `mcpServers`, else chord's own
/// table ([known]) says, and what set it: the flag or the file; none for
/// the table or an agent that takes them.
({bool none, String? from}) mcpServersTaken(
  String agent,
  List<SettingsLayer> layers, {
  required bool flag,
  KnownAgent? known,
}) {
  if (flag) return (none: true, from: noMcpServersFlag);
  final setIn = layers.reversed
      .where((layer) => layer.settings.agents?[agent]?.mcpServers != null)
      .firstOrNull;
  final takes =
      setIn?.settings.agents?[agent]?.mcpServers ?? known?.mcpServers ?? true;
  return takes ? (none: false, from: null) : (none: true, from: setIn?.file);
}

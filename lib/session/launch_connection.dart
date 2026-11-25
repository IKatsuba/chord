/// Connects a successful CLI launch to the live session window.
library;

import '../acp/connection.dart';
import '../cli.dart';
import 'leaving.dart';
import 'session.dart';
import 'start_connection.dart';
import '../agents.dart' show listAgents;
import '../server/runtimes.dart';
import '../server/server.dart';
import '../ui/app/state.dart'
    show AgentOpened, SessionClosed, SpendClosed, SpendClosing;
import 'agents_host.dart';
import 'window_agents.dart' show WindowAgents, agentOf, isLead;
import 'place.dart' show SessionStart;
import 'record.dart';
import 'resource_access.dart';
import 'setting_picked_up.dart';
import 'state_dir.dart';
import 'sessions.dart';

/// Starts the launch's selected catalog or override command in [cwd].
StartConnection startLaunchConnection(
  Launch launch, {
  required String cwd,
  SessionOpener open = openWindowAgent,
  Owned? owner,
  Resume? resume,
  Recording? recording,
  String Function() stateDirectory = chordStateDir,
  ChordServer? server,
  ReadLimits? resources,
}) {
  final start = agentStart(launch);
  late StartConnection connection;
  String? failure;
  var selectedRecording = recording;
  if (selectedRecording == null) {
    try {
      selectedRecording = FileRecording(
        stateDirectory(),
        failed: (message) => connection.conversation.recordingFailed(message),
      );
    } catch (error) {
      failure = "Could not keep this session's record: $error";
    }
  }
  connection = StartConnection(
    command: start.command,
    env: start.env,
    agent: launch.name,
    cwd: cwd,
    open: open,
    owner: owner,
    resume: resume ?? launch.resume,
    recording: selectedRecording,
    starting: launch.starting,
    warnings: launch.warnings,
    keysFailed: launch.keysFailed,
    vim: launch.vim,
    theme: launch.theme,
    mcpServers: [for (final defined in launch.mcpServers) defined.server],
    noMcpServers: launch.noMcpServers,
    noMcpServersFrom: launch.noMcpServersFrom,
    configHome: launch.configHome,
    // What the registry pins, said when its agent does not start; a
    // command of the person's own is theirs to know.
    pinned: launch.command == null && launch.agentCommand == null
        ? launch.agent?.pinned
        : null,
  );
  if (server != null) {
    final childStart = launch.childStart ?? (_) => null;
    final host = AgentsHost(
      cwd: cwd,
      configHome: launch.configHome,
      home: launch.home,
      settingSaved: (path, change) {
        if (settingPickedUp(path, change) case final picked?) {
          connection.settingPickedUp?.call(picked);
        }
      },
      runtimeNames:
          launch.runtimeNames ?? [for (final agent in listAgents()) agent.name],
      startupOf: childStart,
      openChildSession: connection.openChild,
      openForkSession: connection.openChild,
      agents: connection.agents,
      opened: (key) => connection.fold.dispatch(AgentOpened(key)),
      closed: (key, front) =>
          connection.fold.dispatch(SessionClosed(key, front)),
      keepClosing: (key, {from, required name, runtime}) =>
          connection.fold.dispatch(
            spendClosingOf(
              connection.agents.agents,
              key,
              from: from,
              name: name,
              runtime: runtime,
            ),
          ),
      keptClosed: (key) => connection.fold.dispatch(SpendClosed(key)),
      server: server,
      resources: resources,
      watched: connection.notices.watched,
      // Each child's own record, beside main's in the same state
      // directory; a failure to keep it is said nowhere, as the original
      // says nothing of it. A main record given from outside, a test's,
      // keeps the children's out of any directory.
      recordingOf: recording != null
          ? null
          : (child) =>
                FileRecording(stateDirectory(), failed: (_) {}, child: child),
      transcriptOf: (key) => connection.fold.stateOf(key)?.transcript,
      runtimes: Runtimes(
        probe: sessionProbe(
          refusedOf: (runtime) => childStart(runtime)?.refused,
          // Read with no MCP servers, and closed at once.
          open: (runtime, token) {
            final start = childStart(runtime) ?? const SessionStart();
            return connection.openChild(
              runtime,
              SessionStart(
                command: start.command,
                env: start.env,
                noMcpServers: true,
              ),
              initial: (model: null, effort: null, mode: null),
              onTraffic: (_) {},
              cancellationToken: token,
            );
          },
        ),
      ),
    );
    connection
      ..server = server
      ..window = host
      ..closeWith(host.shutDown);
  }
  connection.start();
  if (failure != null) connection.conversation.recordingFailed(failure);
  return connection;
}

/// What the window keeps of session [key] as it closes, or of the session
/// [from] a clear lets go: a team's agent kept under its run, its lead as
/// `lead` under the team's row, a member by its name, each with its run's
/// lead, as the original's keepChild places it.
SpendClosing spendClosingOf<C>(
  WindowAgents<C> agents,
  int key, {
  int? from,
  required String name,
  String? runtime,
}) {
  final child = agentOf(agents, from ?? key)?.child;
  final team = child?.team;
  final lead = child != null && isLead(child.info);
  return SpendClosing(
    key,
    from: from,
    name: lead ? 'lead' : name,
    runtime: runtime,
    team: team,
    lead: lead ? child.id : child?.lead,
    member: team != null,
  );
}

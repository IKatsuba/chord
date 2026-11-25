/// Whose monitors a call to chord's MCP server reaches, and the limit that
/// counts main and its long-lived children together. From the original's
/// `session/window_monitors.ts`.
library;

import '../server/tools.dart'
    show Caller, MonitorAnswer, Refused, StopMonitorAnswer;
import 'monitors.dart';
import 'window_agents.dart';

/// What keeps a session's monitors: its `Conversation`, or a test's.
abstract interface class MonitorsKeeper {
  /// Its monitors still running, in start order.
  List<RunningMonitor> get monitors;

  /// How many it has running or still starting, which the limit counts.
  int get monitorsHeld;

  /// Starts one in [cwd], as `monitor` asks.
  Future<MonitorAnswer> startMonitor(MonitorArgs args, String cwd);

  /// Stops its own [id], as `stop_monitor` asks.
  StopMonitorAnswer stopMonitor(String id);
}

const _closed = Refused('This session has closed');

/// The conversation whose monitors are the caller's own: main's, a fork's
/// or a long-lived child's; none for a task, or a caller whose session has
/// closed.
C? monitorsOwner<C>(WindowAgents<C> agents, Caller caller) {
  if (caller.task != null) return null;
  // A fork calls under its own key, beside main.
  for (final child in agents.children) {
    if (child.key == caller.key && child.forkedFrom != null) {
      return child.conversation;
    }
  }
  final main = agents.main;
  if (main == null || main.key != caller.key) return null;
  final agent = caller.agent;
  if (agent == null) return main.conversation;
  for (final child in agents.children) {
    if (child.id == agent) return child.conversation;
  }
  return null;
}

/// `monitor`: started in the caller's own conversation, in [cwd]; refused
/// past the limit, which main and its children share, those still starting
/// counted, as the original's start, which is at once, would count them.
Future<MonitorAnswer> startMonitorIn<C extends MonitorsKeeper>(
  WindowAgents<C> agents,
  Caller caller,
  MonitorArgs args,
  String cwd,
) async {
  final owner = monitorsOwner(agents, caller);
  final main = agents.main;
  if (owner == null || main == null) return _closed;
  final running = [
    main.conversation,
    for (final child in agents.children) child.conversation,
  ].fold(0, (sum, conversation) => sum + conversation.monitorsHeld);
  final refused = monitorRefusal(args, running);
  return refused == null ? owner.startMonitor(args, cwd) : Refused(refused);
}

/// `stop_monitor`: only the caller's own monitor [id].
StopMonitorAnswer stopMonitorIn<C extends MonitorsKeeper>(
  WindowAgents<C> agents,
  Caller caller,
  String id,
) => monitorsOwner(agents, caller)?.stopMonitor(id) ?? _closed;

/// `list_monitors`: the caller's own monitors still running.
List<RunningMonitor> monitorsIn<C extends MonitorsKeeper>(
  WindowAgents<C> agents,
  Caller caller,
) => monitorsOwner(agents, caller)?.monitors ?? const [];

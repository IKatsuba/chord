/// Subagents: sessions an agent opens of its own for part of a turn, each
/// announced to its parent by a `subagent_update` and then sending its own
/// updates and requests under its own id. Here, which sessions belong to
/// the one chord opened. From the original's `session/subagents.ts`.
library;

import '../acp/schema.dart' as acp;

/// An update as the session heard it: its own, or [subagentId]'s.
typedef Heard = ({acp.SessionUpdate update, String? subagentId});

/// The session chord opened, and every subagent under it so far.
final class SessionTree {
  const SessionTree(this.root, [this.subagents = const {}]);

  /// The session chord opened.
  final String root;

  /// Its subagents at any depth, by session id.
  final Set<String> subagents;
}

/// Where [notification] belongs in [tree]: to the session itself, to one of
/// its subagents (`subagentId`), or to neither (`heard` false), as a session
/// chord never opened. A `subagent_update` from the session or one of its
/// subagents adds the subagent it names, which ACP sends before any of that
/// subagent's own traffic.
({bool heard, String? subagentId, SessionTree tree}) routed(
  SessionTree tree,
  acp.SessionNotification notification,
) {
  final sessionId = notification.sessionId;
  final own = sessionId == tree.root;
  if (!own && !tree.subagents.contains(sessionId)) {
    return (heard: false, subagentId: null, tree: tree);
  }
  final update = notification.update.toJson();
  final named = update['sessionId'];
  final grown =
      update['sessionUpdate'] == 'subagent_update' &&
          named is String &&
          named != tree.root &&
          !tree.subagents.contains(named)
      ? SessionTree(tree.root, Set.unmodifiable({...tree.subagents, named}))
      : tree;
  return (heard: true, subagentId: own ? null : sessionId, tree: grown);
}

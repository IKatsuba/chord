/// The session's one ingress for the agent's updates, as the closures in
/// the original's `openSession`: updates held until the session is open,
/// routed to it by id, folded into the agent's state, and held again until
/// the first subscriber. Pure: no agent, no timer.
library;

import '../acp/schema.dart' as acp;
import '../acp/traffic.dart';
import 'agent_state.dart';
import 'subagents.dart';

/// Where the agent's `session/update`s go once heard.
final class SessionInbox {
  final _early = <acp.SessionNotification>[];
  final _held = <Heard>[];
  // Both kinds of listener, heard in the order they subscribed.
  final _listeners =
      <void Function(acp.SessionUpdate update, String? subagentId)>[];
  String? _id;

  /// The session and the subagents it announced, whose updates are its.
  var _tree = const SessionTree('');

  /// The subagents the session announced so far, at any depth.
  Set<String> get subagents => _tree.subagents;
  String? _reopenMethod, _requestedId;
  Object? _requestId;
  var _reopening = false, _replied = false, _awaitingLive = false;
  var _drainingLive = false;
  final _postReply = <acp.SessionNotification>[];
  final _retainedLive = <acp.SessionNotification>[];
  var _state = AgentState.empty;
  var _closed = false;

  /// Closing: no held update is replayed; live ones still route.
  var _draining = false;

  /// The agent's facts about the session, as the answer and the updates
  /// since left them.
  AgentState get state => _state;

  /// Applies an acknowledged setter's state while the inbox is open.
  void replaceState(AgentState state) {
    if (!_closed) _state = state;
  }

  /// Takes [traffic] in: only the agent's `session/update` notifications,
  /// read by their shape, so an update of a kind chord does not know still
  /// comes through.
  void hear(Traffic traffic) {
    if (_closed) return;
    if (traffic is ChordTraffic && _reopening && _requestId == null) {
      final message = traffic.message;
      final params = message['params'];
      if (message['method'] == _reopenMethod &&
          params is Map &&
          params['sessionId'] == _requestedId &&
          message['id'] != null) {
        _requestId = message['id'];
      }
    }
    if (traffic is! AgentTraffic) return;
    final message = traffic.message;
    if (_reopening &&
        _requestId != null &&
        !message.containsKey('method') &&
        message['id'] == _requestId) {
      // This tap runs before reply routing and before the decoder's next line.
      _replied = true;
    }

    final notification = updateIn(traffic.message);

    if (notification == null) {
      return;
    }

    if (_reopening) {
      (_replied ? _postReply : _early).add(notification);
      return;
    }
    if (_awaitingLive) {
      _retainedLive.add(notification);
      return;
    }
    if (_id == null) {
      _early.add(notification);
      return;
    }

    _route(notification);
  }

  /// Arms before the outbound request, matching both method and requested id.
  void beginReopen(String method, String sessionId) {
    if (_closed) return;
    if (method != 'session/load' && method != 'session/resume') {
      throw ArgumentError.value(method, 'method');
    }
    _reopenMethod = method;
    _requestedId = sessionId;
    _requestId = null;
    _reopening = true;
    _replied = false;
  }

  /// Seeds current answer facts; replay never folds into live settings.
  /// Retained live updates wait for the first post-publication subscription.
  /// What a load replayed is routed through the session's tree, each update
  /// with the subagent it came from, so the subagents it announced are
  /// known to what comes live after it.
  List<Heard> completeReopen(
    acp.SessionResponse answer, {
    required bool rawHasPast,
  }) {
    if (_closed) return const [];
    if (!_reopening || !_replied) throw StateError('No matching reopen reply.');
    _id = _requestedId;
    _tree = SessionTree(_id!);
    _state = stateOf(answer);
    final load = _reopenMethod == 'session/load';
    final history = <Heard>[];
    if (load && !rawHasPast) {
      for (final notification in _early) {
        final where = routed(_tree, notification);
        _tree = where.tree;
        if (where.heard) {
          history.add((
            update: notification.update,
            subagentId: where.subagentId,
          ));
        }
      }
    }
    _retainedLive.addAll([if (!load) ..._early, ..._postReply]);
    _early.clear();
    _postReply.clear();
    _reopening = false;
    _awaitingLive = true;
    return List.unmodifiable(history);
  }

  /// The session is [sessionId], opened with [answer]: its state is seeded
  /// first, then what came early is routed in arrival order, so an early
  /// mode or option update overrides the answer.
  void open(String sessionId, acp.NewSessionResponse answer) {
    if (_closed) {
      return;
    }

    _id = sessionId;
    _tree = SessionTree(sessionId);
    _state = stateOf(answer);

    final early = [..._early];

    _early.clear();

    // A listener may close the inbox while it hears one of these.
    for (final each in early) {
      if (_closed) return;
      _route(each);
    }
  }

  /// Calls [listener] with each update routed to the session; the first
  /// listener hears what was held for it first, synchronously. Returns the
  /// unsubscribe.
  void Function() subscribe(void Function(acp.SessionUpdate update) listener) {
    if (_closed) return () {};
    void own(acp.SessionUpdate update, String? subagentId) {
      if (subagentId == null) listener(update);
    }

    return subscribeAll(own);
  }

  /// Calls [listener] with each update routed to the session or to one of
  /// its subagents, with the subagent's id: they are the session's work
  /// too, but not what the session's own agent said. The first listener
  /// hears what was held for it first, synchronously. Returns the
  /// unsubscribe.
  void Function() subscribeAll(
    void Function(acp.SessionUpdate update, String? subagentId) listener,
  ) {
    if (_closed) return () {};
    _listeners.add(listener);
    _drainLive();
    final held = [..._held];
    _held.clear();
    for (final (:update, :subagentId) in held) {
      if (_closed || _draining) break;
      listener(update, subagentId);
    }
    return () => _listeners.remove(listener);
  }

  // A reopened session's live updates, retained until the first listener.
  void _drainLive() {
    if (!_awaitingLive || _drainingLive) return;
    _drainingLive = true;
    try {
      var index = 0;
      while (!_closed && !_draining && index < _retainedLive.length) {
        _route(_retainedLive[index++]);
      }
    } finally {
      _retainedLive.clear();
      _awaitingLive = false;
      _drainingLive = false;
    }
  }

  /// The session closes: what is held, early or for a listener, is dropped
  /// and no held update is replayed any more, but what the agent sends as
  /// its transport drains still reaches the listeners until [close].
  void closing() {
    _draining = true;
    _early.clear();
    _postReply.clear();
    _retainedLive.clear();
    _held.clear();
  }

  /// Drops everything: what is held, early or for a listener, and every
  /// listener.
  void close() {
    _closed = true;
    _early.clear();
    _postReply.clear();
    _retainedLive.clear();
    _reopening = false;
    _awaitingLive = false;
    _held.clear();
    _listeners.clear();
  }

  void _route(acp.SessionNotification notification) {
    if (_closed) {
      return;
    }

    // A subagent's updates are the session's work; an update for any other
    // session is dropped.
    final where = routed(_tree, notification);
    _tree = where.tree;
    if (!where.heard) return;

    final update = notification.update;
    final subagentId = where.subagentId;

    // A subagent's modes, options and commands are not the session's.
    if (subagentId == null) _state = foldUpdate(_state, update);

    if (_listeners.isEmpty) {
      _held.add((update: update, subagentId: subagentId));
      return;
    }

    for (final listener in [..._listeners]) {
      if (_closed) return;
      listener(update, subagentId);
    }
  }
}

/// The `session/update` in a message the agent sent, when it is one: not
/// checked against ACP's schema, so an update of a kind chord does not know
/// still comes through, for the reducer to pass over.
acp.SessionNotification? updateIn(Map<String, Object?> message) {
  if (message.containsKey('id') || message['method'] != 'session/update') {
    return null;
  }

  final params = message['params'];

  if (params is! Map<String, Object?>) {
    return null;
  }

  final update = params['update'];

  return params['sessionId'] is String &&
          update is Map<String, Object?> &&
          update['sessionUpdate'] is String
      ? acp.SessionNotification.fromJson(params)
      : null;
}

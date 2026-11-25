/// An agent's plan put to the person, from the original's
/// `session/plan_asks.ts`: the request `acp/plans.dart` reads, held until
/// the person answers, and their answer written back in the agent's own
/// words; `cancelled` for every answer that is not the person's, never a
/// yes.
library;

import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:uuid/uuid.dart';

import '../acp/plans.dart';
import '../acp/rpc.dart' show OnCancel;
import 'transcript/types.dart';

/// The person's answer in [agent]'s words; a note goes only with keep.
Map<String, Object?> planResponse(PlanAgent agent, PlanAnswer answer) =>
    switch (answer) {
      PlanAccepted() => {
        'outcome': agent == PlanAgent.cursor ? 'accepted' : 'approved',
      },
      PlanKept(:final note) =>
        agent == PlanAgent.cursor
            ? {'outcome': 'rejected', 'reason': ?note}
            : {'outcome': 'revise', 'feedback': ?note},
      // Only grok takes it; cursor's box never offers it.
      PlanLeft() =>
        agent == PlanAgent.grok ? {'outcome': 'abandoned'} : planCancelled,
      PlanCancelled() || PlanWithdrawn() => planCancelled,
    };

/// A plan the agent is waiting on, held until the person answers, as a
/// permission is.
final class PendingPlan {
  PendingPlan._(this.wait, this.sessionId, this.withdrawn, this._answer);

  final PlanWait wait;

  /// The session that asks, when its request names one.
  final String? sessionId;

  /// Cancelled once the answer stops mattering; the agent has heard
  /// `cancelled`.
  final CancellationToken withdrawn;

  final void Function(Map<String, Object?> response) _answer;

  /// The person's answer; cancelled or withdrawn answer `cancelled`.
  void answer(PlanAnswer answer) => _answer(planResponse(wait.agent, answer));
}

/// Ids unique across processes and records, as a resumed past keeps its
/// plans' ids.
const _uuid = Uuid();

/// Bridges the transport's plan handler to a screen that answers later.
final class PlanBridge {
  final _listeners = <void Function(PendingPlan request)>[];
  final _closed = CancellationToken();

  /// The handler the transport calls with a request it read, or none for
  /// one that did not read, which is answered `cancelled` at once.
  Future<Map<String, Object?>> handler(
    PlanRequest? request,
    CancellationToken token,
  ) {
    final withdrawn = MergedCancellationToken([token, _closed]);
    final answered = Completer<Map<String, Object?>>();
    late final OnCancel listener;

    void answer(Map<String, Object?> response) {
      if (answered.isCompleted) return;
      listener.forget();
      answered.complete(response);
    }

    listener = OnCancel((_) => answer(planCancelled));
    // Nobody to ask, or nothing to show: never taken as a yes.
    if (request == null || withdrawn.isCancelled || _listeners.isEmpty) {
      answer(planCancelled);
      return answered.future;
    }
    final pending = PendingPlan._(
      PlanWait(
        _uuid.v4(),
        request.agent,
        toolCallId: request.toolCallId,
        plan: request.plan,
        name: request.name,
        overview: request.overview,
        todos: request.todos,
        phases: request.phases,
      ),
      request.sessionId,
      withdrawn,
      answer,
    );
    listener.listen(withdrawn);
    for (final each in [..._listeners]) {
      each(pending);
    }
    return answered.future;
  }

  /// Calls [listener] for each new request; returns the unsubscribe.
  void Function() subscribe(void Function(PendingPlan request) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Cancels every waiting request; the session is going away.
  void close() {
    _closed.cancel();
    _listeners.clear();
  }
}

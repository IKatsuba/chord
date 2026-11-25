/// The agent's forms and links, parked until the person answers: the
/// transport asks through a handler that must return the answer, and the
/// window answers whenever a key is pressed. From the original's
/// `session/elicitations.ts`.
library;

import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:uuid/uuid.dart';

import '../acp/rpc.dart' show OnCancel;
import 'questions.dart' show questionsOf;
import 'transcript/types.dart';

/// The answers chord gives a form or link: ACP's three.
sealed class ElicitationReply {
  const ElicitationReply();

  /// As it goes on the wire.
  Map<String, Object?> toJson();
}

/// The form accepted with [content], or the link opened.
final class AcceptReply extends ElicitationReply {
  const AcceptReply([this.content]);

  /// What an accepted form sends, by field.
  final Map<String, Object?>? content;

  @override
  Map<String, Object?> toJson() => {'action': 'accept', 'content': ?content};
}

/// Declined.
final class DeclineReply extends ElicitationReply {
  const DeclineReply();

  @override
  Map<String, Object?> toJson() => {'action': 'decline'};
}

/// Cancelled, as Esc does.
final class CancelReply extends ElicitationReply {
  const CancelReply();

  @override
  Map<String, Object?> toJson() => {'action': 'cancel'};
}

/// What the transcript keeps of [reply].
ElicitationAnswer answerOf(ElicitationReply reply) => switch (reply) {
  AcceptReply(:final content) => ElicitationAccepted(content),
  DeclineReply() => const ElicitationDeclined(),
  CancelReply() => const ElicitationCancelled(),
};

/// A form or link the agent is waiting on, held until the person answers.
final class PendingElicitation {
  PendingElicitation._(
    this.id,
    this.wait,
    this.raw,
    this.withdrawn,
    this._answer,
  );

  /// The bridge's id for the request.
  final String id;

  /// What the window draws to ask it.
  final ElicitationWait wait;

  /// The agent's request as it came.
  final Map<String, Object?> raw;

  /// Cancelled when the request stops mattering, the turn cancelled or
  /// ended or the session closed, so the window takes it off the screen;
  /// the transport has then answered `cancel` itself.
  final CancellationToken withdrawn;

  final void Function(ElicitationReply reply) _answer;

  /// The session that asks: the agent's own, or one of its subagents'.
  String? get sessionId => switch (raw['sessionId']) {
    final String id => id,
    _ => null,
  };

  /// Answers it: accept with the values, decline, or cancel.
  void answer(ElicitationReply reply) => _answer(reply);
}

/// What the transcript keeps of request [raw]: everything the form draws.
/// A mode chord does not draw never gets here, as the transport answers it
/// first.
ElicitationWait waitOf(String id, Map<String, Object?> raw) {
  final message = switch (raw['message']) {
    final String text => text,
    _ => '',
  };
  final toolCallId = switch (raw['toolCallId']) {
    final String id => id,
    _ => null,
  };
  if (raw case {'mode': 'url', 'url': final String url}) {
    return LinkWait(id, message, url, toolCallId: toolCallId);
  }
  return FormWait(
    id,
    message,
    schema: switch (raw['requestedSchema']) {
      final Map<String, Object?> schema => schema,
      _ => const {},
    },
    questions: questionsOf(raw),
    toolCallId: toolCallId,
  );
}

/// Bridges the transport's elicitation handler to a window that answers
/// later.
final class ElicitationBridge {
  final _listeners = <void Function(PendingElicitation request)>[];
  final _closed = CancellationToken();

  /// The handler the transport calls, as the connection's `onElicitation`.
  /// Its [token] is cancelled once the answer stops mattering. With nobody
  /// listening, the agent hears `cancel` rather than wait.
  Future<Map<String, Object?>> handler(
    Map<String, Object?> params,
    CancellationToken token,
  ) {
    final withdrawn = MergedCancellationToken([token, _closed]);
    final answered = Completer<Map<String, Object?>>();
    // Unique across sessions, as a task's asks are answered in its
    // parent by the id they came with.
    final id = const Uuid().v4();
    late final OnCancel listener;

    void answer(ElicitationReply reply) {
      if (answered.isCompleted) return;
      listener.forget();
      answered.complete(reply.toJson());
    }

    final pending = PendingElicitation._(
      id,
      waitOf(id, params),
      params,
      withdrawn,
      answer,
    );
    listener = OnCancel((_) => answer(const CancelReply()));
    if (withdrawn.isCancelled || _listeners.isEmpty) {
      answer(const CancelReply());
      return answered.future;
    }
    listener.listen(withdrawn);
    for (final each in [..._listeners]) {
      each(pending);
    }
    return answered.future;
  }

  /// Calls [listener] for each new request; returns the unsubscribe.
  void Function() subscribe(
    void Function(PendingElicitation request) listener,
  ) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Cancels every waiting request; the session is going away.
  void close() {
    _closed.cancel();
    _listeners.clear();
  }
}

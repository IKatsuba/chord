/// The agent's permission requests, parked until the person answers: the
/// transport asks through a handler that must return the answer, and the
/// window answers whenever a key is pressed.
library;

import 'dart:async';
import 'dart:collection';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:uuid/uuid.dart';

import '../acp/rpc.dart' show OnCancel;
import '../acp/schema.dart' as acp;
import 'permission_review.dart';
import 'transcript/tools.dart' show checkContent, checkLocations;
import 'transcript/types.dart';

/// A permission request the agent is waiting on, held until the person
/// answers.
final class PendingPermission {
  PendingPermission._(this.id, this.raw, this.withdrawn, this._answer);

  /// The bridge's id for the request, not the tool call's.
  final String id;

  /// The agent's request as it came.
  final acp.RequestPermissionRequest raw;

  /// Cancelled when the request stops mattering, the turn cancelled or the
  /// session closed, so the window takes it off the screen; the transport
  /// has then answered `cancelled` itself.
  final CancellationToken withdrawn;

  final void Function(acp.RequestPermissionResponse response) _answer;

  /// The session that asks.
  String get sessionId => raw.sessionId;

  /// The tool call the request is about.
  acp.ToolCallUpdate get toolCall => raw.toolCall;

  /// The agent's own options, in its order.
  List<acp.PermissionOption> get options => raw.options;

  /// Answers with one of [options], by its `optionId`; throws
  /// [ArgumentError] for an option the request did not offer.
  void resolve(String optionId) {
    if (!options.any((option) => option.optionId == optionId)) {
      throw ArgumentError.value(optionId, 'optionId', 'No such option');
    }

    _answer(acp.RequestPermissionResponse.selected(optionId));
  }

  /// Declines, as Esc does: the agent hears its own reject option, and the
  /// turn goes on.
  void reject() => _answer(rejection(options));
}

/// chord's own question [raw], under [id], as a request the window answers
/// as it does an agent's: [answered] hears the option picked, Esc picking
/// the reject option, and null once [withdrawn].
PendingPermission chordsQuestion(
  String id,
  acp.RequestPermissionRequest raw, {
  required CancellationToken withdrawn,
  required void Function(String? optionId) answered,
}) => PendingPermission._(
  id,
  raw,
  withdrawn,
  (response) => answered(response.optionId),
);

/// What Esc answers: the agent's reject-once option, else its reject-always
/// one, else `cancelled`, ACP's only answer that picks no option.
acp.RequestPermissionResponse rejection(List<acp.PermissionOption> options) {
  final option =
      options.where((each) => each.kind == 'reject_once').firstOrNull ??
      options.where((each) => each.kind == 'reject_always').firstOrNull;

  return option == null
      ? acp.RequestPermissionResponse.cancelled()
      : acp.RequestPermissionResponse.selected(option.optionId);
}

/// What the transcript keeps of [request]: everything but the answering.
/// A field the agent sent malformed is left out rather than the request,
/// which the person must still be able to answer.
PermissionWait waitFor(PendingPermission request) {
  final call = request.raw.toJson()['toolCall'] as Map<String, Object?>;
  final title = call['title'];
  final kind = call['kind'];
  final locations = _read(() => request.toolCall.locations, checkLocations);
  final content = _read(() => request.toolCall.content, checkContent);
  final presentation = permissionPresentation(request.raw.meta);

  return PermissionWait(
    request.id,
    toolCallId: request.toolCall.toolCallId,
    title: title is String && title.isNotEmpty ? title : null,
    kind: kind is String && kind.isNotEmpty ? kind : null,
    locations: locations,
    content: content == null || content.isEmpty ? null : content,
    // An MCP tool's request is its name alone, with the arguments only
    // here; a request with content says what it does without them.
    rawInput: (content ?? const []).isEmpty ? call['rawInput'] : null,
    options: UnmodifiableListView(request.options),
    review: presentation.review,
    deadlineAt: presentation.deadlineAt,
  );
}

List<T>? _read<T>(List<T>? Function() list, void Function(List<T>?) check) {
  try {
    final read = list();
    check(read);
    return read == null ? null : UnmodifiableListView(read);
  } on Object {
    return null;
  }
}

/// Bridges the transport's permission handler to a window that answers
/// later.
final class PermissionBridge {
  final _pending = <String, PendingPermission>{};
  final _listeners = <void Function(PendingPermission request)>[];
  final _closed = CancellationToken();

  /// The handler the transport calls; pass it as `openAgent`'s
  /// `onPermission`. Its [token] is cancelled once the answer stops
  /// mattering, and the transport has then answered `cancelled` itself.
  Future<acp.RequestPermissionResponse> handler(
    acp.RequestPermissionRequest request,
    CancellationToken token,
  ) {
    final withdrawn = MergedCancellationToken([token, _closed]);
    final answered = Completer<acp.RequestPermissionResponse>();
    // Unique across sessions, as a task's asks are answered in its
    // parent by the id they came with.
    final id = const Uuid().v4();
    late final OnCancel listener;

    void answer(acp.RequestPermissionResponse response) {
      if (answered.isCompleted) {
        return;
      }

      _pending.remove(id);
      listener.forget();
      answered.complete(response);
    }

    final pending = PendingPermission._(id, request, withdrawn, answer);

    listener = OnCancel(
      (_) => answer(acp.RequestPermissionResponse.cancelled()),
    );

    if (withdrawn.isCancelled) {
      answer(acp.RequestPermissionResponse.cancelled());
      return answered.future;
    }

    listener.listen(withdrawn);
    _pending[id] = pending;

    for (final each in [..._listeners]) {
      each(pending);
    }

    return answered.future;
  }

  /// Calls [listener] for each new request; returns the unsubscribe.
  void Function() subscribe(void Function(PendingPermission request) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// The requests still waiting for an answer, oldest first.
  List<PendingPermission> pending() => [..._pending.values];

  /// Withdraws every waiting request; the session is going away.
  void close() {
    _closed.cancel();
    _listeners.clear();
  }
}

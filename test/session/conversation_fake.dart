// A scripted Session for the conversation's tests: each turn answers when
// the test says, updates and requests come when it sends them, and the
// agent exits on its word. The original's tests/session/conversation_fake.ts.
import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/servers.dart';
import 'package:chord/session/auth_status.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/elicitations.dart';
import 'package:chord/session/permissions.dart';
import 'package:chord/session/plan_asks.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart';

/// One prompt the scripted session took, answered when the test says.
final class ScriptedTurn {
  ScriptedTurn(
    this.text, {
    this.mentions = const [],
    this.parts = PromptParts.none,
  });
  final List<String> mentions;

  /// What it carried beside its text.
  final PromptParts parts;

  /// What was sent.
  final String text;

  final _result = Completer<TurnResult>();

  /// Answers the turn with [result].
  void answer([TurnResult result = const TurnAnswered('end_turn')]) {
    if (!_result.isCompleted) _result.complete(result);
  }
}

/// A dispatched steer with independently controlled wire admission and outcome.
final class ScriptedSteer {
  ScriptedSteer(
    this.text,
    this.mentions,
    this.turnId,
    this.onSubmitted, [
    this.parts = PromptParts.none,
  ]);

  /// What it carried beside its text.
  final PromptParts parts;
  final String text, turnId;
  final List<String> mentions;
  final void Function(SubmittedContent)? onSubmitted;
  final _answer = Completer<SteerOutcome>();
  bool admitted = false;

  /// Admits exactly once, retaining any literal test link facts.
  void admit({List<Map<String, Object?>> links = const []}) {
    if (admitted) return;
    admitted = true;
    onSubmitted?.call(
      SubmittedContent.fromWire(turnId, [
        {'type': 'text', 'text': text},
        for (final image in parts.images)
          {'type': 'image', 'mimeType': image.mimeType, 'data': image.data},
        ...parts.resources,
        ...links,
        ...parts.links,
      ]),
    );
  }

  /// Gives the extension's answer without manufacturing a prompt turn.
  void answer([SteerOutcome outcome = SteerOutcome.injected]) {
    if (!_answer.isCompleted) _answer.complete(outcome);
  }

  /// Refuses the transport request independently of a normal outcome.
  void fail(Object error) {
    if (!_answer.isCompleted) _answer.completeError(error);
  }
}

/// A Session whose agent does what the test says.
final class ScriptedSession implements Session {
  @override
  String agent = 'scripted';

  @override
  final String cwd = '/w';

  /// The agent's id for it; tests with several sessions set each apart.
  @override
  String id = 's1';

  @override
  AgentState state = AgentState.empty;
  @override
  String? record;
  @override
  Resume? resumed;
  PreparedHistory prepared = PreparedHistory.empty;
  @override
  PreparedHistory takeHistory() {
    final result = prepared;
    prepared = PreparedHistory.empty;
    return result;
  }

  @override
  final permissions = PermissionBridge();
  @override
  final plans = PlanBridge();
  @override
  final elicitations = ElicitationBridge();

  final _exit = Completer<void>();
  final _listeners = <void Function(acp.SessionUpdate)>[];

  /// The prompts sent, oldest first.
  final turns = <ScriptedTurn>[];

  /// How many times `session/cancel` was sent.
  var cancels = 0;

  /// A synchronous transport observer reached as cancellation is submitted.
  void Function()? onCancel;

  /// Steering capability and call-cut behavior, independent of each other.
  bool steering = false, cutsSteeringCalls = false;

  /// Whether the agent runs cycles of its own, as Claude's adapter.
  bool ownCycles = false;

  /// Admission can lag call entry, as asynchronous mention resolution does.
  bool admitSteers = true, admitPrompts = true;
  final steered = <ScriptedSteer>[];

  /// How many times it was closed.
  var closes = 0;

  /// The agent's last words once it is gone.
  String? words;

  /// Whether the agent has exited; a prompt then fails at once.
  bool get hasExited => _exit.isCompleted;

  @override
  Future<void> get exited => _exit.future;

  @override
  String? gone() => words;

  @override
  void Function() subscribe(void Function(acp.SessionUpdate update) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  final _allListeners =
      <void Function(acp.SessionUpdate update, String? subagentId)>[];

  @override
  void Function() subscribeAll(
    void Function(acp.SessionUpdate update, String? subagentId) listener,
  ) {
    _allListeners.add(listener);
    return () => _allListeners.remove(listener);
  }

  /// What its `initialize` advertises of prompts.
  bool images = false, embeddedContext = false;

  /// What it says of its account; [hearAccount] changes it.
  @override
  AccountState account = noAccount;
  final _accountListeners = <void Function(AccountState)>{};

  @override
  void Function() subscribeAccount(void Function(AccountState) listener) {
    _accountListeners.add(listener);
    return () => _accountListeners.remove(listener);
  }

  /// The account as the agent now says it.
  void hearAccount(AccountState next) {
    account = next;
    for (final listener in [..._accountListeners]) {
      listener(next);
    }
  }

  /// Whether its `initialize` advertises titles, and how it answers one.
  bool titles = false;
  Future<String> Function(String title)? onTitle;
  final titled = <String>[];

  @override
  bool takesTitles() => titles;

  /// Whether it forks a session.
  bool forking = false;

  @override
  bool forks() => forking;

  @override
  Future<String> setTitle(String title) async {
    titled.add(title);
    return await onTitle?.call(title) ?? title;
  }

  @override
  bool takesImages() => images;

  @override
  bool takesEmbeddedContext() => embeddedContext;

  @override
  Turn prompt(
    String text, {
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
    String? turnId,
    void Function(SubmittedContent content)? onSubmitted,
  }) {
    final turn = ScriptedTurn(text, mentions: mentions, parts: parts);
    turns.add(turn);
    if (!hasExited && admitPrompts) {
      onSubmitted?.call(
        SubmittedContent.fromWire(turnId ?? '${turns.length}', [
          {'type': 'text', 'text': text},
          for (final image in parts.images)
            {'type': 'image', 'mimeType': image.mimeType, 'data': image.data},
          ...parts.resources,
          ...parts.links,
        ]),
      );
    }
    if (hasExited) {
      turn.answer(TurnFailed(_exited));
    }
    return Turn('${turns.length}', turn._result.future, cancel);
  }

  @override
  bool steers() => steering;
  @override
  bool cutsCallsOnSteer() => cutsSteeringCalls;
  @override
  bool startsOwnCycles() => ownCycles;
  @override
  Future<SteerOutcome> steer(
    String text, {
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
    String? turnId,
    void Function(SubmittedContent content)? onSubmitted,
  }) {
    if (!steering) throw const AgentCapabilityError('_session/steering');
    final request = ScriptedSteer(
      text,
      List.unmodifiable(mentions),
      turnId ?? 'steer-${steered.length + 1}',
      onSubmitted,
      parts,
    );
    steered.add(request);
    if (admitSteers) request.admit();
    return request._answer.future;
  }

  /// Test-controlled setter acknowledgements and calls.
  Future<void> Function(String kind, String id, String? value)? change;
  final changes = <(String, String, String?)>[];

  Future<void> _change(String kind, String id, [String? value]) async {
    changes.add((kind, id, value));
    await change?.call(kind, id, value);
  }

  @override
  List<HeldBack> heldBack = const [];

  @override
  String? chordServer;

  @override
  Map<String, Object?>? chordServerPassed;

  /// The client entries set, as sent.
  final entries = <Map<String, Object?>>[];

  @override
  Future<void> setConfigEntry(Map<String, Object?> entry) async {
    entries.add(entry);
    await _change('entry', '${entry['configId']}', '${entry['value']}');
  }

  @override
  Future<void> setMode(String id) => _change('mode', id);
  @override
  Future<void> setModel(String id) => _change('model', id);
  @override
  Future<void> setOption(String id, String value) =>
      _change('option', id, value);

  @override
  Future<void> cancel() async {
    cancels++;
    onCancel?.call();
  }

  /// The subagents asked to stop alone, in order.
  final stopped = <String>[];

  /// What a stop sent throws, when it cannot be sent; awaited first.
  Future<void> Function(String id)? stopping;

  @override
  Future<void> stopSubagent(String id) async {
    stopped.add(id);
    await stopping?.call(id);
  }

  /// Called as it closes, as an agent answers what it was still asked.
  void Function()? onClose;

  /// Awaited as it closes, after it counts the close: an agent slow to go,
  /// or one whose close fails.
  Future<void> Function()? closing;

  @override
  Future<void> close() async {
    closes++;
    onClose?.call();
    await closing?.call();
    permissions.close();
    elicitations.close();
  }

  String get _exited =>
      words == null ? 'The agent exited.' : 'The agent exited: $words';

  /// The agent sends [update], for its subagent [subagentId] when given.
  void say(Map<String, Object?> update, {String? subagentId}) {
    final read = acp.SessionUpdate.fromJson(update);
    if (subagentId == null) {
      for (final listener in [..._listeners]) {
        listener(read);
      }
    }
    for (final listener in [..._allListeners]) {
      listener(read, subagentId);
    }
  }

  /// The agent says [text] as a chunk of its reply.
  void chunk(String text) => say({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  });

  /// The agent asks a permission; its answer comes back on the future.
  Future<acp.RequestPermissionResponse> ask({
    String toolCallId = 'write-1',
    CancellationToken? token,
  }) => permissions.handler(
    acp.RequestPermissionRequest.fromJson({
      'sessionId': id,
      'toolCall': {'toolCallId': toolCallId, 'title': 'Write notes.txt'},
      'options': [
        {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
        {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
      ],
    }),
    token ?? CancellationToken(),
  );

  /// The agent exits, leaving [last] on stderr; a running turn fails.
  void exit([String? last]) {
    words = last;
    for (final turn in turns) {
      turn.answer(TurnFailed(_exited));
    }
    if (!_exit.isCompleted) _exit.complete();
  }
}

/// A conversation over a scripted session, its events kept.
final class Scripted {
  Scripted({
    this.fails,
    Starting starting = const Starting(),
    List<String> warnings = const [],
  }) {
    conversation = Conversation(starting: starting, warnings: warnings, ({
      required onTraffic,
      required cancellationToken,
    }) {
      opens++;
      this.onTraffic = onTraffic;
      final error = fails;
      return error == null ? Future.value(session) : Future.error(error);
    });
    conversation.listen(events.add);
  }

  /// How many times the session was opened.
  var opens = 0;

  /// An error the open fails with, if any.
  final Object? fails;

  final session = ScriptedSession();
  late final Conversation conversation;
  late void Function(Traffic traffic) onTraffic;

  /// Every event, in order.
  final events = <ConversationEvent>[];

  /// The events after the first [from].
  List<ConversationEvent> since(int from) => events.sublist(from);
}

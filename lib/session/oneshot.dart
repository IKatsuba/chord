/// One prompt in a session of its own, for `chord -p`: what the turn came
/// to, read after its agent has exited.
library;

import 'dart:async';

import '../acp/connection.dart';
import '../acp/schema.dart' as acp;
import '../notices.dart' show dimcodeAtRisk, dimcodeWords;
import 'config.dart' show optionsFromConfigOptions;
import 'efforts.dart';
import 'modes.dart';
import 'permission_review.dart';
import 'session.dart';
import 'starting.dart';
import 'elicitations.dart';
import 'transcript/types.dart' show FormWait, TurnAnswered, TurnResult;
import 'turn_costs.dart' show Cost, costReading;
import 'usage.dart';

/// How a one-shot turn ended, read after its agent has exited.
class OneshotOutcome {
  const OneshotOutcome({
    required this.sessionId,
    required this.result,
    this.usage,
    this.cost,
    this.costEstimated = false,
  });

  /// The agent's id for the session, which `--resume` takes.
  final String sessionId;
  final TurnResult result;

  /// The turn's tokens, when the agent reported them.
  final TokenUsage? usage;

  /// The session's cost, as the agent's last `usage_update` gave it.
  final Cost? cost;

  /// Whether that cost is chord's estimate from the tokens, not the agent's.
  final bool costEstimated;
}

/// Plays one prompt in a session of its own, and ends the agent once the
/// turn is over. Nobody is there to answer a permission, so every one is
/// refused, or under [allowAll] allowed, except one a safety review sent,
/// which is always refused. Rejects only when the agent cannot be started; a
/// turn that fails comes back as a failed result.
///
/// [mcpServers] go to the agent by the transports it takes; none with
/// [noMcpServers].
///
/// [effort] and [mode] are asked for once the session exists and before the
/// prompt goes, in the window's order; a refusal goes to
/// [onStartingRefused] and the turn runs on the agent's own.
///
/// [onNotice] hears dimcode's one-time notice, its permission option seen
/// at anything but read-only: said once, recorded nowhere.
Future<OneshotOutcome> runOneshot({
  required String agent,
  required Object command,
  Map<String, String> env = const {},
  required String cwd,
  required String prompt,
  required FutureOr<void> Function(acp.SessionUpdate update) onUpdate,
  required FutureOr<void> Function(acp.ToolCallUpdate toolCall) onRefused,
  FutureOr<void> Function(acp.ToolCallUpdate toolCall)? onAllowed,
  FutureOr<void> Function(FormWait form)? onDeclined,
  FutureOr<void> Function(String refusal)? onStartingRefused,
  FutureOr<void> Function(List<String> paragraphs)? onNotice,
  StartingValue? effort,
  StartingValue? mode,
  bool allowAll = false,
  SessionOpener open = openHeadlessAgent,
  String? pinned,
  List<Map<String, Object?>> mcpServers = const [],
  bool noMcpServers = false,
}) async {
  final session = await openSession(
    pinned: pinned,
    mcpServers: mcpServers,
    noMcpServers: noMcpServers,
    agent: agent,
    command: command,
    env: env,
    cwd: cwd,
    open: open,
    initial: (model: null, effort: effort?.id, mode: mode?.id),
  );

  Cost? cost;
  var costEstimated = false;
  // Each update is handed on in turn, so stdout keeps the reply's order.
  var handed = Future<void>.value();
  late final TurnResult result;

  try {
    session.permissions.subscribe((request) async {
      final reviewed = permissionPresentation(request.raw.meta).review != null;
      final allow = allowAll && !reviewed ? allowOption(request.options) : null;
      if (allow == null) {
        await onRefused(request.toolCall);
        request.reject();
      } else {
        await onAllowed?.call(request.toolCall);
        request.resolve(allow.optionId);
      }
    });

    // No one is there to answer: a form is declined, said first; a link,
    // which no one could open, is cancelled.
    session.elicitations.subscribe((request) async {
      final wait = request.wait;
      if (wait is! FormWait) {
        request.answer(const CancelReply());
        return;
      }
      await onDeclined?.call(wait);
      request.answer(const DeclineReply());
    });

    final asks = [
      if (effort != null)
        StartingAsk(
          value: effort,
          what: 'on ${effort.id} effort',
          kind: 'efforts',
          listedOnly: true,
          offered: () async => [
            for (final e
                in effortsFrom(session.state.configOptions)?.available ??
                    const <({String id, String name})>[])
              e.id,
          ],
          current: () => effortsFrom(session.state.configOptions)?.current,
          ask: () => session.setOption(
            effortsFrom(session.state.configOptions)!.option,
            effort.id,
          ),
        ),
      if (mode != null)
        StartingAsk(
          value: mode,
          what: 'in ${mode.id} mode',
          kind: 'modes',
          listedOnly: true,
          offered: () async => [
            for (final m
                in modesFrom(
                      session.state.configOptions,
                      session.state.modes,
                    )?.available ??
                    const <({String id, String name})>[])
              m.id,
          ],
          current: () => modesFrom(
            session.state.configOptions,
            session.state.modes,
          )?.current,
          ask: () => session.setMode(mode.id),
        ),
    ];
    for (final ask in asks) {
      final refused = await askStarting(ask);
      if (refused != null) await onStartingRefused?.call(refused);
    }

    // dimcode's notice, once, as soon as its permission leaves read-only:
    // at the start, or as an update moves it.
    var noticed = false;
    void notice() {
      if (noticed ||
          !dimcodeAtRisk(
            agent,
            optionsFromConfigOptions(session.state.configOptions),
          )) {
        return;
      }
      noticed = true;
      handed = handed.then((_) => onNotice?.call(dimcodeWords.paragraphs));
    }

    notice();
    session.subscribe((update) {
      if (update.kind == 'config_option_update') notice();
      if (costReading(update) case final reading?) {
        cost = (amount: reading.amount, currency: reading.currency);
        costEstimated = reading.estimated;
      }
      handed = handed.then((_) => onUpdate(update));
    });

    result = await session.prompt(prompt).result;
  } finally {
    // What the agent sends after its answer still arrives as it closes.
    await session.close();
  }

  await handed;

  return OneshotOutcome(
    sessionId: session.id,
    result: result,
    usage: result is TurnAnswered ? result.usage : null,
    cost: cost,
    costEstimated: costEstimated,
  );
}

/// The agent's allow-once option, else its allow-always one.
acp.PermissionOption? allowOption(List<acp.PermissionOption> options) =>
    options.where((o) => o.kind == 'allow_once').firstOrNull ??
    options.where((o) => o.kind == 'allow_always').firstOrNull;

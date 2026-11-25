/// The models, efforts and modes each runtime offers, as `list_agents`
/// answers them. ACP gives them only in a session's answer, so for a
/// runtime with no session open one is opened for the purpose, read and
/// closed, within a bound, and its answer kept for the window. From the
/// original's `server/runtimes.ts`.
library;

import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';

import '../acp/rpc.dart' show RpcException;
import '../session/agent_state.dart';
import '../session/efforts.dart';
import '../session/models.dart';
import '../session/modes.dart';
import '../session/session.dart';

/// How long a runtime gets to start and answer `session/new`.
const probeBound = Duration(seconds: 60);

/// A model a runtime offers, with the efforts of the one a session was on.
typedef OfferedModel = ({
  String id,
  String name,
  List<AgentEffort>? efforts,
  String? effort,
});

/// A runtime's models, efforts and modes, which ACP gives together in a
/// session's answer, or why they could not be read.
sealed class RuntimeOffer {
  const RuntimeOffer();
}

/// What a runtime offers.
final class Offer extends RuntimeOffer {
  const Offer({
    required this.models,
    this.current,
    this.modes,
    this.currentMode,
    this.efforts,
    this.currentEffort,
  });

  final List<OfferedModel> models;

  /// The model in use in the session they were read from: a new session's,
  /// for one opened only to read them.
  final String? current;

  /// Its modes; null for a runtime that offers none.
  final List<AgentMode>? modes;

  /// The mode that session started in.
  final String? currentMode;

  /// The efforts of a runtime that names no model to hang them on, and the
  /// one that session started on.
  final List<AgentEffort>? efforts;
  final String? currentEffort;
}

/// Why a runtime's offer could not be read.
final class OfferError extends RuntimeOffer {
  const OfferError(this.error);

  final String error;
}

/// What a session of a runtime said it offers.
typedef Offered = ({
  AgentModels? models,
  AgentModes? modes,

  /// The efforts of the model the session is on.
  AgentEfforts? efforts,
});

/// What [state], a session's answer, offers.
Offered offeredOf(AgentState state) => (
  models: modelsFrom(state.configOptions, state.models),
  modes: modesFrom(state.configOptions, state.modes),
  efforts: effortsFrom(state.configOptions),
);

/// Opens a session of `runtime`, reads what it offers and closes it; the
/// token gives up on one still starting.
typedef Probe =
    Future<Offered> Function(String runtime, CancellationToken token);

/// Said of a read given up on as the window closes.
final class _Closing implements Exception {
  const _Closing();

  @override
  String toString() => 'chord is closing';
}

/// The runtimes' offers read so far in one window, and those being read.
final class Runtimes {
  /// Reads with [probe], each given [bound] to answer.
  Runtimes({required Probe probe, Duration bound = probeBound})
    : _reader = probe,
      _limit = bound;

  final Probe _reader;
  final Duration _limit;

  // Only what was read: a runtime that failed is tried again when asked.
  final _known = <String, Offer>{};
  final _reading = <String, Future<RuntimeOffer>>{};
  final _stop = CancellationToken();

  /// Keeps what an open session of [runtime] said it offers, once it has
  /// said anything: one still starting leaves the runtime to be read.
  void heard(String runtime, Offered offered) {
    final offer = _offerOf(offered);
    if (offer != null) _known[runtime] = offer;
  }

  /// [runtime]'s offer as last read, or, with [probe], read now if it was
  /// never read; one read at a time for each runtime.
  Future<RuntimeOffer?> read(String runtime, {required bool probe}) {
    final known = _known[runtime];
    if (known != null || !probe) return Future.value(known);
    final under = _reading[runtime];
    if (under != null) return under;
    final reading = _read(runtime);
    _reading[runtime] = reading;
    // Let go once settled, never before it was kept: a probe that throws
    // at once settles the read before this line is reached.
    reading.whenComplete(() {
      if (identical(_reading[runtime], reading)) _reading.remove(runtime);
    });
    return reading;
  }

  /// Gives up on every read still under way, which close their sessions.
  void close() => _stop.cancel(const _Closing());

  Future<RuntimeOffer> _read(String runtime) async {
    final timeout = CancellationToken();
    final timer = Timer(_limit, timeout.cancel);
    final token = MergedCancellationToken([_stop, timeout]);
    try {
      final read =
          _offerOf(await _reader(runtime, token)) ??
          const OfferError('it offers no models or modes');
      if (read is Offer) _known[runtime] = read;
      return read;
    } on Object catch (error) {
      return OfferError(
        timeout.isCancelled
            ? 'it did not open a session within '
                  '${_seconds(_limit)} s'
            : _messageOf(error),
      );
    } finally {
      timer.cancel();
    }
  }
}

/// Seconds as the original's `bound / 1000` prints them: `60`, `0.02`.
String _seconds(Duration bound) {
  final ms = bound.inMilliseconds;
  return ms % 1000 == 0 ? '${ms ~/ 1000}' : '${ms / 1000}';
}

String _messageOf(Object error) => switch (error) {
  RpcException(:final message) => message,
  StateError(:final message) => message,
  FormatException(:final message) => message,
  _ => '$error',
};

Offer? _offerOf(Offered offered) {
  final (:models, :modes, :efforts) = offered;
  if (models == null && modes == null && efforts == null) return null;
  final current = models?.current;
  // On the model they were read for, as each model has its own; beside the
  // models only for an agent that names none.
  final onModel =
      efforts != null &&
      (models?.available.any((model) => model.id == current) ?? false);
  return Offer(
    models: [
      for (final model in models?.available ?? const <AgentModel>[])
        onModel && model.id == current
            ? (
                id: model.id,
                name: model.name,
                efforts: efforts.available,
                effort: efforts.current,
              )
            : (id: model.id, name: model.name, efforts: null, effort: null),
    ],
    current: current,
    modes: modes?.available,
    currentMode: modes?.current,
    efforts: efforts == null || onModel ? null : efforts.available,
    currentEffort: efforts == null || onModel ? null : efforts.current,
  );
}

/// Reads what a runtime offers from a session of its own, opened by [open]
/// with no MCP servers and closed as soon as it has answered. A runtime
/// [refusedOf] names a refusal for is not started even to be read: chord's
/// own command would run in its place (CHD-466).
Probe sessionProbe({
  required String? Function(String runtime) refusedOf,
  required Future<Session> Function(String runtime, CancellationToken token)
  open,
}) => (runtime, token) async {
  final refused = refusedOf(runtime);
  if (refused != null) throw StateError(refused);
  final session = await open(runtime, token);
  try {
    return offeredOf(session.state);
  } finally {
    await session.close();
  }
};

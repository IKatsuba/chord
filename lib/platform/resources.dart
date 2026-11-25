/// The providers' limits as a window reads them: claude and codex by
/// default, in parallel, each bounded, from the official readers, the
/// fixtures, or collectors a test gives. An explicit source choice keeps
/// fake windows away from installed provider authentication. From the
/// original's `platform/resources.ts`.
library;

import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';

import '../session/budgets.dart';
import '../session/resource_access.dart';
import '../session/codex_resources.dart';
import 'resource_executable.dart';
import 'resource_fixture.dart';
import 'resource_worker.dart';
import 'resource_process.dart';

export 'resource_process.dart' show ResourceReadError;

/// How long one provider may take before it is reported as not read.
const readTimeout = Duration(seconds: 10);

/// The providers chord has a limits reader for.
const resourceProviders = ['claude', 'codex'];

/// Where a provider's executable is, or why it is not used.
sealed class ResourceExecutable {
  const ResourceExecutable();
}

/// A verified executable at [path], of [version].
final class ExecutableFound extends ResourceExecutable {
  const ExecutableFound(this.path, this.version);

  final String path;
  final String version;
}

/// No executable to read with, and why, in the answer's words.
final class ExecutableUnavailable extends ResourceExecutable {
  const ExecutableUnavailable(this.unavailable);

  final String unavailable;
}

/// What resolves and reads a provider's limits.
abstract interface class ResourceCollectors {
  /// The executable of [provider] to read with where agents start, [cwd];
  /// [customCommand] when its runtime starts with a command of the
  /// person's own.
  Future<ResourceExecutable> resolve(
    String provider,
    String cwd,
    bool customCommand,
    CancellationToken cancelled,
  );

  /// [provider]'s limits, read with the executable at [path] in [cwd].
  Future<ProviderLimits> read(
    String provider,
    String path,
    String cwd,
    CancellationToken cancelled,
  );
}

/// Where the limits come from: the official readers, the fixtures, or the
/// collectors given.
sealed class ResourceCollectorsChoice {
  const ResourceCollectorsChoice();
}

/// The installed providers, read as their own tools read them.
final class OfficialCollectors extends ResourceCollectorsChoice {
  const OfficialCollectors();
}

/// The fixed fake states, never an installed provider.
final class FixtureCollectors extends ResourceCollectorsChoice {
  const FixtureCollectors([this.fixtureCase = 'normal']);

  /// One of [resourceFixtureCases].
  final String fixtureCase;
}

/// Collectors a test gives.
final class GivenCollectors extends ResourceCollectorsChoice {
  const GivenCollectors(this.collectors);

  final ResourceCollectors collectors;
}

/// The official readers, which read the installed providers as their own
/// tools do: Codex's app server, and Claude's usage getter. A test replaces
/// them, so no test ever reaches an installed provider.
ResourceCollectors officialCollectors = const _OfficialReaders();

final class _OfficialReaders implements ResourceCollectors {
  const _OfficialReaders();

  @override
  Future<ResourceExecutable> resolve(
    String provider,
    String cwd,
    bool customCommand,
    CancellationToken cancelled,
  ) => resolveResourceExecutable(
    provider,
    cwd: cwd,
    cancelled: cancelled,
    customCommand: customCommand,
  );

  @override
  Future<ProviderLimits> read(
    String provider,
    String path,
    String cwd,
    CancellationToken cancelled,
  ) => provider == 'codex'
      ? collectCodexResources(
          [path, 'app-server'],
          cwd: cwd,
          cancelled: cancelled,
        )
      : collectClaudeResources(path, cwd: cwd, cancelled: cancelled);
}

/// A window's limits read, and the close that waits out readers still
/// cleaning up.
abstract interface class Resources {
  ReadLimits get read;

  /// Every reader's cleanup failures, once each reader has finished.
  Future<List<String>> close();
}

/// A number as JavaScript writes it: `10`, `0.05`.
String _js(num value) => value == value.roundToDouble() && value.isFinite
    ? value.toInt().toString()
    : value.toString();

/// Limits read from [collectors]: each provider bounded by [timeout]. An
/// answer past its deadline does not wait for its reader's cleanup; close
/// does, so chord never exits ahead of a provider's process group.
Resources createResources(
  ResourceCollectorsChoice collectors, {
  Duration timeout = readTimeout,
}) => _Resources(collectors, timeout);

final class _Resources implements Resources {
  _Resources(this._choice, this._timeout);

  final ResourceCollectorsChoice _choice;
  final Duration _timeout;
  final _running = <Future<void>>{};
  final _failures = <String>{};

  Future<ProviderLimits> _readOne(
    String agent,
    LimitsPlace place,
    CancellationToken cancelled,
  ) async {
    if (!resourceProviders.contains(agent)) {
      return ProviderUnavailable(agent, 'No limits reader for this runtime.');
    }
    final ResourceCollectors collectors;
    switch (_choice) {
      case OfficialCollectors():
        collectors = officialCollectors;
      case FixtureCollectors(:final fixtureCase):
        return fixtureLimits(agent, fixtureCase, cancelled);
      case GivenCollectors(collectors: final given):
        collectors = given;
    }
    final executable = await collectors.resolve(
      agent,
      place.cwd,
      place.commandOf(agent) != null,
      cancelled,
    );
    return switch (executable) {
      ExecutableUnavailable(:final unavailable) => ProviderUnavailable(
        agent,
        unavailable,
      ),
      ExecutableFound(:final path) => collectors.read(
        agent,
        path,
        place.cwd,
        cancelled,
      ),
    };
  }

  @override
  ReadLimits get read => (agents, place, caller) async {
    final readAt = isoTime(DateTime.now());
    final providers = await Future.wait([
      for (final agent in {...agents ?? resourceProviders})
        _readBounded(agent, place, caller),
    ]);
    return (readAt: readAt, providers: providers);
  };

  Future<ProviderLimits> _readBounded(
    String agent,
    LimitsPlace place,
    CancellationToken caller,
  ) async {
    final timeout = TimeoutCancellationToken(_timeout);
    final cancelled = MergedCancellationToken([caller, timeout]);
    final reading = _readOne(agent, place, cancelled);
    late final Future<void> owned;
    owned = reading
        .then<void>(
          (_) {},
          onError: (Object error) {
            if (error is ResourceReadError && error.kind == 'cleanup') {
              _failures.add(error.message);
            }
          },
        )
        .whenComplete(() => _running.remove(owned));
    _running.add(owned);
    try {
      return await reading.asCancellable(cancelled);
    } on Object catch (error) {
      if (caller.isCancelled) rethrow;
      return ProviderUnavailable(
        agent,
        timeout.isCancelled
            ? 'Timed out after ${_js(_timeout.inMicroseconds / 1e6)} s.'
            : error is ResourceReadError
            ? error.message
            : 'The limits could not be read.',
      );
    } finally {
      timeout.cancel();
    }
  }

  @override
  Future<List<String>> close() async {
    while (_running.isNotEmpty) {
      await Future.wait([..._running]);
    }
    return [..._failures];
  }
}

/// Where a launched chord reads limits from: the fixtures, in the case
/// `CHORD_FAKE_RESOURCE_CASE` in [environment] chooses, when it was built
/// with the private capture [flag], else the official readers. Read once,
/// as the window and `chord acp` start.
ResourceCollectorsChoice launchCollectors(
  String? flag,
  Map<String, String> environment,
) => switch (resourceSourceMode(flag)) {
  ResourceSource.fixture => FixtureCollectors(
    resourceFixtureCase(environment['CHORD_FAKE_RESOURCE_CASE']),
  ),
  ResourceSource.official => const OfficialCollectors(),
};

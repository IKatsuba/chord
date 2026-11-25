/// Fixed fake-only states for captures and tests, as the original's
/// `src/platform/resource_fixture.ts`; no authentication or provider
/// fallback.
library;

import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';

import '../session/budgets.dart';

/// Where providers' limits are read from: the official readers, or the
/// fixture states as a whole.
enum ResourceSource { official, fixture }

/// The fixture states a capture or a test chooses among.
const resourceFixtureCases = ['normal', 'partial', 'timeout', 'unavailable'];

/// The private capture flag, defined only at compile time (`tool/dev.dart`
/// with `--fake` or `--qa`), never read from the environment, so a built
/// chord cannot be switched to fixtures by where it runs.
const resourceFixtureFlag = String.fromEnvironment('CHORD_RESOURCE_FIXTURE');

/// The private capture flag selects fixtures as a whole, never a fallback
/// reader.
ResourceSource resourceSourceMode(String? flag) =>
    flag == 'true' ? ResourceSource.fixture : ResourceSource.official;

/// The fixture state [value] names, `normal` for anything else.
String resourceFixtureCase(String? value) =>
    resourceFixtureCases.contains(value) ? value! : 'normal';

/// [agent]'s limits in the fixture state [scenario]: one window, a second
/// one partly unknown, a read that never answers until [cancelled], or a
/// provider not read.
Future<ProviderLimits> fixtureLimits(
  String agent,
  String scenario,
  CancellationToken cancelled,
) {
  if (scenario == 'timeout') {
    // Never answers: the read's own deadline reports it.
    return Completer<ProviderLimits>().future.asCancellable(cancelled);
  }
  if (scenario == 'unavailable') {
    return Future.value(
      ProviderUnavailable(agent, 'Scripted unavailable provider.'),
    );
  }
  final ResourceWindow window = (
    name: 'five_hour',
    usedPercent: 12.345,
    windowSeconds: 18000,
    resetsAt: isoTime(DateTime.now().add(const Duration(hours: 1))),
    models: null,
  );
  return Future.value(
    ProviderWindows(agent, [
      window,
      if (scenario == 'partial')
        (
          name: 'seven_day',
          usedPercent: null,
          windowSeconds: 604800,
          resetsAt: null,
          models: null,
        ),
    ]),
  );
}

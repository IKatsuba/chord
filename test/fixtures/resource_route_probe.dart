/// Reads the providers' limits as a chord built as this one would at
/// launch, with an official reader that says so and fails if anything
/// reaches it; prints each provider's agent and first window's use.
library;

import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/platform/resource_fixture.dart';
import 'package:chord/platform/resources.dart';
import 'package:chord/session/budgets.dart';

final class _Official implements ResourceCollectors {
  @override
  Future<ResourceExecutable> resolve(
    String provider,
    String cwd,
    bool customCommand,
    CancellationToken cancelled,
  ) {
    stdout.writeln('official resolved $provider');
    return Future.error(StateError('official'));
  }

  @override
  Future<ProviderLimits> read(
    String provider,
    String path,
    String cwd,
    CancellationToken cancelled,
  ) => Future.error(StateError('official'));
}

Future<void> main() async {
  officialCollectors = _Official();
  final budgets =
      await createResources(
        launchCollectors(resourceFixtureFlag, Platform.environment),
      ).read(null, (
        cwd: Directory.current.path,
        commandOf: (_) => null,
      ), CancellationToken());
  for (final provider in budgets.providers) {
    stdout.writeln(switch (provider) {
      ProviderWindows(:final agent, :final windows) =>
        '$agent ${windows.first.usedPercent}',
      ProviderUnavailable(:final agent, :final unavailable) =>
        '$agent $unavailable',
    });
  }
}

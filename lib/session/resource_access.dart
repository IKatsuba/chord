/// How a window reads its providers' limits, injected: test and capture
/// windows never fall back to the official readers. From the original's
/// `session/resource_access.ts`.
library;

import 'package:cancellation_token/cancellation_token.dart';

import 'budgets.dart';

/// Where a window's agents start, which decides how their limits are read.
typedef LimitsPlace = ({
  String cwd,

  /// The custom ACP command a runtime starts with, if any.
  Object? Function(String agent) commandOf,
});

/// Reads each named provider, or claude and codex when none are named.
typedef ReadLimits =
    Future<Budgets> Function(
      List<String>? agents,
      LimitsPlace place,
      CancellationToken cancelled,
    );

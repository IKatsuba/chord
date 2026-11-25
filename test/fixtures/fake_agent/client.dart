// What the client said at `initialize` it takes, which the scenarios play
// to, as the original's client.ts. main.dart reads it from the request; the
// scenarios read it as it stands.

/// Whether the client said at `initialize` that it takes plans by id.
bool clientTakesPlans = false;

/// How the client takes a command's output, as Claude's adapter reads its
/// `_meta`: `delta`, `whole` or `none`.
String clientTerminalOutput = 'none';

/// Whether the client takes compactions by id.
bool clientTakesCompaction = false;

/// Whether the client takes subagents as sessions of their own.
bool clientTakesSubagents = false;

/// Whether the client presents notices (CHD-629).
bool clientTakesNotices = false;

/// Takes what the client declared in `initialize`.
void readCapabilities(Map<String, Object?> params) {
  final capabilities = params['clientCapabilities'];
  final caps = capabilities is Map ? capabilities : const {};
  final meta = caps['_meta'] is Map ? caps['_meta'] as Map : const {};
  final session = caps['session'] is Map ? caps['session'] as Map : const {};

  clientTakesPlans = caps['plan'] != null;
  clientTakesSubagents = _isObject(caps['subagents']);
  clientTakesCompaction = _isObject(session['compaction']);
  clientTakesNotices = _isObject(session['notices']);
  clientTerminalOutput = meta['terminal_output_delta'] == true
      ? 'delta'
      : meta['terminal_output'] == true
      ? 'whole'
      : 'none';
}

/// `typeof value === 'object' && value !== null`.
bool _isObject(Object? value) => value is Map || value is List;

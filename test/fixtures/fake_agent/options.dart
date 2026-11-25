// The fake agent's flags and the environment variables beside them, read
// once at start, as the original's options.ts. Here rather than in main.dart
// because the scenarios read them too, and main.dart imports the scenarios.
import 'dart:convert';
import 'dart:io';

/// The flags after the script, as main gave them.
List<String> args = const [];

/// The environment the fake reads; a test may set another.
Map<String, String> environment = Platform.environment;

bool _flag(String flag, [String? variable]) =>
    args.contains(flag) || (variable != null && environment[variable] == '1');

/// The value given a flag `--name value`, or its environment variable.
String? valueOf(String flag, String variable) {
  final at = args.indexOf(flag);
  if (at >= 0) return at + 1 < args.length ? args[at + 1] : null;
  return environment[variable];
}

/// `Number(text)` as JavaScript reads it: blank is 0, else NaN for what is
/// not a number; a whole number is an int.
num jsNumber(String? text) {
  if (text == null) return double.nan;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  final read = num.tryParse(trimmed);
  if (read == null) return double.nan;
  return read is double && read.isFinite && read == read.truncateToDouble()
      ? read.toInt()
      : read;
}

/// A pause of [ms] as `setTimeout` takes it: NaN or less than 0 is 0.
int milliseconds(num ms) => ms.isNaN || ms < 0 ? 0 : ms.toInt();

final resumeOnly = _flag('--resume-only');

/// It offers `session/fork`, forking any session id it is given into a new
/// one (CHD-101).
final forks = _flag('--fork', 'CHORD_FAKE_FORK');

/// It offers no `session/load` (CHD-492).
final noLoad = _flag('--no-load');

final noUsage = _flag('--no-usage', 'CHORD_FAKE_NO_USAGE');

final tokensOnly = _flag('--tokens-only', 'CHORD_FAKE_TOKENS_ONLY');

/// A turn's answer gives the session's running total of tokens (CHD-472).
final sessionUsage = _flag('--session-usage', 'CHORD_FAKE_SESSION_USAGE');

/// The turn's `usage_update` carries the context and no cost.
final noCost = _flag('--no-cost', 'CHORD_FAKE_NO_COST');

/// With `--tokens-only`, one more model price data does not know (CHD-472).
final unpricedModel = _flag('--unpriced-model', 'CHORD_FAKE_UNPRICED_MODEL');

final embeddedContext = _flag(
  '--embedded-context',
  'CHORD_FAKE_EMBEDDED_CONTEXT',
);

final noImages = _flag('--no-images', 'CHORD_FAKE_NO_IMAGES');

final noHttp = _flag('--no-http', 'CHORD_FAKE_NO_HTTP');

/// The MCP transports past stdio the fake advertises (CHD-441).
final Map<String, bool> mcpTransports = () {
  final flag = args.indexOf('--mcp-transports');
  final chosen = flag >= 0
      ? (flag + 1 < args.length ? args[flag + 1] : null)
      : environment['CHORD_FAKE_MCP_TRANSPORTS'];
  if (chosen == null) return {'http': !noHttp, 'sse': true};
  const known = ['http', 'sse', 'acp'];
  final named = chosen == 'none' ? <String>[] : chosen.split(',');
  for (final each in named) {
    if (!known.contains(each)) {
      throw StateError('unknown MCP transport to advertise "$each"');
    }
  }
  return {for (final transport in known) transport: named.contains(transport)};
}();

final noConfig = _flag('--no-config', 'CHORD_FAKE_NO_CONFIG');

/// Each model offers its own parameters (CHD-626).
final modelParameters = _flag(
  '--model-parameters',
  'CHORD_FAKE_MODEL_PARAMETERS',
);

final noModes = _flag('--no-modes', 'CHORD_FAKE_NO_MODES');

/// A stop of a Claude subagent alone is held until a test lets it go.
final stopGate = _flag('--stop-gate', 'CHORD_FAKE_STOP_GATE');

/// A `session/cancel` with no turn playing is answered at once (CHD-426).
final sayCancels = _flag('--say-cancels', 'CHORD_FAKE_SAY_CANCELS');

/// A message is answered with the whole prompt that came (CHD-482).
final echoMessages = _flag('--echo-messages', 'CHORD_FAKE_ECHO_MESSAGES');

/// Every session names itself this just after the reply (CHD-445).
final titleAtStart = valueOf('--title', 'CHORD_FAKE_TITLE');

/// Every `session/new` answers with this id.
final sessionIdFlag = valueOf('--session-id', 'CHORD_FAKE_SESSION_ID');

/// A change of configuration is said only in the answer that made it.
final configInResponses = _flag(
  '--config-in-responses',
  'CHORD_FAKE_CONFIG_IN_RESPONSES',
);

/// Every session offers dimcode's `permission` option (CHD-434).
final dimcodePermission = valueOf(
  '--dimcode-permission',
  'CHORD_FAKE_DIMCODE_PERMISSION',
);

/// The runtime the scenarios' children are opened on, when given (CHD-493).
final childRuntimeGiven = valueOf(
  '--child-runtime',
  'CHORD_FAKE_CHILD_RUNTIME',
);

/// The runtime `agentother` opens its child on.
final childRuntime = childRuntimeGiven ?? 'codex';

/// The model the scenarios' children ask for.
final childModel = valueOf('--child-model', 'CHORD_FAKE_CHILD_MODEL');

/// The model a forked session is on.
final forkModel = valueOf('--fork-model', 'CHORD_FAKE_FORK_MODEL');

/// How `auth/status` is answered (CHD-629).
final String? authStatusMode = () {
  final chosen = valueOf('--auth-status', 'CHORD_FAKE_AUTH_STATUS');
  const known = [
    'authenticated',
    'unauthenticated',
    'unknown',
    'error',
    'hang',
    'held',
    'several',
  ];
  if (chosen == null || known.contains(chosen)) return chosen;
  throw StateError('unknown --auth-status "$chosen"');
}();

/// It pushes the account just after answering `initialize` (CHD-629).
final authPush = _flag('--auth-push', 'CHORD_FAKE_AUTH_PUSH');

/// It pushes an API key's account before it answers `initialize`.
final authPushEarly = _flag('--auth-push-early', 'CHORD_FAKE_AUTH_PUSH_EARLY');

/// An API key's account pushed just before `auth/status`'s answer, or after.
final String? authRace = () {
  final chosen = valueOf('--auth-race', 'CHORD_FAKE_AUTH_RACE');
  if (chosen == null || chosen == 'push-first' || chosen == 'answer-first') {
    return chosen;
  }
  throw StateError('unknown --auth-race "$chosen"');
}();

/// How `session/set_title` is answered (CHD-629).
final String? setTitleMode = () {
  final chosen = valueOf('--set-title', 'CHORD_FAKE_SET_TITLE');
  const known = ['echo', 'silent', 'refuse', 'hang'];
  if (chosen == null || known.contains(chosen)) return chosen;
  throw StateError('unknown --set-title "$chosen"');
}();

/// A wedged agent says `wedged` on stderr once SIGTERM is ignored, for a
/// test that times the stop ladder from there.
final sayWedged = _flag('--say-wedged');

/// It opens every session in `auto`, which `fake-small` lacks (CHD-629).
final autoFallback = _flag('--auto-fallback', 'CHORD_FAKE_AUTO_FALLBACK');

/// It also offers an `auto` mode.
final autoMode = _flag('--auto-mode', 'CHORD_FAKE_AUTO_MODE') || autoFallback;

/// It also offers Claude's `bypassPermissions` mode.
final bypassMode = _flag('--bypass-mode', 'CHORD_FAKE_BYPASS_MODE');

/// It advertises no slash commands.
final noCommands = _flag('--no-commands', 'CHORD_FAKE_NO_COMMANDS');

/// Commands it offers beside its own, by name.
final List<String> alsoCommands =
    (valueOf('--also-commands', 'CHORD_FAKE_ALSO_COMMANDS') ?? '')
        .split(',')
        .where((name) => name.isNotEmpty)
        .toList();

/// How long a config change takes to answer.
final configDelayMs = jsNumber(
  valueOf('--config-delay', 'CHORD_FAKE_CONFIG_DELAY') ?? '0',
);

/// A person's words for scenarios' names (CHD-493).
final Map<String, String> said =
    (jsonDecode(valueOf('--said', 'CHORD_FAKE_SAID') ?? '{}') as Map)
        .cast<String, String>();

/// The members a team's lead opens on its first turn, in order.
final List<String> leadOpens =
    (valueOf('--lead-opens', 'CHORD_FAKE_LEAD_OPENS') ?? 'tester,coder')
        .split(',')
        .where((name) => name.isNotEmpty)
        .toList();

/// A team file whose team `propose` proposes in place of its own.
final proposeTeam = valueOf('--propose-team', 'CHORD_FAKE_PROPOSE_TEAM');

String? _afterFlag(String flag) {
  final at = args.indexOf(flag);
  return at + 1 < args.length ? args[at + 1] : null;
}

/// What a session's cost starts from, in USD (CHD-373).
final costFrom = jsNumber(
  (args.contains('--cost-from')
          ? _afterFlag('--cost-from')
          : environment['CHORD_FAKE_COST_FROM']) ??
      '0',
);

/// What the agent's own cycle adds to the session's cost (CHD-373).
final num? cycleCost = args.contains('--cycle-cost')
    ? jsNumber(_afterFlag('--cycle-cost'))
    : environment['CHORD_FAKE_CYCLE_COST'] == null
    ? null
    : jsNumber(environment['CHORD_FAKE_CYCLE_COST']);

/// A session resumed runs a Claude cycle of its own once quiet.
final cycleOnResume = _flag('--cycle-on-resume', 'CHORD_FAKE_CYCLE_ON_RESUME');

/// A turn's `usage_update` comes after its answer.
final lateCost = _flag('--late-cost', 'CHORD_FAKE_LATE_COST');

/// A turn's `usage_update` is held until the session's next prompt.
final costAtNext = _flag('--cost-at-next', 'CHORD_FAKE_COST_AT_NEXT');

/// A scenario a team's lead opens `tester` on, in place of its role.
final String? testerPlays = args.contains('--tester-plays')
    ? _afterFlag('--tester-plays')
    : environment['CHORD_FAKE_TESTER_PLAYS'];

/// The step it stops answering at.
final String? hang = () {
  final flag = args.indexOf('--hang');
  final chosen = flag >= 0
      ? _afterFlag('--hang')
      : environment['CHORD_FAKE_HANG'];
  if (chosen == null) return null;
  if (!const ['start', 'config', 'effort', 'turn'].contains(chosen)) {
    throw StateError('unknown step to hang at "$chosen"');
  }
  return chosen;
}();

/// A model switch also sends the new set, before or after its answer.
final String? resendConfig = () {
  final chosen = valueOf('--resend-config', 'CHORD_FAKE_RESEND_CONFIG');
  if (chosen != null && chosen != 'before' && chosen != 'after') {
    throw StateError('unknown time to resend config at "$chosen"');
  }
  return chosen;
}();

final planCapabilityOnly = _flag(
  '--plan-capability-only',
  'CHORD_FAKE_PLAN_CAPABILITY_ONLY',
);

final silentSetMode = _flag('--silent-set-mode', 'CHORD_FAKE_SILENT_SET_MODE');

/// The adapter whose `_session/steering` the fake answers as.
final String? steering = () {
  final flag = args.indexOf('--steering');
  final chosen = flag >= 0
      ? _afterFlag('--steering')
      : environment['CHORD_FAKE_STEERING'];
  if (chosen == null) return null;
  if (!const ['claude', 'codex', 'codex24', 'opencode'].contains(chosen)) {
    throw StateError('unknown adapter to steer as "$chosen"');
  }
  return chosen;
}();

/// The adapter the fake names itself as in `initialize` (CHD-426).
final String? adapter = () {
  final flag = args.indexOf('--adapter');
  final chosen = flag >= 0
      ? _afterFlag('--adapter')
      : environment['CHORD_FAKE_ADAPTER'];
  if (chosen != null && chosen != 'claude') {
    throw StateError('unknown adapter to name as "$chosen"');
  }
  return chosen;
}();

/// A steer lands only once the turn playing has ended.
final steerLate = _flag('--steer-late', 'CHORD_FAKE_STEER_LATE');

/// Every steer is refused (CHD-535).
final steerRefuse = _flag('--steer-refuse', 'CHORD_FAKE_STEER_REFUSE');

/// A turn on a message ends only once the gate is released (CHD-501).
final holdReply = _flag('--hold-reply', 'CHORD_FAKE_HOLD_REPLY');

final refuseConfig = _flag('--refuse-config', 'CHORD_FAKE_REFUSE_CONFIG');

/// How long a step takes, 5 ms by default, and every scenario's pace.
final num stepMs = jsNumber(
  (args.contains('--step-ms') ? _afterFlag('--step-ms') : null) ??
      environment['CHORD_FAKE_STEP_MS'] ??
      '5',
);

/// Every session request fails `authRequired`, as `--auth-required` says
/// (CHD-435, CHD-622, CHD-629).
final String? authRequired = () {
  final flag = args.indexOf('--auth-required');
  final kind = flag >= 0
      ? _afterFlag('--auth-required')
      : environment['CHORD_FAKE_AUTH_REQUIRED'];
  return const [
        'methods',
        'bare',
        'link',
        'linkother',
        'cloud',
        'prompt',
      ].contains(kind)
      ? kind
      : null;
}();

/// The fake fails to start as `--start-fails` says (CHD-454).
final String? startFails = () {
  final flag = args.indexOf('--start-fails');
  final kind = flag >= 0
      ? _afterFlag('--start-fails')
      : environment['CHORD_FAKE_START_FAILS'];
  return const ['traceback', 'stdout', 'notacp', 'alias'].contains(kind)
      ? kind
      : null;
}();

/// The last line of `--start-fails traceback`'s traceback.
const tracebackError =
    "ImportError: cannot import name 'AuthMethod' from 'acp.schema'";

/// How `session/new`'s initial `configOptions` are taken (CHD-629).
final String? initialOptions = () {
  final chosen = valueOf('--options', 'CHORD_FAKE_OPTIONS');
  if (chosen == null || const ['apply', 'ignore', 'reject'].contains(chosen)) {
    return chosen;
  }
  throw StateError('unknown --options "$chosen"');
}();

/// Its model, mode and effort options go by ids of their own (CHD-629).
final bool renamedIds = () {
  final chosen = valueOf('--config-ids', 'CHORD_FAKE_CONFIG_IDS');
  if (chosen != null && chosen != 'renamed') {
    throw StateError('unknown --config-ids "$chosen"');
  }
  return chosen == 'renamed';
}();

/// Every `session/new` sends a `warning` notice titled this (CHD-629).
final startNotice = valueOf('--start-notice', 'CHORD_FAKE_START_NOTICE');

/// Every `session/new` sends an agent message with this text (CHD-622).
final firstMessage = valueOf('--first-message', 'CHORD_FAKE_FIRST_MESSAGE');

/// Reads every option now, so a bad one fails at start, as the original's
/// module does when it loads.
void readOptions() {
  for (final read in <Object? Function()>[
    () => mcpTransports,
    () => authStatusMode,
    () => authRace,
    () => setTitleMode,
    () => said,
    () => hang,
    () => resendConfig,
    () => steering,
    () => adapter,
    () => initialOptions,
    () => renamedIds,
  ]) {
    read();
  }
}

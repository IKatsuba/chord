// What each session holds: its working directory, its MCP servers, and the
// model, mode and effort it runs with, with the config options that offer
// them, as the original's sessions.ts.
import 'dart:async';

import 'options.dart';
import 'signals.dart';

/// Each session's working directory, which its commands run in.
final cwds = <String, String>{};

/// The MCP servers each session was opened with, as they arrived.
final mcpServers = <String, List<Object?>>{};

/// How each session was last opened: the request, its `_meta`, and for a
/// fork the session it was forked from.
final openedWith = <String, Map<String, Object?>>{};

/// Claude Code's first three modes, in its order.
final List<Map<String, String>> availableModes = [
  {'id': 'default', 'name': 'Default'},
  {'id': 'acceptEdits', 'name': 'Accept edits'},
  {'id': 'plan', 'name': 'Plan'},
  if (autoMode) {'id': 'auto', 'name': 'Auto'},
  if (bypassMode) {'id': 'bypassPermissions', 'name': 'Bypass'},
];

/// Each `session/set_config_option` request a session received (CHD-629).
final configsHeard = <String, List<Object?>>{};

/// Each session's mode.
final modes = <String, String>{};

/// Each session's model, once one was asked for.
final models = <String, String>{};

/// Each session's effort, once one was asked for.
final efforts = <String, String>{};

/// Each session's dimcode `permission`, once moved from its start.
final permissions = <String, String>{};

/// dimcode's `permission` values.
const dimcodePermissions = [
  {'value': 'read-only', 'name': 'Read only'},
  {'value': 'workspace-write', 'name': 'Workspace write'},
  {'value': 'full-access', 'name': 'Full access'},
];

/// The efforts every session offers, `medium` until set.
const availableEfforts = [
  {'value': 'low', 'name': 'Low'},
  {'value': 'medium', 'name': 'Medium'},
  {'value': 'high', 'name': 'High'},
];

/// Each session's fast option, `off` until set.
final fasts = <String, String>{};

const _largeEfforts = [
  ...availableEfforts,
  {'value': 'xhigh', 'name': 'Xhigh'},
  {'value': 'max', 'name': 'Max'},
];

/// The efforts [model] offers.
List<Map<String, String>> effortsOf(String model) {
  if (!modelParameters) return availableEfforts;
  return model == firstModel ? _largeEfforts : availableEfforts.sublist(0, 2);
}

/// Whether [model] offers a fast option.
bool hasFast(String model) => modelParameters && model == firstModel;

const fastValues = [
  {'value': 'off', 'name': 'Off'},
  {'value': 'on', 'name': 'On'},
];

/// The models every session offers, the first in use until switched.
final List<Map<String, String>> availableModels = tokensOnly
    ? [
        {'value': 'gpt-5.3-codex', 'name': 'GPT-5.3 Codex'},
        {'value': 'claude-haiku-4-5', 'name': 'Claude Haiku 4.5'},
        {'value': 'claude-opus-5-5', 'name': 'Claude Opus 5.5'},
        {'value': 'gpt-6.1-sol', 'name': 'GPT-6.1 Sol'},
        if (unpricedModel) {'value': 'fake-unpriced', 'name': 'Fake Unpriced'},
      ]
    : [
        {'value': 'fake-large', 'name': 'Fake Large with a 1M context window'},
        {'value': 'fake-small', 'name': 'Fake Small'},
      ];

final String firstModel = availableModels.isEmpty
    ? 'fake-large'
    : availableModels.first['value']!;

final locked = <String>{};

/// Each session's cost so far, in USD.
final costs = <String, num>{};

/// The waits on a message steered into each session, as listeners.
final _steerWaits = <String, List<Completer<void>>>{};

/// Says [sessionId] as a `_session/steering` request for it arrives. The
/// waits settle on the event loop's next turn, after the steer's answer is
/// written, as the original's do behind its SDK's longer way out.
void emitSteer(String sessionId) {
  final waits = _steerWaits.remove(sessionId) ?? const [];
  Timer.run(() {
    for (final wait in waits) {
      if (!wait.isCompleted) wait.complete();
    }
  });
}

/// How many waits on a steer into [sessionId] listen now.
int steerListeners(String sessionId) => _steerWaits[sessionId]?.length ?? 0;

/// Listens, from now, for a message steered into [sessionId]: `steered`
/// settles once one has, and fails once [signal] aborts or `stop` is
/// called, which also stops listening. Its failure is handled here.
({Future<void> steered, void Function() stop}) steeredInto(
  String sessionId,
  Signal signal,
) {
  final wait = Completer<void>();
  final steered = wait.future..ignore();
  if (signal.aborted) {
    wait.completeError(signal.reason!);
    return (steered: steered, stop: () {});
  }
  void drop(Object reason) {
    final waits = _steerWaits[sessionId];
    if (waits != null && waits.remove(wait) && waits.isEmpty) {
      _steerWaits.remove(sessionId);
    }
    if (!wait.isCompleted) wait.completeError(reason);
  }

  (_steerWaits[sessionId] ??= []).add(wait);
  final remove = signal.onAbort(() => drop(signal.reason!));
  steered.then((_) => remove(), onError: (Object _) => remove()).ignore();
  return (steered: steered, stop: () => drop(const AbortError()));
}

/// How many `session/cancel`s each session got with no turn playing.
final strayCancels = <String, int>{};

const _renamed = {'model', 'mode', 'effort'};

/// The id the fake gives option [name].
String configIdOf(String name) =>
    renamedIds && _renamed.contains(name) ? 'x-$name' : name;

/// The option an id asked for names, null for an id the fake does not give.
String? configNameOf(String id) {
  if (!renamedIds) return id;
  if (id.startsWith('x-') && _renamed.contains(id.substring(2))) {
    return id.substring(2);
  }
  return _renamed.contains(id) ? null : id;
}

List<Map<String, Object?>> configOptions(String sessionId) {
  final model = models[sessionId] ?? firstModel;
  return [
    {
      'id': configIdOf('model'),
      'name': 'Model',
      'category': 'model',
      'type': 'select',
      'currentValue': model,
      'options': availableModels,
    },
    if (!noModes)
      {
        'id': configIdOf('mode'),
        'name': 'Mode',
        'category': 'mode',
        'type': 'select',
        'currentValue': modes[sessionId] ?? 'default',
        'options': [
          for (final mode in availableModes)
            {'value': mode['id'], 'name': mode['name']},
        ],
      },
    if (!noConfig)
      {
        'id': configIdOf('effort'),
        'name': 'Effort',
        'category': 'thought_level',
        'type': 'select',
        'currentValue': efforts[sessionId] ?? 'medium',
        'options': effortsOf(model),
      },
    if (hasFast(model))
      {
        'id': 'fast',
        'name': 'Fast',
        'category': 'model_config',
        // Marked as chord's own adapters mark theirs, so `/fast` finds it.
        '_meta': {'chord/parameter': 'fast'},
        'type': 'select',
        'currentValue': fasts[sessionId] ?? 'off',
        'options': fastValues,
      },
    // dimcode's own option, with no category, as dimcode sends it (CHD-434).
    if (dimcodePermission != null)
      {
        'id': 'permission',
        'name': 'Permission',
        'type': 'select',
        'currentValue': permissions[sessionId] ?? dimcodePermission,
        'options': dimcodePermissions,
      },
  ];
}

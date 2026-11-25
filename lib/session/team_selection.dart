/// Per-run choices change a team's configuration for one run, never a saved
/// team's instructions: the run's selection checked and frozen against the
/// person's `teamSelection` policy and what each runtime is known to offer,
/// and the receipt that says what was planned, confirmed or refused. From
/// the original's `src/session/team_selection.ts`.
library;

import 'dart:convert';

import 'package:collection/collection.dart';

import '../js_trim.dart';
import '../settings.dart' show parseSettings;
import '../teams.dart';
import 'budgets.dart' show isIsoTime;
import 'transcript/types.dart' show ChordCall, ChordTool;

/// One role's choices for a run: `agent`, `model`, `effort`, `mode`, each
/// an id of 1 to 128 characters, any of them left out.
typedef RunChoice = Map<String, String>;

const _choiceKeys = ['agent', 'model', 'effort', 'mode'];

/// A run's selection: why, and the lead's and members' choices.
final class RunSelection {
  /// A selection checked as the original's `RunSelection`.
  const RunSelection({required this.reason, this.lead, this.members});

  final String reason;
  final RunChoice? lead;

  /// By the saved member's name.
  final Map<String, RunChoice>? members;

  /// The selection as `run_team` takes and records it.
  Map<String, Object?> toJson() => {
    'reason': reason,
    'lead': ?lead,
    'members': ?members,
  };
}

bool _id(Object? value) =>
    value is String && value.isNotEmpty && value.length <= 128;

bool _reason(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= 500 &&
    jsTrim(value).isNotEmpty;

/// [value] as a run's choice for one role, or null when it is not one: an
/// object of known keys only, each an id.
RunChoice? runChoiceOf(Object? value) {
  if (value is! Map) return null;
  final choice = <String, String>{};
  for (final MapEntry(:key, value: field) in value.entries) {
    if (!_choiceKeys.contains(key) || !_id(field)) return null;
    choice[key as String] = field as String;
  }
  // In the schema's order, as the receipt keeps it.
  return {for (final key in _choiceKeys) key: ?choice[key]};
}

/// [value] as a run's selection, or null when it is not one: unknown keys,
/// a null or blank reason, a wrong type or more than [maxMembers] members.
RunSelection? runSelectionOf(Object? value) {
  if (value is! Map) return null;
  if (value.keys.any(
    (key) => !const ['reason', 'lead', 'members'].contains(key),
  )) {
    return null;
  }
  final reason = value['reason'];
  if (!_reason(reason)) return null;
  RunChoice? lead;
  if (value.containsKey('lead')) {
    lead = runChoiceOf(value['lead']);
    if (lead == null) return null;
  }
  Map<String, RunChoice>? members;
  if (value.containsKey('members')) {
    final given = value['members'];
    if (given is! Map || given.length > maxMembers) return null;
    members = {};
    for (final MapEntry(:key, value: choice) in given.entries) {
      final checked = runChoiceOf(choice);
      if (!_id(key) || checked == null) return null;
      members[key as String] = checked;
    }
  }
  return RunSelection(reason: reason as String, lead: lead, members: members);
}

/// What a runtime is known to offer; a list left out is unknown, an empty
/// one denies every choice.
typedef SelectionCapabilities = ({
  List<({String id, List<String>? efforts})>? models,
  List<String>? modes,
  List<String>? efforts,
});

/// A run's selection frozen: the team as saved, the team as it runs, the
/// policy it was checked against, and the selection.
final class FrozenSelection {
  /// A frozen run, as [freezeSelection] makes it.
  const FrozenSelection({
    required this.saved,
    required this.team,
    required this.policy,
    required this.selection,
  });

  final Team saved;
  final Team team;
  final Map<String, Object?> policy;
  final RunSelection selection;
}

String _refusal(
  String role,
  String field,
  String message, {
  bool member = false,
}) =>
    '$role.$field: $message. ${member ? 'This member was not started.' : 'No run started. Choose a supported configuration.'}';

/// A role's configuration: its runtime, and the model, effort and mode it
/// gives, in the order the receipt's check leaves them.
RunChoice _configuration(RoleConfig role) => {
  'agent': role.agent,
  'model': ?role.model,
  'effort': ?role.effort,
  'mode': ?role.mode,
};

/// [policy] in the order the original's `TeamSelection` check leaves it.
Map<String, Object?> _orderedPolicy(Map<String, Object?> policy) {
  final prefer = policy['prefer'] as Map?;
  final constraints = policy['constraints'] as Map?;
  return {
    if (policy.containsKey('intent')) 'intent': policy['intent'],
    if (prefer != null)
      'prefer': {
        if (prefer.containsKey('agent')) 'agent': prefer['agent'],
        if (prefer.containsKey('model')) 'model': prefer['model'],
      },
    if (constraints != null)
      'constraints': {
        if (constraints.containsKey('agents')) 'agents': constraints['agents'],
        if (constraints.containsKey('models')) 'models': constraints['models'],
        if (constraints.containsKey('modes')) 'modes': constraints['modes'],
      },
  };
}

/// A role's runtime, model, effort and mode.
typedef RoleConfig = ({
  String agent,
  String? model,
  String? effort,
  String? mode,
});

RoleConfig _ofLead(TeamLead lead) => (
  agent: lead.agent,
  model: lead.model,
  effort: lead.effort,
  mode: lead.mode,
);

RoleConfig _ofMember(TeamMember member) => (
  agent: member.agent,
  model: member.model,
  effort: member.effort,
  mode: member.mode,
);

/// The first of [role]'s saved fields, in the choice's order, that cannot
/// be an id; null when all can.
String? _unrepresentable(RoleConfig role) {
  for (final (field, value) in [
    ('agent', role.agent),
    ('model', role.model),
    ('effort', role.effort),
    ('mode', role.mode),
  ]) {
    if (value != null && !_id(value)) return field;
  }
  return null;
}

/// [saved] with [choice] laid over it: on the same runtime, what is left
/// out is kept; on another, model and mode must be given, and effort when
/// the saved role asks for one, and nothing of the old runtime is kept.
({RoleConfig? config, String? error}) _merge(
  String role,
  RoleConfig saved,
  RunChoice? choice,
) {
  final given = choice ?? const <String, String>{};
  final agent = given['agent'];
  if (agent == null || agent == saved.agent) {
    return (
      config: (
        agent: saved.agent,
        model: given['model'] ?? saved.model,
        effort: given['effort'] ?? saved.effort,
        mode: given['mode'] ?? saved.mode,
      ),
      error: null,
    );
  }
  for (final field in const ['model', 'mode', 'effort']) {
    if (given[field] == null && (field != 'effort' || saved.effort != null)) {
      return (
        config: null,
        error: _refusal(
          role,
          field,
          'a runtime change requires an explicit destination value',
        ),
      );
    }
  }
  return (
    config: (
      agent: agent,
      model: given['model'],
      effort: given['effort'],
      mode: given['mode'],
    ),
    error: null,
  );
}

List<String>? _list(Object? value) =>
    value is List ? value.cast<String>() : null;

/// Why [role]'s [choice] may not run under [policy] with [runtimes] and
/// what its runtime is known to offer; null when it may. [explicit] is
/// what the selection itself asked for the role; [member] words a
/// member's refusal, as it opens after the run started.
String? validateSelectedRole(
  String role,
  RoleConfig choice,
  Map<String, Object?> policy,
  List<String> runtimes, {
  SelectionCapabilities? capabilities,
  RunChoice? explicit,
  bool member = false,
}) {
  if (!runtimes.contains(choice.agent)) {
    return _refusal(
      role,
      'agent',
      'the selected runtime is not configured',
      member: member,
    );
  }
  final constraints = policy['constraints'] as Map?;
  for (final (field, allowed, value) in [
    ('agent', _list(constraints?['agents']), choice.agent),
    (
      'model',
      _list((constraints?['models'] as Map?)?[choice.agent]),
      choice.model,
    ),
    (
      'mode',
      _list((constraints?['modes'] as Map?)?[choice.agent]),
      choice.mode,
    ),
  ]) {
    if (allowed != null && (value == null || !allowed.contains(value))) {
      return _refusal(
        role,
        field,
        'the choice is outside the configured allowlist',
        member: member,
      );
    }
  }
  final models = capabilities?.models;
  final modes = capabilities?.modes;
  if (choice.model case final model?
      when models != null && !models.any((one) => one.id == model)) {
    return _refusal(
      role,
      'model',
      '$model is not supported by the selected runtime',
      member: member,
    );
  }
  if (choice.mode case final mode?
      when modes != null && !modes.contains(mode)) {
    return _refusal(
      role,
      'mode',
      '$mode is not supported by the selected runtime',
      member: member,
    );
  }
  // Effort is model-specific; another model's advertised efforts prove
  // nothing.
  final efforts = choice.model == null
      ? capabilities?.efforts
      : models?.firstWhereOrNull((one) => one.id == choice.model)?.efforts;
  final effort = explicit?['effort'];
  if (effort != null && efforts != null && !efforts.contains(effort)) {
    return _refusal(
      role,
      'effort',
      '$effort is not supported by the selected model',
      member: member,
    );
  }
  return null;
}

/// [saved] under [selection]: each role's choice merged and checked
/// against [policy], [runtimes] and what [capabilities] says each runtime
/// offers, or the first refusal. The team a run takes is built anew, so a
/// later read of the file changes nothing of it.
({FrozenSelection? frozen, String? error}) freezeSelection(
  Team saved,
  Object? selection,
  Map<String, Object?> policy,
  List<String> runtimes, {
  Map<String, SelectionCapabilities> capabilities = const {},
}) {
  final parsed = selection is RunSelection
      ? runSelectionOf(selection.toJson())
      : runSelectionOf(selection);
  if (parsed == null) {
    return (frozen: null, error: 'Invalid run selection. No run started.');
  }
  for (final name in parsed.members?.keys ?? const <String>[]) {
    if (!saved.members.any((member) => member.name == name)) {
      return (
        frozen: null,
        error: 'Unknown selected member $name. No run started.',
      );
    }
  }
  final roles = <(String, RoleConfig, RunChoice?)>[
    ('lead', _ofLead(saved.lead), parsed.lead),
    for (final member in saved.members)
      (member.name, _ofMember(member), parsed.members?[member.name]),
  ];
  final merged = <RoleConfig>[];
  for (final (name, role, override) in roles) {
    // Saved values stay in the receipt even when an override replaces them.
    final field = _unrepresentable(role);
    if (field != null) {
      return (
        frozen: null,
        error: _refusal(
          name,
          field,
          'the saved value cannot fit a bounded run receipt',
        ),
      );
    }
    final (:config, :error) = _merge(name, role, override);
    if (error != null) return (frozen: null, error: error);
    final refused = validateSelectedRole(
      name,
      config!,
      policy,
      runtimes,
      capabilities: capabilities[config.agent],
      explicit: override,
    );
    if (refused != null) return (frozen: null, error: refused);
    merged.add(config);
  }
  final lead = merged.first;
  final team = Team(
    description: saved.description,
    lead: TeamLead(
      agent: lead.agent,
      model: lead.model,
      effort: lead.effort,
      mode: lead.mode,
      instructions: saved.lead.instructions,
    ),
    members: List.unmodifiable([
      for (final (index, member) in saved.members.indexed)
        TeamMember(
          name: member.name,
          role: member.role,
          agent: merged[index + 1].agent,
          model: merged[index + 1].model,
          effort: merged[index + 1].effort,
          mode: merged[index + 1].mode,
          instructions: member.instructions,
        ),
    ]),
    body: saved.body,
  );
  return (
    frozen: FrozenSelection(
      saved: Team(
        description: saved.description,
        lead: saved.lead,
        members: List.unmodifiable(saved.members),
        body: saved.body,
      ),
      team: team,
      policy: _deepUnmodifiable(policy) as Map<String, Object?>,
      selection: parsed,
    ),
    error: null,
  );
}

Object? _deepUnmodifiable(Object? value) => switch (value) {
  Map() => Map<String, Object?>.unmodifiable({
    for (final MapEntry(:key, :value) in value.entries)
      '$key': _deepUnmodifiable(value),
  }),
  List() => List<Object?>.unmodifiable([
    for (final each in value) _deepUnmodifiable(each),
  ]),
  _ => value,
};

/// A run's receipt as chord records and serves it: what each role was
/// saved as, planned as, and came up on; the JSON the original's
/// `SelectionReceipt` checks.
typedef SelectionReceipt = Map<String, Object?>;

bool _policyValid(Object? policy) {
  if (policy is! Map) return false;
  final parsed = parseSettings(
    'receipt',
    jsonEncode({'teamSelection': policy}),
  );
  return parsed.problems.isEmpty;
}

bool _strict(Map value, List<String> keys, List<String> required) =>
    value.keys.every(keys.contains) && required.every(value.containsKey);

bool _choiceValid(Object? value, {required bool agent}) {
  final choice = value is Map ? runChoiceOf(value) : null;
  return choice != null && (!agent || choice.containsKey('agent'));
}

bool _nullableId(Object? value) => value == null || _id(value);

bool _roleValid(Object? value) {
  if (value is! Map ||
      !_strict(
        value,
        const ['role', 'name', 'saved', 'planned', 'state', 'actual', 'note'],
        const ['role', 'name', 'saved', 'planned', 'state', 'actual', 'note'],
      )) {
    return false;
  }
  final actual = value['actual'];
  final note = value['note'];
  return const ['lead', 'member'].contains(value['role']) &&
      _id(value['name']) &&
      _choiceValid(value['saved'], agent: true) &&
      _choiceValid(value['planned'], agent: true) &&
      const ['planned', 'confirmed', 'refused'].contains(value['state']) &&
      (actual == null ||
          (actual is Map &&
              _strict(
                actual,
                const ['agent', 'model', 'effort', 'mode'],
                const ['model', 'effort', 'mode'],
              ) &&
              _nullableId(actual['agent']) &&
              _nullableId(actual['model']) &&
              _nullableId(actual['effort']) &&
              _nullableId(actual['mode']))) &&
      (note == null ||
          (note is String && note.isNotEmpty && note.length <= 500));
}

/// Whether [value] is a run's receipt, every field as the original checks
/// it.
bool isSelectionReceipt(Object? value) {
  if (value is! Map ||
      !_strict(
        value,
        const [
          'schemaVersion',
          'runId',
          'saved',
          'reason',
          'policy',
          'roles',
          'decisionRead',
          'warnings',
        ],
        const [
          'schemaVersion',
          'runId',
          'saved',
          'reason',
          'policy',
          'roles',
          'decisionRead',
          'warnings',
        ],
      )) {
    return false;
  }
  final saved = value['saved'];
  final roles = value['roles'];
  final read = value['decisionRead'];
  final warnings = value['warnings'];
  return value['schemaVersion'] == 1 &&
      _id(value['runId']) &&
      saved is Map &&
      _strict(saved, const ['name', 'place'], const ['name', 'place']) &&
      _id(saved['name']) &&
      const ['project', 'user'].contains(saved['place']) &&
      _reason(value['reason']) &&
      _policyValid(value['policy']) &&
      roles is List &&
      roles.isNotEmpty &&
      roles.length <= maxMembers + 1 &&
      roles.every(_roleValid) &&
      (read == null ||
          (read is Map &&
              _strict(
                read,
                const ['readAt', 'observationRefs'],
                const ['readAt', 'observationRefs'],
              ) &&
              isIsoTime(read['readAt']) &&
              read['observationRefs'] is List &&
              (read['observationRefs'] as List).length <= 256 &&
              (read['observationRefs'] as List).every(_id))) &&
      warnings is List &&
      warnings.length <= 256 &&
      warnings.every(
        (warning) =>
            warning is String && warning.isNotEmpty && warning.length <= 500,
      );
}

/// The receipt of a `run_team` call, only when the call is the one the
/// run was admitted as: its `asked` and its answer's id are the receipt's
/// run id. Any other call has none to show.
SelectionReceipt? recordedSelection(ChordCall call) {
  final answer = call.answer;
  if (call.tool != ChordTool.runTeam || answer is! Map) return null;
  final receipt = answer['receipt'];
  if (!isSelectionReceipt(receipt)) return null;
  final runId = (receipt as Map)['runId'];
  return call.asked == runId && answer['id'] == runId
      ? receipt.cast<String, Object?>()
      : null;
}

/// [role] with what its session came up on: refused when the runtime did
/// not confirm the runtime, model or mode planned; confirmed otherwise,
/// with [note]. Effort stays a soft request.
Map<String, Object?> confirmSelectionRole(
  Map<String, Object?> role,
  Map<String, Object?> actual, [
  String? note,
]) {
  final planned = role['planned'] as Map;
  for (final field in const ['agent', 'model', 'mode']) {
    if (field == 'agent' && !actual.containsKey('agent')) continue;
    final requested = planned[field];
    if (requested != null && actual[field] != requested) {
      return {
        ...role,
        'state': 'refused',
        'actual': {...actual},
        'note':
            '${role['name']}.$field: the runtime did not confirm the requested '
            '$field $requested.',
      };
    }
  }
  return {
    ...role,
    'state': 'confirmed',
    'actual': {...actual},
    'note': note,
  };
}

/// What a receipt says when an agent it started may not have gone.
const agentCleanupUnverified =
    'An attempted agent cleanup could not be verified; process exit is '
    'uncertain.';

/// [receipt] saying an agent it started may not have gone, once.
SelectionReceipt withSelectionCleanupWarning(SelectionReceipt receipt) {
  final warnings = (receipt['warnings'] as List).cast<String>();
  return warnings.contains(agentCleanupUnverified)
      ? receipt
      : {
          ...receipt,
          'warnings': [...warnings, agentCleanupUnverified],
        };
}

/// A run's first receipt: every role planned, nothing yet confirmed;
/// `run_team` records no resource read, as an agent calls get_budgets
/// itself.
SelectionReceipt selectionReceipt(
  String runId,
  ({String name, String place}) saved,
  FrozenSelection frozen,
) {
  RunChoice config(RoleConfig role) => _configuration(role);
  return {
    'schemaVersion': 1,
    'runId': runId,
    'saved': {'name': saved.name, 'place': saved.place},
    'reason': frozen.selection.reason,
    'policy': _orderedPolicy(frozen.policy),
    'roles': [
      for (final (kind, name, role, original) in [
        ('lead', 'lead', _ofLead(frozen.team.lead), _ofLead(frozen.saved.lead)),
        for (final (index, member) in frozen.team.members.indexed)
          (
            'member',
            member.name,
            _ofMember(member),
            _ofMember(frozen.saved.members[index]),
          ),
      ])
        {
          'role': kind,
          'name': name,
          'saved': config(original),
          'planned': config(role),
          'state': 'planned',
          'actual': null,
          'note': null,
        },
    ],
    'decisionRead': null,
    'warnings': const <String>[],
  };
}

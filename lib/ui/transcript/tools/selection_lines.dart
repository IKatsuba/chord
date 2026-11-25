/// One frozen run's evidence under its `Team(…)` row, without provider
/// payloads or invented defaults: what was selected and why, each role as
/// planned and as it came up, and, opened with ctrl+o, the saved
/// definition and what changed from it. From the original's
/// `ui/transcript/tools/selection_lines.ts`.
library;

import '../../../session/team_selection.dart';

String _configuration(Map choice) =>
    '${choice['agent'] ?? 'runtime unknown'} · model '
    '${choice['model'] ?? 'agent default (unconfirmed)'} · effort '
    '${choice['effort'] ?? 'agent default (unconfirmed)'} · mode '
    '${choice['mode'] ?? 'agent default (unconfirmed)'}';

/// The lines of [value], a run's receipt, or none when it is not one;
/// [expanded] adds the saved definition and its changes, and [recorded]
/// says the actual configurations are as the record caught them.
List<String> selectionLines(
  Object? value, {
  bool expanded = false,
  bool recorded = false,
}) {
  if (!isSelectionReceipt(value)) return const [];
  final receipt = value! as Map;
  final roles = (receipt['roles'] as List).cast<Map>();
  final read = receipt['decisionRead'] as Map?;
  final saved = receipt['saved'] as Map;
  final actualWord = recorded ? 'Actual at recording' : 'Actual';
  return [
    'Selection: agent-selected · this run',
    'Reason: ${receipt['reason']}',
    for (final warning in (receipt['warnings'] as List)) 'Warning: $warning',
    'Billing: unknown · advisory',
    'Planned for this run:',
    for (final role in roles) ...[
      '${role['name']}${role['role'] == 'lead' ? ' (lead)' : ''}: '
          '${_configuration(role['planned'] as Map)}',
      if (role['state'] == 'planned')
        '$actualWord: not opened · configuration unconfirmed'
      else
        '$actualWord: ${role['state']} · session runtime '
            '${(role['actual'] as Map?)?['agent'] ?? 'unknown'} · model '
            '${(role['actual'] as Map?)?['model'] ?? 'unknown'} · effort '
            '${(role['actual'] as Map?)?['effort'] ?? 'unknown'} · mode '
            '${(role['actual'] as Map?)?['mode'] ?? 'unknown'}',
      if (role['note'] != null) '${role['name']}: ${role['note']}',
    ],
    // run_team no longer reads; only a receipt recorded with a read shows
    // it.
    if (read != null)
      'Read ${(read['readAt'] as String).replaceFirst('T', ' ').replaceFirst('Z', ' UTC')} · advisory',
    if (expanded) ...[
      'Run: ${receipt['runId']} · saved definition: ${saved['name']} '
          '(${saved['place']})',
      for (final role in roles) ...[
        '${role['name']} saved: ${_configuration(role['saved'] as Map)}',
        () {
          final changed = [
            for (final field in const ['agent', 'model', 'effort', 'mode'])
              if ((role['saved'] as Map)[field] !=
                  (role['planned'] as Map)[field])
                field,
          ];
          return 'Changes from saved: '
              '${changed.isEmpty ? 'none' : changed.join(', ')}';
        }(),
      ],
    ] else
      'ctrl+o for saved definition and changes',
  ];
}

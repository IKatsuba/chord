/** One frozen run's evidence, without provider payloads or invented defaults. */
import {
  SelectionReceipt,
  type RunChoice,
} from '../../../session/team_selection.ts';

function configuration(choice: RunChoice): string {
  return `${choice.agent ?? 'runtime unknown'} · model ${choice.model ?? 'agent default (unconfirmed)'} · effort ${choice.effort ?? 'agent default (unconfirmed)'} · mode ${choice.mode ?? 'agent default (unconfirmed)'}`;
}

export function selectionLines(
  value: unknown,
  expanded = false,
  recorded = false,
): string[] {
  const parsed = SelectionReceipt.safeParse(value);

  if (!parsed.success) {
    return [];
  }

  const receipt = parsed.data;

  return [
    'Selection: agent-selected · this run',
    `Reason: ${receipt.reason}`,
    ...receipt.warnings.map((warning) => `Warning: ${warning}`),
    'Billing: unknown · advisory',
    'Planned for this run:',
    ...receipt.roles.flatMap((role) => [
      `${role.name}${role.role === 'lead' ? ' (lead)' : ''}: ${configuration(role.planned)}`,
      role.state === 'planned'
        ? `${recorded ? 'Actual at recording' : 'Actual'}: not opened · configuration unconfirmed`
        : `${recorded ? 'Actual at recording' : 'Actual'}: ${role.state} · session runtime ${role.actual?.agent ?? 'unknown'} · model ${role.actual?.model ?? 'unknown'} · effort ${role.actual?.effort ?? 'unknown'} · mode ${role.actual?.mode ?? 'unknown'}`,
      ...(role.note === null ? [] : [`${role.name}: ${role.note}`]),
    ]),
    // run_team no longer reads; only a receipt recorded with a read shows it.
    ...(receipt.decisionRead === null
      ? []
      : [
          `Read ${receipt.decisionRead.readAt.replace('T', ' ').replace('Z', ' UTC')} · advisory`,
        ]),
    ...(expanded
      ? [
          `Run: ${receipt.runId} · saved definition: ${receipt.saved.name} (${receipt.saved.place})`,
          ...receipt.roles.flatMap((role) => {
            const changed = (
              ['agent', 'model', 'effort', 'mode'] as const
            ).filter((field) => role.saved[field] !== role.planned[field]);

            return [
              `${role.name} saved: ${configuration(role.saved)}`,
              `Changes from saved: ${changed.length === 0 ? 'none' : changed.join(', ')}`,
            ];
          }),
        ]
      : ['ctrl+o for saved definition and changes']),
  ];
}

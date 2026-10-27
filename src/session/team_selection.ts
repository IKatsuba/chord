/** Per-run choices change configuration, never a saved team's instructions. */
import { z } from '@zod/zod';
import { MAX_MEMBERS, type Team, type TeamLead } from '../teams.ts';
import { TeamSelection, type BudgetSnapshot } from './budgets.ts';

const id = z.string().min(1).max(128);
const reason = z
  .string()
  .min(1)
  .max(500)
  .refine((text) => text.trim() !== '');

export const RunChoice = z.strictObject({
  agent: id.optional(),
  model: id.optional(),
  effort: id.optional(),
  mode: id.optional(),
});

export type RunChoice = z.infer<typeof RunChoice>;

export const RunSelection = z.strictObject({
  reason,
  lead: RunChoice.optional(),
  members: z
    .record(id, RunChoice)
    .refine((members) => Object.keys(members).length <= MAX_MEMBERS)
    .optional(),
});

export type RunSelection = z.infer<typeof RunSelection>;

/** Undefined lists mean unknown capabilities, while empty lists deny choices. */
export interface SelectionCapabilities {
  readonly models?: readonly {
    readonly id: string;
    readonly efforts?: readonly { readonly id: string }[];
  }[];
  readonly modes?: readonly { readonly id: string }[];
  readonly efforts?: readonly { readonly id: string }[];
}

export interface FrozenSelection {
  readonly saved: Team;
  readonly team: Team;
  readonly policy: TeamSelection;
  readonly selection: RunSelection;
}

function refusal(role: string, field: string, message: string): string {
  return `${role}.${field}: ${message}. No run started. Choose a supported configuration.`;
}

function mergeChoice(
  role: string,
  saved: TeamLead,
  choice: RunChoice = {},
): { choice: TeamLead } | { error: string } {
  const defined = Object.fromEntries(
    Object.entries(choice).filter(([, value]) => value !== undefined),
  );

  if (choice.agent === undefined || choice.agent === saved.agent) {
    return { choice: { ...saved, ...defined, agent: saved.agent } };
  }

  for (const field of ['model', 'mode', 'effort'] as const) {
    if (
      choice[field] === undefined &&
      (field !== 'effort' || saved.effort !== undefined)
    ) {
      return {
        error: refusal(
          role,
          field,
          'a runtime change requires an explicit destination value',
        ),
      };
    }
  }

  const prose = { ...saved };

  delete prose.model;
  delete prose.mode;
  delete prose.effort;

  return { choice: { ...prose, ...defined, agent: choice.agent } };
}

/** Validate every selected role; direct runs deliberately do not call this. */
export function validateSelectedRole(
  role: string,
  choice: TeamLead,
  policy: TeamSelection,
  runtimes: readonly string[],
  capabilities?: SelectionCapabilities,
  explicit: RunChoice = {},
): string | undefined {
  if (!runtimes.includes(choice.agent)) {
    return refusal(role, 'agent', 'the selected runtime is not configured');
  }

  const constraints = policy.constraints;

  for (const [field, allowed, value] of [
    ['agent', constraints?.agents, choice.agent],
    ['model', constraints?.models?.[choice.agent], choice.model],
    ['mode', constraints?.modes?.[choice.agent], choice.mode],
  ] as const) {
    if (
      allowed !== undefined &&
      (value === undefined || !allowed.includes(value))
    ) {
      return refusal(
        role,
        field,
        'the choice is outside the configured allowlist',
      );
    }
  }

  for (const [field, available, value] of [
    ['model', capabilities?.models, choice.model],
    ['mode', capabilities?.modes, choice.mode],
  ] as const) {
    if (
      value !== undefined &&
      available !== undefined &&
      !available.some((one) => one.id === value)
    ) {
      return refusal(
        role,
        field,
        `${value} is not supported by the selected runtime`,
      );
    }
  }

  // Effort is model-specific; another model's advertised efforts prove nothing.
  const efforts =
    choice.model === undefined
      ? capabilities?.efforts
      : capabilities?.models?.find((model) => model.id === choice.model)
          ?.efforts;

  if (
    explicit.effort !== undefined &&
    efforts !== undefined &&
    !efforts.some((one) => one.id === explicit.effort)
  ) {
    return refusal(
      role,
      'effort',
      `${explicit.effort} is not supported by the selected model`,
    );
  }

  return undefined;
}

/** Clone before freezing so later file reads and callers cannot change a run. */
export function freezeSelection(
  saved: Team,
  selection: RunSelection,
  policy: TeamSelection,
  runtimes: readonly string[],
  capabilities: ReadonlyMap<string, SelectionCapabilities> = new Map(),
): { frozen: FrozenSelection } | { error: string } {
  const parsed = RunSelection.safeParse(selection);

  if (!parsed.success) {
    return { error: 'Invalid run selection. No run started.' };
  }

  for (const name of Object.keys(parsed.data.members ?? {})) {
    if (!saved.members.some((member) => member.name === name)) {
      return { error: `Unknown selected member ${name}. No run started.` };
    }
  }

  const team = structuredClone(saved);

  for (const [name, savedRole, override] of [
    ['lead', team.lead, parsed.data.lead],
    ...team.members.map(
      (member) =>
        [member.name, member, parsed.data.members?.[member.name]] as const,
    ),
  ] as const) {
    // Saved values remain in the receipt even when an override replaces them.
    const represented = RunChoice.safeParse(configuration(savedRole));

    if (!represented.success) {
      const field = String(represented.error.issues[0]?.path[0] ?? 'agent');

      return {
        error: refusal(
          name,
          field,
          'the saved value cannot fit a bounded run receipt',
        ),
      };
    }

    const merged = mergeChoice(name, savedRole, override);

    if ('error' in merged) {
      return merged;
    }

    const error = validateSelectedRole(
      name,
      merged.choice,
      policy,
      runtimes,
      capabilities.get(merged.choice.agent),
      override,
    );

    if (error !== undefined) {
      return { error };
    }

    Object.assign(savedRole, merged.choice);

    // Assigning cannot remove old-runtime fields, so remove only configuration.
    for (const field of ['model', 'mode', 'effort'] as const) {
      if (merged.choice[field] === undefined) {
        delete savedRole[field];
      }
    }
  }

  const frozen = {
    saved: structuredClone(saved),
    team,
    policy: TeamSelection.parse(policy),
    selection: parsed.data,
  };

  freezeValues(frozen);

  return { frozen };
}

function freezeValues(value: object): void {
  for (const child of Object.values(value)) {
    if (child !== null && typeof child === 'object') {
      freezeValues(child);
    }
  }

  Object.freeze(value);
}

const actual = z.strictObject({
  model: id.nullable(),
  effort: id.nullable(),
  mode: id.nullable(),
});

export const SelectionReceipt = z.strictObject({
  schemaVersion: z.literal(1),
  runId: id,
  saved: z.strictObject({ name: id, place: z.enum(['project', 'user']) }),
  reason,
  policy: TeamSelection,
  roles: z
    .array(
      z.strictObject({
        role: z.enum(['lead', 'member']),
        name: id,
        saved: RunChoice.required({ agent: true }),
        planned: RunChoice.required({ agent: true }),
        state: z.enum(['planned', 'confirmed', 'refused']),
        actual: actual.nullable(),
        note: z.string().min(1).max(500).nullable(),
      }),
    )
    .min(1)
    .max(MAX_MEMBERS + 1),
  decisionRead: z
    .strictObject({
      readAt: z.iso.datetime(),
      observationRefs: z.array(id).max(256),
    })
    .nullable(),
  warnings: z.array(z.string().min(1).max(500)).max(256),
});

export type SelectionReceipt = z.infer<typeof SelectionReceipt>;

function configuration(role: TeamLead): RunChoice & { agent: string } {
  return {
    agent: role.agent,
    ...(role.model === undefined ? {} : { model: role.model }),
    ...(role.mode === undefined ? {} : { mode: role.mode }),
    ...(role.effort === undefined ? {} : { effort: role.effort }),
  };
}

/** Exact model/mode need confirmation; effort remains a visible soft request. */
export function confirmSelectionRole(
  role: SelectionReceipt['roles'][number],
  actual: NonNullable<SelectionReceipt['roles'][number]['actual']>,
  note: string | null = null,
): SelectionReceipt['roles'][number] {
  for (const field of ['model', 'mode'] as const) {
    const requested = role.planned[field];

    if (requested !== undefined && actual[field] !== requested) {
      return {
        ...role,
        state: 'refused',
        actual: { ...actual },
        note: `${role.name}.${field}: the runtime did not confirm the requested ${field} ${requested}.`,
      };
    }
  }

  return { ...role, state: 'confirmed', actual: { ...actual }, note };
}

/** Only a response actually served to this caller can be decision provenance. */
export function selectionReceipt(
  runId: string,
  saved: SelectionReceipt['saved'],
  frozen: FrozenSelection,
  decisionRead?: BudgetSnapshot,
): SelectionReceipt {
  const refs =
    decisionRead === undefined
      ? []
      : [
          ...new Set([
            ...decisionRead.pools.map((pool) => pool.poolRef),
            ...decisionRead.unbound.map(
              (observation) => observation.observationRef,
            ),
          ]),
        ];
  const warnings =
    decisionRead === undefined
      ? ['No resource decision read was recorded; capacity is unknown.']
      : [...decisionRead.warnings];

  if (refs.length > 256) {
    warnings.push('Decision observation references are incomplete.');
  }

  if (decisionRead?.unavailable.length) {
    warnings.push(
      'Some referenced resource sources are unavailable; capacity is unknown.',
    );
  }

  if (decisionRead?.unbound.length) {
    warnings.push(
      'Resource identity is unverified; observations remain separate.',
    );
  }

  const uniqueWarnings = [...new Set(warnings)];

  if (uniqueWarnings.length > 256) {
    uniqueWarnings.splice(
      255,
      Infinity,
      'Additional resource warnings are omitted.',
    );
  }

  const receipt = SelectionReceipt.parse({
    schemaVersion: 1,
    runId,
    saved,
    reason: frozen.selection.reason,
    policy: frozen.policy,
    roles: [
      ['lead', 'lead', frozen.team.lead, frozen.saved.lead] as const,
      ...frozen.team.members.map(
        (member, index) =>
          [
            'member',
            member.name,
            member,
            frozen.saved.members[index]!,
          ] as const,
      ),
    ].map(([kind, name, role, original]) => ({
      role: kind,
      name,
      saved: configuration(original),
      planned: configuration(role),
      state: 'planned',
      actual: null,
      note: null,
    })),
    decisionRead:
      decisionRead === undefined
        ? null
        : {
            readAt: decisionRead.observedAt,
            observationRefs: refs.slice(0, 256),
          },
    warnings: uniqueWarnings,
  });

  freezeValues(receipt);

  return receipt;
}

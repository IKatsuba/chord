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
  agent: id
    .optional()
    .describe(
      'Runtime ID from list_agents; omitted fields inherit saved values only on the same runtime. A runtime change requires destination model and mode, plus effort when the saved role requests it.',
    ),
  model: id
    .optional()
    .describe('Supported destination model ID; no cross-runtime inheritance.'),
  effort: id
    .optional()
    .describe(
      'Supported soft effort request, never an exact-effort guarantee.',
    ),
  mode: id
    .optional()
    .describe(
      'Supported exact destination mode ID; do not infer permission equivalence across runtimes.',
    ),
});

export type RunChoice = z.infer<typeof RunChoice>;

export const RunSelection = z
  .strictObject({
    reason: reason.describe(
      'Explain the per-run choice, uncertainties and preservation of all saved role/instruction requirements.',
    ),
    lead: RunChoice.optional().describe(
      'Overrides for the saved lead in this run only.',
    ),
    members: z
      .record(id, RunChoice)
      .refine((members) => Object.keys(members).length <= MAX_MEMBERS)
      .optional()
      .describe(
        'Overrides keyed by existing saved member names; preserve every member and instruction.',
      ),
  })
  .describe(
    'Optional frozen per-run configuration. Current hard constraints apply to every effective selected role, including inherited roles: omitted constraints add no restriction, an explicit empty allowlist denies. Omitted selection uses the unchanged direct saved path outside selection policy. Preferences are advisory, not permission or payment grants. Unknown fields or member names refuse before launch; no null/reset shorthand.',
  );

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

function refusal(
  role: string,
  field: string,
  message: string,
  admission: 'run' | 'member' = 'run',
): string {
  return `${role}.${field}: ${message}. ${admission === 'run' ? 'No run started. Choose a supported configuration.' : 'This member was not started.'}`;
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
  admission: 'run' | 'member' = 'run',
): string | undefined {
  if (!runtimes.includes(choice.agent)) {
    return refusal(
      role,
      'agent',
      'the selected runtime is not configured',
      admission,
    );
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
        admission,
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
        admission,
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
      admission,
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
  agent: id.nullable().optional(),
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

/** Only a receipt tied to its actual admitted call is inspectable history. */
export function recordedSelection(call: {
  readonly tool: string;
  readonly asked?: string;
  readonly answer?: unknown;
}): SelectionReceipt | undefined {
  const answer = call.answer;

  if (
    call.tool !== 'run_team' ||
    typeof answer !== 'object' ||
    answer === null ||
    !('receipt' in answer)
  ) {
    return undefined;
  }

  const parsed = SelectionReceipt.safeParse(answer.receipt);

  return parsed.success &&
    call.asked === parsed.data.runId &&
    'id' in answer &&
    answer.id === parsed.data.runId
    ? parsed.data
    : undefined;
}

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
  for (const field of ['agent', 'model', 'mode'] as const) {
    if (field === 'agent' && actual.agent === undefined) {
      continue;
    }

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

function boundedWarnings(
  warnings: readonly string[],
  required: readonly string[] = [],
): string[] {
  const unique = [...new Set([...warnings, ...required])];

  if (unique.length <= 256) {
    return unique;
  }

  const tail = [
    ...new Set(['Additional resource warnings are omitted.', ...required]),
  ];

  return [
    ...unique
      .filter((warning) => !tail.includes(warning))
      .slice(0, 256 - tail.length),
    ...tail,
  ];
}

/** Cleanup uncertainty cannot disappear behind a full source warning list. */
export function withSelectionCleanupWarning(
  receipt: SelectionReceipt,
): SelectionReceipt {
  return {
    ...receipt,
    warnings: boundedWarnings(receipt.warnings, [
      'An attempted agent cleanup could not be verified; process exit is uncertain.',
    ]),
  };
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

  const sources = [
    ...(decisionRead?.pools ?? []),
    ...(decisionRead?.unbound ?? []),
  ];

  if (
    sources.some(
      (source) =>
        source.coverage !== 'account' || source.externalActivity === 'unknown',
    )
  ) {
    warnings.push(
      'Resource coverage is incomplete; external work may be missing.',
    );
  }

  const windows = sources.flatMap((source) => source.windows);

  if (windows.some((window) => window.state === 'stale')) {
    warnings.push(
      'Some resource windows are stale; current capacity is unknown.',
    );
  }

  if (windows.some((window) => window.state === 'unknown')) {
    warnings.push('Provider freshness is unknown for some resource windows.');
  }

  if (windows.some((window) => window.state === 'unsupported')) {
    warnings.push(
      'Some resource windows are unsupported; capacity is unknown.',
    );
  }

  const uniqueWarnings = boundedWarnings(warnings);

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

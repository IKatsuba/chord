import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  confirmSelectionRole,
  freezeSelection,
  RunChoice,
  RunSelection,
  selectionReceipt,
  SelectionReceipt,
  validateSelectedRole,
  withSelectionCleanupWarning,
} from '../../src/session/team_selection.ts';
import type { Team } from '../../src/teams.ts';
import type { BudgetSnapshot } from '../../src/session/budgets.ts';

const saved: Team = {
  description: 'Selection fixture.',
  lead: {
    agent: 'codex',
    model: 'old-model',
    mode: 'old-mode',
    effort: 'high',
    instructions: 'Lead exactly as written.\nKeep permissions.',
  },
  members: [
    {
      name: 'reviewer',
      role: 'Review byte for byte',
      instructions: 'Read-only review.\nDo not edit.',
      agent: 'codex',
      model: 'old-model',
      mode: 'old-mode',
    },
  ],
  body: '# Handoffs\n\nPreserve QA and permission requirements.\n',
};
const runtimes = ['codex', 'claude'];
const reason = 'Preserve every role and permission; capacity is unknown.';

describe('strict per-run selection', () => {
  test('unrepresentable inherited and overridden saved IDs fail before freezing', () => {
    for (const field of ['agent', 'model', 'mode', 'effort'] as const) {
      const source = structuredClone(saved);

      source.lead[field] = 'x'.repeat(129);

      for (const override of [
        undefined,
        { agent: 'claude', model: 'sonnet', mode: 'plan', effort: 'medium' },
      ]) {
        expect(
          freezeSelection(
            source,
            { reason, ...(override === undefined ? {} : { lead: override }) },
            {},
            runtimes,
          ),
        ).toEqual({
          error: `lead.${field}: the saved value cannot fit a bounded run receipt. No run started. Choose a supported configuration.`,
        });
      }

      const memberSource = structuredClone(saved);

      memberSource.members[0]![field] = 'x'.repeat(129);

      expect(freezeSelection(memberSource, { reason }, {}, runtimes)).toEqual({
        error: `reviewer.${field}: the saved value cannot fit a bounded run receipt. No run started. Choose a supported configuration.`,
      });
    }
  });

  test('boundary-length saved IDs remain unchanged and produce a valid receipt', () => {
    const source = structuredClone(saved);

    source.lead.model = 'm'.repeat(128);
    source.lead.effort = 'e'.repeat(128);
    source.lead.mode = 'p'.repeat(128);

    const result = freezeSelection(source, { reason }, {}, runtimes);

    assert('frozen' in result);
    expect(
      selectionReceipt(
        'run',
        { name: 'fixture', place: 'project' },
        result.frozen,
      ).roles[0]?.saved,
    ).toEqual({
      agent: 'codex',
      model: source.lead.model,
      effort: source.lead.effort,
      mode: source.lead.mode,
    });
  });

  test('rejects unknown keys, null shorthand, blank reasons and oversized input', () => {
    for (const value of [
      { agent: null },
      { model: null },
      { mode: null },
      { effort: null },
      { command: 'other' },
      { agent: '' },
      { model: 'm'.repeat(129) },
    ]) {
      expect(RunChoice.safeParse(value).success).toBe(false);
    }

    for (const value of [
      {},
      { reason: '' },
      { reason: ' \n ' },
      { reason: 'r'.repeat(501) },
      { reason, extra: true },
      {
        reason,
        members: Object.fromEntries(
          Array.from({ length: 9 }, (_, i) => [`member${i}`, {}]),
        ),
      },
    ]) {
      expect(RunSelection.safeParse(value).success).toBe(false);
    }

    expect(
      RunSelection.parse({ reason: 'r'.repeat(500), lead: {} }).reason,
    ).toHaveLength(500);
  });

  test('same-runtime omission inherits saved values and freezes an independent copy', () => {
    const source = structuredClone(saved);
    const policy = { constraints: { agents: ['codex'] } };
    const result = freezeSelection(
      source,
      { reason, lead: { model: 'new-model' } },
      policy,
      runtimes,
    );

    assert('frozen' in result);
    expect(result.frozen.team.lead).toEqual({
      ...saved.lead,
      model: 'new-model',
    });
    expect(result.frozen.team.members).toEqual(saved.members);
    expect(result.frozen.team.body).toBe(saved.body);
    expect(source).toEqual(saved);

    source.members[0]!.instructions = 'changed after launch';

    policy.constraints.agents.push('claude');
    expect(result.frozen.team.members[0]?.instructions).toBe(
      saved.members[0]?.instructions,
    );
    expect(result.frozen.policy.constraints?.agents).toEqual(['codex']);
    expect(Object.isFrozen(result.frozen.team.members)).toBe(true);
    expect(Object.isFrozen(result.frozen.team.members[0])).toBe(true);
    expect(Object.isFrozen(result.frozen.selection)).toBe(true);
  });

  test('runtime change requires destination model/mode and requested effort', () => {
    for (const field of ['model', 'mode', 'effort'] as const) {
      const choice = {
        agent: 'claude',
        model: 'sonnet',
        mode: 'plan',
        effort: 'medium',
      };
      const { [field]: omitted, ...incomplete } = choice;

      expect(omitted).toBeDefined();
      expect(
        freezeSelection(saved, { reason, lead: incomplete }, {}, runtimes),
      ).toEqual({
        error: `lead.${field}: a runtime change requires an explicit destination value. No run started. Choose a supported configuration.`,
      });
    }
  });

  test('runtime change drops incompatible fields and never changes role prose', () => {
    const result = freezeSelection(
      saved,
      {
        reason,
        lead: {
          agent: 'claude',
          model: 'sonnet',
          mode: 'plan',
          effort: 'medium',
        },
        members: {
          reviewer: { agent: 'claude', model: 'sonnet', mode: 'plan' },
        },
      },
      {},
      runtimes,
    );

    assert('frozen' in result);
    expect(result.frozen.team.lead).toEqual({
      ...saved.lead,
      agent: 'claude',
      model: 'sonnet',
      mode: 'plan',
      effort: 'medium',
    });
    expect(result.frozen.team.members[0]).toEqual({
      ...saved.members[0]!,
      agent: 'claude',
      model: 'sonnet',
      mode: 'plan',
    });
    expect(result.frozen.team.members[0]).not.toHaveProperty('effort');
    expect(result.frozen.team.body).toBe(saved.body);
  });

  test('unknown member names and unconfigured runtimes fail before any run', () => {
    expect(
      freezeSelection(saved, { reason, members: { ghost: {} } }, {}, runtimes),
    ).toEqual({ error: 'Unknown selected member ghost. No run started.' });

    const result = freezeSelection(
      saved,
      {
        reason,
        lead: {
          agent: 'missing',
          model: 'model',
          mode: 'mode',
          effort: 'high',
        },
      },
      {},
      runtimes,
    );

    assert('error' in result);
    expect(result.error).toContain(
      'lead.agent: the selected runtime is not configured',
    );
  });

  test('hard allowlists cover unchanged members as well as explicitly overridden roles', () => {
    const result = freezeSelection(
      saved,
      { reason, lead: { model: 'new-model' } },
      {
        constraints: { models: { codex: ['new-model'] } },
      },
      runtimes,
    );

    assert('error' in result);
    expect(result.error).toContain(
      'reviewer.model: the choice is outside the configured allowlist',
    );
  });

  test('empty lists deny and omission adds no constraint or cross-runtime mode mapping', () => {
    for (const constraints of [
      { agents: [] },
      { models: { codex: [] } },
      { modes: { codex: [] } },
    ]) {
      expect(
        freezeSelection(saved, { reason }, { constraints }, runtimes),
      ).toHaveProperty('error');
    }

    expect(
      freezeSelection(
        saved,
        { reason },
        { constraints: { modes: { claude: [] } } },
        runtimes,
      ),
    ).toHaveProperty('frozen');
    expect(freezeSelection(saved, { reason }, {}, runtimes)).toHaveProperty(
      'frozen',
    );
    expect(
      freezeSelection(
        saved,
        { reason },
        { constraints: { modes: { codex: ['plan'] } } },
        runtimes,
      ),
    ).toHaveProperty('error');
  });

  test('configured model/mode restrictions require explicit or inherited values', () => {
    expect(
      validateSelectedRole(
        'lead',
        { agent: 'codex' },
        { constraints: { models: { codex: ['old-model'] } } },
        runtimes,
      ),
    ).toContain('lead.model');
    expect(
      validateSelectedRole(
        'lead',
        { agent: 'codex' },
        { constraints: { modes: { codex: ['old-mode'] } } },
        runtimes,
      ),
    ).toContain('lead.mode');
  });

  test('known unsupported mode has the design refusal; unknown capability remains unconfirmed', () => {
    expect(
      validateSelectedRole(
        'reviewer',
        { agent: 'claude', mode: 'plan' },
        {},
        runtimes,
        { modes: [{ id: 'auto' }] },
      ),
    ).toBe(
      'reviewer.mode: plan is not supported by the selected runtime. No run started. Choose a supported configuration.',
    );
    expect(
      validateSelectedRole(
        'reviewer',
        { agent: 'claude', mode: 'plan' },
        {},
        runtimes,
      ),
    ).toBeUndefined();
    expect(
      validateSelectedRole(
        'reviewer',
        { agent: 'claude', model: 'sonnet' },
        {},
        runtimes,
        { models: [] },
      ),
    ).toContain('reviewer.model');
  });

  test('only known support for the selected model can reject a new soft effort', () => {
    const choice = { agent: 'codex', model: 'new-model', effort: 'high' };
    const capabilities = {
      models: [
        { id: 'old-model', efforts: [{ id: 'low' }] },
        { id: 'new-model' },
      ],
      efforts: [{ id: 'low' }],
    };

    expect(
      validateSelectedRole('lead', choice, {}, runtimes, capabilities, {
        effort: 'high',
      }),
    ).toBeUndefined();
    expect(
      validateSelectedRole(
        'lead',
        choice,
        {},
        runtimes,
        { models: [{ id: 'new-model', efforts: [] }] },
        { effort: 'high' },
      ),
    ).toContain('lead.effort');
    expect(
      validateSelectedRole('lead', choice, {}, runtimes, {
        models: [{ id: 'new-model', efforts: [] }],
      }),
    ).toBeUndefined();
  });
});

describe('selection decision receipts', () => {
  function frozen() {
    const result = freezeSelection(saved, { reason }, {}, runtimes);

    assert('frozen' in result);

    return result.frozen;
  }

  test('unopened roles are planned, with no actual/default claims or invented decision read', () => {
    const receipt = selectionReceipt(
      'run-1',
      { name: 'fixture', place: 'project' },
      frozen(),
    );

    expect(
      receipt.roles.map((role) => [role.name, role.state, role.actual]),
    ).toEqual([
      ['lead', 'planned', null],
      ['reviewer', 'planned', null],
    ]);
    expect(receipt.decisionRead).toBeNull();
    expect(receipt.warnings).toEqual([
      'No resource decision read was recorded; capacity is unknown.',
    ]);
    expect(receipt.reason).toBe(reason);
    expect(receipt.roles[0]?.planned).not.toHaveProperty('instructions');
    expect(SelectionReceipt.parse(JSON.parse(JSON.stringify(receipt)))).toEqual(
      receipt,
    );
    expect(Object.isFrozen(receipt.roles[0]?.planned)).toBe(true);
  });

  test('unknown or mismatched exact model/mode refuses; actual effort may differ', () => {
    const receipt = selectionReceipt(
      'run-1',
      { name: 'fixture', place: 'project' },
      frozen(),
    );
    const role = receipt.roles[0];

    assert(role !== undefined);

    for (const actual of [
      { model: null, mode: 'old-mode', effort: null },
      { model: 'other', mode: 'old-mode', effort: 'high' },
      { model: 'old-model', mode: null, effort: 'high' },
      { model: 'old-model', mode: 'other', effort: 'high' },
    ]) {
      expect(confirmSelectionRole(role, actual).state).toBe('refused');
    }

    const confirmed = confirmSelectionRole(
      role,
      { model: 'old-model', mode: 'old-mode', effort: 'low' },
      'Requested effort was refused.',
    );

    expect(confirmed.state).toBe('confirmed');
    expect(confirmed.actual?.effort).toBe('low');
    expect(confirmed.note).toBe('Requested effort was refused.');
    expect(role.state).toBe('planned');
    expect(role.actual).toBeNull();
  });

  test('omitted model/mode can confirm startup while retaining unknown actual defaults', () => {
    const role: SelectionReceipt['roles'][number] = {
      role: 'lead',
      name: 'lead',
      saved: { agent: 'codex' },
      planned: { agent: 'codex' },
      state: 'planned',
      actual: null,
      note: null,
    };

    expect(
      confirmSelectionRole(role, { model: null, mode: null, effort: null }),
    ).toEqual({
      ...role,
      state: 'confirmed',
      actual: { model: null, mode: null, effort: null },
    });
  });

  test('decision provenance retains actual served read time and only normalized references', () => {
    const read: BudgetSnapshot = {
      schemaVersion: 1,
      observedAt: '2026-10-27T13:00:00Z',
      preferences: {},
      pools: [],
      unbound: [
        {
          observationRef: 'observed-one',
          sourceRef: 'source-one',
          sessionRef: 'session-one',
          agent: 'codex',
          observedAt: null,
          billingKind: 'unknown',
          reason: 'Identity unverified.',
          source: 'official',
          sourceVersion: 'fixture',
          coverage: 'unknown',
          externalActivity: 'unknown',
          windows: [],
        },
      ],
      activeRuns: [],
      unavailable: [],
      warnings: ['Coverage is unknown.'],
    };
    const receipt = selectionReceipt(
      'run-1',
      { name: 'fixture', place: 'user' },
      frozen(),
      read,
    );

    expect(receipt.decisionRead).toEqual({
      readAt: read.observedAt,
      observationRefs: ['observed-one'],
    });
    expect(receipt.warnings).toEqual([
      ...read.warnings,
      'Resource identity is unverified; observations remain separate.',
      'Resource coverage is incomplete; external work may be missing.',
    ]);
    expect(JSON.stringify(receipt)).not.toContain('source-one');
    expect(JSON.stringify(receipt)).not.toContain('session-one');
    read.warnings.push('Later mutation.');
    expect(receipt.warnings).toEqual([
      'Coverage is unknown.',
      'Resource identity is unverified; observations remain separate.',
      'Resource coverage is incomplete; external work may be missing.',
    ]);
  });
});

describe('tester: selected receipt bounds and role isolation', () => {
  test('an overridden member saved value must still fit its historical receipt without mutating the team', () => {
    for (const field of ['agent', 'model', 'mode', 'effort'] as const) {
      const source = structuredClone(saved);

      source.members[0]![field] = 'x'.repeat(129);

      const before = structuredClone(source);
      const result = freezeSelection(
        source,
        {
          reason,
          members: {
            reviewer: {
              agent: 'claude',
              model: 'sonnet',
              mode: 'plan',
              effort: 'medium',
            },
          },
        },
        {},
        runtimes,
      );

      expect(result).toEqual({
        error: `reviewer.${field}: the saved value cannot fit a bounded run receipt. No run started. Choose a supported configuration.`,
      });
      expect(source).toEqual(before);
    }
  });

  test('known capabilities reject an unchanged member even when the overridden lead is supported', () => {
    const before = structuredClone(saved);
    const result = freezeSelection(
      saved,
      {
        reason,
        lead: {
          agent: 'claude',
          model: 'sonnet',
          mode: 'plan',
          effort: 'medium',
        },
      },
      {},
      runtimes,
      new Map([
        [
          'claude',
          {
            models: [{ id: 'sonnet', efforts: [{ id: 'medium' }] }],
            modes: [{ id: 'plan' }],
          },
        ],
        ['codex', { models: [{ id: 'old-model' }], modes: [{ id: 'auto' }] }],
      ]),
    );

    assert('error' in result);
    expect(result.error).toContain('reviewer.mode: old-mode is not supported');
    expect(saved).toEqual(before);
  });

  test('receipt warning overflow is explicit and duplicate served observation refs count once', () => {
    const selected = freezeSelection(saved, { reason }, {}, runtimes);

    assert('frozen' in selected);

    const observation: BudgetSnapshot['unbound'][number] = {
      observationRef: 'same-observation',
      sourceRef: 'source',
      sessionRef: 'session',
      agent: 'codex',
      source: 'fixture',
      sourceVersion: '1',
      observedAt: null,
      billingKind: 'unknown',
      coverage: 'unknown',
      externalActivity: 'unknown',
      windows: [],
      reason: 'Identity unverified.',
    };
    const read: BudgetSnapshot = {
      schemaVersion: 1,
      observedAt: '2026-10-27T13:00:00Z',
      preferences: {},
      pools: [],
      unbound: [observation, { ...observation, sourceRef: 'other-source' }],
      unavailable: [{ agent: 'claude', reason: 'Fixture unavailable.' }],
      activeRuns: [],
      warnings: Array.from(
        { length: 256 },
        (_, index) => `Fixture warning ${index}.`,
      ),
    };
    const receipt = selectionReceipt(
      'run',
      { name: 'fixture', place: 'project' },
      selected.frozen,
      read,
    );

    expect(receipt.decisionRead).toEqual({
      readAt: read.observedAt,
      observationRefs: ['same-observation'],
    });
    expect(receipt.warnings).toHaveLength(256);
    expect(receipt.warnings.at(-1)).toBe(
      'Additional resource warnings are omitted.',
    );
    expect(read.warnings.at(-1)).toBe('Fixture warning 255.');
    expect(SelectionReceipt.safeParse(receipt).success).toBe(true);
  });

  test('actual confirmation copies runtime values without changing planned or unopened roles', () => {
    const selected = freezeSelection(saved, { reason }, {}, runtimes);

    assert('frozen' in selected);

    const receipt = selectionReceipt(
      'run',
      { name: 'fixture', place: 'user' },
      selected.frozen,
    );
    const actual = { model: 'old-model', mode: 'old-mode', effort: 'low' };
    const confirmed = confirmSelectionRole(
      receipt.roles[0]!,
      actual,
      'Soft effort refused.',
    );

    actual.effort = 'medium';
    actual.model = 'later-model';

    expect(confirmed).toMatchObject({
      state: 'confirmed',
      actual: { model: 'old-model', mode: 'old-mode', effort: 'low' },
      note: 'Soft effort refused.',
    });
    expect(receipt.roles.map((role) => [role.state, role.actual])).toEqual([
      ['planned', null],
      ['planned', null],
    ]);
    expect(receipt.roles[0]?.planned.effort).toBe('high');
  });
});

test('cleanup warning preserves explicit omission and uncertainty within the receipt cap without mutating the plan', () => {
  const chosen = freezeSelection(
    saved,
    { reason: 'Preserve all instructions.' },
    {},
    ['codex', 'claude'],
  );

  assert('frozen' in chosen);

  const initial = selectionReceipt(
    'actual-run',
    { name: 'fixture', place: 'project' },
    chosen.frozen,
  );
  const receipt = {
    ...initial,
    warnings: [
      ...Array.from(
        { length: 255 },
        (_, index) => `Source uncertainty ${index}.`,
      ),
      'Additional resource warnings are omitted.',
    ],
  };
  const changed = withSelectionCleanupWarning(receipt);

  expect(changed.warnings).toHaveLength(256);
  expect(new Set(changed.warnings).size).toBe(256);
  expect(changed.warnings).toContain(
    'Additional resource warnings are omitted.',
  );
  expect(changed.warnings).toContain(
    'An attempted agent cleanup could not be verified; process exit is uncertain.',
  );
  expect(withSelectionCleanupWarning(changed).warnings).toEqual(
    changed.warnings,
  );
  expect(receipt.warnings).toHaveLength(256);
  expect(receipt.warnings).not.toContain(
    'An attempted agent cleanup could not be verified; process exit is uncertain.',
  );
  expect(changed.roles).toBe(receipt.roles);
  expect(changed.policy).toBe(receipt.policy);
  expect(SelectionReceipt.safeParse(changed).success).toBe(true);
});

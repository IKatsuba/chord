/** One advisory report, preserving independent windows and explicit uncertainty. */
import {
  BudgetSnapshot,
  type WindowSnapshot,
} from '../../../session/budgets.ts';

function utc(value: string, read: string, seconds = false): string {
  const date = new Date(value);
  const time = date.toISOString().slice(11, seconds ? 19 : 16);

  return `${value.slice(0, 10) === read.slice(0, 10) ? '' : `${date.toISOString().slice(0, 10)} `}${time} UTC`;
}

function duration(seconds: number | null): string {
  if (seconds === null) {
    return 'window duration unknown';
  }

  for (const [unit, size] of [
    ['d', 86400],
    ['h', 3600],
    ['m', 60],
  ] as const) {
    if (seconds % size === 0) {
      return `${seconds / size}${unit}`;
    }
  }

  return `${seconds}s`;
}

function windowLines(window: WindowSnapshot, read: string): string[] {
  const age =
    window.receivedAt === null
      ? null
      : Math.floor((Date.parse(read) - Date.parse(window.receivedAt)) / 1000);
  const receipt =
    age === null || age < 0
      ? 'Received time unknown'
      : `Received ${age}s before read`;
  const freshness =
    window.state === 'unsupported'
      ? 'provider freshness unsupported'
      : window.state === 'stale'
        ? 'provider observation stale'
        : window.state === 'fresh' && window.observedAt !== null
          ? `provider observation ${utc(window.observedAt, read, true)} · fresh`
          : 'provider freshness unknown';

  return [
    `${duration(window.windowSeconds)}: ${window.usedPercent === null ? 'usage unknown' : `${window.usedPercent}% used`} · reset ${window.resetsAt === null ? 'unknown' : utc(window.resetsAt, read)} · ${window.models === null ? 'models unknown' : `models ${window.models.join(', ') || 'none'}`}`,
    `${receipt} · ${freshness}`,
    ...(window.reason === null ? [] : [`Warning: ${window.reason}`]),
  ];
}

export function resourceLines(value: unknown): string[] {
  const parsed = BudgetSnapshot.safeParse(value);

  if (!parsed.success) {
    return ['No usable quota observations; capacity unknown.'];
  }

  const facts = parsed.data;
  const preferences = facts.preferences;
  const lines = [
    `Preferences: ${preferences.intent ?? 'fixed'}${preferences.intent === 'prefer' ? ` · ${[preferences.prefer?.agent, preferences.prefer?.model].filter((item) => item !== null && item !== undefined).join(' / ') || 'no soft preference configured'}` : ''}`,
  ];
  const constraints = preferences.constraints;

  if (constraints?.agents !== undefined) {
    lines.push(`Allowed agents: ${constraints.agents.join(', ') || 'none'}`);
  }

  for (const kind of ['models', 'modes'] as const) {
    for (const [agent, values] of Object.entries(constraints?.[kind] ?? {})) {
      lines.push(`Allowed ${kind} (${agent}): ${values.join(', ') || 'none'}`);
    }
  }

  lines.push(
    `Read: ${utc(facts.observedAt, facts.observedAt, true)} · advisory snapshot`,
  );

  for (const pool of facts.pools) {
    lines.push(
      `${pool.provider} · ${pool.billing} · identity verified`,
      `Source: ${pool.source} ${pool.sourceVersion} · coverage ${pool.coverage} · external activity ${pool.externalActivity}`,
      ...pool.windows.flatMap((window) =>
        windowLines(window, facts.observedAt),
      ),
    );
  }

  for (const source of facts.unbound) {
    lines.push(
      `${source.agent} · ${source.billingKind === 'unknown' ? 'billing unknown' : source.billingKind} · identity unverified`,
      `Source: ${source.source} ${source.sourceVersion} · coverage ${source.coverage} · external activity ${source.externalActivity}`,
      ...source.windows.flatMap((window) =>
        windowLines(window, facts.observedAt),
      ),
      `Warning: ${source.reason}`,
    );
  }

  if (
    facts.pools.length === 0 &&
    facts.unbound.length === 0 &&
    facts.unavailable.length === 0
  ) {
    lines.push('No usable quota observations; capacity unknown.');
  }

  for (const missing of facts.unavailable) {
    lines.push(
      missing.reason === 'Quota read pending; capacity unknown.'
        ? `${missing.agent}: pending · capacity unknown`
        : `${missing.agent}: unavailable · ${missing.reason}`,
    );
  }

  lines.push(
    ...facts.warnings.map((warning) => `Warning: ${warning}`),
    `Active work: ${facts.activeRuns.length === 0 ? 'none' : facts.activeRuns.length} reported · external work may be missing`,
  );

  return lines;
}

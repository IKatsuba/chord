/** Runtime filtering narrows evidence without inferring provider identity. */
import { z } from '@zod/zod';
import type { BudgetSnapshot } from './budgets.ts';
import { boundedWarnings } from './resource_warnings.ts';

export const ResourceAgents = z.array(z.string().min(1).max(128)).max(128);
export const POOL_SCOPE_INCOMPLETE =
  'Some pool observations have no explicit link to requested runtimes; filtered coverage is incomplete.';

export const UNAVAILABLE_SCOPE_INCOMPLETE =
  'Additional runtime unavailability facts are omitted; filtered coverage is incomplete.';

export function filterResourceFacts(
  facts: BudgetSnapshot,
  agents: readonly string[] | undefined,
): BudgetSnapshot {
  if (agents === undefined) {
    return facts;
  }

  const requested = new Set(agents);
  const activeRuns = facts.activeRuns.filter((run) => requested.has(run.agent));
  const poolRefs = new Set(activeRuns.flatMap((run) => run.resourceRefs));
  const pools = facts.pools.filter((pool) => poolRefs.has(pool.poolRef));
  const unbound = facts.unbound.filter((one) => requested.has(one.agent));
  const reasons = new Set<string>();
  const unavailable = facts.unavailable.filter((one) => {
    const key = JSON.stringify([one.agent, one.reason]);

    if (!requested.has(one.agent) || reasons.has(key)) {
      return false;
    }

    reasons.add(key);

    return true;
  });

  for (const agent of requested) {
    if (
      !unbound.some((one) => one.agent === agent) &&
      !unavailable.some((one) => one.agent === agent) &&
      !activeRuns.some(
        (run) =>
          run.agent === agent &&
          run.resourceRefs.some((ref) =>
            pools.some((pool) => pool.poolRef === ref),
          ),
      )
    ) {
      unavailable.push({
        agent,
        reason: 'No resource observations for this runtime; capacity unknown.',
      });
    }
  }

  return {
    ...facts,
    pools,
    unbound,
    unavailable: unavailable.slice(0, 128),
    activeRuns,
    warnings: boundedWarnings(facts.warnings, [
      ...(requested.size > 0 && pools.length < facts.pools.length
        ? [POOL_SCOPE_INCOMPLETE]
        : []),
      ...(unavailable.length > 128 ? [UNAVAILABLE_SCOPE_INCOMPLETE] : []),
    ]),
  };
}

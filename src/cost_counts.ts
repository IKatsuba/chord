/**
 * What each agent's cost counts from, kept by hand beside the registry
 * (`registry.ts`) and the CLI table (`clis.ts`), which say nothing of it:
 * every agent's cost is the sum so far, but some start it again at each
 * opening of a session and others carry it over from the session's start.
 * A cost's first figure after a resume is the turn's alone for the one, and
 * the whole session's for the other (CHD-378, the owner's Q61). An agent not
 * named here is not known to do either.
 */

/** `opening`: from each `session/new`, load or resume; `session`: from its start. */
export type CostCount = 'opening' | 'session';

/**
 * By the name chord starts each by, each from its adapter's source or its
 * own docs as `docs/design/CHD-378.md` gives them.
 */
export const COST_COUNTS: Readonly<Record<string, CostCount>> = {
  // claude-agent-acp 0.93 keeps the SDK's `total_cost_usd` per query and
  // restores none of it on load.
  claude: 'opening',
  // Each reads the session's sum from its own store.
  dimcode: 'session',
  kilo: 'session',
  opencode: 'session',
};

/** What `agent`'s cost counts from, or undefined where it is not known. */
export function costCountOf(agent: string): CostCount | undefined {
  return Object.hasOwn(COST_COUNTS, agent) ? COST_COUNTS[agent] : undefined;
}

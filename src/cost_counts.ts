/**
 * What each agent's cost counts from, kept by hand beside the registry
 * (`registry.ts`) and the CLI table (`clis.ts`), which say nothing of it:
 * every agent's cost is the sum so far, but some start it again at each
 * opening of a session and others carry it over from the session's start.
 * A cost's first figure after a resume is the turn's alone for the one, and
 * the whole session's for the other (CHD-378, the owner's Q61). An agent not
 * named here is not known to do either. Beside it, what each agent's answer
 * usage counts, where it is not the turn's own (CHD-472).
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
  // Each reads the session's sum from its own store. dirac rebuilds it on
  // load, and on resume, which is load, from every message the stored task
  // saved (docs/agent-capabilities.md, di20).
  dimcode: 'session',
  dirac: 'session',
  kilo: 'session',
  opencode: 'session',
};

/** What `agent`'s cost counts from, or undefined where it is not known. */
export function costCountOf(agent: string): CostCount | undefined {
  return Object.hasOwn(COST_COUNTS, agent) ? COST_COUNTS[agent] : undefined;
}

/**
 * What an agent's answer to a prompt gives as its `usage`: `session`, the
 * session's running total from its start, not the turn's own as ACP says.
 * Its tokens are then the last answer's, never added up (CHD-472, the
 * owner's Q103).
 */
export type UsageCount = 'session';

/** By the name chord starts each by, as `COST_COUNTS` is. */
export const USAGE_COUNTS: Readonly<Record<string, UsageCount>> = {
  // dirac 0.5.21 sums a snapshot per model request and subagent kept for the
  // session, rebuilt from the stored task on load (di20). A task whose saved
  // messages do not read is left unrestored, and counts from that opening;
  // chord does not tell that apart.
  dirac: 'session',
};

/** What `agent`'s answer usage counts, or undefined for the turn's own. */
export function usageCountOf(agent: string): UsageCount | undefined {
  return Object.hasOwn(USAGE_COUNTS, agent) ? USAGE_COUNTS[agent] : undefined;
}

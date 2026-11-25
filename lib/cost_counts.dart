/// What each agent's cost counts from, kept by hand beside the registry and
/// the CLI table, which say nothing of it: every agent's cost is the sum so
/// far, but some start it again at each opening of a session and others
/// carry it over from the session's start. Beside it, what each agent's
/// answer usage counts, where it is not the turn's own.
library;

/// `opening`: from each `session/new`, load or resume; `session`: from its
/// start.
enum CostCount { opening, session }

/// By the name chord starts each by, as the original's table gives them.
const costCounts = {
  // claude-agent-acp keeps the SDK's `total_cost_usd` per query and restores
  // none of it on load.
  'claude': CostCount.opening,
  // cursor-cloud-acp sends the cloud agent's whole cost after each run.
  'cursor-cloud': CostCount.session,
  // Each reads the session's sum from its own store.
  'dimcode': CostCount.session,
  'dirac': CostCount.session,
  'kilo': CostCount.session,
  'opencode': CostCount.session,
};

/// What [agent]'s cost counts from, or null where it is not known.
CostCount? costCountOf(String agent) => costCounts[agent];

/// What an agent's answer to a prompt gives as its `usage`: the session's
/// running total from its start, not the turn's own as ACP says.
enum UsageCount { session }

/// By the name chord starts each by, as [costCounts] is.
const usageCounts = {
  // dirac sums a snapshot per model request and subagent kept for the
  // session, rebuilt from the stored task on load.
  'dirac': UsageCount.session,
};

/// What [agent]'s answer usage counts, or null for the turn's own.
UsageCount? usageCountOf(String agent) => usageCounts[agent];

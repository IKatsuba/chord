/**
 * A plan by id: `plan_update` and `plan_removed`. The older `plan` update,
 * which only replaces the live list, the reducer folds itself.
 */
import type { PlanUpdateContent } from '@agentclientprotocol/sdk';
import type { Transcript } from './types.ts';

/**
 * The plan `planId` gone, whichever way it was drawn: the live list it is, or
 * the reply its markdown or file became. Other replies and plans stay.
 */
export function removePlan(state: Transcript, planId: string): Transcript {
  const entries = state.entries.filter(
    (entry) => entry.kind !== 'assistant' || entry.planId !== planId,
  );
  const listed = state.planId === planId;

  if (!listed && entries.length === state.entries.length) {
    return state;
  }

  if (!listed) {
    return { ...state, entries };
  }

  const { planId: _, ...rest } = state;

  return { ...rest, entries, plan: [] };
}

/**
 * A plan by id, as agents that know the client takes one send it. Entries are
 * the live list, as a `plan` update's are; a plan written as markdown or kept
 * in a file is the agent's reply, as such an agent sends it to a client that
 * takes no plan, and each update to it rewrites that reply where it stands.
 */
export function updatePlan(
  state: Transcript,
  turnId: string,
  plan: PlanUpdateContent,
): Transcript {
  if (plan.type === 'items') {
    return { ...state, plan: plan.entries, planId: plan.planId };
  }

  const text = plan.type === 'markdown' ? plan.content : plan.uri;
  const index = state.entries.findIndex(
    (entry) => entry.kind === 'assistant' && entry.planId === plan.planId,
  );
  const entry = state.entries[index];

  if (entry?.kind !== 'assistant') {
    return text === ''
      ? state
      : {
          ...state,
          entries: [
            ...state.entries,
            {
              kind: 'assistant',
              turnId,
              text,
              planId: plan.planId,
            },
          ],
        };
  }

  const entries = [...state.entries];

  entries[index] = { ...entry, text };

  return { ...state, entries };
}

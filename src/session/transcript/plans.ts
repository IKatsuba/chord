/**
 * A plan by id: `plan_update` and `plan_removed`. The older `plan` update,
 * which only replaces the live list, the reducer folds itself.
 */
import type { PlanUpdateContent } from '@agentclientprotocol/sdk';
import type { Entry, Transcript } from './types.ts';

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

  if (plan.type === 'markdown') {
    state = { ...state, entries: shownOnce(state.entries, turnId, text) };
  }

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

/**
 * `entries` with the plan `text` taken out of the turn's latest mode switch
 * that carries it as its content, as Claude's adapter sends an approved plan
 * both ways: the plan is shown once, as the plan. A switch whose text is not
 * the plan, as a rejected or edited one is, keeps it.
 */
function shownOnce(
  entries: readonly Entry[],
  turnId: string,
  text: string,
): readonly Entry[] {
  const plan = text.trim();
  const index = entries.findLastIndex(
    (entry) =>
      entry.kind === 'tool' &&
      entry.turnId === turnId &&
      entry.call.kind === 'switch_mode',
  );
  const entry = entries[index];

  if (entry?.kind !== 'tool' || plan === '') {
    return entries;
  }

  const content = entry.call.content ?? [];
  const said = content
    .flatMap((block) =>
      block.type === 'content' && block.content.type === 'text'
        ? [block.content.text]
        : [],
    )
    .join('')
    .trim();

  if (said !== plan) {
    return entries;
  }

  const kept = content.filter(
    (block) => !(block.type === 'content' && block.content.type === 'text'),
  );

  return entries.with(index, {
    ...entry,
    call: { ...entry.call, content: kept },
  });
}

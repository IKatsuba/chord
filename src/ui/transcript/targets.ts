/**
 * The ids a drawn call's and agent's boxes carry, so the window can find the
 * row a call is drawn on inside its entry, as a jump to it does.
 */

/** A tool call's box, by the call's id. */
export function callTarget(id: string): string {
  return `call:${id}`;
}

/** A subagent's block, or its row in a group, by the subagent's id. */
export function agentTarget(id: string): string {
  return `agent:${id}`;
}

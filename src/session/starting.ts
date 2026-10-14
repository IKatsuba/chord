/**
 * The model, effort and mode a session starts on, asked for once it exists
 * and before anything is shown or sent: the window's `Conversation` and `-p`'s
 * oneshot both ask through here, so a refusal reads the same in either.
 */

/** A starting value, by the agent's id for it. */
export interface StartingValue {
  readonly id: string;
  /**
   * Where it was set, as a refusal says it, such as `set in
   * .chord/settings.json`, so the person knows what to change.
   */
  readonly from?: string;
  /**
   * Whether a refusal stops the session from starting, as a task agent's
   * model does: its job is not run on a model it was not asked for.
   */
  readonly required?: boolean;
}

/** What asking for one starting value needs of the session. */
export interface StartingAsk {
  readonly value: StartingValue;
  /** What is being started, as a refusal says it: `in plan mode`, `on high effort`. */
  readonly what: string;
  /** What the agent would list, as a refusal says it: `modes`. */
  readonly kind: string;
  /**
   * Whether an agent that lists none is refused without being asked, as for
   * a mode; a model is asked for all the same, and refused in its own words.
   */
  readonly listedOnly?: boolean;
  /** The ids the agent lists; none when it lists none. */
  offered(): Promise<readonly { readonly id: string }[] | undefined>;
  ask(): Promise<void>;
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * The agent's own words for a refusal: the `details` in its JSON-RPC error's
 * data, where Claude's adapter puts the reason under a generic message, or
 * else the message itself.
 */
export function agentMessageOf(error: unknown): string {
  for (let at = error; at instanceof Error; at = at.cause) {
    const data = (at as { data?: unknown }).data;
    const details =
      typeof data === 'object' && data !== null
        ? (data as { details?: unknown }).details
        : undefined;

    if (typeof details === 'string' && details.trim() !== '') {
      return details.trim();
    }
  }

  return messageOf(error);
}

/**
 * Asks for one starting value; resolves to what a refusal says after "could
 * not", such as `start in yolo mode, set by --permission-mode: the agent
 * offers default, plan`, or to nothing when the agent took it. A value the
 * agent does not list is not asked for; with `listedOnly`, neither is one
 * when the agent lists nothing, and the refusal says it lists none.
 */
export async function askStarting({
  value,
  what,
  kind,
  listedOnly,
  offered,
  ask,
}: StartingAsk): Promise<string | undefined> {
  let reason: string | undefined;

  try {
    const ids = (await offered())?.map((offer) => offer.id) ?? [];

    if (ids.length === 0 && listedOnly) {
      reason = `the agent offers no ${kind}`;
    } else if (ids.length > 0 && !ids.includes(value.id)) {
      reason = `the agent offers ${ids.join(', ')}`;
    } else {
      await ask();
    }
  } catch (error) {
    reason = agentMessageOf(error);
  }

  return reason === undefined
    ? undefined
    : `start ${what}${
        value.from === undefined ? '' : `, ${value.from}`
      }: ${reason}`;
}

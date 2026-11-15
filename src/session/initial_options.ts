/**
 * The values a new session is asked to open on, sent as `session/new`'s
 * initial `configOptions` where the agent takes them (CHD-629): a value the
 * agent takes at setup then costs no request after the session is up.
 */
import type {
  InitialSessionConfigOption,
  InitializeResponse,
} from '@agentclientprotocol/sdk/unstable';

/** The starting values chord was asked for, by the agent's id for each. */
export interface InitialValues {
  readonly model?: string | undefined;
  readonly effort?: string | undefined;
  readonly mode?: string | undefined;
  /**
   * A `chord acp` client's own initial `configOptions`, passed down as sent
   * and beating chord's value for the same id (the owner's Q4 b).
   */
  readonly entries?: readonly InitialSessionConfigOption[] | undefined;
}

/** The three values the table names, in the order their entries go. */
type Valued = 'model' | 'effort' | 'mode';

/**
 * The config ids an adapter takes as initial `configOptions` (CHD-629), by
 * the name its `initialize` answer gives, read from its source and rechecked
 * at a pin bump beside `agents.ts`'s `FAST_OPTIONS`: asking `session/options`
 * first makes Claude run a throwaway Claude Code and the person's
 * SessionStart hooks (CHD-624). A renamed id costs only a request after the
 * session is up (the owner's Q8 a).
 */
const INITIAL_CONFIG_IDS: ReadonlyMap<
  string,
  Readonly<Record<Valued, string>>
> = new Map([
  [
    '@agentclientprotocol/claude-agent-acp',
    { model: 'model', effort: 'effort', mode: 'mode' },
  ],
]);

/** The order entries go in: a model decides which efforts and modes follow. */
const ORDER = ['model', 'effort', 'mode'] as const;

/**
 * `session/new`'s initial entries for `values`, only where the agent
 * advertises `sessionCapabilities.options`: one per value named, model,
 * effort, mode, where the table knows the agent, then a client's entries as
 * it sent them, which take the place of chord's for the same id. chord adds
 * no value of its own.
 */
export function initialEntries(
  init: InitializeResponse,
  values: InitialValues,
): InitialSessionConfigOption[] {
  const ids =
    init.agentInfo?.name === undefined
      ? undefined
      : INITIAL_CONFIG_IDS.get(init.agentInfo.name);

  if (!init.agentCapabilities?.sessionCapabilities?.options) {
    return [];
  }

  const sent = values.entries ?? [];
  const taken = new Set(sent.map((entry) => entry.configId));
  const own = ORDER.flatMap((key) => {
    const value = values[key];

    return ids === undefined || value === undefined || taken.has(ids[key])
      ? []
      : [{ configId: ids[key], value }];
  });

  return [...own, ...sent];
}

/** A starting value as chord holds it, by the agent's id. */
interface Named {
  readonly id: string;
}

/** The ids of the starting values named, as `Starting` and `-p` hold them. */
export function initialValuesOf(starting: {
  readonly model?: Named | undefined;
  readonly effort?: Named | undefined;
  readonly mode?: Named | undefined;
  readonly entries?: readonly InitialSessionConfigOption[] | undefined;
}): InitialValues {
  return {
    ...(starting.entries === undefined ? {} : { entries: starting.entries }),
    ...(starting.model === undefined ? {} : { model: starting.model.id }),
    ...(starting.effort === undefined ? {} : { effort: starting.effort.id }),
    ...(starting.mode === undefined ? {} : { mode: starting.mode.id }),
  };
}

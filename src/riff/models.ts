/**
 * riff's models, efforts and modes, as its config options offer them
 * (CHD-485, "Models and effort"). libfx has no model list for plans, so riff
 * carries one per provider, each model with its context window and the plan's
 * default first, as other agents carry theirs in their own config options.
 */
import type { SessionConfigOption } from '@agentclientprotocol/sdk/unstable';

/** Where riff's turns run: a plan, or the fake provider of tests. */
export type RiffPlan = 'codex' | 'grok' | 'fake';

export interface RiffModel {
  readonly id: string;
  /** Its context window in tokens: `usage_update`'s `size`. */
  readonly window: number;
}

/**
 * Unverified: placeholders from fx's and libfx's own defaults. The entries
 * and windows still need checking against the live plans, which needs the
 * owner's go-ahead for a real call (CHD-485).
 */
const PLAN_MODELS: Readonly<Record<RiffPlan, readonly RiffModel[]>> = {
  codex: [
    { id: 'gpt-6.1-sol', window: 400_000 },
    { id: 'gpt-6-sol', window: 400_000 },
    { id: 'gpt-6-luna', window: 400_000 },
    { id: 'gpt-5.6-luna', window: 400_000 },
  ],
  grok: [
    { id: 'grok-4.7', window: 256_000 },
    { id: 'grok-4.5', window: 256_000 },
  ],
  // The fake Chat Completions server's one model, for tests, selftest,
  // --fake and --qa alone.
  fake: [{ id: 'fake', window: 128_000 }],
};

export const EFFORTS = ['default', 'low', 'medium', 'high', 'xhigh'] as const;

export type RiffEffort = (typeof EFFORTS)[number];

/** `ask` is the only behaviour until the auto review (CHD-485 part 6). */
export const MODES = ['ask', 'auto'] as const;

export type RiffMode = (typeof MODES)[number];

/** What a session runs its next turn on. */
export interface RiffConfig {
  readonly model: string;
  readonly effort: RiffEffort;
  readonly mode: RiffMode;
}

export function planModels(plan: RiffPlan): readonly RiffModel[] {
  return PLAN_MODELS[plan];
}

/** A new session's: the plan's default model, `default` effort, `ask`. */
export function defaultConfig(plan: RiffPlan): RiffConfig {
  const [first] = PLAN_MODELS[plan];

  return { model: first?.id ?? '', effort: 'default', mode: 'ask' };
}

/** The model's window, or the plan default's for a model not listed. */
export function windowOf(plan: RiffPlan, model: string): number {
  const models = PLAN_MODELS[plan];

  return (models.find(({ id }) => id === model) ?? models[0])?.window ?? 0;
}

export function configOptions(
  plan: RiffPlan,
  config: RiffConfig,
): SessionConfigOption[] {
  return [
    {
      id: 'model',
      name: 'Model',
      category: 'model',
      type: 'select',
      currentValue: config.model,
      options: PLAN_MODELS[plan].map(({ id }) => ({ value: id, name: id })),
    },
    {
      id: 'effort',
      name: 'Effort',
      category: 'thought_level',
      type: 'select',
      currentValue: config.effort,
      options: EFFORTS.map((effort) => ({ value: effort, name: effort })),
    },
    {
      id: 'mode',
      name: 'Mode',
      category: 'mode',
      type: 'select',
      currentValue: config.mode,
      options: MODES.map((mode) => ({ value: mode, name: mode })),
    },
  ];
}

/**
 * `config` with option `id` set to `value`, or undefined for an option or a
 * value riff does not offer.
 */
export function setOption(
  plan: RiffPlan,
  config: RiffConfig,
  id: string,
  value: unknown,
): RiffConfig | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }

  if (id === 'model' && PLAN_MODELS[plan].some((model) => model.id === value)) {
    return { ...config, model: value };
  }

  if (id === 'effort' && (EFFORTS as readonly string[]).includes(value)) {
    return { ...config, effort: value as RiffEffort };
  }

  if (id === 'mode' && (MODES as readonly string[]).includes(value)) {
    return { ...config, mode: value as RiffMode };
  }

  return undefined;
}

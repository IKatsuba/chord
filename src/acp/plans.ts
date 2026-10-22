/**
 * The two requests an agent puts its plan to the client with, and their
 * answers, as the agents' own docs give them (docs/agent-capabilities.md):
 * cursor's `cursor/create_plan` (https://cursor.com/docs/cli/acp) and grok's
 * `x.ai/exit_plan_mode`. Each is read into one shape; a request that does
 * not read is answered `cancelled`, never a yes (CHD-437, CHD-457).
 */
import { z } from '@zod/zod';

/** The two requests, by their method. */
export const PLAN_METHODS = {
  cursor: 'cursor/create_plan',
  grok: 'x.ai/exit_plan_mode',
} as const;

/** Which agent's plan, so its answers are its own. */
export type PlanAgent = keyof typeof PLAN_METHODS;

const TODO = z.object({
  id: z.string(),
  content: z.string(),
  status: z.enum(['pending', 'in_progress', 'completed', 'cancelled']),
});

/** One of cursor's todos, as its request sends it. */
export type PlanTodo = z.infer<typeof TODO>;

/** One of cursor's phases: a name over todos of its own, sent whole. */
export interface PlanPhase {
  readonly name: string;
  readonly todos: readonly PlanTodo[];
}

const CURSOR = z.object({
  sessionId: z.string().optional(),
  toolCallId: z.string(),
  name: z.string().optional(),
  overview: z.string().optional(),
  plan: z.string(),
  todos: z.array(TODO),
  phases: z
    .array(z.object({ name: z.string(), todos: z.array(TODO) }))
    .optional(),
});

const GROK = z.object({
  sessionId: z.string(),
  toolCallId: z.string(),
  planContent: z.string().optional(),
});

/** A plan request as chord reads it. */
export interface PlanRequest {
  readonly agent: PlanAgent;
  /** The session that asks, when its request names one. */
  readonly sessionId?: string;
  readonly toolCallId: string;
  /** The plan's markdown; grok sends none when it wrote no plan. */
  readonly plan?: string;
  readonly name?: string;
  readonly overview?: string;
  readonly todos?: readonly PlanTodo[];
  readonly phases?: readonly PlanPhase[];
}

/** The answer a request is given, in its agent's own words. */
export type PlanResponse =
  | { readonly outcome: 'accepted' | 'approved' | 'abandoned' | 'cancelled' }
  | { readonly outcome: 'rejected'; readonly reason?: string }
  | { readonly outcome: 'revise'; readonly feedback?: string };

/** The answer every request is given that is not the person's. */
export const PLAN_CANCELLED: PlanResponse = { outcome: 'cancelled' };

/** `cursor/create_plan`'s params as chord reads them; none when they do not. */
export function cursorPlan(params: unknown): PlanRequest | undefined {
  const read = CURSOR.safeParse(params);

  if (!read.success) {
    return undefined;
  }

  const { sessionId, toolCallId, name, overview, plan, todos, phases } =
    read.data;

  return {
    agent: 'cursor',
    ...(sessionId === undefined ? {} : { sessionId }),
    toolCallId,
    plan,
    ...(name === undefined ? {} : { name }),
    ...(overview === undefined ? {} : { overview }),
    todos,
    ...(phases === undefined ? {} : { phases }),
  };
}

/** `x.ai/exit_plan_mode`'s params as chord reads them; none when they do not. */
export function grokPlan(params: unknown): PlanRequest | undefined {
  const read = GROK.safeParse(params);

  if (!read.success) {
    return undefined;
  }

  const { sessionId, toolCallId, planContent } = read.data;

  return {
    agent: 'grok',
    sessionId,
    toolCallId,
    ...(planContent === undefined ? {} : { plan: planContent }),
  };
}

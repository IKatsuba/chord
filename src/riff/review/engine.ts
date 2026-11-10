/** A fresh, isolated reviewer conversation, released at the end of each attempt. */
import {
  createFxEngine,
  type FxEngineTurn,
  type FxNodeEngineOptions,
} from 'libfx/node';
import { reviewDecision } from './decision.ts';
import { DECISION_SCHEMA, REVIEW_POLICY } from './policy.ts';
import { review, type ReviewAttempt } from './review.ts';

/** The caller supplies the same provider, credential callbacks and fetch as riff. */
export interface ReviewerOptions {
  readonly configuration: FxNodeEngineOptions;
  /** The factory seam never supplies real providers in tests. */
  readonly createEngine?: typeof createFxEngine;
}

/** libfx has no reviewer API; only this one host tool is exposed to the model. */
export function reviewer(options: ReviewerOptions) {
  const attempt: ReviewAttempt = async (input, signal) => {
    let turn: FxEngineTurn | undefined;
    const decisions: unknown[] = [];
    let calls = 0;
    let proposedCalls = 0;
    const engine = await (options.createEngine ?? createFxEngine)({
      ...options.configuration,
      instructions: REVIEW_POLICY,
      hooks: {
        onEvent: (event) => {
          if (event.type === 'model.end') {
            proposedCalls = event.data.toolCalls?.length ?? 0;
          }
        },
      },
      tools: [
        {
          name: 'permission_decision',
          description:
            'Return the safety review decision for the pending action.',
          inputSchema: DECISION_SCHEMA,
          idempotent: true,
          execute: (value: unknown) => {
            decisions.push(value);
            turn?.cancel();

            return 'The safety review decision was recorded.';
          },
        },
      ],
    });

    try {
      signal.throwIfAborted();

      turn = engine.prompt(input, { signal });

      for await (const event of turn) {
        if (event.type === 'tool_start') {
          calls++;

          if (event.name !== 'permission_decision') {
            return undefined;
          }
        }
      }

      await turn.result;
      signal.throwIfAborted();

      return proposedCalls === 1 && calls === 1 && decisions.length === 1
        ? reviewDecision(decisions[0])
        : undefined;
    } finally {
      await engine.close();
    }
  };

  return (input: string, signal: AbortSignal) => review(attempt, input, signal);
}

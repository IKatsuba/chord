import type {
  Cost,
  McpServer,
  SessionUpdate,
  ToolCallUpdate,
} from '@agentclientprotocol/sdk';
import { filledIn } from './enrich.ts';
import { allowOption } from './permissions.ts';
import { openSession } from './session.ts';
import {
  askStarting,
  type StartingAsk,
  type StartingValue,
} from './starting.ts';
import type { ElicitationWait, TurnResult } from './transcript/types.ts';
import type { TokenUsage } from './usage.ts';

export interface OneshotOptions {
  /** A name `chord agents` lists, or the label for `agentCommand`. */
  agent: string;
  /** The directory the agent works in. */
  cwd: string;
  /** The whole prompt, piped input already joined to it. */
  prompt: string;
  /** Starts this command instead of the registry's for `agent`. */
  agentCommand?: string | string[];
  /** MCP servers for the agent, as the window's sessions get them. */
  mcpServers?: readonly McpServer[];
  /** Each of the agent's updates as it arrives, until the turn is answered. */
  onUpdate(update: SessionUpdate): void | Promise<void>;
  /**
   * The effort to ask for once the session exists and before the prompt
   * goes; the turn runs on the agent's own when it is refused.
   */
  effort?: StartingValue;
  /**
   * The mode to ask for once the session exists and before the prompt goes;
   * the turn runs in the agent's own when it is refused.
   */
  mode?: StartingValue;
  /** What a refused `effort` or `mode` says after "could not". */
  onStartingRefused?(refusal: string): void | Promise<void>;
  /**
   * Allow every permission the agent asks for, with the request's own allow
   * option, instead of refusing it.
   */
  allowAll?: boolean;
  /** A permission the agent asked for, already refused. */
  onRefused(toolCall: ToolCallUpdate): void | Promise<void>;
  /** A permission the agent asked for, already allowed under `allowAll`. */
  onAllowed?(toolCall: ToolCallUpdate): void | Promise<void>;
  /** A form the agent asked the person to fill in, already declined. */
  onDeclined?(
    form: Extract<ElicitationWait, { mode: 'form' }>,
  ): void | Promise<void>;
}

/** How a one-shot turn ended, read after its agent has exited. */
export interface OneshotOutcome {
  /** The agent's id for the session, which `--resume` takes. */
  readonly sessionId: string;
  readonly result: TurnResult;
  /** The turn's tokens, when the agent reported them. */
  readonly usage?: TokenUsage;
  /** The session's cost, as the agent's last `usage_update` gave it. */
  readonly cost?: Cost;
  /** Whether that cost is chord's estimate from the tokens, not the agent's. */
  readonly costEstimated?: boolean;
}

/**
 * Plays one prompt in a session of its own, and ends the agent once the turn
 * is over. Nobody is there to answer a permission, so every one is refused,
 * or under `allowAll` allowed; a form is declined, which an agent reads as
 * its questions skipped and goes on, and a link is cancelled. Rejects only when
 * the agent cannot be started; a turn that fails comes back as a failed
 * `result`.
 */
export async function runOneshot(
  options: OneshotOptions,
): Promise<OneshotOutcome> {
  const session = await openSession({
    agent: options.agent,
    cwd: options.cwd,
    ...(options.agentCommand === undefined
      ? {}
      : { agentCommand: options.agentCommand }),
    ...(options.mcpServers === undefined
      ? {}
      : { mcpServers: options.mcpServers }),
  });

  let cost: Cost | undefined;
  let costEstimated = false;
  // Each update is handed on in turn, so stdout keeps the reply's order.
  let handed: Promise<void> = Promise.resolve();
  let result: TurnResult;

  try {
    session.permissions.subscribe(async (request) => {
      const allow = options.allowAll ? allowOption(request.options) : undefined;

      if (allow === undefined) {
        await options.onRefused(request.toolCall);
        request.reject();
      } else {
        await options.onAllowed?.(request.toolCall);
        request.resolve(allow.optionId);
      }
    });

    session.elicitations.subscribe(async (request) => {
      if (request.wait.mode !== 'form') {
        request.answer({ action: 'cancel' });

        return;
      }

      await options.onDeclined?.(request.wait);
      request.answer({ action: 'decline' });
    });

    const { effort, mode } = options;
    // In the window's order: the effort, then the mode.
    const asks: StartingAsk[] = [
      ...(effort === undefined
        ? []
        : [
            {
              value: effort,
              what: `on ${effort.id} effort`,
              kind: 'efforts',
              listedOnly: true,
              offered: () => Promise.resolve(session.efforts()?.available),
              ask: () => session.setEffort(effort.id),
            },
          ]),
      ...(mode === undefined
        ? []
        : [
            {
              value: mode,
              what: `in ${mode.id} mode`,
              kind: 'modes',
              listedOnly: true,
              offered: () => Promise.resolve(session.modes()?.available),
              ask: () => session.setMode(mode.id),
            },
          ]),
    ];

    for (const ask of asks) {
      const refused = await askStarting(ask);

      if (refused !== undefined) {
        await options.onStartingRefused?.(refused);
      }
    }

    session.subscribe((update, subagentId) => {
      // A subagent's words are not the reply, nor its usage the session's.
      if (subagentId !== undefined) {
        return;
      }

      if (update.sessionUpdate === 'usage_update' && update.cost) {
        cost = update.cost;
        costEstimated = filledIn(update).includes('cost');
      }

      handed = handed.then(() => options.onUpdate(update));
    });

    result = await session.prompt(options.prompt).result;
  } finally {
    // What the agent sends after its answer still arrives as it closes.
    await session.close();
  }

  await handed;

  return {
    sessionId: session.id,
    result,
    ...(result.status !== 'failed' && result.usage
      ? { usage: result.usage }
      : {}),
    ...(cost === undefined ? {} : { cost }),
    ...(costEstimated ? { costEstimated } : {}),
  };
}

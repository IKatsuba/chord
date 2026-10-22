import type {
  Cost,
  McpServer,
  SessionUpdate,
  ToolCallUpdate,
} from '@agentclientprotocol/sdk';
import { type OneshotOutcome, runOneshot } from './session/oneshot.ts';
import type { StartingValue } from './session/starting.ts';
import type { ElicitationWait } from './session/transcript/types.ts';
import type { TokenUsage } from './session/usage.ts';

/** What `--output-format` takes. */
export const OUTPUT_FORMATS = ['text', 'json'] as const;

export type OutputFormat = (typeof OUTPUT_FORMATS)[number];

/**
 * The prompt with piped input after it, joined as Claude Code joins them for
 * `-p`: a line break between, and either left out when empty.
 */
export function joinPiped(prompt: string, piped: string | undefined): string {
  return [prompt, piped].filter(Boolean).join('\n');
}

/**
 * The reply as stdout carries it: the agent's text without its thinking, and a
 * blank line where a tool call came between two stretches of text, which
 * would otherwise run into one another.
 */
export class Reply {
  #text = '';
  #broken = false;
  /** Each markdown plan's text as stdout has it, by plan id. */
  #plans = new Map<string, string>();
  /** Each markdown plan's text as the agent last sent it, by plan id. */
  #latest = new Map<string, string>();
  /** The reply in order: text as taken, and each plan where it first came. */
  #parts: (string | { plan: string })[] = [];

  /**
   * The reply as the turn left it, for `--output-format json`, which is
   * written once at the end: each plan as last sent, rewritten or removed,
   * where stdout could only keep what it had printed.
   */
  get text(): string {
    return this.#parts
      .map((part) =>
        typeof part === 'string' ? part : (this.#latest.get(part.plan) ?? ''),
      )
      .join('');
  }

  /** What `update` adds to stdout; empty when it adds nothing. */
  take(update: SessionUpdate): string {
    if (update.sessionUpdate === 'tool_call') {
      this.#broken = this.#text !== '';

      return '';
    }

    if (
      update.sessionUpdate === 'plan_update' &&
      update.plan.type === 'markdown'
    ) {
      return this.#plan(update.plan.planId, update.plan.content);
    }

    if (update.sessionUpdate === 'plan_removed') {
      this.#latest.delete(update.planId);

      return '';
    }

    if (
      update.sessionUpdate !== 'agent_message_chunk' ||
      update.content.type !== 'text' ||
      update.content.text === ''
    ) {
      return '';
    }

    const added = this.#add(update.content.text);

    this.#parts.push(added);

    return added;
  }

  /**
   * A markdown plan is the reply an agent would have sent a client that takes
   * no plan, but each update carries it whole: stdout gets what it adds to the
   * plan as printed so far. A plan rewritten from the middle cannot be taken
   * back off stdout, so it adds nothing there.
   */
  #plan(id: string, content: string): string {
    const printed = this.#plans.get(id);

    if (printed === undefined && content === '') {
      return '';
    }

    this.#latest.set(id, content);

    if (printed === undefined) {
      const added = this.#add(content);

      this.#plans.set(id, content);
      // The break before the plan, if a tool call came first.
      this.#parts.push(added.slice(0, added.length - content.length), {
        plan: id,
      });

      return added;
    }

    if (!content.startsWith(printed) || content === printed) {
      return '';
    }

    this.#plans.set(id, content);

    return this.#add(content.slice(printed.length));
  }

  #add(text: string): string {
    const added =
      this.#broken && !this.#text.endsWith('\n\n')
        ? `${this.#text.endsWith('\n') ? '\n' : '\n\n'}${text}`
        : text;

    this.#broken = false;
    this.#text += added;

    return added;
  }

  /** The line break a reply that stopped mid-line still needs. */
  end(): string {
    return this.#text === '' || this.#text.endsWith('\n') ? '' : '\n';
  }
}

/** Why the turn did not end as a finished answer; none when it did. */
export function failureOf(outcome: OneshotOutcome): string | undefined {
  const { result } = outcome;

  if (result.status === 'failed') {
    return result.error.message;
  }

  if (result.status === 'cancelled') {
    return 'The turn was cancelled.';
  }

  return result.stopReason === 'end_turn'
    ? undefined
    : `The agent stopped: ${result.stopReason}.`;
}

/** What stderr says of a permission nobody was there to answer. */
export function refusalLine(toolCall: ToolCallUpdate): string {
  return `chord: refused ${
    toolCall.title ?? toolCall.toolCallId
  }: -p cannot ask for permission.\n`;
}

/**
 * What stderr says of a form nobody was there to fill in, a line per
 * question chord read in it, or one for the form.
 */
export function skippedLines(
  agent: string,
  form: Extract<ElicitationWait, { mode: 'form' }>,
): string {
  const asked = form.questions?.questions.map(({ text }) => text) ?? [
    form.message,
  ];

  return asked
    .map(
      (text) =>
        `chord: ${agent} asked: ${text} — skipped (no one to answer under -p)\n`,
    )
    .join('');
}

/** What stderr says of a permission `--dangerously-skip-permissions` allowed. */
export function allowedLine(toolCall: ToolCallUpdate): string {
  return `chord: allowed ${toolCall.title ?? toolCall.toolCallId}.\n`;
}

/** The snake_case names Claude Code's `--output-format json` uses. */
function usageJson(usage: TokenUsage): Record<string, number> {
  const names: [keyof TokenUsage, string][] = [
    ['inputTokens', 'input_tokens'],
    ['outputTokens', 'output_tokens'],
    ['cachedReadTokens', 'cache_read_input_tokens'],
    ['cachedWriteTokens', 'cache_creation_input_tokens'],
    ['thoughtTokens', 'thought_tokens'],
    ['totalTokens', 'total_tokens'],
  ];

  return Object.fromEntries(
    names.flatMap(([from, to]) =>
      usage[from] === undefined ? [] : [[to, usage[from]]],
    ),
  );
}

/** The cost, and `cost_estimated` when chord worked it out from the tokens. */
function costJson(cost: Cost | undefined, estimated: boolean) {
  if (cost === undefined) {
    return {};
  }

  return {
    ...(cost.currency === 'USD'
      ? { total_cost_usd: cost.amount }
      : { cost: { amount: cost.amount, currency: cost.currency } }),
    ...(estimated ? { cost_estimated: true } : {}),
  };
}

/**
 * The one object `--output-format json` prints, in the names Claude Code's
 * uses where it has the same thing to say.
 */
export function resultJson(
  outcome: OneshotOutcome,
  text: string,
): Record<string, unknown> {
  const failure = failureOf(outcome);
  const { result, usage, cost } = outcome;

  return {
    type: 'result',
    is_error: failure !== undefined,
    result: text,
    session_id: outcome.sessionId,
    ...(result.status === 'failed' ? {} : { stop_reason: result.stopReason }),
    ...(usage === undefined ? {} : { usage: usageJson(usage) }),
    ...costJson(cost, outcome.costEstimated === true),
    ...(failure === undefined ? {} : { error: failure }),
  };
}

export interface HeadlessOptions {
  agent: string;
  cwd: string;
  prompt: string;
  format: OutputFormat;
  agentCommand?: string | string[];
  /** MCP servers for the agent, from the settings files and `.mcp.json`. */
  mcpServers?: readonly McpServer[];
  /** The agent takes no MCP servers at all (CHD-441). */
  noMcpServers?: boolean;
  /** `--effort`, or the settings files', and where it was set. */
  effort?: StartingValue;
  /** `--permission-mode`, or the settings files', and where it was set. */
  mode?: StartingValue;
  /** `--dangerously-skip-permissions`: allow what the agent asks. */
  allowAll?: boolean;
  stdout(text: string): Promise<void>;
  stderr(text: string): Promise<void>;
}

/**
 * `chord -p`: one prompt, the reply on stdout, and the exit code a script
 * reads — 0 only when the agent ended its turn.
 */
export async function runHeadless(options: HeadlessOptions): Promise<number> {
  const { format, stdout, stderr } = options;
  const reply = new Reply();
  let outcome: OneshotOutcome;

  try {
    outcome = await runOneshot({
      agent: options.agent,
      cwd: options.cwd,
      prompt: options.prompt,
      ...(options.agentCommand === undefined
        ? {}
        : { agentCommand: options.agentCommand }),
      ...(options.mcpServers === undefined
        ? {}
        : { mcpServers: options.mcpServers }),
      ...(options.noMcpServers === true ? { noMcpServers: true } : {}),
      onUpdate: async (update) => {
        const added = reply.take(update);

        if (format === 'text' && added !== '') {
          await stdout(added);
        }
      },
      ...(options.effort === undefined ? {} : { effort: options.effort }),
      ...(options.mode === undefined ? {} : { mode: options.mode }),
      // The turn still runs, on the agent's own effort and in its own mode.
      onStartingRefused: (refusal) => stderr(`chord: could not ${refusal}\n`),
      allowAll: options.allowAll === true,
      onRefused: (toolCall) => stderr(refusalLine(toolCall)),
      onAllowed: (toolCall) => stderr(allowedLine(toolCall)),
      onDeclined: (form) => stderr(skippedLines(options.agent, form)),
      onNotice: (paragraphs) =>
        stderr(paragraphs.map((paragraph) => `chord: ${paragraph}\n`).join('')),
    });
  } catch (error) {
    await stderr(
      `chord: ${options.agent} did not start: ${
        error instanceof Error ? error.message : String(error)
      }\n`,
    );

    return 1;
  }

  const failure = failureOf(outcome);

  if (format === 'json') {
    await stdout(`${JSON.stringify(resultJson(outcome, reply.text))}\n`);
  } else {
    await stdout(reply.end());
  }

  if (failure !== undefined) {
    await stderr(`chord: ${failure}\n`);

    return 1;
  }

  return 0;
}

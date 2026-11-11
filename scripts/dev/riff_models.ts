/**
 * `bun dev riff-models <codex|grok>`: the owner's check of riff's model list
 * (CHD-611). libfx has no call that lists a plan's models; its engine asks
 * the plan's models endpoint itself, through the `fetch` the host passes.
 * This runs one tiny turn on the stored sign-in with a fetch that passes
 * every request through unchanged and keeps a copy of the models responses,
 * then prints each model's id, context window and reasoning levels and
 * writes the raw responses to a file. Nothing here adds to or changes
 * libfx's traffic.
 */
import {
  createFxAgent,
  type FxFetch,
  type FxNodeBackendOptions,
} from 'libfx/node';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import type { Secrets } from '../../src/platform/secrets.ts';
import { credentialCell } from '../../src/riff/credentials.ts';
import { planModels } from '../../src/riff/models.ts';
import { planProvider } from '../../src/riff/provider.ts';

export const PLANS = ['codex', 'grok'] as const;

export type Plan = (typeof PLANS)[number];

/** The one prompt the check sends. */
export const PROMPT = 'Reply with the word ok.';

export interface RiffModelsOptions {
  readonly plan: Plan;
  /** The store the plan's sign-in is read from: the system's for the owner. */
  readonly secrets: Secrets;
  /** The network edge: the global fetch for the owner, a fake in tests. */
  readonly fetch: FxFetch;
  readonly backend: FxNodeBackendOptions;
  /** chord's state directory, where the credential lock lives. */
  readonly stateDir: string;
  /** Where the raw responses are written. */
  readonly out: string;
  readonly say: (line: string) => void;
}

/** One models response the engine received, as it came. */
export interface Caught {
  readonly url: string;
  readonly status: number;
  readonly body: unknown;
}

/** The engine's own model-list requests, Codex's and Grok's. */
export function isCatalog(url: string): boolean {
  const { pathname } = new URL(url);

  return pathname.endsWith('/models') || pathname === '/v1/language-models';
}

/**
 * `fetch` as it is, keeping a copy of each models response's body; the
 * response the engine reads is the one `fetch` returned, untouched.
 */
export function copying(fetch: FxFetch, caught: Caught[]): FxFetch {
  return async (url, init) => {
    const response = await fetch(url, init);

    if (isCatalog(url)) {
      const text = await response.clone().text();
      let body: unknown = text;

      try {
        body = JSON.parse(text);
      } catch {
        // Kept as text.
      }

      caught.push({ url, status: response.status, body });
    }

    return response;
  };
}

/** A listed model, as far as its entry says; `?` where it says nothing. */
export interface Listed {
  readonly id: string;
  readonly window: string;
  readonly levels: string;
  readonly default: string;
}

/**
 * The models of one response: Codex's `models[]` (`slug`, `context_window`,
 * `supported_reasoning_levels`, `default_reasoning_level`) or a `data[]`
 * list. Fields another shape names differently show as `?`: the raw file is
 * what M1 reads.
 */
export function listed(body: unknown): Listed[] {
  const record = (body ?? {}) as Record<string, unknown>;
  const entries = [record['models'], record['data']].find(Array.isArray) as
    Record<string, unknown>[] | undefined;

  return (entries ?? []).map((entry) => {
    const levels = entry['supported_reasoning_levels'];

    return {
      id: String(entry['slug'] ?? entry['id'] ?? '?'),
      window: String(entry['context_window'] ?? '?'),
      levels: Array.isArray(levels)
        ? levels
            .map((level: unknown) =>
              typeof level === 'object' && level !== null
                ? String((level as Record<string, unknown>)['effort'] ?? '?')
                : String(level),
            )
            .join(' ')
        : '?',
      default: String(entry['default_reasoning_level'] ?? '?'),
    };
  });
}

/** Runs the check; what it found, for tests. */
export async function riffModels(options: RiffModelsOptions): Promise<{
  readonly caught: readonly Caught[];
  readonly reply: string;
}> {
  const { plan, say } = options;
  const model = planModels(plan)[0]?.id ?? '';

  say(`plan:   ${plan}`);
  say(`model:  ${model} (riff's default for the plan)`);
  say(`prompt: ${PROMPT}`);
  say('Sending one turn.');

  const cell = credentialCell(options.secrets, options.stateDir, plan);

  // A plan with no sign-in stops here, before anything is sent.
  await cell.check();

  const caught: Caught[] = [];
  const agent = createFxAgent({
    ...options.backend,
    name: 'riff-models',
    ...planProvider(cell, plan).options,
    fetch: copying(options.fetch, caught),
    model,
  });
  let reply = '';

  try {
    const id = await agent.newSessionId();
    const turn = agent
      .session(id, { model: { id: model, effort: 'default' } })
      .prompt([{ type: 'text', text: PROMPT }]);

    for await (const event of turn) {
      if (event.type === 'text_delta') {
        reply += event.delta;
      }
    }

    const result = await turn.result;

    say(`reply:  ${reply.trim()} (${result.stopReason})`);
  } finally {
    await agent.close();
  }

  await mkdir(dirname(options.out), { recursive: true });
  await writeFile(
    options.out,
    `${JSON.stringify({ plan, model, prompt: PROMPT, reply, responses: caught }, null, 2)}\n`,
  );

  if (caught.length === 0) {
    say('The engine asked for no model list in this turn.');
  }

  for (const response of caught) {
    say('');
    say(`${response.url} (HTTP ${response.status})`);

    for (const each of listed(response.body)) {
      say(
        `  ${each.id}  window ${each.window}  levels ${each.levels}  default ${each.default}`,
      );
    }
  }

  say('');
  say(`The raw responses are in ${options.out}.`);

  return { caught, reply };
}

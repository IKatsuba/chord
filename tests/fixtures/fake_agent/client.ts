/**
 * What the client said at `initialize` it takes, which the scenarios play to.
 * `main.ts` reads it from the request; the scenarios read it as it stands.
 */
import * as acp from '@agentclientprotocol/sdk';

/** Whether the client said at `initialize` that it takes plans by id. */
export let clientTakesPlans = false;

/**
 * How the client said at `initialize` it takes a command's output, as
 * Claude's adapter reads its `_meta`: in pieces, whole, or not at all.
 */
export let clientTerminalOutput: 'delta' | 'whole' | 'none' = 'none';

/**
 * Whether the client said at `initialize` that it takes compactions by id, as
 * both adapters read `clientCapabilities.session.compaction`.
 */
export let clientTakesCompaction = false;

/**
 * Whether the client said at `initialize` that it takes subagents as sessions
 * of their own, as both adapters read `clientCapabilities.subagents`.
 */
export let clientTakesSubagents = false;

/** Takes what the client declared in `initialize`. */
export function readCapabilities(params: acp.InitializeRequest): void {
  const meta = params.clientCapabilities?._meta;

  clientTakesPlans =
    params.clientCapabilities?.plan !== undefined &&
    params.clientCapabilities.plan !== null;
  clientTakesSubagents =
    typeof params.clientCapabilities?.subagents === 'object' &&
    params.clientCapabilities.subagents !== null;
  clientTakesCompaction =
    typeof params.clientCapabilities?.session?.compaction === 'object' &&
    params.clientCapabilities.session.compaction !== null;
  clientTerminalOutput =
    meta?.terminal_output_delta === true
      ? 'delta'
      : meta?.terminal_output === true
        ? 'whole'
        : 'none';
}

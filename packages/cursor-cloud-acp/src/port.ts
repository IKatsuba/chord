/**
 * The seam between the adapter and `@cursor/sdk`: what the adapter uses of
 * the SDK, taken from its published types, so a test's fake Port is checked
 * against the real declarations. Type-only: cursor.ts is the one real Port,
 * and everything it answers throws `CursorError`s (errors.ts), not the SDK's.
 */
import type {
  Agent,
  AgentOptions,
  Cursor,
  ListResult,
  ListRunsOptions,
  Run,
  SDKAgent,
} from '@cursor/sdk';

/** One run of a cloud agent, as a prompt drives it. */
export type PortRun = Pick<
  Run,
  | 'id'
  | 'agentId'
  | 'supports'
  | 'unsupportedReason'
  | 'stream'
  | 'wait'
  | 'cancel'
  | 'conversation'
  | 'status'
>;

/** One cloud agent, a session of the adapter's. */
export interface PortAgent extends Pick<
  SDKAgent,
  'agentId' | 'model' | 'listArtifacts' | typeof Symbol.asyncDispose
> {
  send(...args: Parameters<SDKAgent['send']>): Promise<PortRun>;
}

/** What the adapter calls on Cursor. */
export interface Port {
  readonly me: typeof Cursor.me;
  readonly models: typeof Cursor.models.list;
  readonly login: typeof Cursor.auth.login;
  readonly logout: typeof Cursor.auth.logout;
  readonly status: typeof Cursor.auth.status;
  readonly create: (options: AgentOptions) => Promise<PortAgent>;
  readonly resume: (
    agentId: string,
    options: Partial<AgentOptions>,
  ) => Promise<PortAgent>;
  readonly list: typeof Agent.list;
  readonly get: typeof Agent.get;
  readonly listRuns: (
    agentId: string,
    options: ListRunsOptions,
  ) => Promise<ListResult<PortRun>>;
}

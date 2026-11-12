/**
 * The real Port, over `@cursor/sdk`. Every call it answers, and every call on
 * an agent or run it hands out, throws the SDK's errors as `CursorError`s,
 * told apart here by class and code alone.
 */
import * as sdk from '@cursor/sdk';
import { CursorError, type Kind } from './errors.ts';
import type { Port, PortAgent, PortRun } from './port.ts';

/** The SDK's error in the adapter's kinds; anything else as it came. */
export function normalise(error: unknown, from = sdk): unknown {
  if (!(error instanceof from.CursorSdkError)) {
    return error;
  }

  return new CursorError(kind(error, from), error.message, {
    code: error.code,
    requestId: error.requestId,
    helpUrl:
      error instanceof from.IntegrationNotConnectedError
        ? error.helpUrl
        : undefined,
    cause: error,
  });
}

function kind(error: sdk.CursorSdkError, from: typeof sdk): Kind {
  if (error instanceof from.AuthenticationError) {
    return 'auth';
  }

  // Before ConfigurationError, which it extends.
  if (error instanceof from.IntegrationNotConnectedError) {
    return 'integration';
  }

  if (error instanceof from.RateLimitError) {
    return 'rate-limit';
  }

  if (error instanceof from.AgentBusyError) {
    return 'busy';
  }

  if (error instanceof from.AgentNotFoundError) {
    return 'not-found';
  }

  if (
    error instanceof from.ConfigurationError &&
    error.code === 'agent_archived'
  ) {
    return 'archived';
  }

  if (error instanceof from.NetworkError) {
    return 'network';
  }

  return 'other';
}

/** `call`'s answer, its failure normalised. */
async function guarded<T>(call: () => Promise<T>, from: typeof sdk) {
  try {
    return await call();
  } catch (error) {
    throw normalise(error, from);
  }
}

function run(real: sdk.Run, from: typeof sdk): PortRun {
  return {
    id: real.id,
    agentId: real.agentId,
    supports: (operation) => real.supports(operation),
    async *stream() {
      try {
        yield* real.stream();
      } catch (error) {
        throw normalise(error, from);
      }
    },
    wait: () => guarded(() => real.wait(), from),
    cancel: () => guarded(() => real.cancel(), from),
    conversation: () => guarded(() => real.conversation(), from),
  };
}

function agent(real: sdk.SDKAgent, from: typeof sdk): PortAgent {
  return {
    agentId: real.agentId,
    // A getter: the SDK updates it after each send that sets a model.
    get model() {
      return real.model;
    },
    close: () => real.close(),
    listArtifacts: () => guarded(() => real.listArtifacts(), from),
    send: async (...args) =>
      run(await guarded(() => real.send(...args), from), from),
  };
}

/** The Port over `from`, the SDK itself but in a test. */
export function cursorPort(from: typeof sdk = sdk): Port {
  const { Agent, Cursor } = from;

  return {
    me: (options) => guarded(() => Cursor.me(options), from),
    models: (options) => guarded(() => Cursor.models.list(options), from),
    login: (options) => guarded(() => Cursor.auth.login(options), from),
    logout: (options) => guarded(() => Cursor.auth.logout(options), from),
    status: (options) => guarded(() => Cursor.auth.status(options), from),
    create: async (options) =>
      agent(await guarded(() => Agent.create(options), from), from),
    resume: async (id, options) =>
      agent(await guarded(() => Agent.resume(id, options), from), from),
    list: (options) => guarded(() => Agent.list(options), from),
    listRuns: async (id, options) => {
      const { items, nextCursor } = await guarded(
        () => Agent.listRuns(id, options),
        from,
      );

      return {
        items: items.map((each) => run(each, from)),
        ...(nextCursor === undefined ? {} : { nextCursor }),
      };
    },
  };
}

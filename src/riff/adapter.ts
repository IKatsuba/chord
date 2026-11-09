/**
 * riff's ACP agent: libfx turned into an ACP agent on the SDK's agent side,
 * over any `Stream`, so tests drive it over an in-memory pair (CHD-485, "The
 * protocol between the window and riff"). What is not here is -32601.
 */
import {
  agent,
  type AgentConnection,
  type InitializeResponse,
  type Stream,
} from '@agentclientprotocol/sdk/unstable';
import { RIFF } from './start.ts';

export interface RiffOptions {
  /** chord's version, which riff reports as its own. */
  readonly version: string;
}

/** `initialize`'s answer, as the design gives it. */
export function riffInit(version: string): InitializeResponse {
  return {
    protocolVersion: 1,
    agentInfo: { name: RIFF, title: RIFF, version },
    authMethods: [
      {
        id: 'chatgpt',
        name: 'ChatGPT plan',
        description: 'Sign in to ChatGPT in chord',
      },
      {
        id: 'grok',
        name: 'Grok plan',
        description: 'Sign in to Grok in chord',
      },
    ],
    agentCapabilities: {
      loadSession: false,
      promptCapabilities: { image: true, audio: false, embeddedContext: true },
      mcpCapabilities: { http: true, sse: true },
      sessionCapabilities: { resume: {}, close: {} },
    },
    // At the top, where chord reads it from every agent, as Claude's and
    // Codex's adapters send it; the design drew it under the capabilities.
    _meta: { steering: { supported: true } },
  };
}

export function connectRiff(
  stream: Stream,
  options: RiffOptions,
): AgentConnection {
  return agent({ name: RIFF })
    .onRequest('initialize', () => riffInit(options.version))
    .connect(stream);
}

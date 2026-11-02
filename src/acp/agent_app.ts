/**
 * chord's ACP agent side: the SDK's app and the methods it serves, each handed
 * on to `runAcp`, which holds what they do. What is not here is -32601.
 */
import {
  agent,
  type AgentConnection,
  type AgentRequestContext,
  type CancelNotification,
  type CloseSessionRequest,
  type CloseSessionResponse,
  type InitializeRequest,
  type InitializeResponse,
  type NewSessionRequest,
  type NewSessionResponse,
  type PromptRequest,
  type PromptResponse,
  type SetSessionConfigOptionRequest,
  type SetSessionConfigOptionResponse,
  type SetSessionModeRequest,
  type SetSessionModeResponse,
  type Stream,
} from '@agentclientprotocol/sdk/unstable';

/** What a request hands on beside its params. */
export type AcpRequest<Params> = Pick<
  AgentRequestContext<Params>,
  'params' | 'requestId' | 'signal'
>;

export interface AcpHandlers {
  initialize(request: AcpRequest<InitializeRequest>): InitializeResponse;
  newSession(
    request: AcpRequest<NewSessionRequest>,
  ): Promise<NewSessionResponse>;
  prompt(request: AcpRequest<PromptRequest>): Promise<PromptResponse>;
  cancel(params: CancelNotification): void;
  setConfigOption(
    request: AcpRequest<SetSessionConfigOptionRequest>,
  ): Promise<SetSessionConfigOptionResponse>;
  setMode(
    request: AcpRequest<SetSessionModeRequest>,
  ): Promise<SetSessionModeResponse>;
  close(
    request: AcpRequest<CloseSessionRequest>,
  ): Promise<CloseSessionResponse>;
}

export function connectAgentApp(
  handlers: AcpHandlers,
  stream: Stream,
): AgentConnection {
  return agent({ name: 'chord' })
    .onRequest('initialize', (request) => handlers.initialize(request))
    .onRequest('session/new', (request) => handlers.newSession(request))
    .onRequest('session/prompt', (request) => handlers.prompt(request))
    .onNotification('session/cancel', ({ params }) => handlers.cancel(params))
    .onRequest('session/set_config_option', (request) =>
      handlers.setConfigOption(request),
    )
    .onRequest('session/set_mode', (request) => handlers.setMode(request))
    .onRequest('session/close', (request) => handlers.close(request))
    .connect(stream);
}

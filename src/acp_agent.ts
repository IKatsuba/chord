/**
 * `chord acp`: chord with no interface, an ACP agent on its input and output,
 * as `headless.ts` is to `-p`. One client connection, any number of sessions,
 * each its own `Conversation` and its own agent process.
 */
import {
  type AgentConnection,
  type ClientCapabilities,
  type CreateElicitationResponse,
  type JsonRpcId,
  type LoadSessionRequest,
  type LoadSessionResponse,
  type McpServer,
  MessageTooLargeError,
  ndJsonStream,
  type NewSessionResponse,
  RequestError,
  type RequestPermissionResponse,
  type ResumeSessionRequest,
  type SessionNotification,
  type SessionUpdate,
  type Usage,
} from '@agentclientprotocol/sdk/unstable';
import { type AcpRequest, connectAgentApp } from './acp/agent_app.ts';
import { seeingWrites } from './acp/stdio.ts';
import {
  NO_TURNS,
  reduceTurns,
  type TurnInput,
  turnOf,
  type Turns,
} from './acp/upstream_turns.ts';
import { transportOf } from './mcp.ts';
import { DIMCODE_WORDS, dimcodeAtRisk } from './notices.ts';
import {
  Conversation,
  type ConversationEvent,
  type Starting,
} from './session/conversation.ts';
import {
  createLeaving,
  type LeaveExit,
  type LeaveReason,
  type LeaveStep,
} from './session/leaving.ts';
import { FileRecording } from './session/record.ts';
import type { OpenSessionOptions, Session } from './session/session.ts';
import {
  earlierSessions,
  readRecords,
  type Resume,
  ResumeError,
  sessionById,
} from './session/sessions.ts';
import { signInLines, type SignIn } from './session/sign_in.ts';
import {
  failureLines,
  type StartFailure,
  stepWords,
} from './session/start_failure.ts';
import {
  aliasFor,
  answeredConfig,
  asksIn,
  childOf,
  configChange,
  configSetter,
  elicitationReplyOf,
  mapUpdate,
  messageChunk,
  permissionAnswerOf,
  planAnswerOf,
  planPermission,
  promptOf,
  upstreamIdOf,
  type UpstreamSession,
  upstreamSession,
} from './session/upstream.ts';
import type { TurnResult } from './session/transcript/types.ts';

/** The `_meta` key chord says its own of ACP under. */
const ACP_META = 'chord/acp';

/**
 * What a person who ran it by hand reads on stderr; only a stdin that is a
 * terminal is a person's. A client's stdin is a pipe, and sees no note.
 */
export function byHandNote(stdinIsTerminal: boolean): readonly string[] {
  return stdinIsTerminal
    ? [
        'chord: acp serves ACP on stdin and stdout, for a client that starts it.',
        'chord: nothing to press here. Ctrl-D or Ctrl-C leaves; `chord` opens a window.',
      ]
    : [];
}

/** What a session's directory decides. */
export interface AcpPlace {
  /** Its settings' and `.mcp.json`'s servers; a client's are laid over them. */
  readonly mcpServers: readonly McpServer[];
  readonly noMcpServers?: boolean;
  readonly starting?: Starting;
}

export interface AcpOptions {
  readonly input: ReadableStream<Uint8Array>;
  readonly output: WritableStream<Uint8Array>;
  /** One line for the person; it must not throw. */
  stderr(line: string): void;
  /** Ends the process: `process.exit`, or death by the signal. */
  exit(how: LeaveExit): void;
  /** The one agent this process runs, by the name chord knows it. */
  readonly agent: string;
  readonly agentCommand?: string | string[];
  readonly version: string;
  /** Where records are kept, as the window's are. */
  readonly stateDir: string;
  open(options: OpenSessionOptions): Promise<Session>;
  place(cwd: string): Promise<AcpPlace>;
  readonly leaveMs?: number;
  readonly drainMs?: number;
}

/** A running `chord acp`. */
export interface AcpRun {
  /** The one way out, for what starts it from outside: a signal, a crash. */
  leave(reason: LeaveReason): Promise<void>;
}

/** A session this process holds, from its start until its agent is gone. */
interface Entry {
  readonly conversation: Conversation;
  /** Its name on stderr, for a way out it holds up. */
  readonly name: string;
  /** None until it is up. */
  upstream?: UpstreamSession;
  /** Whether the client has its id: what comes before waits for that. */
  live: boolean;
  /** What goes up once the client has its id. */
  held: (() => void)[];
  /**
   * Set on a `session/load`: its past, which goes up ahead of the answer.
   * A resume keeps nothing of it.
   */
  past?: ConversationEvent[];
  /** The id a load or a resume claimed for it. */
  reopens?: string;
  /** While the conversation replays the session's past, which is no news. */
  replaying: boolean;
  turns: Turns;
  opening?:
    | {
        readonly requestId: JsonRpcId;
        resolve(answer: NewSessionResponse): void;
        reject(error: unknown): void;
      }
    | undefined;
  /** Its agent went: it takes no more prompts, and closes when it can. */
  gone: boolean;
  noticed: boolean;
  closing?: Promise<void>;
}

function closingError(): RequestError {
  return new RequestError(-32603, 'chord is closing');
}

export function runAcp(options: AcpOptions): AcpRun {
  const { agent } = options;
  const wire = seeingWrites(ndJsonStream(options.output, options.input));
  /** Each session the client can name, by the name it has for it. */
  const sessions = new Map<string, Entry>();
  /**
   * The ids a load or a resume is opening again: taken from before its first
   * await until it is up or has failed, or a second could open one record twice.
   */
  const reopening = new Set<string>();
  /** Every session not closed yet, those still starting and those gone too. */
  const entries = new Set<Entry>();
  /** Each ask out with the client, by chord's id for it; its withdrawal. */
  const asks = new Map<string, AbortController>();
  /** Each `session/prompt` not yet answered. */
  const answers = new Map<
    JsonRpcId,
    {
      resolve(answer: { stopReason: string; usage?: unknown }): void;
      reject(error: unknown): void;
    }
  >();
  let capabilities: ClientCapabilities | undefined;
  let starts = 0;

  const say = (line: string) => options.stderr(line);
  const send = (notification: SessionNotification) => {
    connection.client.notify('session/update', notification).catch(() => {
      // The connection went; the way out has it from there.
    });
  };

  const agentState = (entry: Entry) => entry.conversation.session?.agentState();

  const closeEntry = (entry: Entry): Promise<void> => {
    entry.closing ??= entry.conversation.close().finally(() => {
      entries.delete(entry);
    });

    return entry.closing;
  };

  const relay = (
    entry: Entry,
    update: SessionUpdate,
    subagentId?: string,
  ): void => {
    if (entry.upstream === undefined || !entry.live) {
      entry.held.push(() => relay(entry, update, subagentId));

      return;
    }

    const mapped = mapUpdate(
      entry.upstream,
      capabilities ?? {},
      update,
      subagentId,
    );

    entry.upstream = mapped.session;

    if (mapped.notification !== undefined) {
      send(mapped.notification);
    }
  };

  const tellConfig = (entry: Entry): void => {
    const state = agentState(entry);

    if (entry.upstream === undefined || !entry.live || state === undefined) {
      return;
    }

    const changed = configChange(entry.upstream, state);

    entry.upstream = changed.session;

    if (changed.notification !== undefined) {
      send(changed.notification);
    }
  };

  /**
   * One request to the client, settled once. A late answer, after its ask was
   * withdrawn, finds nothing to settle; an error is no answer, whatever the ask
   * makes of that. Nothing is settled when the connection went: the session's
   * close tells the agent `cancelled`.
   */
  const ask = <Answer>(
    id: string,
    method: string,
    params: object,
    settle: (answer: Answer | undefined) => void,
  ): void => {
    const withdrawal = new AbortController();

    asks.set(id, withdrawal);
    connection.client
      .request<Answer, object>(method, params, {
        cancellationSignal: withdrawal.signal,
      })
      .then(
        (answer) => {
          if (asks.delete(id)) {
            settle(answer);
          }
        },
        (error: unknown) => {
          if (!connection.signal.aborted && asks.delete(id)) {
            say(
              `chord: the client answered ${method} with an error: ${
                error instanceof Error ? error.message : String(error)
              }`,
            );
            settle(undefined);
          }
        },
      );
  };

  const withdrawn = (id: string): void => {
    asks.get(id)?.abort();
    asks.delete(id);
  };

  /** Runs once the client has the session's id; at once when it has. */
  const once = (entry: Entry, go: () => void): void => {
    if (entry.live) {
      go();
    } else {
      entry.held.push(go);
    }
  };

  const askPermission = (entry: Entry, id: string): void => {
    const { conversation, upstream } = entry;
    const request = conversation.permissionRequest(id);

    if (request === undefined || upstream === undefined) {
      return;
    }

    if (!asksIn(upstream, request.sessionId)) {
      say(`chord: refused a permission for a session it does not know`);
      conversation.reject(id);

      return;
    }

    // It can name no session that client knows, and must not wait unseen.
    if (request.sessionId !== upstream.agentId && !capabilities?.subagents) {
      say(
        `chord: refused a subagent's permission: the client takes no subagents`,
      );
      conversation.reject(id);

      return;
    }

    ask<RequestPermissionResponse>(
      id,
      'session/request_permission',
      { ...request.raw, sessionId: upstreamIdOf(upstream, request.sessionId) },
      (response) => {
        const answer = permissionAnswerOf(request.options, response);

        if (answer === 'reject') {
          conversation.reject(id);
        } else {
          conversation.choose(id, answer.optionId);
        }
      },
    );
  };

  const askElicitation = (entry: Entry, id: string): void => {
    const { conversation, upstream } = entry;
    const request = conversation.elicitationRequest(id);

    if (request === undefined || upstream === undefined) {
      return;
    }

    const { sessionId } = request;

    // One scoped to a request names none of the client's; a subagent's, none
    // that client knows.
    if (
      sessionId === undefined ||
      !asksIn(upstream, sessionId) ||
      (sessionId !== upstream.agentId && !capabilities?.subagents)
    ) {
      conversation.answer(id, { action: 'cancel' });

      return;
    }

    ask<CreateElicitationResponse>(
      id,
      'elicitation/create',
      { ...request.raw, sessionId: upstreamIdOf(upstream, sessionId) },
      (response) => conversation.answer(id, elicitationReplyOf(response)),
    );
  };

  /** What chord carries on past: stderr always, and `notice` for who takes it. */
  const warn = (entry: Entry, message: string): void => {
    say(`chord: ${message}`);
    relay(entry, {
      sessionUpdate: 'notice',
      severity: 'warning',
      title: message,
    });
  };

  const tellDimcode = (entry: Entry): void => {
    const session = entry.conversation.session;

    if (
      entry.noticed ||
      session === undefined ||
      !dimcodeAtRisk(agent, session.options())
    ) {
      return;
    }

    entry.noticed = true;

    for (const paragraph of DIMCODE_WORDS.paragraphs) {
      say(`chord: ${paragraph}`);
    }

    relay(entry, {
      sessionUpdate: 'notice',
      severity: 'warning',
      title: DIMCODE_WORDS.title,
      description: DIMCODE_WORDS.paragraphs.join('\n\n'),
    });
  };

  const answerOf = (result: TurnResult) =>
    result.status === 'failed'
      ? new RequestError(-32603, result.error.message)
      : {
          stopReason: result.stopReason,
          ...(result.usage === undefined
            ? {}
            : { usage: result.usage as Usage }),
        };

  const step = (entry: Entry, input: TurnInput): void => {
    const { turns, sends } = reduceTurns(entry.turns, input);

    entry.turns = turns;

    for (const send of sends) {
      switch (send.type) {
        case 'answer': {
          const answer = answerOf(send.result);
          const waiting = answers.get(send.requestId);

          answers.delete(send.requestId);

          if (answer instanceof RequestError) {
            waiting?.reject(answer);
          } else {
            waiting?.resolve(answer);
          }

          break;
        }
        case 'cancelled':
          answers.get(send.requestId)?.resolve({ stopReason: 'cancelled' });
          answers.delete(send.requestId);

          break;
        case 'session_gone': {
          const waiting = answers.get(send.requestId);

          answers.delete(send.requestId);
          waiting?.reject(
            RequestError.sessionNotFound(entry.upstream?.upstreamId ?? ''),
          );
          // Not left for a dead session to play.
          entry.conversation.cancelPrompt(send.turnId);

          break;
        }
        case 'message':
          relay(
            entry,
            messageChunk(entry.upstream?.upstreamId ?? '', send.text, send.from)
              .update,
          );

          break;
      }
    }
  };

  const failedStart = (
    message: string,
    signIn: SignIn | undefined,
    failure: StartFailure | undefined,
  ): RequestError => {
    const words = stepWords(message, failure);
    const lines = [
      ...failureLines(agent, failure),
      ...(signIn === undefined ? [] : signInLines(agent, signIn)),
    ];

    return new RequestError(signIn === undefined ? -32603 : -32000, words, {
      lines,
    });
  };

  const connected = (entry: Entry, agentId: string): void => {
    const { opening } = entry;
    const state = agentState(entry);

    if (opening === undefined || state === undefined) {
      return;
    }

    // A reopened session is under the id the client asked for, claimed for it.
    // Anything else keeps clear of what is claimed as of what is live.
    const upstreamId =
      entry.reopens === agentId
        ? agentId
        : aliasFor(new Set([...sessions.keys(), ...reopening]), agentId);
    const session = entry.conversation.session;
    const { session: upstream, configOptions } = answeredConfig(
      upstreamSession(agentId, upstreamId),
      state,
    );

    entry.upstream = upstream;
    entry.opening = undefined;

    sessions.set(upstreamId, entry);

    const release = () => {
      entry.live = true;

      for (const go of entry.held.splice(0)) {
        go();
      }

      tellConfig(entry);
    };

    // The client asked for this id: its past goes ahead of the answer. A new
    // id goes first, as nothing of the session can be placed without it.
    if (entry.past === undefined) {
      void wire.expect(opening.requestId).then(release);
    } else {
      entry.live = true;

      for (const event of entry.past.splice(0)) {
        if (event.type === 'prompt') {
          relay(entry, messageChunk(upstreamId, event.text, event.from).update);
        } else if (event.type === 'update') {
          relay(entry, event.update, event.subagentId);
        }
      }
    }

    opening.resolve({
      sessionId: upstreamId,
      configOptions,
      _meta: {
        [ACP_META]: { image: session?.takesImages() === true },
        ...(session === undefined || session.heldBack.length === 0
          ? {}
          : { 'chord/held_back': session.heldBack }),
      },
    });

    if (entry.past !== undefined) {
      release();
    }

    tellDimcode(entry);
  };

  const heard = (entry: Entry, event: ConversationEvent): void => {
    if (entry.replaying) {
      entry.past?.push(event);

      return;
    }

    switch (event.type) {
      case 'update':
        relay(entry, event.update, event.subagentId);
        tellConfig(entry);

        break;
      case 'modes':
      case 'model':
        tellConfig(entry);

        break;
      case 'options':
        tellConfig(entry);
        tellDimcode(entry);

        break;
      case 'prompt':
        step(entry, {
          type: 'prompt',
          turnId: event.turnId,
          text: event.text,
          ...(event.from === undefined ? {} : { from: event.from }),
          ...(event.into === undefined ? {} : { into: event.into }),
        });

        break;
      case 'result':
        step(entry, {
          type: 'result',
          turnId: event.turnId,
          result: event.result,
        });

        if (entry.gone && entry.turns.lost === undefined) {
          void closeEntry(entry).catch(() => {});
        }

        break;
      case 'queue_withdrawn':
        step(entry, {
          type: 'queue_withdrawn',
          ...(event.turnIds === undefined ? {} : { turnIds: event.turnIds }),
        });

        break;
      case 'cycle_started':
      case 'self_started':
        step(entry, { type: event.type, turnId: event.turnId });

        break;
      case 'disconnected':
        entry.gone = true;

        if (entry.upstream !== undefined) {
          sessions.delete(entry.upstream.upstreamId);
        }

        step(entry, { type: 'disconnected' });

        if (entry.turns.lost === undefined) {
          void closeEntry(entry).catch(() => {});
        }

        break;
      case 'permission_requested':
        once(entry, () => askPermission(entry, event.permission.id));

        break;
      case 'elicitation_requested':
        once(entry, () => askElicitation(entry, event.elicitation.id));

        break;
      case 'plan_requested':
        once(entry, () => {
          const { plan } = event;

          ask<RequestPermissionResponse>(
            plan.id,
            'session/request_permission',
            planPermission(entry.upstream?.upstreamId ?? '', plan),
            (response) =>
              entry.conversation.answerPlan(
                plan.id,
                planAnswerOf(plan, response),
              ),
          );
        });

        break;
      case 'permission_settled':
      case 'elicitation_settled':
      case 'plan_settled':
        // The client's own answer has left the table already.
        withdrawn(event.id);

        break;
      case 'connected':
        connected(entry, event.sessionId);

        break;
      case 'connect_failed': {
        const { opening } = entry;

        entry.opening = undefined;

        const error = failedStart(event.message, event.signIn, event.failure);

        void closeEntry(entry)
          .catch(() => {})
          .then(() => opening?.reject(error));

        break;
      }
      case 'failed':
        // A set the client asked for is that request's error instead.
        if (!/^(mode|model)-/.test(event.turnId)) {
          warn(entry, event.message);
        }

        break;
      case 'warned':
        warn(entry, event.message);

        break;
      default:
        break;
    }
  };

  const openEntry = (
    place: AcpPlace,
    cwd: string,
    servers: readonly McpServer[],
    resume?: { readonly from: Resume; readonly replays: boolean },
  ): Entry => {
    starts += 1;

    const entry: Entry = {
      name: `session ${starts}`,
      live: false,
      held: [],
      turns: NO_TURNS,
      gone: false,
      noticed: false,
      replaying: false,
      ...(resume?.replays === true ? { past: [] } : {}),
      ...(resume === undefined ? {} : { reopens: resume.from.sessionId }),
      conversation: new Conversation(
        (signal) =>
          options.open({
            agent,
            cwd,
            signal,
            ...(options.agentCommand === undefined
              ? {}
              : { agentCommand: options.agentCommand }),
            mcpServers: servers,
            ...(resume === undefined ? {} : { resume: resume.from }),
            onElicitationComplete: (params) => {
              connection.client
                .notify('elicitation/complete', params)
                .catch(() => {});
            },
            ...(place.noMcpServers === true ? { noMcpServers: true } : {}),
          }),
        (event) => heard(entry, event),
        Date.now,
        place.starting,
        new FileRecording(options.stateDir, (message) => warn(entry, message)),
        (replay) => {
          entry.replaying = true;

          try {
            replay();
          } finally {
            entry.replaying = false;
          }
        },
      ),
    };

    entries.add(entry);

    return entry;
  };

  /** Until the session is up, its start given up on by a cancel of the request. */
  const up = (
    entry: Entry,
    requestId: JsonRpcId,
    signal: AbortSignal,
  ): Promise<NewSessionResponse> =>
    new Promise((resolve, reject) => {
      entry.opening = { requestId, resolve, reject };

      signal.addEventListener(
        'abort',
        () => {
          entry.opening = undefined;

          void closeEntry(entry)
            .catch(() => {})
            .then(() => reject(RequestError.requestCancelled()));
        },
        { once: true },
      );
      entry.conversation.start();
    });

  /** What a client's servers and the session's directory start a session on. */
  const placed = async (
    params: { readonly cwd: string; readonly mcpServers?: McpServer[] | null },
    signal: AbortSignal,
  ): Promise<{ place: AcpPlace; servers: McpServer[] }> => {
    const asked = params.mcpServers ?? [];
    const refused = asked.find((server) => transportOf(server) === 'acp');

    if (refused !== undefined) {
      throw RequestError.invalidParams(
        undefined,
        `MCP server ${refused.name} has an acp transport, which chord does not take from a client.`,
      );
    }

    const place = await options.place(params.cwd);

    refuseIfClosing();

    // A cancel while the place was read: its signal has fired already, and
    // no agent is to be started for it.
    if (signal.aborted) {
      throw RequestError.requestCancelled();
    }

    // A client's is the nearest layer, by name.
    const servers = new Map(
      [...place.mcpServers, ...asked].map((server) => [server.name, server]),
    );

    return { place, servers: [...servers.values()] };
  };

  /** A session opened again, under the id the client asked for. */
  const reopened = async (
    {
      params,
      requestId,
      signal,
    }: AcpRequest<LoadSessionRequest | ResumeSessionRequest>,
    replays: boolean,
  ): Promise<LoadSessionResponse> => {
    refuseIfClosing();

    const { sessionId } = params;

    if (sessions.has(sessionId) || reopening.has(sessionId)) {
      throw RequestError.invalidParams(
        undefined,
        `Session ${sessionId} is already open here.`,
      );
    }

    reopening.add(sessionId);

    try {
      const { sessionId: _id, ...answer } = await reopen(
        { params, requestId, signal },
        replays,
      );

      return answer;
    } finally {
      reopening.delete(sessionId);
    }
  };

  const reopen = async (
    {
      params,
      requestId,
      signal,
    }: AcpRequest<LoadSessionRequest | ResumeSessionRequest>,
    replays: boolean,
  ): Promise<NewSessionResponse> => {
    const { sessionId, cwd } = params;
    let from: Resume;

    try {
      from = sessionById(await readRecords(options.stateDir), sessionId, {
        agent,
        cwd,
      });
    } catch (error) {
      if (error instanceof ResumeError) {
        throw RequestError.invalidParams(undefined, error.message);
      }

      throw error;
    }

    if (from.cwd !== cwd) {
      throw RequestError.invalidParams(
        undefined,
        `Session ${sessionId} is in ${from.cwd}.`,
      );
    }

    const { place, servers } = await placed(params, signal);

    return up(
      openEntry(place, cwd, servers, { from, replays }),
      requestId,
      signal,
    );
  };

  const refuseIfClosing = () => {
    if (leaving.started()) {
      throw closingError();
    }
  };

  const named = (sessionId: string): Entry => {
    const entry = sessions.get(sessionId);

    if (entry === undefined) {
      throw RequestError.sessionNotFound(sessionId);
    }

    return entry;
  };

  /** A set's refusal as that request's error, the agent's words kept. */
  const refusal = (error: unknown): RequestError =>
    error instanceof RequestError
      ? error
      : new RequestError(
          -32603,
          error instanceof Error ? error.message : String(error),
        );

  const leaving = createLeaving({
    answer: () => {
      for (const id of [...asks.keys()]) {
        withdrawn(id);
      }

      for (const entry of [...entries]) {
        for (const requestId of entry.turns.bound.values()) {
          void wire.expect(requestId);
        }

        step(entry, { type: 'closing' });

        const { opening } = entry;

        if (opening !== undefined) {
          entry.opening = undefined;

          void wire.expect(opening.requestId);
          opening.reject(closingError());
        }
      }
    },
    drained: () => wire.drained(),
    closeConnection: () => {
      connection.close();
    },
    get steps(): readonly LeaveStep[] {
      return [...entries].map((entry) => ({
        name: entry.upstream?.upstreamId ?? entry.name,
        run: () => closeEntry(entry),
      }));
    },
    stderr: say,
    exit: options.exit,
    ...(options.leaveMs === undefined ? {} : { leaveMs: options.leaveMs }),
    ...(options.drainMs === undefined ? {} : { drainMs: options.drainMs }),
  });

  const connection: AgentConnection = connectAgentApp(
    {
      initialize: ({ params }) => {
        capabilities ??= params.clientCapabilities ?? {};

        return {
          protocolVersion: 1,
          agentInfo: { name: 'chord', version: options.version },
          authMethods: [],
          agentCapabilities: {
            loadSession: true,
            promptCapabilities: {
              image: true,
              audio: false,
              embeddedContext: false,
            },
            mcpCapabilities: { http: true, sse: true },
            sessionCapabilities: { list: {}, resume: {}, close: {} },
          },
          _meta: {
            [ACP_META]: { version: 1, extensions: {}, agent: { name: agent } },
          },
        };
      },
      newSession: async ({ params, requestId, signal }) => {
        refuseIfClosing();

        const { place, servers } = await placed(params, signal);

        return up(openEntry(place, params.cwd, servers), requestId, signal);
      },
      listSessions: async ({ cwd }) => ({
        sessions: earlierSessions(await readRecords(options.stateDir), {
          agent,
          ...(typeof cwd === 'string' ? { cwd } : {}),
        }).map(({ resume, prompt, lastUsedAt }) => ({
          sessionId: resume.sessionId,
          cwd: resume.cwd,
          title: prompt,
          updatedAt: lastUsedAt,
        })),
      }),
      loadSession: (request) => reopened(request, true),
      resumeSession: (request) => reopened(request, false),
      prompt: ({ params, requestId, signal }) => {
        refuseIfClosing();

        // A cancel that came right behind it has fired already, and an abort
        // listener hears nothing of one past.
        if (signal.aborted) {
          return Promise.resolve({ stopReason: 'cancelled' as const });
        }

        const entry = named(params.sessionId);
        const session = entry.conversation.session;
        const parsed = promptOf(
          params.prompt,
          agent,
          session?.takesImages() === true,
        );

        if ('refused' in parsed) {
          throw RequestError.invalidParams(undefined, parsed.refused);
        }

        const turnId = crypto.randomUUID();
        const answer = Promise.withResolvers<never>();

        answers.set(requestId, answer as never);
        // Before `send`, which emits before it returns, and with no await
        // since the request came, or a cancel could pass it.
        step(entry, { type: 'bind', requestId, turnId });

        signal.addEventListener(
          'abort',
          () => {
            // The connection's end aborts this too, and is no client's cancel.
            if (!connection.signal.aborted) {
              const running = turnOf(entry.turns, requestId);

              if (running !== undefined) {
                entry.conversation.cancelPrompt(running);
              }
            }
          },
          { once: true },
        );

        if (
          !entry.conversation.send(
            parsed.text,
            parsed.text,
            parsed.attachments,
            [],
            { turnId, links: parsed.links },
          )
        ) {
          step(entry, { type: 'unbind', turnId });
          answers.delete(requestId);

          throw RequestError.sessionNotFound(params.sessionId);
        }

        return answer.promise;
      },
      cancel: ({ sessionId }) => {
        const entry = sessions.get(sessionId);

        if (entry !== undefined) {
          entry.conversation.interrupt();

          return;
        }

        for (const each of sessions.values()) {
          const child =
            each.upstream === undefined
              ? undefined
              : childOf(each.upstream, sessionId);

          if (child !== undefined) {
            void each.conversation.stopSubagent(child).catch(() => {
              // The subagent may have ended before the stop landed.
            });

            return;
          }
        }
      },
      setConfigOption: async ({ params }) => {
        refuseIfClosing();

        const entry = named(params.sessionId);
        const state = agentState(entry);
        const setter =
          state === undefined
            ? undefined
            : configSetter(state, params.configId);

        if (
          setter === undefined ||
          !('value' in params) ||
          typeof params.value !== 'string' ||
          ('type' in params && params.type === 'boolean')
        ) {
          throw RequestError.invalidParams(
            undefined,
            `No option ${params.configId} takes that value.`,
          );
        }

        const { conversation } = entry;
        const { configId, value } = params;

        await (
          setter === 'mode'
            ? conversation.setMode(value)
            : setter === 'model'
              ? conversation.setModel(value)
              : conversation.setOption(configId, value)
        ).catch((error: unknown) => {
          throw refusal(error);
        });

        const now = agentState(entry);

        if (now === undefined || entry.upstream === undefined) {
          throw RequestError.sessionNotFound(params.sessionId);
        }

        const { session: told, configOptions } = answeredConfig(
          entry.upstream,
          now,
        );

        entry.upstream = told;

        return { configOptions };
      },
      setMode: async ({ params }) => {
        refuseIfClosing();

        await named(params.sessionId)
          .conversation.setMode(params.modeId)
          .catch((error: unknown) => {
            throw refusal(error);
          });

        return {};
      },
      close: async ({ params }) => {
        refuseIfClosing();

        const entry = named(params.sessionId);

        sessions.delete(params.sessionId);
        step(entry, { type: 'closing' });

        await closeEntry(entry);

        return {};
      },
    },
    wire.stream,
  );

  void connection.closed.then(() => {
    if (leaving.started()) {
      return;
    }

    const reason: unknown = connection.signal.reason;

    if (wire.failed() || reason instanceof MessageTooLargeError) {
      say(
        `chord: the connection closed: ${
          reason instanceof Error ? reason.message : String(reason)
        }`,
      );

      void leaving.leave({ kind: 'broken' });

      return;
    }

    void leaving.leave({ kind: 'eof' });
  });

  return { leave: (reason) => leaving.leave(reason) };
}

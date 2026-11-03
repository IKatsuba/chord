/**
 * What `chord acp` tells its client, from what its sessions hear: pure, beside
 * the reducer. One surface for every agent; what an agent lacks is absent, not
 * differently shaped.
 */
import type {
  ClientCapabilities,
  ContentBlock,
  CreateElicitationResponse,
  PermissionOption,
  RequestPermissionRequest,
  RequestPermissionResponse,
  SessionConfigOption,
  SessionNotification,
  SessionUpdate,
  StateUpdate,
  StopReason,
} from '@agentclientprotocol/sdk/unstable';
import type { ResourceLink } from '../files.ts';
import {
  type AgentState,
  modelsOf,
  modesOf,
  optionsOf,
} from './agent_state.ts';
import type { FoldedSession } from './agents_host.ts';
import { busyOf } from './busy.ts';
import type { ElicitationReply } from './elicitations.ts';
import { FILLED } from './enrich.ts';
import { modelConfigId } from './models.ts';
import { modeConfigId } from './modes.ts';
import type { Attachment } from './session.ts';
import { TASK_META } from './transcript/subagents.ts';
import type { MessageFrom, PlanAnswer, PlanWait } from './transcript/types.ts';

/** The `_meta` key on a turn's words that no client prompt began. */
export const FROM = 'chord/from';

/** The `_meta` key on what chord says of a subagent beyond ACP's words. */
export const AGENT = 'chord/agent';

// Maps, as these are looked up by words off the wire: an object would find
// `toString` on its prototype.
const NEEDS: ReadonlyMap<
  string,
  (capabilities: ClientCapabilities) => unknown
> = new Map<string, (capabilities: ClientCapabilities) => unknown>([
  ['subagent_update', (capabilities) => capabilities.subagents],
  ['session_message', (capabilities) => capabilities.subagents],
  ['session_message_chunk', (capabilities) => capabilities.subagents],
  ['plan_update', (capabilities) => capabilities.plan],
  ['plan_removed', (capabilities) => capabilities.plan],
  ['compaction_update', (capabilities) => capabilities.session?.compaction],
  [
    'compaction_summary_chunk',
    (capabilities) => capabilities.session?.compaction,
  ],
  ['notice', (capabilities) => capabilities.session?.notices],
]);

/** The v1 schema's kinds that need nothing declared. */
const OPEN = new Set([
  'user_message_chunk',
  'agent_message_chunk',
  'agent_thought_chunk',
  'tool_call',
  'tool_call_update',
  'plan',
  'available_commands_update',
  'config_option_update',
  'session_info_update',
  'usage_update',
]);

/**
 * Whether an update may go to a client. The SDK does not validate what it
 * sends, and the schema says an agent MUST NOT send these kinds undeclared: the
 * check only drops, the same live and on a load, and the record keeps them.
 */
export function reaches(
  capabilities: ClientCapabilities,
  kind: string,
  child: boolean,
): boolean {
  if (child && !capabilities.subagents) {
    return false;
  }

  const needs = NEEDS.get(kind);

  return needs === undefined ? OPEN.has(kind) : Boolean(needs(capabilities));
}

/**
 * An id free of the sessions live here: an agent with per-process counter ids
 * answers a second `session/new` with one already taken. Upstream only.
 */
export function aliasFor(live: ReadonlySet<string>, id: string): string {
  let alias = id;

  for (let count = 2; live.has(alias); count += 1) {
    alias = `${id}~${count}`;
  }

  return alias;
}

/** How one session's ids go up, and what it last told of its configuration. */
export interface UpstreamSession {
  /** The agent's id for it. */
  readonly agentId: string;
  /** The client's. */
  readonly upstreamId: string;
  /** Each subagent by the agent's id, under `<main>/<child>`. */
  readonly children: ReadonlyMap<string, string>;
  readonly configSent?: readonly SessionConfigOption[];
  /** A long-lived child's: all it says is a child's traffic to the client. */
  readonly nested?: true;
}

export function upstreamSession(
  agentId: string,
  upstreamId: string = agentId,
): UpstreamSession {
  return { agentId, upstreamId, children: new Map() };
}

/** A long-lived child's session, under its composite id. */
export function childSession(
  agentId: string,
  upstreamId: string,
): UpstreamSession {
  return { ...upstreamSession(agentId, upstreamId), nested: true };
}

/**
 * The agent's id for a subagent's composite id: looked up exactly, never parsed,
 * as a child's own id may hold a `/`.
 */
export function childOf(
  session: UpstreamSession,
  upstreamId: string,
): string | undefined {
  for (const [child, composite] of session.children) {
    if (composite === upstreamId) {
      return child;
    }
  }

  return undefined;
}

/** A session's id or a child's as the client knows it; unknown ones as they are. */
export function upstreamIdOf(session: UpstreamSession, id: string): string {
  return id === session.agentId
    ? session.upstreamId
    : (session.children.get(id) ?? id);
}

/**
 * Whether an ask may name this id: the session or a child it announced. Anything
 * else would reach the client as it is, where it could be another live session.
 */
export function asksIn(session: UpstreamSession, id: string): boolean {
  return id === session.agentId || session.children.has(id);
}

const ENDED_AS: ReadonlyMap<string, StateUpdate> = new Map<string, StateUpdate>(
  [
    ['completed', { state: 'idle', stopReason: 'end_turn' }],
    ['failed', { state: 'idle', stopReason: 'error' }],
    ['cancelled', { state: 'idle', stopReason: 'cancelled' }],
    ['disconnected', { state: 'unknown' }],
  ],
);

/** A subagent's update with the adapters' draft state words as ACP's. */
function acpStateWords(
  update: SessionUpdate & { sessionUpdate: 'subagent_update' },
): SessionUpdate {
  const word = update.state?.state;
  const state = word === undefined ? undefined : ENDED_AS.get(word);

  return state === undefined
    ? update
    : {
        ...update,
        state,
        _meta: { ...update._meta, [AGENT]: { state: word } },
      };
}

/**
 * One update of a session as it goes up, or none: under the client's ids, whole,
 * `_meta` included, read after the enrichers. The configuration kinds go as one
 * shape by `configChange`, never as the agent sent them.
 */
export function mapUpdate(
  session: UpstreamSession,
  capabilities: ClientCapabilities,
  update: SessionUpdate,
  subagentId?: string,
): {
  readonly session: UpstreamSession;
  readonly notification?: SessionNotification;
} {
  const kind = update.sessionUpdate;

  if (kind === 'config_option_update' || kind === 'current_mode_update') {
    return { session };
  }

  const parent =
    subagentId === undefined
      ? session.upstreamId
      : upstreamIdOf(session, subagentId);
  const grown =
    kind === 'subagent_update' && !session.children.has(update.sessionId)
      ? {
          ...session,
          children: new Map(session.children).set(
            update.sessionId,
            `${parent}/${update.sessionId}`,
          ),
        }
      : session;

  if (
    !reaches(
      capabilities,
      kind,
      session.nested === true || subagentId !== undefined,
    )
  ) {
    return { session: grown };
  }

  const sessionId = upstreamIdOf(grown, subagentId ?? grown.agentId);

  return {
    session: grown,
    notification: { sessionId, update: rewritten(grown, update) },
  };
}

function rewritten(
  session: UpstreamSession,
  update: SessionUpdate,
): SessionUpdate {
  switch (update.sessionUpdate) {
    case 'subagent_update':
      return acpStateWords({
        ...update,
        sessionId: upstreamIdOf(session, update.sessionId),
        // chord's own task: chord stops it, whatever its runtime offers.
        ...(update._meta?.[TASK_META] === undefined
          ? {}
          : { capabilities: { cancel: {} } }),
      });
    case 'session_message': {
      const { senderSessionId: sender, recipientSessionId: recipient } = update;

      return {
        ...update,
        ...(typeof sender === 'string'
          ? { senderSessionId: upstreamIdOf(session, sender) }
          : {}),
        ...(typeof recipient === 'string'
          ? { recipientSessionId: upstreamIdOf(session, recipient) }
          : {}),
      };
    }
    default:
      return update;
  }
}

/** What chord says of a long-lived child, as no agent's update does. */
export interface AgentReport {
  /** Its immediate parent's id: main's, or its lead's. */
  readonly parent: string;
  readonly upstreamId: string;
  readonly title: string;
  readonly state: StateUpdate;
  readonly runtime: string;
  readonly model?: string | undefined;
  readonly effort?: string | undefined;
  readonly team?: string | undefined;
  readonly role?: 'lead' | 'member' | undefined;
  /** Its process went on its own. */
  readonly gone?: string | undefined;
  /** Why it did not start. */
  readonly failed?: string | undefined;
  readonly closed?: true | undefined;
}

/** A child's state as ACP words it, from what is folded of it. */
export function agentStateOf(
  fold: FoldedSession,
  stopReason?: StopReason,
): StateUpdate {
  const asks =
    fold.transcript.planAsks?.some((ask) => ask.answer === undefined) === true;
  const busy = busyOf(fold);

  if (asks || busy?.kind === 'permission' || busy?.kind === 'input') {
    return { state: 'requires_action' };
  }

  return busy !== undefined
    ? { state: 'running' }
    : { state: 'idle', ...(stopReason === undefined ? {} : { stopReason }) };
}

/**
 * A long-lived child's `subagent_update`, on its immediate parent. chord makes
 * it, so no record holds it; one closed has nothing left to cancel.
 */
export function agentUpdate(
  capabilities: ClientCapabilities,
  report: AgentReport,
): SessionNotification | undefined {
  if (!reaches(capabilities, 'subagent_update', false)) {
    return undefined;
  }

  const { parent, upstreamId, title, state, ...agent } = report;

  return {
    sessionId: parent,
    update: {
      sessionUpdate: 'subagent_update',
      sessionId: upstreamId,
      title,
      state,
      ...(report.closed === true ? {} : { capabilities: { cancel: {} } }),
      _meta: {
        [AGENT]: Object.fromEntries(
          Object.entries(agent).filter(([, value]) => value !== undefined),
        ),
      },
    },
  };
}

/**
 * Modes, models and efforts as one list: the mode and the model, the agent's own
 * option or made from the older fields, then its other selects. Booleans never
 * appear, as the window shows none.
 */
export function configOptionsOf(state: AgentState): SessionConfigOption[] {
  const modes = modesOf(state);
  const models = modelsOf(state);
  const named = (id: string) =>
    state.configOptions.find((option) => option.id === id);
  const modeId = modeConfigId(state.configOptions) ?? 'mode';
  const modelId = modelConfigId(state.configOptions) ?? 'model';

  return [
    ...(modes?.current === undefined
      ? []
      : [
          {
            type: 'select' as const,
            id: modeId,
            name: named(modeId)?.name ?? 'Mode',
            category: 'mode',
            currentValue: modes.current,
            options: modes.available.map(({ id, name }) => ({
              value: id,
              name,
            })),
          },
        ]),
    ...(models?.current === undefined
      ? []
      : [
          {
            type: 'select' as const,
            id: modelId,
            name: named(modelId)?.name ?? 'Model',
            category: 'model',
            currentValue: models.current,
            options: models.available.map(({ id, name }) => ({
              value: id,
              name,
            })),
          },
        ]),
    ...optionsOf(state).map(({ id, name, current, values }) => ({
      type: 'select' as const,
      id,
      name,
      currentValue: current,
      options: values.map(({ value, name: label }) => ({
        value,
        name: label,
      })),
    })),
  ];
}

/** Which of `Conversation`'s sets an option of `configOptionsOf` goes to. */
export function configSetter(
  state: AgentState,
  id: string,
): 'mode' | 'model' | 'option' | undefined {
  const known = configOptionsOf(state).find((option) => option.id === id);

  return known === undefined
    ? undefined
    : known.category === 'mode'
      ? 'mode'
      : known.category === 'model'
        ? 'model'
        : 'option';
}

/**
 * The whole update if the list differs from what the client last had. So an
 * agent that changes its config only in responses, one that answers `set_mode`
 * with nothing, and one that sends updates all look alike.
 */
export function configChange(
  session: UpstreamSession,
  state: AgentState,
): {
  readonly session: UpstreamSession;
  readonly notification?: SessionNotification;
} {
  const configOptions = configOptionsOf(state);

  if (JSON.stringify(configOptions) === JSON.stringify(session.configSent)) {
    return { session };
  }

  return {
    session: { ...session, configSent: configOptions },
    notification: {
      sessionId: session.upstreamId,
      update: {
        sessionUpdate: 'config_option_update',
        configOptions,
        _meta: { [FILLED]: ['configOptions'] },
      },
    },
  };
}

/** The list a session's answer carries, which `configChange` then goes on from. */
export function answeredConfig(
  session: UpstreamSession,
  state: AgentState,
): {
  readonly session: UpstreamSession;
  readonly configOptions: SessionConfigOption[];
} {
  const configOptions = configOptionsOf(state);

  return {
    session: { ...session, configSent: configOptions },
    configOptions,
  };
}

/** A message no client prompt began, as the client hears of it. */
export function messageChunk(
  sessionId: string,
  text: string,
  from?: MessageFrom,
): SessionNotification {
  return {
    sessionId,
    update: {
      sessionUpdate: 'user_message_chunk',
      content: { type: 'text', text },
      ...(from === undefined ? {} : { _meta: { [FROM]: from } }),
    },
  };
}

function todosMarkdown(wait: {
  readonly todos?: PlanWait['todos'];
}): readonly string[] {
  return (wait.todos ?? []).map(
    ({ content, status }) =>
      `- [${status === 'completed' ? 'x' : ' '}] ${content}`,
  );
}

function planMarkdown(plan: PlanWait): string {
  return [
    ...(plan.overview === undefined ? [] : [plan.overview]),
    ...(plan.plan === undefined ? [] : [plan.plan]),
    ...(plan.todos === undefined || plan.todos.length === 0
      ? []
      : [todosMarkdown(plan).join('\n')]),
    ...(plan.phases ?? []).map((phase) =>
      [`## ${phase.name}`, ...todosMarkdown(phase)].join('\n'),
    ),
  ].join('\n\n');
}

/** A plan ask as an ordinary permission, one small function for every agent. */
export function planPermission(
  sessionId: string,
  plan: PlanWait,
): RequestPermissionRequest {
  return {
    sessionId,
    toolCall: {
      toolCallId: plan.toolCallId,
      title: plan.name ?? 'Plan',
      content: [
        {
          type: 'content',
          content: { type: 'text', text: planMarkdown(plan) },
        },
      ],
    },
    options: [
      {
        optionId: 'accepted',
        name: 'Yes, accept the plan',
        kind: 'allow_once',
      },
      { optionId: 'kept', name: 'No, keep planning', kind: 'reject_once' },
      ...(plan.agent === 'grok'
        ? [
            {
              optionId: 'left',
              name: 'No, and leave plan mode',
              kind: 'reject_once' as const,
            },
          ]
        : []),
    ],
  };
}

/**
 * The client's answer to a plan ask: a cancel, an error (none) or an id it was
 * not offered is `cancelled`, **never a yes**.
 */
export function planAnswerOf(
  plan: PlanWait,
  response: RequestPermissionResponse | undefined,
): PlanAnswer {
  const outcome = response?.outcome;

  if (outcome?.outcome !== 'selected') {
    return { type: 'cancelled' };
  }

  switch (outcome.optionId) {
    case 'accepted':
      return { type: 'accepted' };
    case 'kept':
      return { type: 'kept' };
    case 'left':
      return plan.agent === 'grok' ? { type: 'left' } : { type: 'cancelled' };
    default:
      return { type: 'cancelled' };
  }
}

/**
 * The client's answer to a permission, checked against what it was offered
 * before `choose`, which removes the ask and emits chosen before `resolve` could
 * throw. Anything else is a refusal: a cancel, an error (none), an unknown id.
 */
export function permissionAnswerOf(
  options: readonly PermissionOption[],
  response: RequestPermissionResponse | undefined,
): { readonly optionId: string } | 'reject' {
  const outcome = response?.outcome;

  return outcome?.outcome === 'selected' &&
    options.some((option) => option.optionId === outcome.optionId)
    ? { optionId: outcome.optionId }
    : 'reject';
}

/**
 * The client's answer to a form or a link, passed on as it came: an error (none)
 * or a word ACP does not have is `cancel`.
 */
export function elicitationReplyOf(
  response: CreateElicitationResponse | undefined,
): ElicitationReply {
  return response?.action === 'accept' ||
    response?.action === 'decline' ||
    response?.action === 'cancel'
    ? (response as ElicitationReply)
    : { action: 'cancel' };
}

/** A client's prompt as `Conversation.send` takes it. */
export interface UpstreamPrompt {
  readonly text: string;
  readonly attachments: readonly Attachment[];
  readonly links: readonly ResourceLink[];
}

/**
 * A prompt's blocks, or why it is refused: `resource` and `audio` go unadvertised,
 * and an image to an agent that takes none says so in the window's words.
 */
export function promptOf(
  blocks: readonly ContentBlock[],
  agent: string,
  takesImages: boolean,
): UpstreamPrompt | { readonly refused: string } {
  const texts: string[] = [];
  const attachments: Attachment[] = [];
  const links: ResourceLink[] = [];

  for (const block of blocks) {
    switch (block.type) {
      case 'text':
        texts.push(block.text);

        break;
      case 'image':
        if (!takesImages) {
          return { refused: `${agent} does not take images` };
        }

        attachments.push({ mediaType: block.mimeType, data: block.data });

        break;
      case 'resource_link':
        links.push(block);

        break;
      default:
        return { refused: `A prompt cannot carry a ${block.type} block.` };
    }
  }

  return { text: texts.join('\n'), attachments, links };
}

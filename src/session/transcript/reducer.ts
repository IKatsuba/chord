/**
 * The transcript: everything a session's turns have produced, as plain state
 * every visible slice draws from. A pure reducer folds the session layer's
 * happenings into it — the agent's `session/update`s as they came over the
 * wire, its subagents' with them, plus the moments no update carries: the
 * prompt, a permission request and its answer, a form or link the agent asks
 * the person for and its answer, a cancel, the turn's result, and the agent
 * going away.
 */
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { filledIn } from '../enrich.ts';
import { awaitedCall, replacedCall, served } from './chord.ts';
import { mergeCompaction } from './compactions.ts';
import { appendText } from './messages.ts';
import {
  elicitationRequested,
  elicitationSettled,
  permissionRequested,
  permissionSettled,
} from './permissions.ts';
import { removePlan, updatePlan } from './plans.ts';
import {
  shellEnded,
  shellOutput,
  shellReplayed,
  shellStarted,
} from './shell.ts';
import {
  childUpdate,
  itemEndLines,
  mergeSubagent,
  subagentStopping,
} from './subagents.ts';
import { mergeToolCall } from './tools.ts';
import {
  cancelled,
  cycleStarted,
  disconnected,
  prompted,
  settle,
} from './turn.ts';
import type {
  Entry,
  PlanAsk,
  Transcript,
  TranscriptAction,
  UsageField,
} from './types.ts';

const USAGE_FIELDS: readonly string[] = ['used', 'size', 'cost'];

export function reduceTranscript(
  state: Transcript,
  action: TranscriptAction,
): Transcript {
  const last = state.entries.at(-1);

  // What a turn the agent started on its own sends after chord cancelled it
  // draws above the line that closed it.
  if (
    last?.kind === 'self_started' &&
    action.type !== 'self_started' &&
    'turnId' in action &&
    action.turnId === last.turnId
  ) {
    const under = reduceAction(
      { ...state, entries: state.entries.slice(0, -1) },
      action,
    );

    return {
      ...under,
      entries: [...under.entries, closed(under.entries, last.turnId, last)],
    };
  }

  return reduceAction(state, action);
}

/** The line that closes turn `turnId`, alone while the turn drew nothing. */
function closed(
  entries: readonly Entry[],
  turnId: string,
  line: Extract<Entry, { kind: 'self_started' }>,
): Entry {
  const alone = entries.at(-1)?.turnId !== turnId;

  return line.alone === alone ? line : { ...line, alone };
}

/** `next` with a line for each agent item it ended since `state`. */
function withEndLines(state: Transcript, next: Transcript): Transcript {
  const lines = itemEndLines(state.entries, next.entries, state.turn);

  return lines.length === 0
    ? next
    : { ...next, entries: [...next.entries, ...lines] };
}

/** `entries` with `ask` on the call it came out of, the latest of that id. */
function withPlan(entries: readonly Entry[], ask: PlanAsk): readonly Entry[] {
  const at = entries.findLastIndex(
    (entry) => entry.kind === 'tool' && entry.call.id === ask.wait.toolCallId,
  );
  const entry = entries[at];

  return entry?.kind === 'tool'
    ? entries.with(at, { ...entry, call: { ...entry.call, plan: ask } })
    : entries;
}

function reduceAction(state: Transcript, action: TranscriptAction): Transcript {
  switch (action.type) {
    case 'prompt':
      return prompted(
        state,
        action.turnId,
        action.text,
        action.at,
        action.from,
        action.team,
        action.into,
      );
    case 'served':
      return served(state, action);
    case 'update': {
      const next =
        action.subagentId === undefined
          ? applyUpdate(state, action.turnId, action.update, action.at)
          : childUpdate(state, action, applyUpdate);

      // Said here, at the top, with the turn that runs, whether the agent
      // item ended is the session's own or one under another's work: a
      // subagent's work folds with no turn of its own (CHD-479).
      return action.update.sessionUpdate === 'subagent_update' && next !== state
        ? withEndLines(state, next)
        : next;
    }
    case 'permission_requested':
      return permissionRequested(
        state,
        action.turnId,
        action.permission,
        action.at,
        action.between,
      );
    case 'permission_settled':
      return permissionSettled(state, action.turnId, action.id, action.answer);
    case 'elicitation_requested':
      return elicitationRequested(state, action.turnId, action.elicitation);
    case 'elicitation_settled':
      return elicitationSettled(state, action.turnId, action.id, action.answer);
    case 'plan_requested': {
      if (
        (state.planAsks ?? []).some((ask) => ask.wait.id === action.plan.id)
      ) {
        return state;
      }

      const waiting =
        state.turn.status === 'awaiting_permission'
          ? state.turn.permissions.map((wait) => wait.id)
          : [];
      const ask: PlanAsk = {
        turnId: action.turnId,
        wait: action.plan,
        ...(waiting.length === 0 ? {} : { after: waiting }),
      };

      return {
        ...state,
        entries: withPlan(state.entries, ask),
        planAsks: [...(state.planAsks ?? []), ask],
      };
    }
    case 'plan_settled': {
      const ask = (state.planAsks ?? []).find(
        (each) => each.wait.id === action.id && each.answer === undefined,
      );

      if (ask === undefined) {
        return state;
      }

      const answered: PlanAsk = { ...ask, answer: action.answer };

      return {
        ...state,
        entries: withPlan(state.entries, answered),
        planAsks: (state.planAsks ?? []).map((each) =>
          each === ask ? answered : each,
        ),
      };
    }
    case 'cancel':
      return cancelled(state, action.turnId, action.at);
    case 'subagent_stopping':
      return subagentStopping(state, action.subagentId, action.stopping);
    case 'disconnected':
      return disconnected(state, action.at);
    case 'result':
      return settle(state, action.turnId, action.result);
    case 'shell_started':
      return shellStarted(state, action.turnId, action.command);
    case 'shell_replayed':
      return shellReplayed(state, action.turnId, action.run);
    case 'shell_output':
      return shellOutput(state, action.turnId, action.stream, action.text);
    case 'shell_ended':
      return shellEnded(state, action);
    case 'reported':
      return {
        ...state,
        entries: [
          ...state.entries,
          {
            kind: 'report',
            turnId: action.turnId,
            command: action.command,
            rows: action.rows,
          },
        ],
      };
    case 'noted':
      return {
        ...state,
        entries: [
          ...state.entries,
          {
            kind: 'note',
            turnId: action.turnId,
            command: action.command,
            text: action.text,
            failed: action.failed,
          },
        ],
      };
    case 'team_shown':
      return {
        ...state,
        entries: [
          ...state.entries,
          {
            kind: 'team',
            turnId: action.turnId,
            command: action.command,
            shown: action.shown,
          },
        ],
      };
    case 'failed':
      return {
        ...state,
        entries: [
          ...state.entries,
          {
            kind: 'error',
            turnId: action.turnId,
            message: action.message,
          },
        ],
      };
    case 'warned':
      return {
        ...state,
        entries: [
          ...state.entries,
          {
            kind: 'warning',
            turnId: action.turnId,
            message: action.message,
          },
        ],
      };
    case 'left_open':
      return {
        ...state,
        entries: [
          ...state.entries,
          {
            kind: 'left_open',
            turnId: action.turnId,
            agents: action.agents,
          },
        ],
      };
    case 'monitors_left':
      return {
        ...state,
        entries: [
          ...state.entries,
          {
            kind: 'monitors_left',
            turnId: action.turnId,
            monitors: action.monitors,
          },
        ],
      };
    case 'cycle_started':
      return cycleStarted(state, action.turnId, action.at);
    case 'self_started':
      return {
        ...state,
        entries: [
          ...state.entries,
          closed(state.entries, action.turnId, {
            kind: 'self_started',
            turnId: action.turnId,
            from: action.from,
            alone: true,
          }),
        ],
      };
  }
}

function applyUpdate(
  state: Transcript,
  turnId: string,
  update: SessionUpdate,
  at?: number,
): Transcript {
  switch (update.sessionUpdate) {
    case 'subagent_update':
      return mergeSubagent(state, turnId, update, at);
    case 'agent_message_chunk':
    case 'agent_thought_chunk':
      return appendText(
        state,
        turnId,
        update.sessionUpdate === 'agent_thought_chunk'
          ? 'thought'
          : 'assistant',
        update.content,
        update.messageId ?? undefined,
      );
    case 'tool_call':
    case 'tool_call_update':
      return replacedCall(state.entries, update.toolCallId)
        ? state
        : awaitedCall(mergeToolCall(state, turnId, update), update.toolCallId);
    // Updates are not checked against ACP's schema, so a list that is not
    // there leaves the last one.
    case 'plan': {
      const { planId: _, ...rest } = state;

      return { ...rest, plan: update.entries ?? state.plan };
    }
    case 'compaction_update':
    case 'compaction_summary_chunk':
      return mergeCompaction(state, turnId, update);
    case 'plan_update':
      return updatePlan(state, turnId, update.plan);
    case 'plan_removed':
      return removePlan(state, update.planId);
    case 'usage_update': {
      const estimated = filledIn(update).filter((field): field is UsageField =>
        USAGE_FIELDS.includes(field),
      );

      return {
        ...state,
        usage: {
          used: update.used,
          size: update.size,
          ...(update.cost ? { cost: update.cost } : {}),
          ...(estimated.length > 0 ? { estimated } : {}),
        },
      };
    }
    case 'current_mode_update':
      return { ...state, mode: update.currentModeId };
    case 'available_commands_update':
      return {
        ...state,
        commands: update.availableCommands ?? state.commands,
      };
    // The prompt is drawn from what was sent; the rest is not drawn yet.
    default:
      return state;
  }
}

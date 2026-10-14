import type { SessionUpdate } from '@agentclientprotocol/sdk';
import {
  type PendingPermission,
  waitFor,
} from '../../src/session/permissions.ts';
import type { Heard } from '../../src/session/replay.ts';
import type { Attachment, Session, Turn } from '../../src/session/session.ts';
import type {
  PermissionAnswer,
  TranscriptAction,
  TurnResult,
} from '../../src/session/transcript/types.ts';

/**
 * What one prompt brought: the agent's updates until its answer, and that.
 * `updates` are the session's own; `subagents` hears its subagents', each
 * with the subagent's id.
 */
export interface Ran {
  readonly turn: Turn;
  readonly updates: SessionUpdate[];
  readonly subagents: Heard[];
  readonly result: TurnResult;
}

/**
 * Sends `text`, with `attachments` and `mentions`, and gathers the updates
 * the session hears until the agent answers; `onUpdate` sees each as it
 * comes, with those so far.
 */
export async function run(
  session: Session,
  text: string,
  {
    attachments = [],
    mentions = [],
    onUpdate,
  }: {
    attachments?: readonly Attachment[];
    mentions?: readonly string[];
    onUpdate?: (updates: SessionUpdate[], turn: Turn) => void;
  } = {},
): Promise<Ran> {
  const updates: SessionUpdate[] = [];
  const subagents: Heard[] = [];
  let turn: Turn | undefined;
  const unsubscribe = session.subscribe((update, subagentId) => {
    if (subagentId !== undefined) {
      subagents.push({ update, subagentId });

      return;
    }

    updates.push(update);

    if (turn) {
      onUpdate?.(updates, turn);
    }
  });

  try {
    turn = session.prompt(text, attachments, mentions);

    return { turn, updates, subagents, result: await turn.result };
  } finally {
    unsubscribe();
  }
}

/** The text of the agent's message chunks, or of its thought chunks. */
export function said(
  updates: readonly SessionUpdate[],
  kind: 'agent_message_chunk' | 'agent_thought_chunk' = 'agent_message_chunk',
): string[] {
  return updates.flatMap((update) =>
    update.sessionUpdate === kind && update.content.type === 'text'
      ? [update.content.text]
      : [],
  );
}

export interface PlayOptions {
  /** Cancels the turn once this many updates have arrived. */
  cancelAfterEvents?: number;
  /**
   * How a permission request is met: resolved with this option id, rejected,
   * or the turn cancelled while it waits. The first option by default.
   */
  answer?: string | 'reject' | 'cancel';
}

/**
 * Plays one prompt through the session layer and returns what the interface
 * would dispatch to the transcript reducer, in the order it happened, so the
 * reducer's tests run on what the fake agent really sends.
 */
export async function play(
  session: Session,
  text: string,
  options: PlayOptions = {},
): Promise<TranscriptAction[]> {
  const actions: TranscriptAction[] = [];
  const turnId = crypto.randomUUID();
  let turn: Turn | undefined;
  const cancel = async () => {
    actions.push({ type: 'cancel', turnId, at: Date.now() });
    await turn?.cancel();
  };

  const onPermission = (request: PendingPermission) => {
    const settled = (answer: PermissionAnswer) => {
      actions.push({
        type: 'permission_settled',
        turnId,
        id: request.id,
        answer,
      });
    };

    const withdrawn = () => settled({ type: 'withdrawn' });

    actions.push({
      type: 'permission_requested',
      turnId,
      permission: waitFor(request, session.id),
    });
    request.signal.addEventListener('abort', withdrawn, { once: true });
    // The interface answers on a later key press, never inside the callback.
    setTimeout(() => {
      const answer = options.answer ?? request.options[0]?.optionId;

      if (answer === 'cancel') {
        return void cancel();
      }

      request.signal.removeEventListener('abort', withdrawn);

      if (answer === 'reject' || answer === undefined) {
        settled({ type: 'rejected' });
        request.reject();
      } else {
        settled({ type: 'chosen', optionId: answer });
        request.resolve(answer);
      }
    }, 10);
  };

  let count = 0;
  const unsubscribe = session.permissions.subscribe(onPermission);
  const unheard = session.subscribe((update, subagentId) => {
    actions.push({
      type: 'update',
      turnId,
      update,
      ...(subagentId === undefined ? {} : { subagentId }),
    });
    count++;

    if (count === options.cancelAfterEvents) {
      void cancel();
    }
  });

  actions.push({ type: 'prompt', turnId, text, at: Date.now() });

  try {
    turn = session.prompt(text);

    actions.push({ type: 'result', turnId, result: await turn.result });
  } finally {
    unsubscribe();
    unheard();
  }

  return actions;
}

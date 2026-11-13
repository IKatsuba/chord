/**
 * What `chord acp` keeps of each of a host's sessions for the host to read back
 * through `stateOf`, folded as each event comes. It has no window, so nothing
 * lags: the fold is as fresh as the event just heard.
 */
import type { ConversationEvent } from '../session/conversation.ts';
import type { FoldedSession } from '../session/agents_host.ts';
import { reduceTranscript } from '../session/transcript/reducer.ts';
import {
  emptyTranscript,
  type TranscriptAction,
} from '../session/transcript/types.ts';

/** Every event that is no action of the reducer's; a new one fails `bun check`. */
const NOT_ACTIONS: Record<
  Exclude<ConversationEvent, TranscriptAction>['type'],
  true
> = {
  agent_closed: true,
  cleared: true,
  closing: true,
  commands: true,
  connect_failed: true,
  connected: true,
  mode_answered: true,
  mode_asked: true,
  model: true,
  modes: true,
  monitors: true,
  options: true,
  prompt_capabilities: true,
  queue_withdrawn: true,
  queued: true,
  resumed: true,
  retired_update: true,
  retired_usage: true,
  run_typed: true,
  usage: true,
};

/**
 * A session nothing has been heard of. Its queue stays empty: the host reads it
 * only for a person's prompts held behind a child's turn, and every prompt to a
 * child here is a message.
 */
export const NO_FOLD: FoldedSession = {
  transcript: emptyTranscript,
  queue: [],
};

/** `fold` with `event` in; a clear starts it again, as it does the session. */
export function foldEvent(
  fold: FoldedSession = NO_FOLD,
  event: ConversationEvent,
): FoldedSession {
  if (event.type === 'cleared') {
    return NO_FOLD;
  }

  if (Object.hasOwn(NOT_ACTIONS, event.type)) {
    return fold;
  }

  const transcript = reduceTranscript(
    fold.transcript,
    event as TranscriptAction,
  );

  return transcript === fold.transcript ? fold : { ...fold, transcript };
}

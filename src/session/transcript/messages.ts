/**
 * The agent's replies and thoughts, as chunks run on into one block until a
 * new message, another kind or another turn starts the next.
 */
import type { ContentBlock } from '@agentclientprotocol/sdk';
import type { Transcript } from './types.ts';
import { appended, lastReplaced } from './entries.ts';

/** A chunk's words: a text block's, and nothing of an image or a link. */
export function textOf(content: ContentBlock): string {
  return content.type === 'text' ? content.text : '';
}

export function appendText(
  state: Transcript,
  turnId: string,
  kind: 'assistant' | 'thought',
  content: ContentBlock,
  messageId: string | undefined,
): Transcript {
  const text = textOf(content);

  if (text === '') {
    return state;
  }

  const last = state.entries.at(-1);
  const continues =
    last?.kind === kind &&
    last.turnId === turnId &&
    last.planId === undefined &&
    (last.messageId === undefined ||
      messageId === undefined ||
      last.messageId === messageId);

  if (continues) {
    return {
      ...state,
      entries: lastReplaced(state.entries, {
        ...last,
        text: last.text + text,
      }),
    };
  }

  return {
    ...state,
    entries: appended(state.entries, {
      kind,
      turnId,
      text,
      ...(messageId === undefined ? {} : { messageId }),
    }),
  };
}

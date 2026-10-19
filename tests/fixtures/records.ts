import {
  Conversation,
  type ConversationEvent,
  type Starting,
} from '../../src/session/conversation.ts';
import type { ElicitationReply } from '../../src/session/elicitations.ts';
import { FileRecording } from '../../src/session/record.ts';
import { openSession } from '../../src/session/session.ts';
import type { Resume } from '../../src/session/sessions.ts';

/**
 * A prompt to send: its text, the `@` mentions it names, and whether the
 * person interrupts it as soon as it is sent.
 */
export interface Sending {
  readonly text: string;
  readonly mentions?: readonly string[];
  readonly interrupt?: boolean;
}

/**
 * Leaves a session record in `stateDir` as the window does, through a
 * conversation that records into it, with a turn for each of `prompts`;
 * returns the agent's id for the session. With `resume`, the session is that
 * one opened again, and its record goes on. `heard` hears every event the
 * conversation reports, as the window would. With `permit`, each permission
 * the agent asks is answered with its first option, as a key would, and with
 * `answer`, each form or link with that reply, or `interrupt` for the
 * person interrupting the turn while it waits. `agent` is the name the
 * session is opened as, `fake` unless a test needs another's ways; with
 * `lateCost`, each turn is waited on until its cost has come after it.
 */
export async function recordSession({
  stateDir,
  cwd,
  command,
  prompts,
  resume,
  starting = {},
  heard,
  permit = false,
  answer,
  agent = 'fake',
  lateCost = false,
}: {
  stateDir: string;
  cwd: string;
  command: string[];
  prompts: readonly (string | Sending)[];
  resume?: Resume;
  starting?: Starting;
  heard?: (event: ConversationEvent) => void;
  permit?: boolean;
  answer?: ElicitationReply | 'interrupt';
  agent?: string;
  lateCost?: boolean;
}): Promise<string> {
  const failures: string[] = [];
  const {
    promise: up,
    resolve: connected,
    reject: failed,
  } = Promise.withResolvers<string>();
  let ended: (() => void) | undefined;
  /** With `lateCost`, the turn has answered and its cost is still to come. */
  let answered = false;
  const conversation = new Conversation(
    (signal) =>
      openSession({
        agent,
        cwd,
        agentCommand: command,
        signal,
        ...(resume === undefined ? {} : { resume }),
      }),
    (event) => {
      heard?.(event);

      const option =
        event.type === 'permission_requested'
          ? event.permission.options[0]
          : undefined;

      if (permit && event.type === 'permission_requested' && option) {
        const { id } = event.permission;

        setTimeout(() => conversation.choose(id, option.optionId), 10);
      }

      if (answer !== undefined && event.type === 'elicitation_requested') {
        const { id } = event.elicitation;

        setTimeout(() => {
          if (answer === 'interrupt') {
            conversation.interrupt();
          } else {
            conversation.answer(id, answer);
          }
        }, 10);
      }

      if (event.type === 'connected') {
        connected(event.sessionId);
      } else if (event.type === 'connect_failed') {
        failed(new Error(event.message));
      } else if (
        event.type === 'result' &&
        !event.turnId.startsWith('history-')
      ) {
        if (lateCost) {
          answered = true;
        } else {
          ended?.();
        }
      } else if (
        answered &&
        event.type === 'update' &&
        event.update.sessionUpdate === 'usage_update'
      ) {
        answered = false;

        ended?.();
      }
    },
    Date.now,
    starting,
    new FileRecording(stateDir, (message) => failures.push(message)),
  );

  conversation.start();

  let id: string;

  try {
    id = await up;

    for (const prompt of prompts) {
      const { promise, resolve } = Promise.withResolvers<void>();

      ended = resolve;

      const {
        text,
        mentions = [],
        interrupt = false,
      } = typeof prompt === 'string' ? { text: prompt } : prompt;

      conversation.send(text, text, [], mentions);

      if (interrupt) {
        conversation.interrupt();
      }

      await promise;
    }
  } finally {
    await conversation.close();
  }

  if (failures.length > 0) {
    throw new Error(failures.join('\n'));
  }

  return id;
}

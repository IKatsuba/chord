/**
 * The past an agent replays as it loads a session, as the transcript
 * reducer's actions, so it draws as its turns did live: each prompt and the
 * shell runs whose output went with it, and what followed it, and each turn's
 * end. A past chord recorded itself is drawn by `record.ts`.
 */
import type { ContentBlock, SessionUpdate } from '@agentclientprotocol/sdk';
import { splitContext } from './context.ts';
import { withImages } from './record.ts';
import type { TranscriptAction } from './transcript/types.ts';

/**
 * An update the session heard: its own, or one of its subagents', named by
 * the subagent's id.
 */
export interface Heard {
  readonly update: SessionUpdate;
  readonly subagentId?: string;
}

/**
 * The updates an agent replayed as it loaded a session, as the reducer's
 * actions: each run of the session's own `user_message_chunk`s is a prompt,
 * and what follows it, its turn, until the next. `at` stands for every
 * prompt's time, as no update carries one; a subagent's times are not made
 * up from it, and a subagent the past left running is disconnected, as the
 * agent that ran it is not the one loading it.
 */
export function pastActions(
  updates: readonly Heard[],
  at: number,
): TranscriptAction[] {
  const actions: TranscriptAction[] = [];
  let turnId: string | undefined;
  let turns = 0;
  let typed: ContentBlock[] = [];

  const end = () => {
    if (turnId !== undefined) {
      actions.push({
        type: 'result',
        turnId,
        result: { status: 'completed', stopReason: 'end_turn' },
      });
    }
  };

  // A prompt is whole once something other than its chunks comes.
  const prompt = () => {
    if (typed.length === 0) {
      return;
    }

    end();

    turnId = `history-${++turns}`;

    const { runs, text } = splitContext(promptOf(typed));

    actions.push(
      ...runs.map((run, index): TranscriptAction => ({
        type: 'shell_replayed',
        turnId: `${turnId}-shell-${index + 1}`,
        run,
      })),
      { type: 'prompt', turnId, text, at },
    );

    typed = [];
  };

  for (const { update, subagentId } of updates) {
    if (
      update.sessionUpdate === 'user_message_chunk' &&
      subagentId === undefined
    ) {
      typed.push(update.content);

      continue;
    }

    prompt();

    turnId ??= `history-${++turns}`;

    actions.push({
      type: 'update',
      turnId,
      update,
      ...(subagentId === undefined ? {} : { subagentId }),
    });
  }

  prompt();
  end();

  if (
    updates.some(({ update }) => update.sessionUpdate === 'subagent_update')
  ) {
    actions.push({ type: 'disconnected', turnId: turnId ?? 'history' });
  }

  return actions;
}

/**
 * A replayed prompt's blocks as the text the person typed, with its images as
 * `[Image #N]`. A `resource_link` draws nothing: chord sends one beside the
 * `@path` its text names already.
 */
function promptOf(blocks: readonly ContentBlock[]): string {
  return withImages(
    blocks
      .map((block) =>
        block.type === 'text'
          ? block.text
          : block.type === 'resource'
            ? block.resource.uri
            : block.type === 'audio'
              ? '[audio]'
              : '',
      )
      .join(''),
    blocks.filter((block) => block.type === 'image').length,
  );
}

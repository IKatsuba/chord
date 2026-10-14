/** Folding actions through the transcript's reducer, for its tests. */
import { reduceTranscript } from '../../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type Transcript,
  type TranscriptAction,
} from '../../../src/session/transcript/types.ts';

export function fold(
  actions: readonly TranscriptAction[],
  from: Transcript = emptyTranscript,
): Transcript {
  return actions.reduce(reduceTranscript, from);
}

export /** The state after each action, to check what happened on the way. */
function states(actions: readonly TranscriptAction[]): Transcript[] {
  const seen: Transcript[] = [];

  actions.reduce((state, action) => {
    const next = reduceTranscript(state, action);

    seen.push(next);

    return next;
  }, emptyTranscript);

  return seen;
}

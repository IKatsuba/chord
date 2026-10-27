/** Actual unlinked receipts are Chord history, never synthetic ACP calls. */
import { recordedSelection } from '../../session/team_selection.ts';
import type { ChordCall, Transcript } from '../../session/transcript/types.ts';

export function recordedReceipts(transcript: Transcript): readonly ChordCall[] {
  const linked = new Set(
    transcript.entries.flatMap((entry) => {
      if (entry.kind !== 'tool' || entry.call.chord === undefined) {
        return [];
      }

      const receipt = recordedSelection(entry.call.chord);

      return receipt === undefined ? [] : [receipt.runId];
    }),
  );
  const latest = new Map<string, ChordCall>();

  for (const call of transcript.served ?? []) {
    const receipt = recordedSelection(call);

    if (receipt !== undefined && !linked.has(receipt.runId)) {
      latest.set(receipt.runId, call);
    }
  }

  return [...latest.values()];
}

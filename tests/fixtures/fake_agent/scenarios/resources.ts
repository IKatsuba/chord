/** The ordinary MCP path draws advisory resource states supplied by the injected fixture reader. */
import type { Play } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';

export const RESOURCES = {
  async resources(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'get_budgets', {});
      await turn.say(
        'Resource facts are advisory; unknown data remains unknown.',
      );
    } finally {
      await client.close();
    }

    return 'end_turn';
  },
} satisfies Record<string, Play>;

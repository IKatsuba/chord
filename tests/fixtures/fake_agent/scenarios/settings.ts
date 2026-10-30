/**
 * chord's `settings` tool, called as an agent calls it. The file it reads is
 * whatever the run's `XDG_CONFIG_HOME` holds: a test's fixture, never a
 * person's own.
 */
import type { Play } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';

const reads =
  (args: Record<string, unknown>): Play =>
  async (turn) => {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'settings', args);
    } finally {
      await client.close();
    }

    return 'end_turn';
  };

export const SETTINGS = {
  // Every key, folded on its row until ctrl+o.
  settingsread: reads({ action: 'read' }),
  // One key under a mask, its secret never drawn.
  settingsreadkey: reads({
    action: 'read',
    path: ['mcpServers', 'linear', 'env', 'TOKEN'],
  }),
  // A name that can be no key, refused.
  settingsreadbad: reads({ action: 'read', path: ['__proto__'] }),
} satisfies Record<string, Play>;

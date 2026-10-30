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
      // As long as the person takes to answer the box.
      await callChord(turn, client, 'settings', args, 600_000);
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
  // A user-only key: `set` on an unset file, `unchanged` once it holds it.
  settingstheme: reads({ action: 'set', path: ['theme'], value: 'light' }),
  // An agent's model, next to whatever else that agent holds.
  settingsmodel: reads({
    action: 'set',
    path: ['agents', 'fake', 'model'],
    value: 'fake-small',
  }),
  // The theme again: `remove`, or `unchanged` where it is not set.
  settingsremove: reads({ action: 'remove', path: ['theme'] }),
  // A kind B key, which a project's file holding it shadows.
  settingsagent: reads({ action: 'set', path: ['agent'], value: 'fake' }),
  // The prompt's editing, which the window takes up at once.
  settingsvim: reads({ action: 'set', path: ['editorMode'], value: 'vim' }),
  // What `/new` lists, which the window takes up at once.
  settingsoffered: reads({
    action: 'set',
    path: ['offeredAgents'],
    value: ['claude'],
  }),
  // A value far taller than the room left above the box at 80x24.
  settingslong: reads({
    action: 'set',
    path: ['agents', 'fake', 'model'],
    value: 'l'.repeat(1200),
  }),
} satisfies Record<string, Play>;

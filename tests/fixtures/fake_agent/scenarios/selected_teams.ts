/** Fake-only selected compositions travel through the ordinary MCP surface. */
import process from 'node:process';
import type { Play } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';

export const SELECTED_TEAMS = {
  async selectedteam(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      return 'end_turn';
    }

    const scenario = process.env.CHORD_FAKE_SELECTION_CASE ?? 'normal';

    try {
      await callChord(turn, client, 'get_budgets', {});
      await callChord(turn, client, 'run_team', {
        team: 'fixture',
        job: scenario === 'members' ? 'selectedlead' : 'selectedidle',
        selection: {
          reason:
            scenario === 'long'
              ? 'Preserve every role instruction and exact permission requirement. Capacity is advisory, provider observation age is unknown, and external activity may be missing. '
                  .repeat(3)
                  .trim()
              : 'Preserve all instructions and exact permission requirements; provider freshness is unknown.',
          lead: {
            agent: ['refused', 'soft'].includes(scenario) ? 'claude' : 'codex',
            model: 'fake-small',
            mode: 'plan',
            ...(scenario === 'soft' ? { effort: 'high' } : {}),
          },
          members: { reviewer: { model: 'fake-small', mode: 'plan' } },
        },
      });
      await turn.say('Selection attempt recorded; no automatic retry.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },
  async selectedlead(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'open_agent', {
        member: 'reviewer',
        prompt: 'selectedidle',
      });
    } finally {
      await client.close();
    }

    return 'end_turn';
  },
  async selectedidle(turn) {
    await turn.say('The selected fake role received its first job.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;

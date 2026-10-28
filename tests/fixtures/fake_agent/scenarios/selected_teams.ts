/** Fake-only selected compositions travel through the ordinary MCP surface. */
import process from 'node:process';
import assert from 'node:assert/strict';
import type { TeamsAnswer } from '../../../../src/server/tools.ts';
import type { Play } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';
import { gateOpened } from './agents.ts';

/** These fixtures follow their fixed saved instructions, never interpret prose. */
async function discoveredTeam(turn: Parameters<Play>[0], select: boolean) {
  const client = await chordClient(turn);

  if (client === undefined) {
    return 'end_turn' as const;
  }

  try {
    await client.listTools();

    const listed = await callChord(turn, client, 'list_teams', {});

    assert(listed !== undefined);

    const answer = JSON.parse(listed) as TeamsAnswer;
    const definition = answer.teams.find((one) => one.name === 'fixture');

    assert(definition !== undefined && 'lead' in definition);

    if (select) {
      await callChord(turn, client, 'list_agents', {});

      const agents = [
        ...new Set([
          definition.lead.agent,
          ...definition.members.map((member) => member.agent),
        ]),
      ];

      await callChord(turn, client, 'get_budgets', { agents });
      await callChord(turn, client, 'get_budgets', { agents });
    }

    await callChord(turn, client, 'run_team', {
      team: 'fixture',
      job: 'selectedidle',
      ...(select
        ? {
            selection: {
              reason:
                'Preserve every saved role, instruction and permission; capacity is unknown.',
              lead: { model: 'fake-small', mode: 'plan' },
            },
          }
        : {}),
    });
    await turn.say(
      select
        ? 'Ordinary budget-aware handoff completed.'
        : 'Ordinary saved-composition handoff completed.',
    );
  } finally {
    await client.close();
  }

  return 'end_turn' as const;
}

export const SELECTED_TEAMS = {
  budgetawareteam: (turn) => discoveredTeam(turn, true),
  savedteamplain: (turn) => discoveredTeam(turn, false),
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
              ? 'Preserve every role instruction and exact permission requirement. Capacity is unknown until get_budgets is read, and external activity may be missing. '
                  .repeat(3)
                  .trim()
              : 'Preserve all instructions and exact permission requirements; capacity is unknown.',
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
  async selectedlate(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      return 'end_turn';
    }

    const input = {
      team: 'fixture',
      job: 'selectedidle',
      selection: {
        reason:
          'Preserve all instructions and exact permissions; capacity is unknown.',
        lead: { agent: 'codex', model: 'fake-small', mode: 'plan' },
      },
    };
    const toolCallId = turn.callId('run_team');

    try {
      const pending = client.callTool(
        { name: 'run_team', arguments: input },
        undefined,
        { timeout: 45_000, signal: turn.signal },
      );

      await turn.say(
        'Selected startup waits for the start gate (bounded to 30 seconds).',
      );

      const result = await pending;

      await turn.say(
        'Selected receipt revised; ACP link waits for the link gate (at most 10 seconds).',
      );
      await gateOpened(turn, 'link');
      // This is the fake provider's delayed notification for its actual request.
      await turn.send({
        sessionUpdate: 'tool_call',
        toolCallId,
        title: 'mcp__chord__run_team',
        kind: 'other',
        status: 'pending',
        rawInput: input,
      });
      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId,
        status: result.isError === true ? 'failed' : 'completed',
        content: [
          {
            type: 'content',
            content: {
              type: 'text',
              text: JSON.stringify(result.structuredContent ?? {}),
            },
          },
        ],
      });
      await turn.say('Late ACP link completed.');
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

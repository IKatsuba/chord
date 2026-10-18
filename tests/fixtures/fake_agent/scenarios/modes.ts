/**
 * The agent's mode moved, held and said from inside a turn, and a status of
 * its own.
 */
import { NO_MODES } from '../options.ts';
import { configOptions, locked, modes } from '../sessions.ts';
import * as acp from '@agentclientprotocol/sdk';
import { type Play } from '../turn.ts';

/** The plan `claudeexitplan` asks to have approved. */
const EXIT_PLAN =
  '# Route updates by session\n\n' +
  '1. Read src/acp/connection.ts.\n' +
  '2. Move the routing into src/session/session.ts.\n' +
  '3. Run the tests.\n';

export const MODES = {
  // The mode moves by `current_mode_update` alone, as an agent without a mode
  // config option would report it.
  async status(turn) {
    modes.set(turn.sessionId, 'plan');
    await turn.send({
      sessionUpdate: 'current_mode_update',
      currentModeId: 'plan',
    });
    await turn.send({
      sessionUpdate: 'usage_update',
      used: 1200,
      size: 200000,
      cost: { amount: 0.01, currency: 'USD' },
    });
    await turn.say('Status sent.');

    turn.usage = { inputTokens: 1000, outputTokens: 200, totalTokens: 1200 };

    return 'end_turn';
  },

  // The agent leaves plan mode by itself, as Claude does once its plan is
  // approved: it says so both ways.
  async exitplan(turn) {
    await turn.say('Plan approved.');
    modes.set(turn.sessionId, 'default');
    await turn.send({
      sessionUpdate: 'current_mode_update',
      currentModeId: 'default',
    });
    await turn.send({
      sessionUpdate: 'config_option_update',
      configOptions: configOptions(turn.sessionId),
    });

    return 'end_turn';
  },

  // What the turn runs under, from inside it, so a mode asked for before the
  // prompt is shown to have reached the connection the prompt came on.
  async mode(turn) {
    await turn.say(
      `Mode: ${NO_MODES ? 'none' : (modes.get(turn.sessionId) ?? 'default')}.`,
    );

    return 'end_turn';
  },

  // The agent moves to plan by `current_mode_update` alone and holds it,
  // refusing every mode asked for after, as an agent may refuse a mode its
  // settings forbid.
  async lock(turn) {
    locked.add(turn.sessionId);
    await turn.send({
      sessionUpdate: 'current_mode_update',
      currentModeId: 'plan',
    });
    await turn.say('Mode locked.');

    return 'end_turn';
  },

  // Claude's ExitPlanMode, as its adapter sends it to a client that takes
  // plans: the plan as the call's content, the person asked to approve it;
  // approved, the mode it chose and the plan again, as a markdown
  // `plan_update`; refused, the call fails and the plan is not sent again.
  async claudeexitplan(turn) {
    const toolCallId = turn.callId('exitplan');
    const toolCall: acp.ToolCall = {
      toolCallId,
      title: 'Approve Plan',
      kind: 'switch_mode',
      status: 'pending',
      rawInput: { plan: EXIT_PLAN },
      content: [
        { type: 'content', content: { type: 'text', text: EXIT_PLAN } },
      ],
    };

    modes.set(turn.sessionId, 'plan');
    await turn.send({
      sessionUpdate: 'current_mode_update',
      currentModeId: 'plan',
    });
    await turn.send({ sessionUpdate: 'tool_call', ...toolCall });

    const answer = await turn.client.request('session/request_permission', {
      sessionId: turn.sessionId,
      toolCall,
      options: [
        {
          optionId: 'exit-plan-accept-edits',
          name: 'Yes, auto-accept edits',
          kind: 'allow_always',
        },
        {
          optionId: 'exit-plan-default',
          name: 'Yes, manually approve edits',
          kind: 'allow_once',
        },
        { optionId: 'reject', name: 'No, keep planning', kind: 'reject_once' },
      ],
    });
    const chosen =
      answer.outcome.outcome === 'selected'
        ? answer.outcome.optionId
        : 'reject';

    if (chosen === 'reject') {
      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId,
        status: 'failed',
      });
      await turn.say('I will keep planning.');

      return 'end_turn';
    }

    const mode =
      chosen === 'exit-plan-accept-edits' ? 'acceptEdits' : 'default';

    modes.set(turn.sessionId, mode);
    await turn.send({
      sessionUpdate: 'current_mode_update',
      currentModeId: mode,
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      title: 'Exited Plan Mode',
      status: 'completed',
    });
    await turn.send({
      sessionUpdate: 'plan_update',
      plan: {
        type: 'markdown',
        planId: 'plan-mode',
        content: EXIT_PLAN.trim(),
      },
    });
    await turn.say('Starting with the routing.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;

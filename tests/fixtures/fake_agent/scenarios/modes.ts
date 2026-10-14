/**
 * The agent's mode moved, held and said from inside a turn, and a status of
 * its own.
 */
import { NO_MODES } from '../options.ts';
import { configOptions, locked, modes } from '../sessions.ts';
import { type Play } from '../turn.ts';

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
} satisfies Record<string, Play>;

// The agent's mode moved, held and said from inside a turn, and a status
// of its own, as the original's scenarios/modes.ts.
import '../options.dart';
import '../sessions.dart';
import '../turn.dart';

/// The plan `claudeexitplan` asks to have approved.
const _exitPlan =
    '# Route updates by session\n\n'
    '1. Read src/acp/connection.ts.\n'
    '2. Move the routing into src/session/session.ts.\n'
    '3. Run the tests.\n';

Update _modeUpdate(String mode) => {
  'sessionUpdate': 'current_mode_update',
  'currentModeId': mode,
};

final Map<String, Play> modePlays = {
  // The mode moves by `current_mode_update` alone.
  'status': (turn) async {
    modes[turn.sessionId] = 'plan';
    await turn.send(_modeUpdate('plan'));
    await turn.send({
      'sessionUpdate': 'usage_update',
      'used': 1200,
      'size': 200000,
      'cost': {'amount': 0.01, 'currency': 'USD'},
    });
    await turn.say(['Status sent.']);
    turn.usage = {
      'inputTokens': 1000,
      'outputTokens': 200,
      'totalTokens': 1200,
    };
    return 'end_turn';
  },

  // dimcode's permission moved to full-access from the agent's side
  // (CHD-434).
  'fullaccess': (turn) async {
    permissions[turn.sessionId] = 'full-access';
    await turn.send({
      'sessionUpdate': 'config_option_update',
      'configOptions': configOptions(turn.sessionId),
    });
    await turn.say(['Permission is full-access.']);
    return 'end_turn';
  },

  // The agent leaves plan mode by itself, and says so both ways.
  'exitplan': (turn) async {
    await turn.say(['Plan approved.']);
    modes[turn.sessionId] = 'default';
    await turn.send(_modeUpdate('default'));
    await turn.send({
      'sessionUpdate': 'config_option_update',
      'configOptions': configOptions(turn.sessionId),
    });
    return 'end_turn';
  },

  // What the turn runs under, from inside it.
  'mode': (turn) async {
    await turn.say([
      'Mode: ${noModes ? 'none' : (modes[turn.sessionId] ?? 'default')}.',
    ]);
    return 'end_turn';
  },

  // The agent moves to plan and holds it, refusing every mode after.
  'lock': (turn) async {
    locked.add(turn.sessionId);
    await turn.send(_modeUpdate('plan'));
    await turn.say(['Mode locked.']);
    return 'end_turn';
  },

  // Claude's ExitPlanMode, as its adapter sends it to a client that takes
  // plans.
  'claudeexitplan': (turn) async {
    final toolCallId = turn.callId('exitplan');
    final toolCall = {
      'toolCallId': toolCallId,
      'title': 'Approve Plan',
      'kind': 'switch_mode',
      'status': 'pending',
      'rawInput': {'plan': _exitPlan},
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': _exitPlan},
        },
      ],
    };
    modes[turn.sessionId] = 'plan';
    await turn.send(_modeUpdate('plan'));
    await turn.send({'sessionUpdate': 'tool_call', ...toolCall});

    final answer = await turn.client.request('session/request_permission', {
      'sessionId': turn.sessionId,
      'toolCall': toolCall,
      'options': [
        {
          'optionId': 'exit-plan-accept-edits',
          'name': 'Yes, auto-accept edits',
          'kind': 'allow_always',
        },
        {
          'optionId': 'exit-plan-default',
          'name': 'Yes, manually approve edits',
          'kind': 'allow_once',
        },
        {
          'optionId': 'reject',
          'name': 'No, keep planning',
          'kind': 'reject_once',
        },
      ],
    });
    final outcome = (answer['outcome'] as Map?) ?? const {};
    final chosen = outcome['outcome'] == 'selected'
        ? outcome['optionId']
        : 'reject';
    if (chosen == 'reject') {
      await turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': toolCallId,
        'status': 'failed',
      });
      await turn.say(['I will keep planning.']);
      return 'end_turn';
    }
    final mode = chosen == 'exit-plan-accept-edits' ? 'acceptEdits' : 'default';
    modes[turn.sessionId] = mode;
    await turn.send(_modeUpdate(mode));
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'title': 'Exited Plan Mode',
      'status': 'completed',
    });
    await turn.send({
      'sessionUpdate': 'plan_update',
      'plan': {
        'type': 'markdown',
        'planId': 'plan-mode',
        'content': _exitPlan.trim(),
      },
    });
    await turn.say(['Starting with the routing.']);
    return 'end_turn';
  },
};

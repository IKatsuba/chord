// An agent's own cycles after its turn has ended (CHD-426), as the
// original's scenarios/cycles.ts: here so far the cycle a session resumed
// runs with `--cycle-on-resume`.
import '../options.dart';
import '../sessions.dart';
import '../turn.dart';

/// Longer than chord waits for a turn's tail to go quiet.
const quiet = 1500;

/// Between one part of a cycle and the next.
const step = 200;

/// Sends [update] to [sessionId] with no turn running.
Future<void> sendTo(Client client, String sessionId, Object? update) =>
    client.notify('session/update', {'sessionId': sessionId, 'update': update});

Future<void> sayTo(Client client, String sessionId, String text) =>
    sendTo(client, sessionId, {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
    });

/// The usage update that ends a Claude cycle, with `--cycle-cost` the
/// session's cost so far with the cycle's added (CHD-373).
Update cycleUsage(String sessionId) {
  final num? cost = cycleCost == null
      ? null
      : (costs[sessionId] ?? costFrom) + cycleCost!;
  if (cost != null) costs[sessionId] = cost;
  return {
    'sessionUpdate': 'usage_update',
    'used': 1200,
    'size': 200000,
    if (cost != null) 'cost': {'amount': cost, 'currency': 'USD'},
    '_meta': {
      '_claude/origin': {'kind': 'task-notification'},
    },
  };
}

/// A Claude cycle with no turn before it, once the session has gone quiet.
void runCycle(Client client, String sessionId) {
  () async {
    try {
      await pause(lifetime.signal, quiet);
      await sayTo(
        client,
        sessionId,
        'A background task ended while you were away.',
      );
      await pause(lifetime.signal, step);
      await sendTo(client, sessionId, cycleUsage(sessionId));
    } catch (_) {
      // The client went first.
    }
  }();
}

/// Ends the turn, then, once it has gone quiet, works on its own as Claude
/// Code does when a background task ends; with [usage] it ends that cycle
/// with a usage update of a `task-notification` origin.
Play _claudeCycle(bool usage) => (turn) async {
  () async {
    try {
      // Quiet counts from the turn's end, which may be slow to go.
      await turn.over;
      await pause(lifetime.signal, quiet);
      await sayTo(
        turn.client,
        turn.sessionId,
        'The background build ended; reading its log.',
      );
      await pause(lifetime.signal, step);
      await sayTo(turn.client, turn.sessionId, ' The build passed.');
      if (usage) {
        await pause(lifetime.signal, step);
        await sendTo(turn.client, turn.sessionId, cycleUsage(turn.sessionId));
      }
    } catch (_) {
      // The client went first.
    }
  }();
  await turn.say(['The build runs in the background; I will read it after.']);
  return 'end_turn';
};

final Map<String, Play> cycles = {
  'claudecycle': _claudeCycle(true),
  'claudecyclebare': _claudeCycle(false),

  // As claudecycle, the cycle asking to write a file before it ends.
  'claudecycleask': (turn) async {
    () async {
      try {
        await turn.over;
        await pause(lifetime.signal, quiet);
        await sayTo(
          turn.client,
          turn.sessionId,
          'The background build ended; saving its log.',
        );
        final toolCall = {
          'toolCallId': turn.callId('write'),
          'title': 'Write notes/build.md',
          'kind': 'edit',
          'status': 'pending',
          'locations': [
            {'path': 'notes/build.md'},
          ],
        };
        await sendTo(turn.client, turn.sessionId, {
          'sessionUpdate': 'tool_call',
          ...toolCall,
        });
        final answer = await turn.client.request('session/request_permission', {
          'sessionId': turn.sessionId,
          'toolCall': toolCall,
          'options': [
            {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
            {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
          ],
        });
        final outcome = (answer['outcome'] as Map?) ?? const {};
        final chosen = outcome['outcome'] == 'selected'
            ? (outcome['optionId'] ?? 'undefined')
            : 'cancelled';
        await sayTo(turn.client, turn.sessionId, 'Permission: $chosen.');
        await pause(lifetime.signal, step);
        await sendTo(turn.client, turn.sessionId, cycleUsage(turn.sessionId));
      } catch (_) {
        // The client went first.
      }
    }();
    await turn.say(['The build runs in the background; I will read it after.']);
    return 'end_turn';
  },

  // Ends the turn, then runs an unasked turn as codebuddy does once a
  // background task drains, marked at both ends.
  'codebuddycycle': (turn) async {
    () async {
      try {
        await pause(lifetime.signal, step);
        await sendTo(turn.client, turn.sessionId, {
          'sessionUpdate': 'session_info_update',
          '_meta': {
            'codebuddy.ai/unsolicitedTurn': {
              'requestId': 'unasked-1',
              'reason': 'background_drain',
            },
          },
        });
        await pause(lifetime.signal, step);
        await sayTo(
          turn.client,
          turn.sessionId,
          'The background task drained; all checks are green.',
        );
        await pause(lifetime.signal, step);
        await sendTo(turn.client, turn.sessionId, {
          'sessionUpdate': 'session_end',
        });
      } catch (_) {
        // The client went first.
      }
    }();
    await turn.say(['The checks run in the background.']);
    return 'end_turn';
  },
};

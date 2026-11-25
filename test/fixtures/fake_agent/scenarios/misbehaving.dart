// What a transport has to survive: a turn that fails, a chunk after the
// answer, and what ACP does not have, as the original's
// scenarios/misbehaving.ts.
import '../options.dart';
import '../rpc.dart';
import '../sessions.dart';
import '../turn.dart';

const _floodChunk = 64 * 1024;
const _floodBytes = 64 * 1024 * 1024;

/// What `turnfailed`'s turn fails with, as goose words a model error.
const turnFailed = 'Request failed: the model is overloaded.';

final Map<String, Play> misbehaving = {
  // More than any pipe holds, as fast as chord takes it, for a client that
  // stopped reading; a cancel or the client's going ends it.
  'flood': (turn) async {
    final chunk = 'x' * _floodChunk;
    for (var sent = 0; sent < _floodBytes; sent += _floodChunk) {
      if (turn.signal.aborted || lifetime.signal.aborted) return 'cancelled';
      await turn.say([chunk]);
    }
    return 'end_turn';
  },

  // A cancel changes nothing: the prompt stays open until the client goes,
  // or 30 s.
  'ignorescancel': (turn) async {
    await turn.say(['Holding on.']);
    try {
      await pause(lifetime.signal, 30000);
    } catch (_) {}
    return 'end_turn';
  },

  // How many cancels came with no turn playing.
  'cancels': (turn) async {
    await turn.say([
      'Cancels with no turn: ${strayCancels[turn.sessionId] ?? 0}.',
    ]);
    return 'end_turn';
  },

  'error': (turn) async {
    await turn.say(['About to fail.']);
    await pause(turn.signal);
    throw RequestError(-32603, 'The fake agent failed on purpose.');
  },

  // A turn that ends on the model's error, as goose from 1.59 fails
  // `session/prompt`.
  'turnfailed': (turn) async {
    await turn.say(['Reading the tests.']);
    throw RequestError(-32603, turnFailed, {'reason': 'turn_failed'});
  },

  // An update after the answer.
  'late': (turn) async {
    await turn.say(['Answered.']);
    later(
      milliseconds(stepMs * 4),
      () => turn.client.notify('session/update', {
        'sessionId': turn.sessionId,
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': ' Late, after the answer.'},
        },
      }).ignore(),
    );
    return 'end_turn';
  },

  // An update of a kind ACP may add later, and a notification of the
  // agent's own.
  'unknown': (turn) async {
    await turn.client.notify('session/update', {
      'sessionId': turn.sessionId,
      'update': {'sessionUpdate': 'future_update', 'detail': 'from later'},
    });
    await turn.client.notify('_fake/notice', {'text': 'an extension'});
    await turn.say(['Sent the unknown.']);
    return 'end_turn';
  },

  // Claude's sign-in state, under the old underscore name and the method.
  'authstatus': (turn) async {
    const status = {
      'state': 'authenticated',
      'accounts': [
        {'label': 'Claude Max', 'active': true},
      ],
    };
    await turn.client.notify('_auth/status_update', status);
    await turn.client.notify('auth/status_update', status);
    await turn.say(['Sent the sign-in state.']);
    return 'end_turn';
  },
};

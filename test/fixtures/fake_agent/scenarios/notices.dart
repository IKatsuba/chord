// Notices (CHD-629), as the original's scenarios/notices.ts: here so far the
// update that says one, and the notice of auto falling back.
import '../client.dart';
import '../turn.dart';

/// The update that says [notice], as the client takes it.
Update noticeUpdate(Map<String, Object?> notice) {
  if (clientTakesNotices) return {'sessionUpdate': 'notice', ...notice};
  final description = notice['description'];
  final text =
      '> **${notice['title']}**'
      '${description is String && description.isNotEmpty ? '\n> $description' : ''}\n\n';
  return {
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  };
}

const autoOff = <String, Object?>{
  'severity': 'info',
  'title': 'Auto mode unavailable',
  'description':
      'The selected model does not support Auto mode; using Accept edits '
      'instead.',
};

/// Longer than chord waits for a turn's tail to go quiet.
const _quiet = 1500;

const _fastOff = <String, Object?>{
  'severity': 'warning',
  'title': 'Fast mode turned off',
  'description':
      'Rate limit for fast mode reached; it comes back after the limit '
      'resets.',
};

/// A description longer than two rows at 80 columns, with blank lines to
/// fold.
const _long = <String, Object?>{
  'severity': 'error',
  'title': 'MCP server "files" failed to start',
  'description':
      'Its tools are unavailable in this session: the server exited before '
      'it answered initialize, with status 1.\n\n\nCheck its command and '
      'environment in .mcp.json, then start a new session; the server wrote '
      'nothing to stderr that names a reason, so this is all that is known.',
};

final Map<String, Play> notices = {
  'noticelong': (turn) async {
    await turn.send(noticeUpdate(_long));
    await turn.say(['Carrying on without it.']);
    return 'end_turn';
  },
  'notice': (turn) async {
    await turn.say(['Running the lexer suite with coverage now. ']);
    await turn.send(noticeUpdate(_fastOff));
    await turn.say(['Done.']);
    return 'end_turn';
  },
  'noticeidle': (turn) async {
    await turn.say(['Switched.']);
    () async {
      await turn.over;
      await pause(lifetime.signal, _quiet);
      await turn.client.notify('session/update', {
        'sessionId': turn.sessionId,
        'update': noticeUpdate(autoOff),
      });
    }().ignore();
    return 'end_turn';
  },
};

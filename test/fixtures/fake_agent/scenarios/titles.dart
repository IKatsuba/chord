// Titles a client gives a session (CHD-629), as the original's
// scenarios/titles.ts: here so far `session/set_title` as `--set-title`
// plays it.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../options.dart';
import '../rpc.dart';
import '../sessions.dart';
import '../turn.dart';
import 'agents.dart';

/// The longest title the fake stores, as an adapter cuts one.
const _titleCut = 80;

/// The title the agent gives the session of its own in `titledlater`.
const laterTitle = 'Tidy the parser tests';

/// The file in the session's gate each `session/set_title` title goes into.
const titlesHeard = 'titles-heard';

Future<void> _released(String sessionId) async {
  final at = p.join(cwds[sessionId] ?? '.', gate, gateRelease);
  final deadline = now() + 10000;
  while (!File(at).existsSync() && now() < deadline) {
    await pause(lifetime.signal);
  }
}

/// Answers `session/set_title` as `--set-title` says.
Future<Map<String, Object?>> setTitle(
  Client client,
  Map<String, Object?> params,
) async {
  final sessionId = params['sessionId'] as String;
  final asked = params['title'] as String;
  final at = Directory(p.join(cwds[sessionId] ?? '.', gate));
  await at.create(recursive: true);
  await File(
    p.join(at.path, titlesHeard),
  ).writeAsString('$asked\n', mode: FileMode.append);
  final folded = asked.replaceAll(RegExp(r'\s+'), ' ').trim();
  final title = folded.length > _titleCut
      ? folded.substring(0, _titleCut)
      : folded;
  if (title.isEmpty) {
    throw RequestError.invalidParams(null, 'The title is empty.');
  }
  if (setTitleMode == 'refuse') {
    throw RequestError(
      -32600,
      'This version of the fake agent cannot rename a session.',
    );
  }
  if (setTitleMode == 'hang') await _released(sessionId);
  if (setTitleMode != 'silent') {
    await client.notify('session/update', {
      'sessionId': sessionId,
      'update': {'sessionUpdate': 'session_info_update', 'title': title},
    });
  }
  return {'title': title};
}

final Map<String, Play> titles = {
  // The agent's own title, once the gate is released.
  'titledlater': (turn) async {
    await turn.say(['Naming this session later.']);
    await gateOpened(turn, gateRelease);
    await turn.send({
      'sessionUpdate': 'session_info_update',
      'title': laterTitle,
    });
    return 'end_turn';
  },
};

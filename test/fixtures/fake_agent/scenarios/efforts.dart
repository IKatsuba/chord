// Agents started on an effort, and the effort a turn runs on, said from
// inside it, as the original's scenarios/efforts.ts.
import 'dart:convert';

import '../options.dart';
import '../sessions.dart';
import '../turn.dart';
import 'chord_tools.dart';

/// The task `taskeffort` and `taskmaxeffort` start, on `text`.
const effortTaskArgs = <String, Object?>{
  'agent': 'fake',
  'model': 'fake-small',
  'prompt': 'text',
  'name': 'Tune the parser',
};

/// The agent `agenteffort` and `agentmaxeffort` open, on `text`.
const effortAgentArgs = <String, Object?>{
  'agent': 'fake',
  'model': 'fake-small',
  'prompt': 'text',
  'name': 'tuner',
};

/// Calls [tool] on [effort] and says where the agent started.
Future<String> _startOn(
  Turn turn,
  String tool,
  Map<String, Object?> arguments,
  String effort,
) async {
  final client = await chordClient(turn);
  if (client == null) {
    await turn.say(['No chord server in this session.']);
    return 'end_turn';
  }
  try {
    final text = await callChord(turn, client, tool, {
      ...arguments,
      'effort': effort,
    });
    final answer = jsonDecode(text ?? '{}') as Map;
    final note = answer['note'];
    await turn.say([
      'Started on ${answer['effort'] ?? 'no effort'}.'
          '${note == null ? '' : ' $note.'}',
    ]);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

final Map<String, Play> effortPlays = {
  // What the turn runs on, from inside it.
  'effort': (turn) async {
    await turn.say([
      'Effort: ${noConfig ? 'none' : (efforts[turn.sessionId] ?? 'medium')}.',
    ]);
    return 'end_turn';
  },
  'taskeffort': (turn) => _startOn(turn, 'spawn_task', effortTaskArgs, 'high'),
  'taskmaxeffort': (turn) =>
      _startOn(turn, 'spawn_task', effortTaskArgs, 'max'),
  'agenteffort': (turn) =>
      _startOn(turn, 'open_agent', effortAgentArgs, 'high'),
  'agentmaxeffort': (turn) =>
      _startOn(turn, 'open_agent', effortAgentArgs, 'max'),
};

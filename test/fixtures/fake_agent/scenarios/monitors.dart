// Monitors: sessions that start commands through chord's `monitor` tool,
// whose lines come back later as messages, as the original's
// scenarios/monitors.ts. Each command is plain shell.
import 'package:mcp_dart/mcp_dart.dart' as mcp;

import '../turn.dart';
import 'chord_tools.dart';

/// A dev server's error a second in, then quiet until it is stopped.
const errorsArgs = <String, Object?>{
  'command':
      'sleep 1; echo "ERROR [router] POST /login 500: Cannot read '
      'properties of undefined (reading \'trim\')"; echo "    at validate '
      '(src/routes/login.tsx:41:22)"; sleep 600',
  'description': 'dev server errors',
};

/// A run that says nothing while it lasts.
const quietArgs = <String, Object?>{
  'command': 'sleep 600',
  'description': 'CI run 4812',
};

/// A run that prints its jobs and fails.
const failingArgs = <String, Object?>{
  'command':
      'sleep 1; echo "✓ lint in 41s"; echo "X test (ubuntu-latest) in '
      '3m 12s"; echo "Run 4812 (ci.yml) failed: 1 of 3 jobs failed"; exit 1',
  'description': 'CI run 4812',
};

/// A heartbeat a second in, then chord's timeout five seconds in.
const timeoutArgs = <String, Object?>{
  'command': 'sleep 1; echo "heartbeat 1: check the ship run"; sleep 600',
  'description': 'heartbeat',
  'timeout_ms': 5000,
};

/// A log nobody filtered.
const floodArgs = <String, Object?>{
  'command': 'yes \'127.0.0.1 - - "GET /health HTTP/1.1" 200 2\'',
  'description': 'request log',
};

/// What the child `monitorchild` opens starts.
const childMonitorArgs = <String, Object?>{
  'command':
      'sleep 1; echo "ok 1 - parse a string at the end of a line"; '
      'sleep 600',
  'description': 'parser tests',
};

/// Runs [play] on chord's server, or says the session has none.
Future<String> _withChord(
  Turn turn,
  Future<void> Function(mcp.McpClient client) play,
) async {
  final client = await chordClient(turn);
  if (client == null) {
    await turn.say(['No chord server in this session.']);
    return 'end_turn';
  }
  try {
    await play(client);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

final Map<String, Play> monitors = {
  // Starts one monitor that prints an error a second in.
  'monitor': (turn) => _withChord(turn, (client) async {
    await callChord(turn, client, 'monitor', errorsArgs);
    await turn.say(['I will hear from the dev server when it errs.']);
  }),
  // Starts two: the one that errs and one that stays quiet.
  'monitors': (turn) => _withChord(turn, (client) async {
    await callChord(turn, client, 'monitor', errorsArgs);
    await callChord(turn, client, 'monitor', quietArgs);
    await turn.say(['Two monitors are running.']);
  }),
  // Starts one whose command exits 1 after a second.
  'monitorexit': (turn) => _withChord(turn, (client) async {
    await callChord(turn, client, 'monitor', failingArgs);
    await turn.say(['I will hear when the CI run ends.']);
  }),
  // Starts one that says one thing and then reaches its timeout.
  'monitortimeout': (turn) => _withChord(turn, (client) async {
    await callChord(turn, client, 'monitor', timeoutArgs);
    await turn.say(['The heartbeat stops itself in five seconds.']);
  }),
  // Starts one that prints far more than a monitor may.
  'monitorflood': (turn) => _withChord(turn, (client) async {
    await callChord(turn, client, 'monitor', floodArgs);
    await turn.say(['Watching the request log.']);
  }),
  // Opens `parser` on `childmonitor`, then starts a monitor of its own.
  'monitorchild': (turn) => _withChord(turn, (client) async {
    await callChord(turn, client, 'open_agent', {
      'agent': 'fake',
      'prompt': 'childmonitor',
      'name': 'parser',
    });
    await callChord(turn, client, 'monitor', errorsArgs);
    await turn.say(['parser watches its tests; I watch the dev server.']);
  }),
  // A child's first turn: a monitor of its own.
  'childmonitor': (turn) => _withChord(turn, (client) async {
    await callChord(turn, client, 'monitor', childMonitorArgs);
    await turn.say(['Watching the parser tests.']);
  }),
};

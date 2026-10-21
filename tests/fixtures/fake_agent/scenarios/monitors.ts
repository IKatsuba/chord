/**
 * Monitors: sessions that start commands through chord's `monitor` tool,
 * whose lines come back later as messages. Each command is plain shell, so
 * nothing outside the fake agent runs: one that prints an error a second
 * after it starts and then waits, one that prints nothing, one that exits
 * non-zero, one that reaches its timeout, one that floods, and a child that
 * starts one of its own.
 */
import type { Client } from '@modelcontextprotocol/sdk/client/index.js';
import type { Play, Turn } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';

/** A dev server's error a second in, then quiet until it is stopped. */
export const ERRORS_ARGS = {
  command:
    'sleep 1; echo "ERROR [router] POST /login 500: Cannot read ' +
    'properties of undefined (reading \'trim\')"; echo "    at validate ' +
    '(src/routes/login.tsx:41:22)"; sleep 600',
  description: 'dev server errors',
};

/** A run that says nothing while it lasts. */
export const QUIET_ARGS = {
  command: 'sleep 600',
  description: 'CI run 4812',
};

/** A run that prints its jobs and fails. */
export const FAILING_ARGS = {
  command:
    'sleep 1; echo "✓ lint in 41s"; echo "X test (ubuntu-latest) in ' +
    '3m 12s"; echo "Run 4812 (ci.yml) failed: 1 of 3 jobs failed"; exit 1',
  description: 'CI run 4812',
};

/** A heartbeat a second in, then chord's timeout five seconds in. */
export const TIMEOUT_ARGS = {
  command: 'sleep 1; echo "heartbeat 1: check the ship run"; sleep 600',
  description: 'heartbeat',
  timeout_ms: 5000,
};

/** A log nobody filtered. */
export const FLOOD_ARGS = {
  command: 'yes \'127.0.0.1 - - "GET /health HTTP/1.1" 200 2\'',
  description: 'request log',
};

/** What the child `monitorchild` opens starts. */
export const CHILD_MONITOR_ARGS = {
  command:
    'sleep 1; echo "ok 1 - parse a string at the end of a line"; ' +
    'sleep 600',
  description: 'parser tests',
};

/** Runs `play` on chord's server, or says the session has none. */
async function withChord(
  turn: Turn,
  play: (client: Client) => Promise<void>,
): Promise<'end_turn'> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await play(client);
  } finally {
    await client.close();
  }

  return 'end_turn';
}

export const MONITORS = {
  // Starts one monitor that prints an error a second in.
  monitor(turn) {
    return withChord(turn, async (client) => {
      await callChord(turn, client, 'monitor', ERRORS_ARGS);
      await turn.say('I will hear from the dev server when it errs.');
    });
  },
  // Starts two: the one that errs and one that stays quiet.
  monitors(turn) {
    return withChord(turn, async (client) => {
      await callChord(turn, client, 'monitor', ERRORS_ARGS);
      await callChord(turn, client, 'monitor', QUIET_ARGS);
      await turn.say('Two monitors are running.');
    });
  },
  // Starts one whose command exits 1 after a second.
  monitorexit(turn) {
    return withChord(turn, async (client) => {
      await callChord(turn, client, 'monitor', FAILING_ARGS);
      await turn.say('I will hear when the CI run ends.');
    });
  },
  // Starts one that says one thing and then reaches its timeout.
  monitortimeout(turn) {
    return withChord(turn, async (client) => {
      await callChord(turn, client, 'monitor', TIMEOUT_ARGS);
      await turn.say('The heartbeat stops itself in five seconds.');
    });
  },
  // Starts one that prints far more than a monitor may.
  monitorflood(turn) {
    return withChord(turn, async (client) => {
      await callChord(turn, client, 'monitor', FLOOD_ARGS);
      await turn.say('Watching the request log.');
    });
  },
  // Opens `parser` on `childmonitor`, then starts a monitor of its own.
  monitorchild(turn) {
    return withChord(turn, async (client) => {
      await callChord(turn, client, 'open_agent', {
        agent: 'fake',
        prompt: 'childmonitor',
        name: 'parser',
      });
      await callChord(turn, client, 'monitor', ERRORS_ARGS);
      await turn.say('parser watches its tests; I watch the dev server.');
    });
  },
  // A child's first turn: a monitor of its own.
  childmonitor(turn) {
    return withChord(turn, async (client) => {
      await callChord(turn, client, 'monitor', CHILD_MONITOR_ARGS);
      await turn.say('Watching the parser tests.');
    });
  },
} satisfies Record<string, Play>;

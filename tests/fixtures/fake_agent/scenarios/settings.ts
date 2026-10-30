/**
 * chord's `settings` tool, called as an agent calls it. The file it reads is
 * whatever the run's `XDG_CONFIG_HOME` holds: a test's fixture, never a
 * person's own.
 */
import type { Play } from '../turn.ts';
import { GATE_RELEASE, gateOpened } from './agents.ts';
import { callChord, chordClient } from './chord_tools.ts';

const calls =
  (...each: readonly Record<string, unknown>[]): Play =>
  async (turn) => {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server.');

      return 'end_turn';
    }

    try {
      for (const args of each) {
        // As long as the person takes to answer the box.
        await callChord(turn, client, 'settings', args, 600_000);
      }
    } finally {
      await client.close();
    }

    return 'end_turn';
  };

/**
 * A second change while the first's box is up: the first asks, and once the
 * gate opens, at most 10 s on, the second is refused with that box still open;
 * the turn ends once the person answers.
 */
const overlap: Play = async (turn) => {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server.');

    return 'end_turn';
  }

  try {
    const first = callChord(
      turn,
      client,
      'settings',
      { action: 'set', path: ['theme'], value: 'light' },
      600_000,
    );

    await gateOpened(turn, GATE_RELEASE);
    await callChord(
      turn,
      client,
      'settings',
      { action: 'set', path: ['agents', 'fake', 'model'], value: 'fake-small' },
      600_000,
    );
    await first;
  } finally {
    await client.close();
  }

  return 'end_turn';
};

/**
 * A change whose call the agent gives up on with the box up, once the gate
 * opens, at most 10 s on, as a cancelled request is withdrawn: chord says the
 * person was not asked to the end.
 */
const withdrawn: Play = async (turn) => {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server.');

    return 'end_turn';
  }

  const toolCallId = turn.callId('settings');
  const args = { action: 'set', path: ['theme'], value: 'light' };

  try {
    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      status: 'pending',
      title: 'mcp__chord__settings',
      kind: 'other',
      rawInput: args,
    });

    const cancelled = new AbortController();
    const call = client
      .callTool({ name: 'settings', arguments: args }, undefined, {
        signal: cancelled.signal,
      })
      .catch(() => {});

    await gateOpened(turn, GATE_RELEASE);
    cancelled.abort();
    await call;

    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      status: 'failed',
    });
  } finally {
    await client.close();
  }

  return 'end_turn';
};

export const SETTINGS = {
  settingsoverlap: overlap,
  // Every key, folded on its row until ctrl+o.
  settingsread: calls({ action: 'read' }),
  // One key under a mask, its secret never drawn.
  settingsreadkey: calls({
    action: 'read',
    path: ['mcpServers', 'linear', 'env', 'TOKEN'],
  }),
  // A name that can be no key, refused.
  settingsreadbad: calls({ action: 'read', path: ['__proto__'] }),
  // A user-only key: `set` on an unset file, `unchanged` once it holds it.
  settingstheme: calls({ action: 'set', path: ['theme'], value: 'light' }),
  // An agent's model, next to whatever else that agent holds.
  settingsmodel: calls({
    action: 'set',
    path: ['agents', 'fake', 'model'],
    value: 'fake-small',
  }),
  // The theme again: `remove`, or `unchanged` where it is not set.
  settingsremove: calls({ action: 'remove', path: ['theme'] }),
  // A kind B key, which a project's file holding it shadows.
  settingsagent: calls({ action: 'set', path: ['agent'], value: 'fake' }),
  // The prompt's editing, which the window takes up at once.
  settingsvim: calls({ action: 'set', path: ['editorMode'], value: 'vim' }),
  // What `/new` lists, which the window takes up at once.
  settingsoffered: calls({
    action: 'set',
    path: ['offeredAgents'],
    value: ['claude'],
  }),
  // One of each refusal that reading no file can tell, none asking the box.
  settingsrefused: calls(
    { action: 'set', path: ['agents', 'claude', 'modle'], value: 'm' },
    { action: 'set', path: ['agents', 'claude', 'command'], value: 'c' },
    { action: 'remove', path: ['mcpServers', 'linear'] },
    { action: 'set', path: ['agents', 'codex'], value: {} },
    { action: 'set', path: ['teamSelection'], value: {} },
    { action: 'set', path: ['editorMode'], value: 'emacs' },
    { action: 'set', path: ['agents', 'nope', 'model'], value: 'm' },
  ),
  settingswithdrawn: withdrawn,
  // A value far taller than the room left above the box at 80x24.
  settingslong: calls({
    action: 'set',
    path: ['agents', 'fake', 'model'],
    value: 'l'.repeat(1200),
  }),
} satisfies Record<string, Play>;

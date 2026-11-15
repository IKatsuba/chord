/**
 * Titles a client gives a session (CHD-629): `session/set_title` as
 * `--set-title` plays it, Claude's and Codex's adapters storing the title
 * and saying so in a `session_info_update` before they answer, and a title
 * of the agent's own that comes later and takes over.
 */
import { existsSync } from 'node:fs';
import { appendFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import * as acp from '@agentclientprotocol/sdk/unstable';
import { SET_TITLE } from '../options.ts';
import { cwds } from '../sessions.ts';
import { type Client, lifetime, pause, type Play } from '../turn.ts';
import { GATE, GATE_RELEASE, gateOpened } from './agents.ts';

/** The longest title the fake stores, as an adapter cuts one. */
const TITLE_CUT = 80;

/** The title the agent gives the session of its own in `titledlater`. */
export const LATER_TITLE = 'Tidy the parser tests';

/**
 * The file in the session's gate each `session/set_title` request's title
 * goes into, a line each, as it arrives: a test sees what reached the agent.
 */
export const TITLES_HEARD = 'titles-heard';

/**
 * Until the session's gate is released, or 10 s on the monotonic clock, or
 * the client goes.
 */
async function released(sessionId: string): Promise<void> {
  const at = join(cwds.get(sessionId) ?? '.', GATE, GATE_RELEASE);
  const deadline = performance.now() + 10_000;

  while (!existsSync(at) && performance.now() < deadline) {
    await pause(lifetime.signal);
  }
}

/**
 * Answers `session/set_title` as `--set-title` says: `echo` stores the
 * title, trimmed, its whitespace folded and cut at 80, sends it in a
 * `session_info_update`, then answers it; `silent` only answers; `refuse`
 * refuses -32600 as Claude's adapter on an old CLI does; `hang` answers as
 * `echo` once the gate is released. An empty title is -32602 whichever.
 */
export async function setTitle(
  client: Client,
  params: acp.SetSessionTitleRequest,
): Promise<acp.SetSessionTitleResponse> {
  const gate = join(cwds.get(params.sessionId) ?? '.', GATE);

  await mkdir(gate, { recursive: true });
  await appendFile(join(gate, TITLES_HEARD), `${params.title}\n`);

  const title = params.title.replaceAll(/\s+/g, ' ').trim().slice(0, TITLE_CUT);

  if (title === '') {
    throw acp.RequestError.invalidParams(undefined, 'The title is empty.');
  }

  if (SET_TITLE === 'refuse') {
    throw new acp.RequestError(
      -32600,
      'This version of the fake agent cannot rename a session.',
    );
  }

  if (SET_TITLE === 'hang') {
    await released(params.sessionId);
  }

  if (SET_TITLE !== 'silent') {
    await client.notify('session/update', {
      sessionId: params.sessionId,
      update: { sessionUpdate: 'session_info_update', title },
    });
  }

  return { title };
}

export const TITLES = {
  // The agent's own title, once the gate is released: a rename it did not
  // make takes over, as one made outside chord would.
  titledlater: async (turn) => {
    await turn.say('Naming this session later.');
    await gateOpened(turn, GATE_RELEASE);
    await turn.send({
      sessionUpdate: 'session_info_update',
      title: LATER_TITLE,
    });

    return 'end_turn';
  },
} satisfies Record<string, Play>;

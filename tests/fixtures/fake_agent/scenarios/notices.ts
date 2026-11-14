/**
 * Notices (CHD-629): advice the agent sends as a `notice` to a client that
 * declared `session.notices`, and to any other as Claude's adapter does, a
 * bold blockquote of reply text.
 */
import type * as acp from '@agentclientprotocol/sdk/unstable';
import { clientTakesNotices } from '../client.ts';
import { lifetime, pause, type Play, type Turn } from '../turn.ts';

/** Longer than chord waits for a turn's tail to go quiet (`cycles.ts`). */
const QUIET = 1500;

/** The update that says `notice`, as the client takes it. */
export function noticeUpdate(notice: acp.Notice): acp.SessionUpdate {
  if (clientTakesNotices) {
    return { sessionUpdate: 'notice', ...notice };
  }

  const text = `> **${notice.title}**${
    notice.description ? `\n> ${notice.description}` : ''
  }\n\n`;

  return {
    sessionUpdate: 'agent_message_chunk',
    content: { type: 'text', text },
  };
}

const FAST_OFF: acp.Notice = {
  severity: 'warning',
  title: 'Fast mode turned off',
  description:
    'Rate limit for fast mode reached; it comes back after the limit resets.',
};

const AUTO_OFF: acp.Notice = {
  severity: 'info',
  title: 'Auto mode unavailable',
  description:
    'The selected model does not support Auto mode; using Accept edits instead.',
};

/** A description longer than two rows at 80 columns, with blank lines to fold. */
const LONG: acp.Notice = {
  severity: 'error',
  title: 'MCP server "files" failed to start',
  description:
    'Its tools are unavailable in this session: the server exited before it answered initialize, with status 1.\n\n\nCheck its command and environment in .mcp.json, then start a new session; the server wrote nothing to stderr that names a reason, so this is all that is known.',
};

export const NOTICES = {
  noticelong: async (turn) => {
    await turn.send(noticeUpdate(LONG));
    await turn.say('Carrying on without it.');

    return 'end_turn';
  },
  notice: async (turn) => {
    await turn.say('Running the lexer suite with coverage now. ');
    await turn.send(noticeUpdate(FAST_OFF));
    await turn.say('Done.');

    return 'end_turn';
  },
  noticeidle: async (turn: Turn) => {
    await turn.say('Switched.');

    void (async () => {
      await turn.over;
      await pause(lifetime.signal, QUIET);
      await turn.client.notify('session/update', {
        sessionId: turn.sessionId,
        update: noticeUpdate(AUTO_OFF),
      });
    })().catch(() => {});

    return 'end_turn';
  },
} satisfies Record<string, Play>;

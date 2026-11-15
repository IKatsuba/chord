/**
 * Tool calls that name a subagent (CHD-629): `{type: "session"}` content
 * referring to a child announced before, as Claude's adapter appends one to
 * TaskStop and SendMessage, and to one never announced.
 */
import type * as acp from '@agentclientprotocol/sdk/unstable';
import { type Play, Turn } from '../turn.ts';
import { GATE_RELEASE, gateOpened } from './agents.ts';

/** The grandchild `subagentgrandlinked` announces, then refers to. */
export const GRANDCHILD_TITLE = 'Lint the parser';

/** The child `subagentlinked` announces, then refers to. */
export const LINKED_TITLE = 'Watch the build';

/** A reference to session `sessionId`, as a call's content carries it. */
function reference(sessionId: string): acp.ToolCallContent {
  return { type: 'session', sessionId } as acp.ToolCallContent;
}

export const LINKS = {
  // A child announced, then a call about it with text, running and then
  // completed, and one whose content is only the reference, failed.
  subagentlinked: async (turn) => {
    const child = turn.callId('child');

    await turn.send({
      sessionUpdate: 'subagent_update',
      sessionId: child,
      title: LINKED_TITLE,
      capabilities: {},
      state: { state: 'running' },
    });

    const stop = turn.callId('stop');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: stop,
      title: 'TaskStop',
      kind: 'other',
      status: 'in_progress',
      content: [reference(child)],
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: stop,
      status: 'completed',
      content: [
        { type: 'content', content: { type: 'text', text: 'Stopped.' } },
        reference(child),
        reference(child),
      ],
    });

    const send = turn.callId('send');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: send,
      title: 'SendMessage',
      kind: 'other',
      status: 'pending',
      content: [reference(child)],
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: send,
      status: 'failed',
      content: [reference(child)],
    });
    await turn.say('Stopped the build watcher.');

    return 'end_turn';
  },
  // A child that announces a child of its own; then a call of the parent's
  // whose content is only a reference to the grandchild, running until the
  // gate is released, then completed.
  subagentgrandlinked: async (turn) => {
    const child = new Turn(turn.client, turn.callId('child'), turn.signal);
    const grandchild = turn.callId('grandchild');

    await turn.send({
      sessionUpdate: 'subagent_update',
      sessionId: child.sessionId,
      title: LINKED_TITLE,
      capabilities: {},
      state: { state: 'running' },
    });
    await child.send({
      sessionUpdate: 'subagent_update',
      sessionId: grandchild,
      title: GRANDCHILD_TITLE,
      capabilities: {},
      state: { state: 'running' },
    });

    const stop = turn.callId('stop');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: stop,
      title: 'TaskStop',
      kind: 'other',
      status: 'in_progress',
      content: [reference(grandchild)],
    });
    await gateOpened(turn, GATE_RELEASE);
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: stop,
      status: 'completed',
      content: [
        { type: 'content', content: { type: 'text', text: 'Stopped.' } },
        reference(grandchild),
      ],
    });

    return 'end_turn';
  },
  // A reference to a session never announced names nothing.
  subagentstranger: async (turn) => {
    const stop = turn.callId('stop');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: stop,
      title: 'TaskStop',
      kind: 'other',
      status: 'completed',
      content: [
        { type: 'content', content: { type: 'text', text: 'Stopped.' } },
        reference('never-announced'),
      ],
    });

    return 'end_turn';
  },
} satisfies Record<string, Play>;

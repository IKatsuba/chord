import type { SessionUpdate } from '@agentclientprotocol/sdk';
import type { TranscriptAction } from '../../../src/session/transcript/types.ts';

/**
 * A resumed session's past, as long as `turns` says, with every kind of write
 * the reducers make: text run on and new, thoughts, tool calls and their
 * updates, a plan, subagents with their own work and their ends, calls cut off
 * by a steer, cancelled turns and a lost agent.
 */
export function pastOf(turns: number): TranscriptAction[] {
  return Array.from({ length: turns }, (_, at): TranscriptAction[] => {
    const turnId = `history-${at}`;
    const update = (each: SessionUpdate, subagentId?: string) =>
      ({
        type: 'update',
        turnId,
        update: each,
        at,
        ...(subagentId === undefined ? {} : { subagentId }),
      }) as TranscriptAction;
    const text = (words: string): SessionUpdate => ({
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text: words },
    });
    const task = `task-${at}`;

    return [
      { type: 'prompt', turnId, text: `ask ${at}`, at },
      update({
        sessionUpdate: 'agent_thought_chunk',
        content: { type: 'text', text: `think ${at}` },
      }),
      update(text(`Reply ${at} starts `)),
      update(text('and runs on.\n```sh\n$ echo\n```')),
      update({
        sessionUpdate: 'tool_call',
        toolCallId: `call-${at}`,
        title: `Read ${at}.ts`,
        kind: 'read',
        status: 'pending',
      }),
      update({
        sessionUpdate: 'tool_call_update',
        toolCallId: `call-${at}`,
        status: 'completed',
        content: [
          { type: 'content', content: { type: 'text', text: `out ${at}` } },
        ],
      }),
      update({
        sessionUpdate: 'plan',
        entries: [
          { content: 'first', priority: 'high', status: 'completed' },
          {
            content: 'second',
            priority: 'low',
            status: at % 2 === 0 ? 'completed' : 'pending',
          },
        ],
      }),
      update({
        sessionUpdate: 'subagent_update',
        sessionId: task,
        title: `Task ${at}`,
        description: `Task ${at}, in full.`,
      } as unknown as SessionUpdate),
      update(text(`work of task ${at}`), task),
      update(
        {
          sessionUpdate: 'tool_call',
          toolCallId: `inner-${at}`,
          title: 'Edit',
          kind: 'edit',
          status: 'in_progress',
        },
        task,
      ),
      update({
        sessionUpdate: 'subagent_update',
        sessionId: task,
        state: { state: at % 3 === 0 ? 'cancelled' : 'completed' },
      } as unknown as SessionUpdate),
      // An agent item left running, which the next turn sees end: its end
      // line reads what it was before the update that ended it.
      update({
        sessionUpdate: 'subagent_update',
        sessionId: `left-${at}`,
        title: `Left ${at}`,
        description: `Left ${at}, in full.`,
      } as unknown as SessionUpdate),
      ...(at === 0
        ? []
        : [
            update({
              sessionUpdate: 'subagent_update',
              sessionId: `left-${at - 1}`,
              state: { state: at % 2 === 0 ? 'completed' : 'failed' },
            } as unknown as SessionUpdate),
          ]),
      // Cut off by a steer before it ran.
      update({
        sessionUpdate: 'tool_call',
        toolCallId: `cut-${at}`,
        title: 'Run',
        kind: 'execute',
        status: 'failed',
        _meta: { claudeCode: { nonExecutionKind: 'interrupted' } },
      }),
      ...(at % 5 === 0
        ? ([
            { type: 'cancel', turnId, at },
            {
              type: 'result',
              turnId,
              result: { status: 'cancelled', stopReason: 'cancelled' },
            },
          ] as TranscriptAction[])
        : at % 7 === 0
          ? ([
              {
                type: 'warned',
                turnId,
                message: 'a warning',
              },
              { type: 'disconnected', at },
              {
                type: 'result',
                turnId,
                result: { status: 'failed', error: { message: 'gone' } },
              },
            ] as TranscriptAction[])
          : ([
              {
                type: 'result',
                turnId,
                result: { status: 'completed', stopReason: 'end_turn' },
              },
            ] as TranscriptAction[])),
    ];
  }).flat();
}

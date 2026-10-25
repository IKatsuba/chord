/** Codex Guardian reviews, with codex-acp v2.2.2's structured verdicts. */
import type { ToolCallContent } from '@agentclientprotocol/sdk';
import { gateOpened, GATE_RELEASE } from './agents.ts';
import type { Play, Turn } from '../turn.ts';

const VERDICTS = ['approved', 'denied', 'timedOut', 'aborted'] as const;

function event(status: string) {
  return {
    action: { type: 'command', source: 'unifiedExec', command: 'printf ready' },
    review: {
      status,
      riskLevel: 'low',
      userAuthorization: 'high',
      rationale: 'A scripted Guardian review.',
    },
  };
}

function content(status: string): ToolCallContent[] {
  return [
    {
      type: 'content',
      content: {
        type: 'text',
        text: `Status: ${status}\nAction: exec printf ready\nRisk: low\nAuthorization: high\nRationale: A scripted Guardian review.`,
      },
    },
  ];
}

async function guardian(turn: Turn, gated: boolean) {
  const ids = new Map<string, string>();

  for (const status of [...VERDICTS, 'inProgress', 'unstructured']) {
    const toolCallId = `guardian_assessment:${turn.callId(status)}`;

    ids.set(status, toolCallId);

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      title: 'Guardian Review',
      kind: 'think',
      status: 'in_progress',
      ...(status === 'unstructured' ? {} : { rawInput: event('inProgress') }),
      content: content('In progress'),
    });
  }

  await turn.say('Guardian reviews opened.');

  if (gated) {
    await gateOpened(turn, GATE_RELEASE);
  }

  for (const status of VERDICTS) {
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: ids.get(status)!,
      status: status === 'approved' ? 'completed' : 'failed',
      rawInput: null,
      rawOutput: event(status),
      content: content(
        {
          approved: 'Approved',
          denied: 'Denied',
          timedOut: 'Timed out',
          aborted: 'Aborted',
        }[status],
      ),
    });
  }

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId: `guardian_assessment:${turn.callId('already-approved')}`,
    title: 'Guardian Review',
    kind: 'think',
    status: 'completed',
    rawInput: event('approved'),
    content: content('Approved'),
  });

  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId: ids.get('unstructured')!,
    status: 'completed',
    content: content('Approved'),
  });
  await turn.say('Guardian reviews finished.');

  return 'end_turn' as const;
}

export const GUARDIAN = {
  guardian: (turn) => guardian(turn, false),
  guardiangated: (turn) => guardian(turn, true),
} satisfies Record<string, Play>;

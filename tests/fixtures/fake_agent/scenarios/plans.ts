/**
 * Plans: one that moves a step at a time, Codex's proposed plan, and the
 * plans cursor and grok put to the client to approve (CHD-437, CHD-457).
 */
import * as acp from '@agentclientprotocol/sdk';
import { clientTakesPlans } from '../client.ts';
import { PLAN_CAPABILITY_ONLY, STEP_MS } from '../options.ts';
import { pause, type Play, type Turn } from '../turn.ts';
import { GATE_RELEASE, gateOpened } from './agents.ts';

/** How long the `plan` scenario holds each step: 400 steps, 2 s by default. */
const PLAN_STEP_MS = STEP_MS * 400;

const PRIORITIES = ['high', 'medium', 'low'] as const;

/**
 * Three steps, the first in progress, then the first dropped: after a
 * while, or with `gated` once the test opens the gate (`gateOpened`).
 */
async function planShrink(turn: Turn, gated: boolean) {
  const entry = (content: string, index: number): acp.PlanEntry => ({
    content,
    priority: PRIORITIES[index] ?? 'low',
    status: index === 0 ? 'in_progress' : 'pending',
  });
  const steps = ['Read the code', 'Write the change', 'Run the tests'];

  await turn.send({ sessionUpdate: 'plan', entries: steps.map(entry) });
  await turn.say('Planned.');

  if (gated) {
    await gateOpened(turn, GATE_RELEASE);
  } else {
    await pause(turn.signal, STEP_MS * 200);
  }

  await turn.send({
    sessionUpdate: 'plan',
    entries: steps.slice(1).map(entry),
  });
  await turn.say(' Dropped a step.');
  await pause(turn.signal, STEP_MS * 200);

  return 'end_turn' as const;
}

/** The plan cursor's and grok's scenarios put to the person. */
export const ASKED_PLAN =
  '# Route updates by session\n\n1. Read src/acp/connection.ts.\n' +
  '2. Move the routing into src/session/session.ts.\n3. Run the tests.';

/** cursor's todos for `ASKED_PLAN`. */
const CURSOR_TODOS = [
  { id: 'read', content: 'Read the connection', status: 'completed' },
  { id: 'move', content: 'Move the routing', status: 'in_progress' },
  { id: 'test', content: 'Run the tests', status: 'pending' },
] as const;

/** The answer each session's last plan got, which `planheard` says. */
const planAnswers = new Map<string, string>();

/**
 * Puts a plan to the client with `method` under a `Plan` call, announced
 * first unless `early`, and says the answer it got back whole, so a test
 * reads what the agent heard.
 */
async function askPlan(
  turn: Turn,
  method: string,
  params: (toolCallId: string) => Record<string, unknown>,
  early = false,
): Promise<acp.StopReason> {
  const toolCallId = turn.callId('plan');
  const announce = () =>
    turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      title: 'Plan',
      kind: 'switch_mode',
      status: 'pending',
    });

  if (!early) {
    await announce();
  }

  const asked = turn.client.request(method, params(toolCallId));

  if (early) {
    await announce();
  }

  const answer: unknown = await asked;

  // Kept before the turn goes on, which an interrupt may have ended.
  planAnswers.set(turn.sessionId, JSON.stringify(answer));

  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'completed',
  });
  await turn.say(`Plan answer: ${planAnswers.get(turn.sessionId)}`);

  return 'end_turn';
}

export const PLANS = {
  // The plan moves a step at a time, slowly enough to be seen mid-turn.
  async plan(turn) {
    const steps = ['Read the code', 'Write the change', 'Run the tests'];
    const at = (done: number): acp.PlanEntry[] =>
      steps.map((content, index) => ({
        content,
        priority: PRIORITIES[index] ?? 'low',
        status:
          index < done
            ? 'completed'
            : index === done
              ? 'in_progress'
              : 'pending',
      }));

    const planId = crypto.randomUUID();
    const send = async (entries: acp.PlanEntry[]) => {
      if (!PLAN_CAPABILITY_ONLY) {
        await turn.send({ sessionUpdate: 'plan', entries });
      } else if (clientTakesPlans) {
        await turn.send({
          sessionUpdate: 'plan_update',
          plan: { type: 'items', planId, entries },
        });
      } else {
        await turn.say(
          entries
            .map(
              (entry) =>
                `- [${entry.status === 'completed' ? 'x' : ' '}] ${entry.content}\n`,
            )
            .join(''),
        );
      }
    };

    for (let done = 1; done <= steps.length; done++) {
      await send(at(done));
      await turn.say(done === 1 ? 'Planned.' : ` Step ${done} done.`);

      if (done < steps.length) {
        await pause(turn.signal, PLAN_STEP_MS);
      }
    }

    return 'end_turn';
  },

  // A plan whose first step goes mid-turn, a second after it is drawn, so
  // a selection on that step can be seen not to pass to the next.
  planshrink: (turn) => planShrink(turn, false),

  // As `planshrink`, the step dropped only once the test writes
  // `GATE_RELEASE` in the session's gate, so a selection made on it is
  // made before it goes however slow the test is (CHD-399).
  planshrinkgated: (turn) => planShrink(turn, true),

  // Codex's proposed plan: whole markdown each time, rewritten from the
  // start, then a file plan beside it, then the markdown one withdrawn.
  async proposal(turn) {
    const drafts = [
      '1. Read the code',
      '1. Inspect the code',
      '1. Inspect the code\n2. Write the change',
    ];
    const uri = 'file:///plans/proposal.md';
    // Fresh ids each run, or a second run would rewrite the first run's plans
    // up in the earlier turn.
    const draftId = crypto.randomUUID();
    const fileId = crypto.randomUUID();

    await turn.say("I'll look first.");

    if (!clientTakesPlans) {
      await turn.say(`\n\n${drafts.at(-1)}\n\n${uri}\n\nPlan written.`);

      return 'end_turn';
    }

    for (const content of drafts) {
      await pause(turn.signal, PLAN_STEP_MS);
      await turn.send({
        sessionUpdate: 'plan_update',
        plan: { type: 'markdown', planId: draftId, content },
      });
    }

    await pause(turn.signal, PLAN_STEP_MS);
    await turn.send({
      sessionUpdate: 'plan_update',
      plan: { type: 'file', planId: fileId, uri },
    });
    await turn.say('Plan written.');
    await pause(turn.signal, PLAN_STEP_MS);
    await turn.send({ sessionUpdate: 'plan_removed', planId: draftId });
    await turn.say(' Draft dropped.');

    return 'end_turn';
  },
  // cursor's cursor/create_plan, its todos and a phase of them.
  cursorplan: (turn) =>
    askPlan(turn, 'cursor/create_plan', (toolCallId) => ({
      toolCallId,
      name: 'Route updates by session',
      overview: 'Split the session routing out of the connection.',
      plan: ASKED_PLAN,
      todos: CURSOR_TODOS,
      phases: [{ name: 'Move', todos: CURSOR_TODOS.slice(1) }],
    })),

  // The same, asked before the call it names is announced.
  cursorplanearly: (turn) =>
    askPlan(
      turn,
      'cursor/create_plan',
      (toolCallId) => ({ toolCallId, plan: ASKED_PLAN, todos: [] }),
      true,
    ),

  // A plan request that does not read: its todos are no list.
  cursorplanbad: (turn) =>
    askPlan(turn, 'cursor/create_plan', (toolCallId) => ({
      toolCallId,
      plan: ASKED_PLAN,
      todos: 'three',
    })),

  // grok's x.ai/exit_plan_mode, with its plan, and with none written.
  grokplan: (turn) =>
    askPlan(turn, 'x.ai/exit_plan_mode', (toolCallId) => ({
      sessionId: turn.sessionId,
      toolCallId,
      planContent: ASKED_PLAN,
    })),
  // grok's request naming a session other than its own.
  grokplanwrong: (turn) =>
    askPlan(turn, 'x.ai/exit_plan_mode', (toolCallId) => ({
      sessionId: 'another-session',
      toolCallId,
      planContent: ASKED_PLAN,
    })),

  // cursor's request sent only once the turn has been cancelled, before the
  // turn ends: it waits for its answer, which only chord can give.
  async cursorplanlate(turn) {
    const toolCallId = turn.callId('plan');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      title: 'Plan',
      kind: 'switch_mode',
      status: 'pending',
    });
    await new Promise((resolve) =>
      turn.signal.addEventListener('abort', resolve, { once: true }),
    );

    const answer: unknown = await turn.client.request('cursor/create_plan', {
      toolCallId,
      plan: ASKED_PLAN,
      todos: [],
    });

    planAnswers.set(turn.sessionId, JSON.stringify(answer));

    return 'cancelled';
  },

  // Says the answer the session's last plan got, which a turn cut short
  // by an interrupt could not.
  async planheard(turn) {
    await turn.say(`Plan answer: ${planAnswers.get(turn.sessionId) ?? 'none'}`);

    return 'end_turn';
  },
  grokplanempty: (turn) =>
    askPlan(turn, 'x.ai/exit_plan_mode', (toolCallId) => ({
      sessionId: turn.sessionId,
      toolCallId,
    })),
} satisfies Record<string, Play>;

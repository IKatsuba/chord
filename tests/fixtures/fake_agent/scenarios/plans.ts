/** Plans: one that moves a step at a time, and Codex's proposed plan. */
import * as acp from '@agentclientprotocol/sdk';
import { clientTakesPlans } from '../client.ts';
import { PLAN_CAPABILITY_ONLY, STEP_MS } from '../options.ts';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { cwds } from '../sessions.ts';
import { pause, type Play, type Turn } from '../turn.ts';
import { GATE, GATE_RELEASE } from './agents.ts';

/** How long the `plan` scenario holds each step: 400 steps, 2 s by default. */
const PLAN_STEP_MS = STEP_MS * 400;

const PRIORITIES = ['high', 'medium', 'low'] as const;

/** How long `planshrinkgated` waits for its gate before dropping the step. */
const GATE_WITHIN_MS = 10_000;

/**
 * Three steps, the first in progress, then the first dropped: after a
 * while, or with `gated` once the test opens the gate, 10 s at most.
 */
async function planShrink(turn: Turn, gated: boolean) {
  const entry = (content: string, index: number): acp.PlanEntry => ({
    content,
    priority: PRIORITIES[index] ?? 'low',
    status: index === 0 ? 'in_progress' : 'pending',
  });
  const steps = ['Read the code', 'Write the change', 'Run the tests'];
  const release = join(cwds.get(turn.sessionId) ?? '.', GATE, GATE_RELEASE);
  const deadline = Date.now() + GATE_WITHIN_MS;

  await turn.send({ sessionUpdate: 'plan', entries: steps.map(entry) });
  await turn.say('Planned.');

  if (gated) {
    while (!existsSync(release) && Date.now() < deadline) {
      await pause(turn.signal, STEP_MS * 2);
    }
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
} satisfies Record<string, Play>;

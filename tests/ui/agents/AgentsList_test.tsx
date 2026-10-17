/** The list under the prompt drawn on its own, its times counting. */
import { expect, test } from 'bun:test';
import { until } from '../app/render.tsx';
import { draw } from '../harness.tsx';
import stripAnsi from 'strip-ansi';
import { emptyWatch } from '../../../src/notify.ts';
import { type AgentRow, listRows } from '../../../src/ui/agents/agents.ts';
import { AgentsList } from '../../../src/ui/agents/Agents.tsx';

function row(name: string, key: number, more: Partial<AgentRow> = {}) {
  return {
    key,
    name,
    runtime: 'fake',
    model: 'Fake',
    picked: false,
    failed: false,
    wait: { watch: emptyWatch },
    ...more,
  };
}

test("a folded member's permission time goes on counting with its lead idle and seen", async () => {
  // main and the lead idle and seen, no monitor and no other timed row:
  // only the folded tester's wait can keep the list ticking.
  const agents: AgentRow[] = [
    row('main', 1, { picked: true }),
    row('bugfix', 2, { runtime: 'team · fake', team: 2 }),
    row('tester', 3, {
      team: 2,
      wait: {
        watch: emptyWatch,
        asking: { on: { kind: 'permission' }, since: Date.now() - 12_000 },
      },
    }),
    row('coder', 4, { team: 2 }),
    row('parser', 5),
  ];
  const drawn = await draw(
    <AgentsList
      rows={listRows(agents, 4)}
      limit={4}
      width={76}
      focused={false}
    />,
  );

  try {
    expect(stripAnsi(drawn.frame())).toContain('tester: permission 12s');
    // The clock ticks a second at a time from the mount, so 14s is due a
    // little after 2s; a fixed sleep just past that read 13s whenever a
    // loaded run held the tick or its frame back a tenth of a second.
    await until(
      'two more seconds on the folded wait',
      () => stripAnsi(drawn.frame()).includes('tester: permission 14s'),
      4_000,
    );
  } finally {
    await drawn.unmount();
  }
});

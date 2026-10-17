/** The list under the prompt drawn on its own, its times counting. */
import { describe, expect, test } from 'bun:test';
import { until } from '../app/render.tsx';
import { draw } from '../harness.tsx';
import stripAnsi from 'strip-ansi';
import chalk from 'chalk';
import { Colours } from '../../../src/ui/app/context.ts';
import { paletteOf } from '../../../src/ui/theme/theme.ts';
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

describe('CHD-264 tester: folded failure rendering', () => {
  for (const columns of [80, 120]) {
    for (const cause of ['turn', 'start', 'exited'] as const) {
      test(`a folded member's ${cause} is named and coloured at ${columns} columns`, async () => {
        const level = chalk.level;

        chalk.level = 3;

        const wait = {
          watch: emptyWatch,
          ...(cause === 'turn'
            ? {
                unseen: {
                  kind: 'failed' as const,
                  failure: 'turn' as const,
                  since: Date.now() - 12_000,
                },
              }
            : {}),
          ...(cause === 'exited' ? { exited: true as const } : {}),
        };
        const agents = [
          row('main', 1, { picked: true }),
          row('bugfix', 2, { runtime: 'team · fake', team: 2 }),
          row('tester', 3, { team: 2, wait, failed: cause === 'start' }),
          row('coder', 4, { team: 2 }),
          row('reviewer', 5, { team: 2 }),
        ];
        const words =
          cause === 'turn'
            ? 'turn failed 12s ago'
            : cause === 'start'
              ? 'failed to start'
              : 'exited';
        const drawn = await draw(
          <Colours.Provider
            value={{ ...paletteOf('dark', true), error: '#ff0000' }}
          >
            <AgentsList
              rows={listRows(agents, 4)}
              limit={4}
              width={columns - 4}
              focused={false}
            />
          </Colours.Provider>,
          { columns, rows: 24 },
        );

        try {
          expect(stripAnsi(drawn.frame())).toContain(`✗ tester: ${words}`);
          expect(stripAnsi(drawn.frame())).not.toMatch(/^ {4}tester /m);
          expect(drawn.frame()).toContain(
            `\x1b[38;2;255;0;0m  ✗ tester: ${words}`,
          );
        } finally {
          await drawn.unmount();

          chalk.level = level;
        }
      });
    }
  }
});

describe('CHD-364 tester: folded reply clock', () => {
  for (const columns of [80, 120]) {
    test(`the folded lead uses its member's newest reply clock at ${columns} columns`, async () => {
      const now = Date.now();
      const agents = [
        row('main', 1, { picked: true }),
        row('bugfix', 2, { runtime: 'team · fake', team: 2 }),
        row('coder', 3, {
          team: 2,
          wait: {
            watch: emptyWatch,
            unseen: {
              kind: 'replied',
              since: now - 120_000,
              repliedAt: now - 1000,
            },
          },
        }),
        row('tester', 4, { team: 2 }),
        row('reviewer', 5, { team: 2 }),
      ];
      const drawn = await draw(
        <AgentsList
          rows={listRows(agents, 4)}
          limit={4}
          width={columns - 4}
          focused={false}
        />,
        { columns, rows: 24 },
      );

      try {
        expect(stripAnsi(drawn.frame())).toContain('coder: replied 1s ago');
        await until(
          'the folded reply clock ticks',
          () => stripAnsi(drawn.frame()).includes('coder: replied 3s ago'),
          4000,
        );
      } finally {
        await drawn.unmount();
      }
    });
  }
});

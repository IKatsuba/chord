/** The list under the prompt drawn on its own, its times counting. */
import { describe, expect, spyOn, test } from 'bun:test';
import { useEffect } from 'react';
import { until } from '../app/render.tsx';
import { draw } from '../harness.tsx';
import stripAnsi from 'strip-ansi';
import chalk from 'chalk';
import { Colours } from '../../../src/ui/app/context.ts';
import { paletteOf } from '../../../src/ui/theme/theme.ts';
import { emptyWatch } from '../../../src/notify.ts';
import { type AgentRow, listRows } from '../../../src/ui/agents/agents.ts';
import { AgentsList, useAgentsClock } from '../../../src/ui/agents/Agents.tsx';

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
      test(`a folded member's ${cause} has its designed state or mark and colour at ${columns} columns`, async () => {
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
            ? 'turn failed'
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
          expect(stripAnsi(drawn.frame())).toContain(
            cause === 'turn' ? `◦ idle 0s  ✗ ${words}` : `✗ tester: ${words}`,
          );
          expect(stripAnsi(drawn.frame())).not.toMatch(/^ {4}tester /m);
          expect(drawn.frame()).toContain(
            `\x1b[38;2;255;0;0m  ✗ ${cause === 'turn' ? words : `tester: ${words}`}`,
          );
        } finally {
          await drawn.unmount();

          chalk.level = level;
        }
      });
    }
  }
});

describe('CHD-364 tester: folded idle clock beside reply mark', () => {
  for (const columns of [80, 120]) {
    test(`the folded lead uses its latest stop beside an unnamed reply mark at ${columns} columns`, async () => {
      const now = Date.now();
      const agents = [
        row('main', 1, { picked: true }),
        row('bugfix', 2, {
          runtime: 'team · fake',
          team: 2,
          wait: { watch: emptyWatch, stopped: now - 30000 },
        }),
        row('coder', 3, {
          team: 2,
          wait: {
            watch: emptyWatch,
            stopped: now - 1000,
            unseen: {
              kind: 'replied',
              since: now - 120_000,
              repliedAt: now - 1000,
            },
          },
        }),
        row('tester', 4, {
          team: 2,
          wait: { watch: emptyWatch, stopped: now - 30000 },
        }),
        row('reviewer', 5, {
          team: 2,
          wait: { watch: emptyWatch, stopped: now - 30000 },
        }),
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
        expect(stripAnsi(drawn.frame())).toContain('◦ idle 1s  ✓ new reply');
        await until(
          'the folded idle clock ticks beside the unchanged mark',
          () => stripAnsi(drawn.frame()).includes('◦ idle 3s  ✓ new reply'),
          4000,
        );
      } finally {
        await drawn.unmount();
      }
    });
  }
});

describe('CHD-471 tester: list clock lifecycle', () => {
  test('two live subscribers share ticks and the last unmount releases the interval', async () => {
    const renders: number[] = [];
    const intervals = spyOn(globalThis, 'setInterval');
    const cleared = spyOn(globalThis, 'clearInterval');

    function Clock() {
      const now = useAgentsClock(true);

      useEffect(() => {
        renders.push(now);
      }, [now]);

      return <text>{`clock ${now}`}</text>;
    }

    const first = await draw(<Clock />);
    let second: Awaited<ReturnType<typeof draw>> | undefined;

    try {
      const start = renders.length;

      await until('first actual clock tick', () => renders.length > start);

      second = await draw(<Clock />);

      const timers = intervals.mock.calls.flatMap((args, index) =>
        args[1] === 1000 ? [intervals.mock.results[index]!.value] : [],
      );

      expect(timers).toHaveLength(1);
      await first.unmount();
      expect(cleared.mock.calls.some(([timer]) => timer === timers[0])).toBe(
        false,
      );

      const afterFirst = renders.length;

      await until(
        'remaining subscriber still ticks',
        () => renders.length > afterFirst,
      );
      await second.unmount();
      expect(cleared.mock.calls.some(([timer]) => timer === timers[0])).toBe(
        true,
      );

      const afterLast = renders.length;

      await new Promise((resolve) => setTimeout(resolve, 1100));
      expect(renders).toHaveLength(afterLast);
    } finally {
      await first.unmount();
      await second?.unmount();
      intervals.mockRestore();
      cleared.mockRestore();
    }
  });
});

test("a narrow list wraps a long name in its column and draws a state under its detail in the state's colour, cutting nothing (CHD-471)", async () => {
  const level = chalk.level;

  chalk.level = 3;

  const agents: AgentRow[] = [
    row('main', 1, { picked: true }),
    row('a-child-with-a-long-name', 2, {
      wait: {
        watch: emptyWatch,
        asking: { on: { kind: 'permission' }, since: Date.now() - 8_000 },
      },
    }),
  ];
  const drawn = await draw(
    <Colours.Provider value={paletteOf('dark', true)}>
      <AgentsList rows={agents} limit={6} width={30} focused={false} />
    </Colours.Provider>,
    { columns: 34, rows: 8 },
  );

  try {
    const frame = drawn.frame();

    expect(
      stripAnsi(frame)
        .split('\n')
        .map((line) => line.trimEnd())
        .filter((line) => line !== ''),
    ).toStrictEqual([
      '    main        fake  ◦ idle 0s',
      '    a-child-wi  fake',
      '    th-a-long-  ● permission 8s',
      '    name',
    ]);
    // #ffc107, the dark palette's warning, on the state under the detail.
    expect(frame).toContain('\x1b[38;2;255;193;7m● permission 8s');
  } finally {
    chalk.level = level;

    await drawn.unmount();
  }
});

test('a detail wider than the list on its own is drawn whole, wrapped under its start, nothing clipped (CHD-471)', async () => {
  const drawn = await draw(
    <AgentsList
      rows={[
        row('main', 1, { model: undefined, picked: true }),
        row('parser', 2, {
          runtime: 'a-runtime-named-past-the-line and more words',
          model: undefined,
        }),
      ]}
      limit={9}
      width={30}
      focused={false}
    />,
    { columns: 34, rows: 8 },
  );

  try {
    expect(
      stripAnsi(drawn.frame())
        .split('\n')
        .map((line) => line.trimEnd())
        .filter((line) => line !== ''),
    ).toStrictEqual([
      '    main    fake  ◦ idle 0s',
      '    parser  a-runtime-named-past',
      '            -the-line and more',
      '            words',
      '            ◦ idle 0s',
    ]);
  } finally {
    await drawn.unmount();
  }
});

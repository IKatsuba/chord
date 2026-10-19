import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import stringWidth from 'string-width';
import { Colours } from '../../../src/ui/app/context.ts';
import { Strip } from '../../../src/ui/app/Strip.tsx';
import { stripLayout, type StripTab } from '../../../src/ui/app/strip.ts';
import { paletteOf } from '../../../src/ui/theme/theme.ts';
import { draw } from '../harness.tsx';

describe('CHD-471 tester: rendered strip state and mark', () => {
  for (const columns of [80, 120]) {
    test(`nine tabs retain both glyphs in order and idle adds no glyph at ${columns} columns`, async () => {
      const tabs: StripTab[] = Array.from({ length: 9 }, (_, index) => ({
        number: index + 1,
        agent: 'fake',
        front: index === 4,
        ...(index === 0
          ? {}
          : {
              glyphs: { state: 'working' as const, mark: 'replied' as const },
            }),
      }));
      const view = stripLayout(tabs, '~/src/app', columns - 2);

      assert(view);

      const level = chalk.level;

      chalk.level = 3;

      const app = await draw(
        <Colours.Provider value={paletteOf('dark', true)}>
          <Strip view={view} />
        </Colours.Provider>,
        { columns, rows: 4 },
      );

      try {
        const frame = stripAnsi(app.frame());

        expect(frame).toContain('2 ✻✓');
        expect(frame).toContain('9 ✻✓');
        expect(frame).not.toContain('◦');
        expect(frame).not.toMatch(/1(?: fake)? [✻✓]/);
        expect(frame).not.toMatch(/5 fake [✻✓]/);
        expect(frame.match(/✻✓/g)).toHaveLength(7);
        expect(
          Math.max(...frame.split('\n').map(stringWidth)),
        ).toBeLessThanOrEqual(columns);
        expect(app.frame()).toContain('\x1b[38;2;78;186;101m✓');
      } finally {
        await app.unmount();

        chalk.level = level;
      }
    });
  }
});

import { describe, expect, test } from 'bun:test';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  GATE,
  GATE_RELEASE,
} from '../../fixtures/fake_agent/scenarios/agents.ts';
import { copiedStub, ESC, left, send, until, withWindow } from './render.tsx';
import stripAnsi from 'strip-ansi';
import { cellsOf } from './selecting.ts';

describe('tester: held rule on a tall transcript (CHD-397)', () => {
  test('the first row below a held bottom counts two and stays stable across frames', () =>
    withWindow(
      async (window) => {
        await send(window, 'longheld');
        await window.shows('20. Line 20');

        const { x, y } = cellsOf(window, '20. Line 20');

        await window.press(left(x, y, 'down'));
        expect(window.frame()).not.toContain('below');
        await mkdir(join(window.dir, GATE), { recursive: true });
        await writeFile(join(window.dir, GATE, GATE_RELEASE), '');
        await window.shows('2 lines below');

        const held = stripAnsi(window.frame()).split('\n').slice(0, 15);

        await window.press(left(x, y, 'drag'));
        expect(window.frame()).toContain('2 lines below');
        expect(
          stripAnsi(window.frame()).split('\n').slice(0, 15),
        ).toStrictEqual(held);
        await window.press(left(x, y, 'up'));
        await window.press(ESC);
        await until(
          'the turn to end',
          () => !window.frame().includes('Working'),
        );
      },
      {
        columns: 80,
        rows: 24,
        copy: copiedStub,
        agentCommand: fakeAgentCommand(undefined, '--step-ms', '20'),
      },
    ));

  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`a completed tall reply stays uncovered during a press at ${columns}x${rows}`, () =>
      withWindow(
        async (window) => {
          await send(window, 'long');
          await window.shows('200. Line 200');
          await until(
            'the turn to end',
            () => !window.frame().includes('Working'),
          );

          const { x, y } = cellsOf(window, '200. Line 200');

          await window.press(left(x, y, 'down'));
          expect(window.frame()).not.toContain('below');
          await window.press(left(x, y, 'up'));
          expect(window.frame()).not.toContain('below');
        },
        {
          columns,
          rows,
          copy: copiedStub,
          agentCommand: fakeAgentCommand(undefined, '--step-ms', '1'),
        },
      ));
  }
});

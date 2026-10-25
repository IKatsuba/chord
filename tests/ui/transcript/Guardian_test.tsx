/** Guardian presentation in the real transcript renderer and fake session. */
import { describe, expect, test } from 'bun:test';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import stripAnsi from 'strip-ansi';
import chalk from 'chalk';
import type { ToolCall } from '../../../src/session/transcript/types.ts';
import { emptyTranscript } from '../../../src/session/transcript/types.ts';
import { reduceTranscript } from '../../../src/session/transcript/reducer.ts';
import {
  recordActions,
  type RecordEntry,
} from '../../../src/session/record.ts';
import { TranscriptEntry } from '../../../src/ui/transcript/Transcript.tsx';
import { Tool } from '../../../src/ui/transcript/tools/Tool.tsx';
import { BlockGap } from '../../../src/ui/transcript/gap.ts';
import { draw } from '../harness.tsx';
import { CTRL_O, ready, send, until, withWindow } from '../app/render.tsx';

const REVIEW: ToolCall = {
  id: 'guardian_assessment:review',
  title: 'Guardian Review',
  kind: 'think',
  status: 'completed',
  content: [
    {
      type: 'content',
      content: {
        type: 'text',
        text: 'Status: Approved\nAction: printf ready\nRisk: low\nAuthorization: high\nRationale: review-only detail',
      },
    },
  ],
};

test('an old metadata-free record hides approved reviews and keeps denied reviews on screen (CHD-521)', async () => {
  const records: RecordEntry[] = ['approved', 'denied'].map((status) => ({
    type: 'update',
    turnId: 'old-turn',
    update: {
      sessionUpdate: 'tool_call',
      toolCallId: `guardian_assessment:${status}`,
      title: 'Guardian Review',
      kind: 'think',
      status: status === 'approved' ? 'completed' : 'failed',
      rawInput: { review: { status } },
      content: [
        {
          type: 'content',
          content: { type: 'text', text: `metadata-free ${status}` },
        },
      ],
    },
  }));
  let transcript = emptyTranscript;

  for (const action of recordActions(records)) {
    if (action.type !== 'usage') {
      transcript = reduceTranscript(transcript, action);
    }
  }

  const screen = await draw(
    <box>
      {transcript.entries.map((entry, at) => (
        <TranscriptEntry
          key={at}
          entry={entry}
          turn={transcript.turn}
          agent='codex'
          expanded
          width={77}
        />
      ))}
    </box>,
    { columns: 80, rows: 24 },
  );

  try {
    expect(screen.frame()).not.toContain('metadata-free approved');
    expect(screen.frame()).toContain('metadata-free denied');
  } finally {
    await screen.unmount();
  }
});

describe('Guardian rows and spacing (CHD-521)', () => {
  for (const columns of [80, 120]) {
    for (const gap of ['margin', 'row'] as const) {
      test(`approved reviews leave no row or gap, expanded too, at ${columns} columns with ${gap} gaps`, async () => {
        const frame = async (reviews: boolean) => {
          const screen = await draw(
            <BlockGap value={gap}>
              <box>
                <text>before</text>
                {reviews && (
                  <>
                    <Tool
                      call={{ ...REVIEW, guardian: 'approved' }}
                      expanded
                      width={columns - 3}
                    />
                    <Tool
                      call={{
                        ...REVIEW,
                        id: 'review-two',
                        guardian: 'approved',
                      }}
                      expanded
                      width={columns - 3}
                    />
                  </>
                )}
                <text>after</text>
              </box>
            </BlockGap>,
            { columns, rows: 24 },
          );

          try {
            return stripAnsi(screen.frame());
          } finally {
            await screen.unmount();
          }
        };

        expect(await frame(true)).toBe(await frame(false));
      });
    }

    test(`inProgress stays one dim text line at column 3 even after its turn ends at ${columns} columns`, async () => {
      const level = chalk.level;

      chalk.level = 3;

      const screen = await draw(
        <box paddingLeft={1}>
          <Tool
            call={{ ...REVIEW, guardian: 'inProgress' }}
            expanded
            ended
            width={columns - 3}
          />
        </box>,
        { columns, rows: 24 },
      );

      try {
        const frame = screen.frame();
        const lines = stripAnsi(frame)
          .split('\n')
          .filter((line) => line.trim());

        expect(lines.map((line) => line.trim())).toStrictEqual([
          'Guardian reviewing…',
        ]);
        expect(lines[0]?.indexOf('Guardian reviewing…')).toBe(3);
        expect(frame).toContain('\x1b[2mGuardian reviewing…');
        expect(frame).not.toContain('review-only detail');
      } finally {
        chalk.level = level;

        await screen.unmount();
      }
    });

    for (const guardian of [
      'denied',
      'timedOut',
      'aborted',
      'futureStatus',
      undefined,
    ]) {
      test(`${guardian ?? 'unstructured'} keeps the ordinary block at ${columns} columns`, async () => {
        const screen = await draw(
          <Tool
            call={{
              ...REVIEW,
              ...(guardian === undefined ? {} : { guardian }),
            }}
            expanded
            width={columns - 3}
          />,
          { columns, rows: 24 },
        );

        try {
          expect(screen.frame()).toContain('Guardian');
          expect(screen.frame()).toContain('review-only detail');
          expect(screen.frame()).not.toContain('Guardian reviewing…');
        } finally {
          await screen.unmount();
        }
      });
    }
  }
});

for (const columns of [80, 120]) {
  test(`Guardian verdicts update live, in ctrl+o and after /resume at ${columns} columns`, () =>
    withWindow(
      async (window) => {
        await ready(window);
        await mkdir(join(window.dir, '.fake-gate'), { recursive: true });
        await send(window, 'guardiangated');
        await window.shows('Guardian reviews opened.');
        expect(window.frame().split('Guardian reviewing…')).toHaveLength(6);
        await writeFile(join(window.dir, '.fake-gate/release'), '');
        await window.shows('Guardian reviews finished.');
        await until(
          'turn ended',
          () => !window.frame().includes('esc to interrupt'),
        );

        const check = () => {
          const frame = stripAnsi(window.frame());

          expect(frame.split('Guardian(Review)')).toHaveLength(5);
          expect(frame.split('Guardian reviewing…')).toHaveLength(2);

          for (const status of ['Denied', 'Timed out', 'Aborted', 'Approved']) {
            expect(frame).toContain(`Status: ${status}`);
          }
        };

        check();
        await window.press(CTRL_O);
        check();
        await send(window, '/clear');
        await ready(window);
        await send(window, '/resume');
        await window.shows('Resume a session');

        const choice = stripAnsi(window.frame())
          .split('\n')
          .find((line) => line.includes('guardiangated'))
          ?.match(/(\d+)\./)?.[1];

        expect(choice).toBeDefined();
        await window.press(choice!);
        await window.shows('Guardian reviews finished.');
        check();
      },
      { columns, rows: 80 },
    ));
}
